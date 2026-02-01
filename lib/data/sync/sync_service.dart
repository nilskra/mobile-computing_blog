import 'dart:io';
import 'package:computing_blog/core/logger.util.dart';
import 'package:injectable/injectable.dart';

import '../api/blog_api.dart';
import '../../domain/models/blog.dart';
import '../../local/cache/blog_cache.dart';
import '../../local/pending/pending_ops_store.dart';
import '../../local/pending/pending_ops.dart';

@lazySingleton
class SyncService {
  SyncService(this._api, this._pending, this._cache);

  final BlogApi _api;
  final PendingOpsStore _pending;
  final BlogCache _cache;
  final logger = getLogger();

  bool _isSyncing = false;

  /// Flush queued ops. Safe to call often.
  Future<void> sync() async {
    if (_isSyncing) return;
    _isSyncing = true;
    logger.i('[SYNC] start');

    try {
      final ops = await _pending.getAllOldestFirst();
      if (ops.isEmpty) return;
      logger.i('[SYNC] loaded ops=${ops.length}');
      if (ops.isEmpty) {
        logger.i('[SYNC] nothing to do');
        return;
      }

      for (final op in ops) {
        logger.i(
          '[SYNC] op start id=${op.id} type=${op.type.name} blogId=${op.blogId}',
        );
        try {
          switch (op.type) {
            case PendingOpType.patchBlog:
              logger.d(
                '[SYNC] patchBlog blogId=${op.blogId} titleLen=${(op.payload?['title'] as String?)?.length} contentLen=${(op.payload?['content'] as String?)?.length}',
              );
              await _api.patchBlog(
                blogId: op.blogId,
                title: op.payload?['title'] as String?,
                content: op.payload?['content'] as String?,
              );
              break;

            case PendingOpType.deleteBlog:
              logger.d('[SYNC] deleteBlog blogId=${op.blogId}');
              await _api.deleteBlog(blogId: op.blogId);
              break;

            case PendingOpType.setLike:
              logger.d(
                '[SYNC] setLike blogId=${op.blogId} likedByMe=${(op.payload?['likedByMe'] as bool?) ?? false}',
              );

              await _api.setLike(
                blogId: op.blogId,
                likedByMe: (op.payload?['likedByMe'] as bool?) ?? false
              );
              break;
            case PendingOpType.createBlog:
              logger.d(
                '[SYNC] createBlog tempId=${op.blogId} titleLen=${(op.payload?['title'] as String?)?.length}',
              );

              final created = await _api.addBlog(
                title: (op.payload?['title'] as String?) ?? '',
                content: (op.payload?['content'] as String?) ?? '',
                headerImageUrl: op.payload?['headerImageUrl'] as String?,
              );

              // tempId ist op.blogId → diesen lokalen Blog entfernen und echten speichern
              await _cache.removeById(op.blogId);
              await _cache.upsert(created);
              break;
          }

          // ✅ Erfolgreich → aus Queue entfernen
          logger.i('[SYNC] op success -> removing from queue id=${op.id}');
          await _pending.remove(op.id);
          logger.d('[SYNC] removed id=${op.id}');
        } on SocketException catch (e) {
          logger.w(
            '[SYNC] offline during op id=${op.id} type=${op.type.name} -> stop sync',
            error: e,
          );
          break;
        }
      }

      // Optional: danach einmal “Source of truth” ziehen
      // (wenn online und alles ok)
      try {
        logger.i('[SYNC] refresh from API (source of truth)');
        final blogs = await _api.getBlogs();
        blogs.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
        await _cache.saveAll(blogs);
        logger.i('[SYNC] refresh done -> cache updated count=${blogs.length}');
      } catch (e) {
        logger.w('[SYNC] refresh failed (non critical): $e');
      }
    } finally {
      logger.i('[SYNC] done');
      _isSyncing = false;
    }
  }
}
