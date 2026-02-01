import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast_web/sembast_web.dart';

class LocalDb {
  static Database? _database;

  static Future<Database> instance() async {
    if (_database != null) return _database!;

    final DatabaseFactory factory =
        kIsWeb ? databaseFactoryWeb : databaseFactoryIo;

    final String dbPath = kIsWeb
        ? 'blog_app.db'
        : p.join(
            (await getApplicationDocumentsDirectory()).path,
            'blog_app.db',
          );

    _database = await factory.openDatabase(dbPath);
    return _database!;
  }
}
