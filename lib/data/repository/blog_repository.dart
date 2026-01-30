import 'dart:async';
import 'dart:io';

import 'package:computing_blog/core/exceptions.dart';
import 'package:computing_blog/core/logger.util.dart';
import 'package:computing_blog/core/result.dart';
import 'package:computing_blog/data/api/blog_api.dart';
import 'package:computing_blog/domain/models/blog.dart';
import 'package:computing_blog/local/blog_cache.dart';
import 'package:computing_blog/local/pending_ops.dart';
import 'package:computing_blog/local/pending_ops_store.dart';
import 'package:computing_blog/local/sync_service.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;

@lazySingleton
class BlogRepository {
  BlogRepository(this._api, this._cache, this._pendingOps, this._sync) {
    logger.i('[REPO] BlogRepository created (hash=$hashCode)');
  }

  final BlogApi _api;
  final BlogCache _cache;
  final PendingOpsStore _pendingOps;
  final SyncService _sync;
  final logger = getLogger();

  final _uuid = const Uuid();

  final _blogController = StreamController<List<Blog>>.broadcast();
  Stream<List<Blog>> get blogStream => _blogController.stream;

  List<Blog> _currentBlogs = [];

  static const _minFetchInterval = Duration(seconds: 60);

  Future<Result<List<Blog>>> getBlogPosts({bool forceRefresh = false}) async {
    logger.i('[REPO] getBlogPosts(forceRefresh=$forceRefresh)');

    try {
      if (!forceRefresh) {
        final lastSync = await _cache.getLastSync();
        logger.d('[REPO] cache lastSync=$lastSync');

        if (lastSync != null &&
            DateTime.now().difference(lastSync) < _minFetchInterval) {
          logger.i('[REPO] cache valid -> load from cache');

          final cached = await _cache.getAll();
          logger.i('[REPO] cache loaded count=${cached.length}');

          if (cached.isNotEmpty) {
            _currentBlogs = cached;
            _blogController.add(_currentBlogs);
            logger.d(
              '[REPO] stream emit from cache count=${_currentBlogs.length}',
            );
            return Success(cached);
          } else {
            logger.w('[REPO] cache valid but empty -> fallback to API');
          }
        } else {
          logger.d('[REPO] cache stale/empty lastSync -> fetch API');
        }
      } else {
        logger.d('[REPO] forceRefresh -> fetch API');
      }

      logger.i('[REPO] fetching blogs from API');
      final blogs = await _api.getBlogs();
      blogs.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      logger.i('[REPO] API fetched count=${blogs.length}');

      await _cache.saveAll(blogs);
      logger.i('[REPO] cache saveAll done count=${blogs.length}');

      _currentBlogs = blogs;
      _blogController.add(_currentBlogs);
      logger.d('[REPO] stream emit from API count=${_currentBlogs.length}');

      // queued offline changes flushen
      logger.i('[REPO] sync flush start');
      await _sync.sync();
      logger.i('[REPO] sync flush done');

      return Success(blogs);
    } on SocketException catch (e, s) {
      logger.w(
        '[REPO] offline (SocketException) -> fallback to cache',
        error: e,
        stackTrace: s,
      );

      final cached = await _cache.getAll();
      logger.i('[REPO] cache loaded (offline fallback) count=${cached.length}');

      if (cached.isNotEmpty) {
        _currentBlogs = cached;
        _blogController.add(_currentBlogs);
        logger.d('[REPO] stream emit from cache count=${_currentBlogs.length}');
        return Success(cached);
      }

      logger.w('[REPO] offline and no cache available -> NetworkException');
      return Failure(NetworkException());
    } catch (e, s) {
      logger.e(
        '[REPO] getBlogPosts failed -> try cache fallback',
        error: e,
        stackTrace: s,
      );

      final cached = await _cache.getAll();
      logger.i('[REPO] cache loaded (error fallback) count=${cached.length}');

      if (cached.isNotEmpty) {
        _currentBlogs = cached;
        _blogController.add(_currentBlogs);
        logger.d('[REPO] stream emit from cache count=${_currentBlogs.length}');
        return Success(cached);
      }

      return Failure(ServerException(e.toString()));
    }
  }

  Future<void> addBlogPost(Blog blog) async {
    logger.i('[REPO] addBlogPost title="${blog.title}"');

    try {
      await _api.addBlog(
        title: blog.title,
        content: blog.content ?? "",
        headerImageUrl: blog.headerImageUrl,
      );

      logger.i('[REPO] create online -> refresh');
      await getBlogPosts(forceRefresh: true);

      logger.i('[REPO] sync flush start');
      await _sync.sync();
      logger.i('[REPO] sync flush done');
    } catch (e, s) {
      if (!_isOfflineError(e)) {
        logger.e(
          '[REPO] create failed (not offline) -> rethrow',
          error: e,
          stackTrace: s,
        );
        rethrow;
      }

      logger.w(
        '[REPO] offline -> enqueue create + optimistic insert',
        error: e,
        stackTrace: s,
      );

      final tempId = 'local-${_uuid.v4()}';
      final opId = _uuid.v4();

      await _pendingOps.add(
        PendingOp(
          id: opId,
          type: PendingOpType.createBlog,
          blogId: tempId,
          createdAt: DateTime.now(),
          payload: {
            'title': blog.title,
            'content': blog.content ?? '',
            'headerImageUrl': blog.headerImageUrl,
            'author': blog.author,
          },
        ),
      );
      logger.w('[REPO] queued op=$opId type=createBlog tempId=$tempId');

      final optimistic = Blog(
        id: tempId,
        author: blog.author,
        title: blog.title,
        content: blog.content,
        contentPreview: blog.contentPreview ?? blog.content,
        publishedAt: DateTime.now(),
        lastUpdate: DateTime.now(),
        headerImageUrl: blog.headerImageUrl,
        createdByMe: true,
        isLikedByMe: false,
        likes: 0,
        comments: blog.comments,
        userIdsWithLikes: blog.userIdsWithLikes,
      );

      await _cache.upsert(optimistic);
      logger.i('[REPO] optimistic cached tempId=$tempId');
      await _emitFromCache();
    }
  }

  Future<void> updateBlogPost(
    String id, {
    required String blogId,
    required String title,
    required String content,
  }) async {
    logger.i('[REPO] updateBlogPost blogId=$id');

    try {
      await _api.patchBlog(blogId: id, title: title, content: content);

      logger.i('[REPO] patch online -> refresh');
      await getBlogPosts(forceRefresh: true);

      logger.i('[REPO] sync flush start');
      await _sync.sync();
      logger.i('[REPO] sync flush done');
    } catch (e, s) {
      if (!_isOfflineError(e)) {
        logger.e(
          '[REPO] patch failed (not offline) -> rethrow',
          error: e,
          stackTrace: s,
        );
        rethrow;
      }

      logger.w(
        '[REPO] offline -> enqueue patch + optimistic update',
        error: e,
        stackTrace: s,
      );

      final opId = _uuid.v4();
      await _pendingOps.add(
        PendingOp(
          id: opId,
          type: PendingOpType.patchBlog,
          blogId: id,
          createdAt: DateTime.now(),
          payload: {'title': title, 'content': content},
        ),
      );
      logger.w('[REPO] queued op=$opId type=patchBlog blogId=$id');

      final cached = await _cache.getAll();
      final idx = cached.indexWhere((b) => b.id == id);
      if (idx == -1) {
        logger.w('[REPO] optimistic patch skipped -> not in cache blogId=$id');
      } else {
        final updated = _applyPatchLocally(
          cached[idx],
          title: title,
          content: content,
        );
        await _cache.upsert(updated);
        logger.i('[REPO] optimistic patched in cache blogId=$id');
      }

      await _emitFromCache();
    }
  }

  Future<void> deleteBlogPost(String blogId) async {
    logger.i('[REPO] deleteBlogPost blogId=$blogId');

    try {
      await _api.deleteBlog(blogId: blogId);

      logger.i('[REPO] delete online -> refresh');
      await getBlogPosts(forceRefresh: true);

      logger.i('[REPO] sync flush start');
      await _sync.sync();
      logger.i('[REPO] sync flush done');
    } catch (e, s) {
      if (!_isOfflineError(e)) {
        logger.e(
          '[REPO] delete failed (not offline) -> rethrow',
          error: e,
          stackTrace: s,
        );
        rethrow;
      }

      logger.w(
        '[REPO] offline -> enqueue delete + optimistic remove',
        error: e,
        stackTrace: s,
      );

      final opId = _uuid.v4();
      await _pendingOps.add(
        PendingOp(
          id: opId,
          type: PendingOpType.deleteBlog,
          blogId: blogId,
          createdAt: DateTime.now(),
        ),
      );
      logger.w('[REPO] queued op=$opId type=deleteBlog blogId=$blogId');

      await _cache.removeById(blogId);
      logger.i('[REPO] optimistic removed from cache blogId=$blogId');
      await _emitFromCache();
    }
  }

  Future<void> toggleLike(Blog blog) async {
    logger.i(
      '[REPO] toggleLike blogId=${blog.id} currentLiked=${blog.isLikedByMe} likes=${blog.likes}',
    );

    final nextLiked = !blog.isLikedByMe;

    try {
      await _api.setLike(blogId: blog.id, likedByMe: nextLiked);

      logger.i('[REPO] like online -> refresh');
      await getBlogPosts(forceRefresh: true);

      logger.i('[REPO] sync flush start');
      await _sync.sync();
      logger.i('[REPO] sync flush done');
    } catch (e, s) {
      if (!_isOfflineError(e)) {
        logger.e(
          '[REPO] like failed (not offline) -> rethrow',
          error: e,
          stackTrace: s,
        );
        rethrow;
      }

      logger.w(
        '[REPO] offline -> enqueue like + optimistic update',
        error: e,
        stackTrace: s,
      );

      final opId = _uuid.v4();
      await _pendingOps.add(
        PendingOp(
          id: opId,
          type: PendingOpType.setLike,
          blogId: blog.id,
          createdAt: DateTime.now(),
          payload: {'likedByMe': nextLiked},
        ),
      );
      logger.w(
        '[REPO] queued op=$opId type=setLike blogId=${blog.id} nextLiked=$nextLiked',
      );

      final updated = _applyLikeLocally(blog, nextLiked);
      await _cache.upsert(updated);
      logger.i(
        '[REPO] optimistic like cached blogId=${blog.id} likedByMe=${updated.isLikedByMe} likes=${updated.likes}',
      );
      await _emitFromCache();
    }
  }

  void dispose() {
    logger.i('[REPO] disposed');
    _blogController.close();
  }

  Future<void> _emitFromCache() async {
    final cached = await _cache.getAll();
    _currentBlogs = cached;
    _blogController.add(_currentBlogs);
    logger.d('[REPO] stream emit from cache count=${_currentBlogs.length}');
  }

  Blog _applyPatchLocally(Blog blog, {String? title, String? content}) {
    // HomeScreen rendert `contentPreview ?? content`, daher muss Preview bei Offline-Patch mitkommen.
    final nextContent = content ?? blog.content;
    final nextPreview = (content != null) ? content : blog.contentPreview;

    return Blog(
      id: blog.id,
      author: blog.author,
      title: title ?? blog.title,
      contentPreview: nextPreview,
      content: nextPreview,
      publishedAt: blog.publishedAt,
      lastUpdate: DateTime.now(),
      comments: blog.comments,
      headerImageUrl: blog.headerImageUrl,
      userIdsWithLikes: blog.userIdsWithLikes,
      isLikedByMe: blog.isLikedByMe,
      likes: blog.likes,
      createdByMe: blog.createdByMe,
    );
  }

  Blog _applyLikeLocally(Blog blog, bool likedByMe) {
    final newLikes = likedByMe
        ? blog.likes + 1
        : (blog.likes - 1).clamp(0, 1 << 31);
    return Blog(
      id: blog.id,
      author: blog.author,
      title: blog.title,
      contentPreview: blog.contentPreview,
      content: blog.content,
      publishedAt: blog.publishedAt,
      lastUpdate: blog.lastUpdate,
      comments: blog.comments,
      headerImageUrl: blog.headerImageUrl,
      userIdsWithLikes: blog.userIdsWithLikes,
      isLikedByMe: likedByMe,
      likes: newLikes as int,
      createdByMe: blog.createdByMe,
    );
  }

  bool _isOfflineError(Object e) {
    if (e is SocketException) return true;
    if (e is http.ClientException) return true;
    if (e is HandshakeException) return true;

    final msg = e.toString().toLowerCase();
    return msg.contains('failed to fetch') ||
        msg.contains('internet_disconnected') ||
        msg.contains('err_internet_disconnected') ||
        msg.contains('networkerror');
  }
}
