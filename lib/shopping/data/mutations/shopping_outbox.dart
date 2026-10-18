import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/shopping_mutation.dart';

class ShoppingOutboxEntry {
  const ShoppingOutboxEntry(
    this.request,
    this.status,
    this.resultJson,
    this.noticeAcknowledged,
  );
  final ShoppingMutationRequest request;
  final ShoppingMutationStatus status;
  final String? resultJson;
  final bool noticeAcknowledged;
}

/// A local transaction commits before UI acceptance. Firestore is transport, not
/// the sole journal: rule rejection must not erase an accepted offline intention.
class ShoppingOutbox {
  ShoppingOutbox(this.database);
  final Database database;
  static const maxPending = 100;

  static Future<ShoppingOutbox> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final location =
        path ?? '${await f.getDatabasesPath()}/shopping-outbox-v1.db';
    final db = await f.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA synchronous = FULL');
        },
        onCreate: (db, _) async {
          await db.execute('''CREATE TABLE mutations (
          sequence INTEGER PRIMARY KEY AUTOINCREMENT,
          uid TEXT NOT NULL,
          id TEXT NOT NULL,
          request TEXT NOT NULL,
          status TEXT NOT NULL,
          result TEXT,
          terminal INTEGER NOT NULL DEFAULT 0,
          noticeAcknowledged INTEGER NOT NULL DEFAULT 0,
          UNIQUE(uid, id))''');
          await db.execute(
            'CREATE INDEX pending_uid ON mutations(uid, terminal, sequence)',
          );
          await db.execute(
            '''CREATE TABLE contexts (
          uid TEXT PRIMARY KEY, householdId TEXT NOT NULL, epoch TEXT NOT NULL)''',
          );
        },
      ),
    );
    return ShoppingOutbox(db);
  }

  Future<void> enqueue(ShoppingMutationRequest request) async {
    final encoded = jsonEncode(request.toJson());
    await database.transaction((tx) async {
      final existing = await tx.query(
        'mutations',
        columns: ['request'],
        where: 'uid = ? AND id = ?',
        whereArgs: [request.context.uid, request.mutationId],
      );
      if (existing.isNotEmpty) {
        if (existing.single['request'] != encoded) {
          throw StateError('Mutation identity conflict');
        }
        return;
      }
      final count = Sqflite.firstIntValue(
        await tx.rawQuery(
          'SELECT COUNT(*) FROM mutations WHERE uid = ? AND terminal = 0',
          [request.context.uid],
        ),
      )!;
      if (count >= maxPending) throw StateError('Shopping queue full');
      await tx.insert('mutations', {
        'uid': request.context.uid,
        'id': request.mutationId,
        'request': encoded,
        'status': 'PENDING',
      });
    });
  }

  Future<List<ShoppingOutboxEntry>> entries(
    String uid, {
    bool includeTerminal = false,
  }) async {
    final rows = await database.query(
      'mutations',
      where: includeTerminal ? 'uid = ?' : 'uid = ? AND terminal = 0',
      whereArgs: [uid],
      orderBy: 'sequence',
      limit: includeTerminal ? 200 : maxPending,
    );
    return rows
        .map(
          (r) => ShoppingOutboxEntry(
            ShoppingMutationRequest.restore(
              Map<String, Object?>.from(
                jsonDecode(r['request'] as String) as Map,
              ),
            ),
            ShoppingMutationStatusContract.parse(r['status'] as String),
            r['result'] as String?,
            r['noticeAcknowledged'] == 1,
          ),
        )
        .toList();
  }

  Future<void> recordResult(
    String uid,
    String id,
    ShoppingMutationStatus status, {
    String? resultJson,
  }) => database.transaction((tx) async {
    final rows = await tx.query(
      'mutations',
      columns: ['terminal'],
      where: 'uid = ? AND id = ?',
      whereArgs: [uid, id],
    );
    if (rows.isEmpty) throw StateError('Unknown local mutation');
    // Late transport callbacks cannot turn a terminal result back into pending.
    if (rows.single['terminal'] == 1) return;
    await tx.update(
      'mutations',
      {
        'status': status.wire,
        'terminal': status.terminal ? 1 : 0,
        'result': resultJson,
        'noticeAcknowledged': status == ShoppingMutationStatus.applied ? 1 : 0,
      },
      where: 'uid = ? AND id = ?',
      whereArgs: [uid, id],
    );
  });

  Future<void> acknowledgeNotice(String uid, String id) async {
    await database.update(
      'mutations',
      {'noticeAcknowledged': 1},
      where: 'uid = ? AND id = ? AND terminal = 1',
      whereArgs: [uid, id],
    );
  }

  /// Explicit bounded notice pagination; old terminal successes cannot hide new
  /// conflicts behind a limit on the mixed pending/terminal journal.
  Future<List<ShoppingOutboxEntry>> notices(
    String uid, {
    int limit = 20,
  }) async {
    if (limit < 1 || limit > 100) throw ArgumentError.value(limit);
    final rows = await database.query(
      'mutations',
      where: 'uid = ? AND terminal = 1 AND noticeAcknowledged = 0',
      whereArgs: [uid],
      orderBy: 'sequence',
      limit: limit,
    );
    return rows
        .map(
          (r) => ShoppingOutboxEntry(
            ShoppingMutationRequest.restore(
              Map<String, Object?>.from(
                jsonDecode(r['request'] as String) as Map,
              ),
            ),
            ShoppingMutationStatusContract.parse(r['status'] as String),
            r['result'] as String?,
            false,
          ),
        )
        .toList();
  }

  Future<void> saveContext(ShoppingMutationContext context) async {
    await database.insert('contexts', {
      'uid': context.uid,
      'householdId': context.householdId,
      'epoch': context.epoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<ShoppingMutationContext?> readContext(String uid) async {
    final rows = await database.query(
      'contexts',
      where: 'uid = ?',
      whereArgs: [uid],
    );
    if (rows.isEmpty) return null;
    return ShoppingMutationContext(
      uid: uid,
      householdId: rows.single['householdId'] as String,
      epoch: rows.single['epoch'] as String,
    );
  }

  Future<void> clearContext(String uid) async {
    await database.delete('contexts', where: 'uid = ?', whereArgs: [uid]);
  }

  /// Only acknowledged terminal outcomes beyond server retention can be removed.
  /// A missing old receipt is never grounds for generating a replacement action.
  Future<void> prune(String uid, DateTime now) async {
    final cutoff = now.subtract(const Duration(days: 7)).millisecondsSinceEpoch;
    await database.delete(
      'mutations',
      where:
          'uid = ? AND terminal = 1 AND noticeAcknowledged = 1 '
          'AND CAST(substr(id, 1, 13) AS INTEGER) <= ?',
      whereArgs: [uid, cutoff],
    );
  }

  Future<void> close() => database.close();
}
