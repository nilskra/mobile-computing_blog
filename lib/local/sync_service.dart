import 'dart:io';
import 'package:injectable/injectable.dart';

import '../data/api/blog_api.dart';
import '../domain/models/blog.dart';
import '../local/blog_cache.dart';
import '../local/pending_ops_store.dart';
import '../local/pending_ops.dart';

@lazySingleton
class SyncService {
  SyncService(this._api, this._pending, this._cache);

  final BlogApi _api;
  final PendingOpsStore _pending;
  final BlogCache _cache;

  bool _isSyncing = false;

  /// Flush queued ops. Safe to call often.
  Future<void> sync() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final ops = await _pending.getAllOldestFirst();
      if (ops.isEmpty) return;

      for (final op in ops) {
        try {
          switch (op.type) {
            case PendingOpType.patchBlog:
              await _api.patchBlog(
                blogId: op.blogId,
                title: op.payload?['title'] as String?,
                content: op.payload?['content'] as String?,
              );
              break;

            case PendingOpType.deleteBlog:
              await _api.deleteBlog(blogId: op.blogId);
              break;

            case PendingOpType.setLike:
              await _api.setLike(
                blogId: op.blogId,
                likedByMe: (op.payload?['likedByMe'] as bool?) ?? false,
              );
              break;
            case PendingOpType.createBlog:
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
          await _pending.remove(op.id);
        } on SocketException {
          // noch offline → abbrechen, später erneut
          break;
        }
      }

      // Optional: danach einmal “Source of truth” ziehen
      // (wenn online und alles ok)
      try {
        final blogs = await _api.getBlogs();
        blogs.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
        await _cache.saveAll(blogs);
      } catch (_) {
        // nicht kritisch
      }
    } finally {
      _isSyncing = false;
    }
  }
}
