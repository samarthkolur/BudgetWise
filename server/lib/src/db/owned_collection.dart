import 'package:mongo_dart/mongo_dart.dart';

/// A collection that can only be queried on behalf of one owner.
///
/// **This class is the replacement for row-level security, and it is the most
/// important file in the server.**
///
/// Under Postgres, RLS applied `user_id = auth.uid()` to every statement in the
/// database itself. A developer who forgot a filter got no rows; a developer who
/// wrote a deliberately broad query still got no rows. That safety net does not
/// exist in MongoDB — an unfiltered `find()` returns every user's documents, and
/// nothing anywhere complains.
///
/// So the filter is moved into the type system instead. An [OwnedCollection] is
/// constructed with an owner and injects `ownerId` into every read, write and
/// delete it performs. Application code never assembles a raw filter, and the
/// owner comes from the verified access token — never from the request body,
/// which the caller controls.
///
/// The rules that make this hold:
///
/// 1. **Route handlers never touch `DbCollection` directly.** They receive an
///    [OwnedCollection] built from the authenticated principal.
/// 2. **`ownerId` is stamped on insert**, overwriting whatever the client sent,
///    so a forged `ownerId` in a request body is discarded rather than trusted.
/// 3. **Cross-parent writes are checked explicitly.** Postgres had composite
///    foreign keys — `(budget_id, user_id) references budgets (id, user_id)` —
///    which made attaching your own row to someone else's budget impossible.
///    Mongo has no foreign keys, so [owns] performs that check by hand,
///    and the test suite has a case for exactly that attack.
class OwnedCollection {
  const OwnedCollection(this._collection, this.ownerId);

  final DbCollection _collection;
  final ObjectId ownerId;

  /// Merges the caller's filter with the owner scope.
  ///
  /// Owner is applied last so a filter carrying its own `ownerId` cannot
  /// override it. That ordering is **defence in depth, not the live defence**:
  /// no route today passes a caller-controlled map here — handlers extract
  /// typed fields from the body and build filters themselves — so reversing
  /// these two lines currently changes nothing observable, and the test suite
  /// does not catch it. Verified by doing exactly that and watching every test
  /// still pass.
  ///
  /// It stays this way round because the day someone does forward a raw filter,
  /// this ordering is what makes that harmless. The defences that *are* live and
  /// tested are [owns] and the explicit field extraction in the route layer.
  Map<String, dynamic> scoped([Map<String, dynamic>? filter]) => {
    ...?filter,
    'ownerId': ownerId,
  };

  /// Reads the owner's matching documents.
  ///
  /// Uses `modernFind` rather than `find`. The legacy `{$query, $orderby}`
  /// wrapper that `find` accepts was removed in MongoDB 4.2 and now fails with
  /// "unknown top level operator: $query" — sorting has to go through the
  /// dedicated parameter instead.
  Future<List<Map<String, dynamic>>> find({
    Map<String, dynamic>? where,
    Map<String, Object>? sort,
    int? limit,
  }) => _collection
      .modernFind(filter: scoped(where), sort: sort, limit: limit)
      .toList();

  Future<Map<String, dynamic>?> findOne([Map<String, dynamic>? where]) =>
      _collection.findOne(scoped(where));

  Future<Map<String, dynamic>?> findById(ObjectId id) =>
      _collection.findOne(scoped({'_id': id}));

  Future<int> count([Map<String, dynamic>? where]) =>
      _collection.count(scoped(where));

  /// Inserts, stamping ownership and timestamps.
  ///
  /// Any `ownerId` in [document] is replaced, not merged — the client does not
  /// get a say in who owns what it creates.
  Future<Map<String, dynamic>> insert(Map<String, dynamic> document) async {
    final now = DateTime.now().toUtc();
    final record = <String, dynamic>{
      ...document,
      'ownerId': ownerId,
      'createdAt': document['createdAt'] ?? now,
      'updatedAt': now,
    };
    await _collection.insertOne(record);
    return record;
  }

  Future<void> insertMany(List<Map<String, dynamic>> documents) async {
    if (documents.isEmpty) return;
    final now = DateTime.now().toUtc();
    await _collection.insertMany([
      for (final document in documents)
        {...document, 'ownerId': ownerId, 'createdAt': now, 'updatedAt': now},
    ]);
  }

  /// Updates by id. Returns null when the document does not exist *or* belongs
  /// to somebody else — the two are deliberately indistinguishable to the
  /// caller, exactly as they were under RLS.
  Future<Map<String, dynamic>?> updateById(
    ObjectId id,
    Map<String, dynamic> changes,
  ) async {
    final existing = await findById(id);
    if (existing == null) return null;

    // ownerId and _id are never client-writable, whatever the caller sent.
    final safe = Map<String, dynamic>.from(changes)
      ..remove('ownerId')
      ..remove('_id')
      ..remove('createdAt');

    await _collection.updateOne(scoped({'_id': id}), {
      r'$set': {...safe, 'updatedAt': DateTime.now().toUtc()},
    });
    return findById(id);
  }

  Future<bool> deleteById(ObjectId id) async {
    final result = await _collection.deleteOne(scoped({'_id': id}));
    return result.nRemoved > 0;
  }

  Future<int> deleteWhere(Map<String, dynamic> filter) async {
    final result = await _collection.deleteMany(scoped(filter));
    return result.nRemoved;
  }

  /// Sums a numeric field across the owner's matching documents.
  Future<int> sum(String field, [Map<String, dynamic>? where]) async {
    final pipeline = <Map<String, Object>>[
      {r'$match': scoped(where)},
      {
        r'$group': {
          '_id': null,
          'total': {r'$sum': '\$$field'},
        },
      },
    ];
    final result = await _collection.aggregateToStream(pipeline).toList();
    if (result.isEmpty) return 0;
    return (result.first['total'] as num?)?.toInt() ?? 0;
  }

  /// Confirms the owner actually owns [id], for cross-collection writes.
  ///
  /// This is the composite-foreign-key check, done by hand. Adding an expense
  /// requires both a budget and a category; without this, a caller could pass
  /// another user's budgetId and — because their own `ownerId` is stamped on the
  /// new row — create a document that looks perfectly legitimate while pointing
  /// into someone else's month.
  Future<bool> owns(ObjectId id) async => await findById(id) != null;
}

/// Raised when a request references a parent the caller does not own.
///
/// Reported as 404 rather than 403: telling an attacker "that exists but is not
/// yours" confirms the id is real, which is a slow enumeration oracle.
class NotOwnedException implements Exception {
  const NotOwnedException(this.what);
  final String what;

  @override
  String toString() => 'NotOwnedException($what)';
}
