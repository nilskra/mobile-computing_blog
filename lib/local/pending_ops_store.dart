import 'package:computing_blog/core/logger.util.dart';
import 'package:injectable/injectable.dart';
import 'package:sembast/sembast.dart';

import 'local_db.dart';
import 'pending_ops.dart';

@lazySingleton
class PendingOpsStore {
  static final _store = stringMapStoreFactory.store('pending_ops');
  final logger = getLogger();

  Future<void> add(PendingOp op) async {
    final db = await LocalDb.instance();
    logger.w(
      '[PENDING] add id=${op.id} type=${op.type.name} blogId=${op.blogId} '
      'payloadKeys=${op.payload?.keys.toList()}',
    );
    await _store.record(op.id).put(db, op.toMap());
    logger.d('[PENDING] add stored id=${op.id}');
  }

  Future<List<PendingOp>> getAllOldestFirst() async {
    logger.d('[PENDING] getAllOldestFirst start');
    final db = await LocalDb.instance();
    final records = await _store.find(db);
    logger.i('[PENDING] getAllOldestFirst loaded=${records.length}');

    final ops = records.map((r) => PendingOp.fromMap(r.value)).toList();
    ops.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (ops.isNotEmpty) {
      logger.d(
        '[PENDING] oldest=${ops.first.createdAt.toIso8601String()} newest=${ops.last.createdAt.toIso8601String()}',
      );
    }
    return ops;
  }

  Future<void> remove(String id) async {
    final db = await LocalDb.instance();
    logger.i('[PENDING] remove id=$id');
    await _store.record(id).delete(db);
  }

  Future<void> clear() async {
    final db = await LocalDb.instance();
    logger.w('[PENDING] clear');
    await _store.delete(db);
  }
}
