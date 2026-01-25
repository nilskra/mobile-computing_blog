import 'package:computing_blog/domain/models/blog.dart';
import 'package:injectable/injectable.dart';
import 'package:sembast/sembast.dart';

import 'local_db.dart';

@lazySingleton
class BlogCache {
  static final _blogStore = stringMapStoreFactory.store('blogs');
  static final _metaStore = stringMapStoreFactory.store('meta');

  Future<void> saveAll(List<Blog> blogs) async {
    final db = await LocalDb.instance();

    await db.transaction((txn) async {
      // Store leeren
      await _blogStore.delete(txn);

      // Neu schreiben
      for (final blog in blogs) {
        await _blogStore.record(blog.id).put(txn, blog.toCacheMap());
      }

      // lastSync speichern
      await _metaStore.record('lastSync').put(txn, {
        'value': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<List<Blog>> getAll() async {
    final db = await LocalDb.instance();
    final records = await _blogStore.find(db);

    final blogs = records
        .map((r) => Blog.fromCacheMap(r.value))
        .toList();

    blogs.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return blogs;
  }

  Future<void> upsert(Blog blog) async {
  final db = await LocalDb.instance();
  await _blogStore.record(blog.id).put(db, blog.toCacheMap());

  await _metaStore.record('lastSync').put(db, {
    'value': DateTime.now().toIso8601String(),
  });
}

Future<void> removeById(String id) async {
  final db = await LocalDb.instance();
  await _blogStore.record(id).delete(db);

  await _metaStore.record('lastSync').put(db, {
    'value': DateTime.now().toIso8601String(),
  });
}

  Future<DateTime?> getLastSync() async {
    final db = await LocalDb.instance();
    final meta = await _metaStore.record('lastSync').get(db);
    final raw = meta?['value']?.toString();
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> clear() async {
    final db = await LocalDb.instance();
    await _blogStore.delete(db);
    await _metaStore.delete(db);
  }
}
