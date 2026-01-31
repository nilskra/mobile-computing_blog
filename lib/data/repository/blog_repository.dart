import 'dart:async';
import 'dart:convert';

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
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

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

  // ----------------------------
  // Header image (fallback + cache)
  // ----------------------------

  /// Deterministic fallback so it stays stable across reloads.
  String _fallbackHeaderImageUrl(String blogId) {
    return 'https://picsum.photos/seed/$blogId/800/450';
  }

  Future<List<Blog>> _migrateMissingHeaderUrls(
    List<Blog> blogs, {
    bool persist = true,
  }) async {
    final out = <Blog>[];

    for (final b in blogs) {
      if (b.headerImageUrl == null || b.headerImageUrl!.isEmpty) {
        final updated = b.copyWith(headerImageUrl: _fallbackHeaderImageUrl(b.id));
        if (persist) await _cache.upsert(updated);
        out.add(updated);
      } else {
        out.add(b);
      }
    }

    return out;
  }

  Future<Blog> _ensureHeaderImageDownloaded(
    Blog blog, {
    bool persist = true,
  }) async {
    final url = (blog.headerImageUrl == null || blog.headerImageUrl!.isEmpty)
        ? _fallbackHeaderImageUrl(blog.id)
        : blog.headerImageUrl!;

    // If base64 exists, ensure URL is set and return.
    if (blog.headerImageBase64 != null && blog.headerImageBase64!.isNotEmpty) {
      if (url == blog.headerImageUrl) return blog;
      final updated = blog.copyWith(headerImageUrl: url);
      if (persist) await _cache.upsert(updated);
      return updated;
    }

    // Try downloading the image (best-effort; may fail on web due to CORS).
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final bytes = resp.bodyBytes;
        if (bytes.isNotEmpty) {
          final b64 = base64Encode(bytes);
          final updated = blog.copyWith(
            headerImageUrl: url,
            headerImageBase64: b64,
          );
          if (persist) await _cache.upsert(updated);
          return updated;
        }
      } else {
        logger.w('[REPO] image download failed url=$url status=${resp.statusCode}');
      }
    } catch (e, s) {
      logger.w('[REPO] image download error url=$url', error: e, stackTrace: s);
    }

    // At least persist the url so UI can load online
    final updated = blog.copyWith(headerImageUrl: url);
    if (persist) await _cache.upsert(updated);
    return updated;
  }

  Future<List<Blog>> _ensureHeaderImagesDownloaded(
    List<Blog> blogs, {
    bool persist = true,
  }) async {
    // Sequential to avoid too many parallel downloads.
    final out = <Blog>[];
    for (final b in blogs) {
      out.add(await _ensureHeaderImageDownloaded(b, persist: persist));
    }
    return out;
  }

  // ----------------------------
  // Public API
  // ----------------------------

  Future<Result<List<Blog>>> getBlogPosts({bool forceRefresh = false}) async {
    logger.i('[REPO] getBlogPosts(forceRefresh=$forceRefresh)');

    // 1) Cache path (if still fresh)
    try {
      if (!forceRefresh) {
        final lastSync = await _cache.getLastSync();
        logger.d('[REPO] cache lastSync=$lastSync');

        final cacheFresh = lastSync != null &&
            DateTime.now().difference(lastSync) < _minFetchInterval;

        if (cacheFresh) {
          logger.i('[REPO] cache fresh -> load from cache');
          final cached = await _cache.getAll();
          logger.i('[REPO] cache loaded count=${cached.length}');

          if (cached.isNotEmpty) {
            // Only ensure URL exists (no network download here)
            final migrated = await _migrateMissingHeaderUrls(cached, persist: true);

            _currentBlogs = migrated;
            _blogController.add(_currentBlogs);
            logger.d('[REPO] stream emit from cache count=${_currentBlogs.length}');
            return Success(migrated);
          }

          logger.w('[REPO] cache fresh but empty -> fallback to API');
        }
      }

      // 2) API path
      logger.i('[REPO] fetching blogs from API');
      final blogs = await _api.getBlogs();
      blogs.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      logger.i('[REPO] API fetched count=${blogs.length}');

      // Ensure fallback URL exists and download base64 where possible.
      // Persisting in cache is done by saveAll afterwards, so we can do persist:false here.
      final withUrl = await _migrateMissingHeaderUrls(blogs, persist: false);
      final enriched = await _ensureHeaderImagesDownloaded(withUrl, persist: false);

      await _cache.saveAll(enriched);
      logger.i('[REPO] cache saveAll done count=${enriched.length}');

      _currentBlogs = enriched;
      _blogController.add(_currentBlogs);
      logger.d('[REPO] stream emit from API count=${_currentBlogs.length}');

      // Flush pending ops (best-effort)
      logger.i('[REPO] sync flush start');
      await _sync.sync();
      logger.i('[REPO] sync flush done');

      return Success(enriched);
    } catch (e, s) {
      // 3) Offline/error fallback to cache
      if (_isOfflineError(e)) {
        logger.w('[REPO] offline -> fallback to cache', error: e, stackTrace: s);
      } else {
        logger.e('[REPO] getBlogPosts failed -> try cache fallback', error: e, stackTrace: s);
      }

      final cached = await _cache.getAll();
      logger.i('[REPO] cache loaded (fallback) count=${cached.length}');

      if (cached.isNotEmpty) {
        final migrated = await _migrateMissingHeaderUrls(cached, persist: true);

        _currentBlogs = migrated;
        _blogController.add(_currentBlogs);
        logger.d('[REPO] stream emit from cache count=${_currentBlogs.length}');
        return Success(migrated);
      }

      if (_isOfflineError(e)) return Failure(NetworkException());
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
        logger.e('[REPO] create failed (not offline) -> rethrow', error: e, stackTrace: s);
        rethrow;
      }

      logger.w('[REPO] offline -> enqueue create + optimistic insert', error: e, stackTrace: s);

      final tempId = 'local-${_uuid.v4()}';
      final opId = _uuid.v4();

      // Ensure we always have a header URL even for optimistic entries
      final headerUrl = (blog.headerImageUrl == null || blog.headerImageUrl!.isEmpty)
          ? _fallbackHeaderImageUrl(tempId)
          : blog.headerImageUrl;

      await _pendingOps.add(
        PendingOp(
          id: opId,
          type: PendingOpType.createBlog,
          blogId: tempId,
          createdAt: DateTime.now(),
          payload: {
            'title': blog.title,
            'content': blog.content ?? '',
            'headerImageUrl': headerUrl,
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
        headerImageUrl: headerUrl,
        headerImageBase64: blog.headerImageBase64, // optional if you have it
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
    required String blogId, // (dein Signature-Stand) – wird hier nicht gebraucht, aber bleibt kompatibel
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
        logger.e('[REPO] patch failed (not offline) -> rethrow', error: e, stackTrace: s);
        rethrow;
      }

      logger.w('[REPO] offline -> enqueue patch + optimistic update', error: e, stackTrace: s);

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
        logger.e('[REPO] delete failed (not offline) -> rethrow', error: e, stackTrace: s);
        rethrow;
      }

      logger.w('[REPO] offline -> enqueue delete + optimistic remove', error: e, stackTrace: s);

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
        logger.e('[REPO] like failed (not offline) -> rethrow', error: e, stackTrace: s);
        rethrow;
      }

      logger.w('[REPO] offline -> enqueue like + optimistic update', error: e, stackTrace: s);

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
      logger.w('[REPO] queued op=$opId type=setLike blogId=${blog.id} nextLiked=$nextLiked');

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

  // ----------------------------
  // Cache emit helpers
  // ----------------------------

  Future<void> _emitFromCache() async {
    final cached = await _cache.getAll();
    final migrated = await _migrateMissingHeaderUrls(cached, persist: true);

    _currentBlogs = migrated;
    _blogController.add(_currentBlogs);
    logger.d('[REPO] stream emit from cache count=${_currentBlogs.length}');
  }

  // ----------------------------
  // Local apply helpers
  // ----------------------------

  Blog _applyPatchLocally(Blog blog, {String? title, String? content}) {
    final nextContent = content ?? blog.content;
    final nextPreview = (content != null) ? content : blog.contentPreview;

    return blog.copyWith(
      title: title ?? blog.title,
      content: nextContent,
      contentPreview: nextPreview,
      lastUpdate: DateTime.now(),
      // headerImageUrl/headerImageBase64 bleiben unverändert
    );
  }

  Blog _applyLikeLocally(Blog blog, bool likedByMe) {
    final int newLikes = likedByMe ? blog.likes + 1 : (blog.likes - 1).clamp(0, 1 << 31);
    return blog.copyWith(
      isLikedByMe: likedByMe,
      likes: newLikes,
    );
  }

  // ----------------------------
  // Offline detection (web-safe)
  // ----------------------------

  bool _isOfflineError(Object e) {
    if (e is TimeoutException) return true;
    if (e is http.ClientException) return true;

    final msg = e.toString().toLowerCase();
    return msg.contains('failed to fetch') ||
        msg.contains('internet_disconnected') ||
        msg.contains('err_internet_disconnected') ||
        msg.contains('networkerror') ||
        msg.contains('connection closed') ||
        msg.contains('connection refused') ||
        msg.contains('socket') ||
        msg.contains('host lookup') ||
        msg.contains('dns');
  }
}
