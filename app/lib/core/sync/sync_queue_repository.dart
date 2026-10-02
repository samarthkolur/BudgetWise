import 'dart:convert';

import 'package:budgetwise/core/db/local_database.dart';
import 'package:uuid/uuid.dart';

/// One write that couldn't reach the server, waiting to be replayed.
///
/// [payload] is the exact body the matching `Api*Repository` method would
/// have sent — replaying a queued item is "call that method again with this
/// map", not a second wire format to keep in step with the first.
class PendingSyncItem {
  const PendingSyncItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.createdAt,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String operation;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
}

/// The offline-write outbox. See `pending_sync` in `core/db/local_database.dart`
/// for why it exists and how it's replayed.
class SyncQueueRepository {
  SyncQueueRepository(this._dbFuture);

  final Future<LocalDatabase> _dbFuture;

  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    final db = (await _dbFuture).db;
    await db.insert('pending_sync', {
      'id': const Uuid().v4(),
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': operation,
      'payload_json': jsonEncode(payload),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Oldest first — operations must replay in the order they happened, since
  /// a later update or delete can target a row an earlier queued create made.
  Future<List<PendingSyncItem>> all() async {
    final db = (await _dbFuture).db;
    final rows = await db.query('pending_sync', orderBy: 'created_at ASC');
    return rows
        .map(
          (row) => PendingSyncItem(
            id: row['id']! as String,
            entityType: row['entity_type']! as String,
            entityId: row['entity_id']! as String,
            operation: row['operation']! as String,
            payload:
                jsonDecode(row['payload_json']! as String)
                    as Map<String, dynamic>,
            createdAt: DateTime.parse(row['created_at']! as String),
          ),
        )
        .toList();
  }

  Future<int> count() async {
    final db = (await _dbFuture).db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM pending_sync',
    );
    return result.first['cnt']! as int;
  }

  Future<void> remove(String id) async {
    final db = (await _dbFuture).db;
    await db.delete('pending_sync', where: 'id = ?', whereArgs: [id]);
  }
}
