import 'package:injectable/injectable.dart';
import 'package:sembast/sembast.dart';

import 'local_db.dart';
import 'pending_ops.dart';

@lazySingleton
class PendingOpsStore {
  static final _store = stringMapStoreFactory.store('pending_ops');

  Future<void> add(PendingOp op) async {
    final db = await LocalDb.instance();
    await _store.record(op.id).put(db, op.toMap());
  }

  Future<List<PendingOp>> getAllOldestFirst() async {
    final db = await LocalDb.instance();
    final records = await _store.find(db);

    final ops = records.map((r) => PendingOp.fromMap(r.value)).toList();
    ops.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return ops;
  }

  Future<void> remove(String id) async {
    final db = await LocalDb.instance();
    await _store.record(id).delete(db);
  }

  Future<void> clear() async {
    final db = await LocalDb.instance();
    await _store.delete(db);
  }
}
