import 'dart:async';
import 'dart:convert';

import 'package:computing_blog/core/exceptions.dart';
import 'package:computing_blog/core/logger.util.dart';
import 'package:computing_blog/core/result.dart';
import 'package:computing_blog/data/api/blog_api.dart';
import 'package:computing_blog/domain/models/blog.dart';
import 'package:computing_blog/local/cache/blog_cache.dart';
import 'package:computing_blog/local/pending/pending_ops.dart';
import 'package:computing_blog/local/pending/pending_ops_store.dart';
import 'package:computing_blog/data/sync/sync_service.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';
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

  // Broadcast stream for UI
  final _blogController = StreamController<List<Blog>>.broadcast();
  Stream<List<Blog>> get blogStream => _blogController.stream;

  List<Blog> _currentBlogs = [];

  static const _writeFastFailTimeout = Duration(seconds: 6);

  static const _minFetchInterval = Duration(seconds: 60);

  // ---------------------------------------------------------------------------
  // Header image (fallback + cache)
  // ---------------------------------------------------------------------------

  /// Deterministic fallback so it stays stable across reloads.
  String _fallbackHeaderImageUrl(String blogId) =>
      'https://picsum.photos/seed/$blogId/800/450';

  Future<List<Blog>> _ensureHeaderUrlExists(
    List<Blog> blogs, {
    bool persist = true,
  }) async {
    final out = <Blog>[];

    for (final b in blogs) {
      final hasUrl = b.headerImageUrl != null && b.headerImageUrl!.isNotEmpty;
      if (hasUrl) {
        out.add(b);
        continue;
      }

      final updated = b.copyWith(headerImageUrl: _fallbackHeaderImageUrl(b.id));
      if (persist) await _cache.upsert(updated);
      out.add(updated);
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

    // Already have base64 -> only ensure URL is stored
    if (blog.headerImageBase64 != null && blog.headerImageBase64!.isNotEmpty) {
      if (url == blog.headerImageUrl) return blog;

      final updated = blog.copyWith(headerImageUrl: url);
      if (persist) await _cache.upsert(updated);
      return updated;
    }

    // Try download (best-effort; can fail on web due to CORS)
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final bytes = resp.bodyBytes;
        if (bytes.isNotEmpty) {
          final updated = blog.copyWith(
            headerImageUrl: url,
            headerImageBase64: base64Encode(bytes),
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

    // Persist URL at least
    final updated = blog.copyWith(headerImageUrl: url);
    if (persist) await _cache.upsert(updated);
    return updated;
  }

  Future<List<Blog>> _ensureHeaderImagesDownloaded(
    List<Blog> blogs, {
    bool persist = true,
  }) async {
    // sequential: avoid too many parallel requests
    final out = <Blog>[];
    for (final b in blogs) {
      out.add(await _ensureHeaderImageDownloaded(b, persist: persist));
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  Future<Result<List<Blog>>> getBlogPosts({bool forceRefresh = false}) async {
    logger.i('[REPO] getBlogPosts(forceRefresh=$forceRefresh)');

    try {
      if (!forceRefresh) {
        final cached = await _tryLoadFreshCache();
        if (cached != null && cached.isNotEmpty) {
          logger.i('[REPO] cache fresh -> emit');
          final migrated = await _ensureHeaderUrlExists(cached, persist: true);
          await _emit(migrated, source: 'cache');
          return Success(migrated);
        }
      }

      logger.i('[REPO] fetching blogs from API');
      final blogs = await _api.getBlogs();
      blogs.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      logger.i('[REPO] API fetched count=${blogs.length}');

      final withUrl = await _ensureHeaderUrlExists(blogs, persist: false);
      final enriched = await _ensureHeaderImagesDownloaded(withUrl, persist: false);

      await _cache.saveAll(enriched);
      logger.i('[REPO] cache saveAll done count=${enriched.length}');

      await _emit(enriched, source: 'api');

      await _syncSafe();

      return Success(enriched);
    } catch (e, s) {
      if (_isOfflineError(e)) {
        logger.w('[REPO] offline -> fallback to cache', error: e, stackTrace: s);
      } else {
        logger.e('[REPO] getBlogPosts failed -> try cache fallback', error: e, stackTrace: s);
      }

      final cached = await _cache.getAll();
      logger.i('[REPO] cache loaded (fallback) count=${cached.length}');

      if (cached.isNotEmpty) {
        final migrated = await _ensureHeaderUrlExists(cached, persist: true);
        await _emit(migrated, source: 'cache-fallback');
        return Success(migrated);
      }

      return _isOfflineError(e) ? Failure(NetworkException()) : Failure(ServerException(e.toString()));
    }
  }

  Future<void> addBlogPost(Blog blog) async {
    logger.i('[REPO] addBlogPost title="${blog.title}"');

    await _onlineOrOffline(
      online: () async {
        await _api
            .addBlog(
              title: blog.title,
              content: blog.content ?? '',
              headerImageUrl: blog.headerImageUrl,
            ).timeout(_writeFastFailTimeout);

        logger.i('[REPO] create online -> refresh');
        await _refreshAndSync();
      },
      offline: () async {
        final tempId = 'local-${_uuid.v4()}';
        final headerUrl = _ensureOptimisticHeaderUrl(blog, tempId);

        await _queueOp(
          type: PendingOpType.createBlog,
          blogId: tempId,
          payload: {
            'title': blog.title,
            'content': blog.content ?? '',
            'headerImageUrl': headerUrl,
            'author': blog.author,
          },
        );

        final optimistic = Blog(
          id: tempId,
          author: blog.author,
          title: blog.title,
          content: blog.content,
          contentPreview: blog.contentPreview ?? blog.content,
          publishedAt: DateTime.now(),
          lastUpdate: DateTime.now(),
          headerImageUrl: headerUrl,
          headerImageBase64: blog.headerImageBase64,
          createdByMe: true,
          isLikedByMe: false,
          likes: 0,
          comments: blog.comments,
          userIdsWithLikes: blog.userIdsWithLikes,
        );

        await _optimisticUpsert(optimistic);
      },
    );
  }

  Future<void> updateBlogPost(
    String id, {
    required String blogId, // bleibt kompatibel (wird nicht genutzt)
    required String title,
    required String content,
  }) async {
    logger.i('[REPO] updateBlogPost blogId=$id');

    await _onlineOrOffline(
      online: () async {
        await _api
            .patchBlog(blogId: id, title: title, content: content).timeout(_writeFastFailTimeout);

        logger.i('[REPO] patch online -> refresh');
        await _refreshAndSync();
      },
      offline: () async {
        await _queueOp(
          type: PendingOpType.patchBlog,
          blogId: id,
          payload: {'title': title, 'content': content},
        );

        final cached = await _cache.getAll();
        final idx = cached.indexWhere((b) => b.id == id);

        if (idx == -1) {
          logger.w('[REPO] optimistic patch skipped -> not in cache blogId=$id');
        } else {
          final updated = _applyPatchLocally(cached[idx], title: title, content: content);
          await _cache.upsert(updated);
          logger.i('[REPO] optimistic patched in cache blogId=$id');
        }

        await _emitFromCache();
      },
    );
  }

  Future<void> deleteBlogPost(String blogId) async {
    logger.i('[REPO] deleteBlogPost blogId=$blogId');

    await _onlineOrOffline(
      online: () async {
        await _api.deleteBlog(blogId: blogId).timeout(_writeFastFailTimeout);

        logger.i('[REPO] delete online -> refresh');
        await _refreshAndSync();
      },
      offline: () async {
        await _queueOp(
          type: PendingOpType.deleteBlog,
          blogId: blogId,
        );

        await _cache.removeById(blogId);
        logger.i('[REPO] optimistic removed from cache blogId=$blogId');
        await _emitFromCache();
      },
    );
  }

  Future<void> toggleLike(Blog blog) async {
    logger.i(
      '[REPO] toggleLike blogId=${blog.id} currentLiked=${blog.isLikedByMe} likes=${blog.likes}',
    );

    final nextLiked = !blog.isLikedByMe;

    await _onlineOrOffline(
      online: () async {
        await _api
            .setLike(blogId: blog.id, likedByMe: nextLiked).timeout(_writeFastFailTimeout);

        logger.i('[REPO] like online -> refresh');
        await _refreshAndSync();
      },
      offline: () async {
        await _queueOp(
          type: PendingOpType.setLike,
          blogId: blog.id,
          payload: {'likedByMe': nextLiked},
        );

        final updated = _applyLikeLocally(blog, nextLiked);
        await _cache.upsert(updated);

        logger.i(
          '[REPO] optimistic like cached blogId=${blog.id} likedByMe=${updated.isLikedByMe} likes=${updated.likes}',
        );
        await _emitFromCache();
      },
    );
  }

  void dispose() {
    logger.i('[REPO] disposed');
    _blogController.close();
  }

  // ---------------------------------------------------------------------------
  // Small flow helpers
  // ---------------------------------------------------------------------------

  Future<void> _refreshAndSync() async {
    await getBlogPosts(forceRefresh: true);
    await _syncSafe();
  }

  Future<void> _syncSafe() async {
    try {
      logger.i('[REPO] sync flush start');
      await _sync.sync();
      logger.i('[REPO] sync flush done');
    } catch (e, s) {
      // best-effort: don't fail UI flows due to sync
      logger.w('[REPO] sync flush failed (ignored)', error: e, stackTrace: s);
    }
  }

  Future<void> _onlineOrOffline({
    required Future<void> Function() online,
    required Future<void> Function() offline,
  }) async {
    try {
      await online();
    } catch (e, s) {
      if (!_isOfflineError(e)) {
        logger.e('[REPO] operation failed (not offline) -> rethrow', error: e, stackTrace: s);
        rethrow;
      }

      logger.w('[REPO] offline -> fallback', error: e, stackTrace: s);
      await offline();
    }
  }

  Future<void> _queueOp({
    required PendingOpType type,
    required String blogId,
    Map<String, dynamic>? payload,
  }) async {
    final opId = _uuid.v4();

    await _pendingOps.add(
      PendingOp(
        id: opId,
        type: type,
        blogId: blogId,
        createdAt: DateTime.now(),
        payload: payload,
      ),
    );

    logger.w('[REPO] queued op=$opId type=$type blogId=$blogId payloadKeys=${payload?.keys.toList() ?? []}');
  }

  Future<void> _optimisticUpsert(Blog blog) async {
    await _cache.upsert(blog);
    logger.i('[REPO] optimistic cached blogId=${blog.id}');
    await _emitFromCache();
  }

  String _ensureOptimisticHeaderUrl(Blog blog, String idForFallback) {
    final hasUrl = blog.headerImageUrl != null && blog.headerImageUrl!.isNotEmpty;
    return hasUrl ? blog.headerImageUrl! : _fallbackHeaderImageUrl(idForFallback);
  }

  // ---------------------------------------------------------------------------
  // Cache emit helpers
  // ---------------------------------------------------------------------------

  Future<List<Blog>?> _tryLoadFreshCache() async {
    final lastSync = await _cache.getLastSync();
    logger.d('[REPO] cache lastSync=$lastSync');

    final cacheFresh = lastSync != null &&
        DateTime.now().difference(lastSync) < _minFetchInterval;

    if (!cacheFresh) return null;

    final cached = await _cache.getAll();
    logger.i('[REPO] cache loaded count=${cached.length}');
    return cached;
  }

  Future<void> _emitFromCache() async {
    final cached = await _cache.getAll();
    final migrated = await _ensureHeaderUrlExists(cached, persist: true);
    await _emit(migrated, source: 'cache');
  }

  Future<void> _emit(List<Blog> blogs, {required String source}) async {
    _currentBlogs = blogs;
    _blogController.add(_currentBlogs);
    logger.d('[REPO] stream emit source=$source count=${_currentBlogs.length}');
  }

  // ---------------------------------------------------------------------------
  // Local apply helpers
  // ---------------------------------------------------------------------------

  Blog _applyPatchLocally(Blog blog, {String? title, String? content}) {
    final nextContent = content ?? blog.content;
    final nextPreview = (content != null) ? content : blog.contentPreview;

    return blog.copyWith(
      title: title ?? blog.title,
      content: nextContent,
      contentPreview: nextPreview,
      lastUpdate: DateTime.now(),
    );
  }

  Blog _applyLikeLocally(Blog blog, bool likedByMe) {
    final newLikes = likedByMe
        ? blog.likes + 1
        : (blog.likes - 1).clamp(0, 1 << 31);

    return blog.copyWith(
      isLikedByMe: likedByMe,
      likes: newLikes,
    );
  }

  // ---------------------------------------------------------------------------
  // Offline detection (web-safe)
  // ---------------------------------------------------------------------------

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
