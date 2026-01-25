import 'dart:async';
import 'dart:io';

import 'package:computing_blog/core/exceptions.dart';
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
    debugPrint('BlogRepository created (hash=$hashCode)');
  }

  final BlogApi _api;
  final BlogCache _cache;
  final PendingOpsStore _pendingOps;
  final SyncService _sync;

  final _uuid = const Uuid();

  final _blogController = StreamController<List<Blog>>.broadcast();
  Stream<List<Blog>> get blogStream => _blogController.stream;

  List<Blog> _currentBlogs = [];

  static const _minFetchInterval = Duration(seconds: 60);

  Future<Result<List<Blog>>> getBlogPosts({bool forceRefresh = false}) async {
    debugPrint('getBlogPosts called (forceRefresh=$forceRefresh)');

    try {
      if (!forceRefresh) {
        final lastSync = await _cache.getLastSync();
        debugPrint('Last cache sync: $lastSync');

        if (lastSync != null &&
            DateTime.now().difference(lastSync) < _minFetchInterval) {
          debugPrint('Cache still valid, loading blogs from cache');

          final cached = await _cache.getAll();
          debugPrint('Loaded ${cached.length} blogs from cache');

          if (cached.isNotEmpty) {
            _currentBlogs = cached;
            _blogController.add(_currentBlogs);
            return Success(cached);
          }
        }
      }

      debugPrint('Fetching blogs from API');
      final blogs = await _api.getBlogs();
      blogs.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

      debugPrint('Fetched ${blogs.length} blogs from API');

      await _cache.saveAll(blogs);
      debugPrint('Blogs saved to cache');

      _currentBlogs = blogs;
      _blogController.add(_currentBlogs);

      // queued offline changes flushen
      await _sync.sync();

      return Success(blogs);
    } on SocketException {
      debugPrint('SocketException → offline, trying cache');

      final cached = await _cache.getAll();
      debugPrint('Loaded ${cached.length} blogs from cache (offline fallback)');

      if (cached.isNotEmpty) {
        _currentBlogs = cached;
        _blogController.add(_currentBlogs);
        return Success(cached);
      }

      debugPrint('No cached blogs available');
      return Failure(NetworkException());
    } catch (e) {
      debugPrint('Error while fetching blogs: $e');
      debugPrint('Trying cache as fallback');

      final cached = await _cache.getAll();
      debugPrint('Loaded ${cached.length} blogs from cache (error fallback)');

      if (cached.isNotEmpty) {
        _currentBlogs = cached;
        _blogController.add(_currentBlogs);
        return Success(cached);
      }

      return Failure(ServerException(e.toString()));
    }
  }

  Future<void> addBlogPost(Blog blog) async {
    debugPrint('addBlogPost started (title="${blog.title}")');

    try {
      await _api.addBlog(
        title: blog.title,
        content: blog.content ?? "",
        headerImageUrl: blog.headerImageUrl,
      );

      debugPrint('Blog created online, refreshing blog list');
      await getBlogPosts(forceRefresh: true);

      await _sync.sync();
    } catch (e) {
      if (!_isOfflineError(e)) rethrow;

      debugPrint('Offline (web/mobile) → enqueue create + optimistic insert');

      // 1) Temp-ID generieren
      final tempId = 'local-${_uuid.v4()}';

      // 2) Queue Eintrag
      await _pendingOps.add(
        PendingOp(
          id: _uuid.v4(),
          type: PendingOpType.createBlog,
          blogId: tempId, // tempId hier rein
          createdAt: DateTime.now(),
          payload: {
            'title': blog.title,
            'content': blog.content ?? '',
            'headerImageUrl': blog.headerImageUrl,
            'author': blog.author, // optional
          },
        ),
      );

      // 3) Optimistisch lokalen Blog erstellen (wird in Cache + UI angezeigt)
      final optimistic = Blog(
        id: tempId,
        author: blog.author,
        title: blog.title,
        content: blog.content,
        contentPreview: blog.contentPreview ?? blog.content, // optional
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
      await _emitFromCache();
    }
  }

  Future<void> updateBlogPost(
    String id, {
    required String blogId,
    required String title,
    required String content,
  }) async {
    debugPrint('updateBlogPost started (blogId=$id)');

    try {
      await _api.patchBlog(blogId: id, title: title, content: content);

      debugPrint('Blog updated online, refreshing blog list');
      await getBlogPosts(forceRefresh: true);

      await _sync.sync();
    } catch (e) {
      if (!_isOfflineError(e)) rethrow;

      debugPrint('Offline (web/mobile) → enqueue patch + optimistic update');

      await _pendingOps.add(
        PendingOp(
          id: _uuid.v4(),
          type: PendingOpType.patchBlog,
          blogId: id,
          createdAt: DateTime.now(),
          payload: {'title': title, 'content': content},
        ),
      );

      final cached = await _cache.getAll();
      final idx = cached.indexWhere((b) => b.id == id);
      if (idx != -1) {
        final updated = _applyPatchLocally(
          cached[idx],
          title: title,
          content: content,
        );
        await _cache.upsert(updated);
      }

      await _emitFromCache();
    }
  }

  Future<void> deleteBlogPost(String blogId) async {
    debugPrint('deleteBlogPost started (blogId=$blogId)');

    try {
      await _api.deleteBlog(blogId: blogId);

      debugPrint('Blog deleted online, refreshing blog list');
      await getBlogPosts(forceRefresh: true);

      // queued ops ggf. flushen
      await _sync.sync();
    } catch (e) {
      if (!_isOfflineError(e)) rethrow;

      debugPrint('Offline (web/mobile) → enqueue delete + optimistic remove');

      // 1) Queue
      await _pendingOps.add(
        PendingOp(
          id: _uuid.v4(),
          type: PendingOpType.deleteBlog,
          blogId: blogId,
          createdAt: DateTime.now(),
        ),
      );

      // 2) Cache optimistisch entfernen + UI updaten
      await _cache.removeById(blogId);
      await _emitFromCache();
    }
  }

  Future<void> toggleLike(Blog blog) async {
    debugPrint(
      'toggleLike started (blogId=${blog.id}, currentLike=${blog.isLikedByMe})',
    );

    final nextLiked = !blog.isLikedByMe;

    try {
      await _api.setLike(blogId: blog.id, likedByMe: nextLiked);

      debugPrint('Like toggled online, refreshing blog list');
      await getBlogPosts(forceRefresh: true);

      await _sync.sync();
    } catch (e) {
      if (!_isOfflineError(e)) rethrow;

      debugPrint('Offline (web/mobile) → enqueue like + optimistic update');

      // 1) Queue
      await _pendingOps.add(
        PendingOp(
          id: _uuid.v4(),
          type: PendingOpType.setLike,
          blogId: blog.id,
          createdAt: DateTime.now(),
          payload: {'likedByMe': nextLiked},
        ),
      );

      // 2) Cache optimistisch updaten + UI pushen
      final updated = _applyLikeLocally(blog, nextLiked);
      await _cache.upsert(updated);
      await _emitFromCache();
    }
  }

  void dispose() {
    debugPrint('BlogRepository disposed');
    _blogController.close();
  }

  Future<void> _emitFromCache() async {
    final cached = await _cache.getAll();
    _currentBlogs = cached;
    _blogController.add(_currentBlogs);
  }

  Blog _applyPatchLocally(Blog blog, {String? title, String? content}) {
    return Blog(
      id: blog.id,
      author: blog.author,
      title: title ?? blog.title,
      contentPreview: blog.contentPreview,
      content: content ?? blog.content,
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

    // Flutter Web: "ClientException: Failed to fetch"
    if (e is http.ClientException) return true;

    // optional: manche SSL/Handshake Fälle
    if (e is HandshakeException) return true;

    final msg = e.toString().toLowerCase();
    return msg.contains('failed to fetch') ||
        msg.contains('internet_disconnected') ||
        msg.contains('err_internet_disconnected') ||
        msg.contains('networkerror');
  }
}
