import 'package:computing_blog/core/logger.util.dart';
import 'package:computing_blog/domain/models/blog.dart';
import 'package:injectable/injectable.dart';
import 'package:sembast/sembast.dart';

import 'local_db.dart';

@lazySingleton
class BlogCache {
  final logger = getLogger();

  static final _blogStore = stringMapStoreFactory.store('blogs');
  static final _metaStore = stringMapStoreFactory.store('meta');

  Future<void> saveAll(List<Blog> blogs) async {
    logger.i('[CACHE] saveAll start count=${blogs.length}');
    final db = await LocalDb.instance();

    await db.transaction((txn) async {
      await _blogStore.delete(txn);
      logger.d('[CACHE] saveAll cleared store');

      for (final blog in blogs) {
        logger.t('[CACHE] saveAll put id=${blog.id}');
        await _blogStore.record(blog.id).put(txn, blog.toCacheMap());
      }

      await _metaStore.record('lastSync').put(txn, {
        'value': DateTime.now().toIso8601String(),
      });
      logger.i('[CACHE] saveAll done (lastSync updated)');
    });
  }

  Future<List<Blog>> getAll() async {
    logger.d('[CACHE] getAll start');

    final db = await LocalDb.instance();
    final records = await _blogStore.find(db);
    logger.i('[CACHE] getAll loaded=${records.length}');

    final blogs = records.map((r) => Blog.fromCacheMap(r.value)).toList();

    blogs.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    logger.d('[CACHE] getAll done (sorted)');
    return blogs;
  }

  Future<void> upsert(Blog blog) async {
    logger.i('[CACHE] upsert id=${blog.id} title="${blog.title}"');

    final db = await LocalDb.instance();
    await _blogStore.record(blog.id).put(db, blog.toCacheMap());
    logger.d('[CACHE] upsert stored id=${blog.id}');

    await _metaStore.record('lastSync').put(db, {
      'value': DateTime.now().toIso8601String(),
    });
  }

  Future<void> removeById(String id) async {
    logger.w('[CACHE] removeById id=$id');

    final db = await LocalDb.instance();
    await _blogStore.record(id).delete(db);

    await _metaStore.record('lastSync').put(db, {
      'value': DateTime.now().toIso8601String(),
    });
  }

  Future<DateTime?> getLastSync() async {
    logger.t('[CACHE] getLastSync');

    final db = await LocalDb.instance();
    final meta = await _metaStore.record('lastSync').get(db);
    final raw = meta?['value']?.toString();
    if (raw == null) {
      logger.t('[CACHE] getLastSync -> null');
      return null;
    }

    final parsed = DateTime.tryParse(raw);
    logger.t('[CACHE] getLastSync -> $parsed');
    return parsed;
  }

  Future<void> clear() async {
    logger.w('[CACHE] clear start');
    final db = await LocalDb.instance();
    await _blogStore.delete(db);
    await _metaStore.delete(db);
    logger.w('[CACHE] clear done');
  }
}
