import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' hide Query;
import 'package:simsplit/data/database/app_database.dart';

typedef _Doc = DocumentSnapshot<Map<String, dynamic>>;

/// Pulls every group the account belongs to from Firestore into Drift and
/// keeps it up to date in real time (AC15, AC18b).
///
/// One listener watches the account's groups. Each group gets one listener
/// per subcollection, filtered on `updatedAt` after the last change pulled,
/// so a restart reads only what changed meanwhile. A remote record replaces
/// the local one as a whole: the last write to reach the server wins
/// (AC17). Records with changes still in the outbox are skipped: those
/// changes are about to overwrite the server, and the listener delivers the
/// result once they do. Pulled changes go straight into Drift and are never
/// recorded for push.
///
/// Snapshots are applied one at a time, in arrival order. Members are
/// pulled before a group's expenses and settlements, which reference them;
/// a record whose members have not arrived yet waits for them.
class FirestoreSyncPuller {
  FirestoreSyncPuller({
    required AppDatabase database,
    required FirebaseFirestore firestore,
    this.retryDelay = const Duration(seconds: 30),
    void Function(String message)? log,
  })  : _db = database,
        _firestore = firestore,
        _log = log ?? _noLog;

  /// How long to wait before listening again after the groups listener
  /// failed (e.g. a network or server error).
  final Duration retryDelay;

  final AppDatabase _db;
  final FirebaseFirestore _firestore;
  final void Function(String message) _log;

  static void _noLog(String message) {}

  /// Sync-state keys: `pulled:<group>` marks a group that was pulled, and
  /// `pull:<group>:<collection>` holds the newest `updatedAt` pulled, in
  /// epoch microseconds (Firestore's precision).
  static String _pulledKey(String groupId) => 'pulled:$groupId';
  static String _cursorKey(String groupId, String collection) =>
      'pull:$groupId:$collection';

  String? _uid;

  /// Bumped on every start and stop, so work queued for an earlier session
  /// never runs in a later one.
  int _session = 0;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _groupsSub;
  bool _awaitingFirstGroups = true;
  final _groups = <String, _GroupPull>{};
  Future<void> _queue = Future.value();
  Timer? _retry;

  bool get isRunning => _uid != null;

  /// Starts pulling the groups of [uid].
  void start(String uid) {
    if (_uid == uid) return;
    if (_uid != null) unawaited(stop());
    _uid = uid;
    _session++;
    _listenToGroups();
  }

  /// Stops pulling, after the snapshot being applied (if any).
  Future<void> stop() async {
    _uid = null;
    _session++;
    _retry?.cancel();
    _retry = null;
    await _cancelListeners();
    await _queue;
  }

  /// Completes once every snapshot received so far is applied. For tests.
  Future<void> idle() async {
    Future<void> seen;
    do {
      seen = _queue;
      await seen;
      await Future<void>.delayed(Duration.zero);
    } while (!identical(seen, _queue));
  }

  void _listenToGroups() {
    _awaitingFirstGroups = true;
    _groupsSub = _firestore
        .collection('groups')
        .where('memberUids', arrayContains: _uid)
        .snapshots()
        .listen(
      (snapshot) => _enqueue(() => _applyGroups(snapshot)),
      onError: (Object e) {
        _log('pulling groups failed, retrying: $e');
        _retryLater();
      },
    );
  }

  void _retryLater() {
    _retry?.cancel();
    final session = _session;
    _retry = Timer(retryDelay, () async {
      if (session != _session) return;
      await _cancelListeners();
      if (session == _session) _listenToGroups();
    });
  }

  Future<void> _cancelListeners() async {
    final cancelled = _groupsSub?.cancel();
    final subs = [for (final group in _groups.values) ...group.subs];
    _groupsSub = null;
    _groups.clear();
    await Future.wait([
      if (cancelled != null) cancelled,
      ...subs.map((s) => s.cancel()),
    ]);
  }

  void _enqueue(Future<void> Function() work) {
    final session = _session;
    _queue = _queue.then((_) async {
      if (session != _session) return;
      try {
        await work();
      } catch (e) {
        _log('applying pulled changes failed: $e');
      }
    });
  }

  // ── Groups ───────────────────────────────────────────────────────────────

  Future<void> _applyGroups(
      QuerySnapshot<Map<String, dynamic>> snapshot) async {
    final pending = await _db.syncDao.pendingEntityIds();
    for (final change in snapshot.docChanges) {
      final doc = change.doc;
      if (change.type == DocumentChangeType.removed) {
        // Left or deleted on another device.
        await _removeGroup(doc.id);
        continue;
      }
      if (!doc.metadata.hasPendingWrites && !pending.contains(doc.id)) {
        await _guard(doc, () => _upsertGroup(doc));
      }
      await _listenToGroup(doc.id);
    }

    // Groups pulled earlier that the account no longer belongs to: it left
    // or deleted them on another device while this one was not listening.
    if (_awaitingFirstGroups && !snapshot.metadata.isFromCache) {
      _awaitingFirstGroups = false;
      final current = {for (final doc in snapshot.docs) doc.id};
      for (final key in await _db.syncDao.stateKeysWithPrefix('pulled:')) {
        final groupId = key.substring('pulled:'.length);
        if (!current.contains(groupId)) await _removeGroup(groupId);
      }
    }
  }

  Future<void> _upsertGroup(_Doc doc) async {
    final d = doc.data()!;
    await _db.into(_db.groups).insertOnConflictUpdate(GroupsCompanion.insert(
          id: doc.id,
          name: d['name'] as String,
          emoji: Value(d['emoji'] as String?),
          colorValue: d['colorValue'] as int,
          currencyCode: Value(d['currencyCode'] as String),
          isArchived: Value(d['isArchived'] as bool? ?? false),
          createdAt: _date(d['createdAt']),
          updatedAt: _serverTime(d) ?? _date(d['createdAt']),
          createdBy: Value(d['createdBy'] as String?),
          updatedBy: Value(d['updatedBy'] as String?),
          deleted: Value(d['deleted'] as bool? ?? false),
        ));
    await _db.syncDao.writeState(_pulledKey(doc.id), '1');
  }

  /// Removes a group the account is no longer in, with everything under it.
  Future<void> _removeGroup(String groupId) async {
    final pull = _groups.remove(groupId);
    if (pull != null) await Future.wait(pull.subs.map((s) => s.cancel()));
    await _db.transaction(() async {
      final expenseIds = _db.selectOnly(_db.expenses)
        ..addColumns([_db.expenses.id])
        ..where(_db.expenses.groupId.equals(groupId));
      await (_db.delete(_db.expenseSplits)
            ..where((s) => s.expenseId.isInQuery(expenseIds)))
          .go();
      await (_db.delete(_db.settlements)
            ..where((s) => s.groupId.equals(groupId)))
          .go();
      await (_db.delete(_db.expenses)..where((e) => e.groupId.equals(groupId)))
          .go();
      await (_db.delete(_db.members)..where((m) => m.groupId.equals(groupId)))
          .go();
      await (_db.delete(_db.groups)..where((g) => g.id.equals(groupId))).go();
      await (_db.delete(_db.outboxEntries)
            ..where((o) => o.groupId.equals(groupId)))
          .go();
      await (_db.delete(_db.activities)
            ..where((a) => a.groupId.equals(groupId)))
          .go();
      await _db.syncDao.deleteStatesWithPrefix('pull:$groupId:');
      await _db.syncDao.deleteStatesWithPrefix(_pulledKey(groupId));
    });
  }

  // ── Records ──────────────────────────────────────────────────────────────

  Future<void> _listenToGroup(String groupId) async {
    if (_groups.containsKey(groupId)) return;
    final pull = _groups[groupId] = _GroupPull();
    await _listen(groupId, pull, 'members');
  }

  Future<void> _listen(
      String groupId, _GroupPull pull, String collection) async {
    final cursor = await _db.syncDao.readState(_cursorKey(groupId, collection));
    // The group may have been removed while the cursor was read.
    if (!identical(_groups[groupId], pull)) return;
    Query<Map<String, dynamic>> query =
        _firestore.collection('groups').doc(groupId).collection(collection);
    if (cursor != null) {
      query = query.where('updatedAt',
          isGreaterThan:
              Timestamp.fromMicrosecondsSinceEpoch(int.parse(cursor)));
    }
    pull.subs.add(query.snapshots().listen(
          (snapshot) => _enqueue(
              () => _applyRecords(groupId, pull, collection, snapshot)),
          // Access ends when the account leaves the group; the groups
          // listener then removes it.
          onError: (Object e) =>
              _log('pulling $collection of $groupId failed: $e'),
        ));
  }

  Future<void> _applyRecords(
    String groupId,
    _GroupPull pull,
    String collection,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (!identical(_groups[groupId], pull)) return;
    final pending = await _db.syncDao.pendingEntityIds();
    var newest = pull.newest[collection] ?? 0;
    for (final change in snapshot.docChanges) {
      final doc = change.doc;
      // Records leave a group only together with it (see _removeGroup).
      if (change.type == DocumentChangeType.removed) continue;
      if (doc.metadata.hasPendingWrites) continue;
      final updatedAt =
          (doc.data()!['updatedAt'] as Timestamp?)?.microsecondsSinceEpoch;
      if (updatedAt != null && updatedAt > newest) newest = updatedAt;
      if (pending.contains(doc.id)) continue;
      switch (collection) {
        case 'members':
          await _guard(doc, () => _upsertMember(groupId, doc));
        case 'expenses':
          if (await _hasMembers(_expenseMemberIds(doc.data()!))) {
            await _guard(doc, () => _upsertExpense(groupId, doc));
          } else {
            pull.waiting[doc.id] = (collection, doc);
          }
        case 'settlements':
          final d = doc.data()!;
          if (await _hasMembers(
              {d['fromMemberId'] as String, d['toMemberId'] as String})) {
            await _guard(doc, () => _upsertSettlement(groupId, doc));
          } else {
            pull.waiting[doc.id] = (collection, doc);
          }
      }
    }
    pull.newest[collection] = newest;

    if (collection == 'members') {
      await _applyWaiting(groupId, pull);
      if (!pull.recordsStarted) {
        pull.recordsStarted = true;
        await _listen(groupId, pull, 'expenses');
        await _listen(groupId, pull, 'settlements');
      }
    }
    await _saveCursors(groupId, pull);
  }

  /// Applies records that were waiting for their members.
  Future<void> _applyWaiting(String groupId, _GroupPull pull) async {
    for (final MapEntry(key: id, value: (collection, doc))
        in pull.waiting.entries.toList()) {
      final d = doc.data()!;
      final memberIds = collection == 'expenses'
          ? _expenseMemberIds(d)
          : {d['fromMemberId'] as String, d['toMemberId'] as String};
      if (!await _hasMembers(memberIds)) continue;
      pull.waiting.remove(id);
      await _guard(
          doc,
          () => collection == 'expenses'
              ? _upsertExpense(groupId, doc)
              : _upsertSettlement(groupId, doc));
    }
  }

  /// Saves how far each collection was pulled. While records wait for their
  /// members, their collection's cursor stays put, so a restart pulls them
  /// again.
  Future<void> _saveCursors(String groupId, _GroupPull pull) async {
    final waiting = {for (final (c, _) in pull.waiting.values) c};
    for (final MapEntry(key: collection, value: newest)
        in pull.newest.entries) {
      if (newest == 0 || waiting.contains(collection)) continue;
      await _db.syncDao
          .writeState(_cursorKey(groupId, collection), newest.toString());
    }
  }

  Future<void> _upsertMember(String groupId, _Doc doc) async {
    final d = doc.data()!;
    final linkedUid = d['linkedUid'] as String?;
    await _db.into(_db.members).insertOnConflictUpdate(MembersCompanion.insert(
          id: doc.id,
          groupId: groupId,
          name: d['name'] as String,
          avatarColorValue: d['avatarColorValue'] as int,
          emoji: Value(d['emoji'] as String?),
          isMe: Value(linkedUid != null && linkedUid == _uid),
          createdAt: _date(d['createdAt']),
          linkedUid: Value(linkedUid),
          createdBy: Value(d['createdBy'] as String?),
          updatedBy: Value(d['updatedBy'] as String?),
          deleted: Value(d['deleted'] as bool? ?? false),
        ));
  }

  /// The expense and its splits replace the local ones together (AC17,
  /// AC21).
  Future<void> _upsertExpense(String groupId, _Doc doc) async {
    final d = doc.data()!;
    final splits = (d['splits'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((s) => ExpenseSplitsCompanion.insert(
              id: s['id'] as String,
              expenseId: doc.id,
              memberId: s['memberId'] as String,
              value: s['value'] as int,
              amountCents: s['amountCents'] as int,
            ))
        .toList();
    await _db.transaction(() async {
      await _db.into(_db.expenses).insertOnConflictUpdate(
            ExpensesCompanion.insert(
              id: doc.id,
              groupId: groupId,
              title: d['title'] as String,
              amountCents: d['amountCents'] as int,
              currencyCode: d['currencyCode'] as String,
              paidByMemberId: d['paidByMemberId'] as String,
              splitType: d['splitType'] as String,
              category: Value(d['category'] as String? ?? 'other'),
              note: Value(d['note'] as String?),
              expenseDate: _date(d['expenseDate']),
              createdAt: _date(d['createdAt']),
              updatedAt: d['editedAt'] is int
                  ? _date(d['editedAt'])
                  : _serverTime(d) ?? _date(d['createdAt']),
              isDeleted: Value(d['deleted'] as bool? ?? false),
              createdBy: Value(d['createdBy'] as String?),
              updatedBy: Value(d['updatedBy'] as String?),
            ),
          );
      await (_db.delete(_db.expenseSplits)
            ..where((s) => s.expenseId.equals(doc.id)))
          .go();
      await _db.batch((b) => b.insertAll(_db.expenseSplits, splits));
    });
  }

  Future<void> _upsertSettlement(String groupId, _Doc doc) async {
    final d = doc.data()!;
    await _db.into(_db.settlements).insertOnConflictUpdate(
          SettlementsCompanion.insert(
            id: doc.id,
            groupId: groupId,
            fromMemberId: d['fromMemberId'] as String,
            toMemberId: d['toMemberId'] as String,
            amountCents: d['amountCents'] as int,
            currencyCode: d['currencyCode'] as String,
            note: Value(d['note'] as String?),
            settledAt: _date(d['settledAt']),
            createdAt: _date(d['createdAt']),
            createdBy: Value(d['createdBy'] as String?),
            updatedBy: Value(d['updatedBy'] as String?),
            deleted: Value(d['deleted'] as bool? ?? false),
          ),
        );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// A malformed record is logged and skipped, so it never blocks the rest.
  Future<void> _guard(_Doc doc, Future<void> Function() upsert) async {
    try {
      await upsert();
    } catch (e) {
      _log('skipped ${doc.reference.path}: $e');
    }
  }

  static Set<String> _expenseMemberIds(Map<String, dynamic> d) => {
        d['paidByMemberId'] as String,
        for (final s in (d['splits'] as List? ?? const []).cast<Map>())
          s['memberId'] as String,
      };

  Future<bool> _hasMembers(Set<String> ids) async {
    final count = _db.members.id.count();
    final row = await (_db.selectOnly(_db.members)
          ..addColumns([count])
          ..where(_db.members.id.isIn(ids)))
        .getSingle();
    return row.read(count) == ids.length;
  }

  static DateTime _date(Object? millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis as int);

  static DateTime? _serverTime(Map<String, dynamic> d) =>
      (d['updatedAt'] as Timestamp?)?.toDate();
}

/// The listeners and progress of one group.
class _GroupPull {
  final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

  /// Newest `updatedAt` seen per collection, in epoch microseconds.
  final newest = <String, int>{};

  /// Expenses and settlements whose members have not arrived yet, by ID.
  final waiting = <String, (String, _Doc)>{};

  bool recordsStarted = false;
}
