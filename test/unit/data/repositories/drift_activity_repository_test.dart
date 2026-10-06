import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/data/database/app_database.dart';
import 'package:simsplit/data/repositories/drift_activity_repository.dart';
import 'package:simsplit/domain/entities/activity_entry.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase database;

  ActivitiesCompanion activity(String id, DateTime time,
          {String action = 'update', String group = 'g1'}) =>
      ActivitiesCompanion.insert(
        id: id,
        groupId: group,
        actorUid: 'alice',
        action: action,
        entityType: 'expense',
        entityId: 'e1',
        before: const Value('{"amountCents":1}'),
        after: '{"amountCents":2}',
        clientTime: time,
      );

  setUp(() => database = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('lists a group\'s entries newest first, marking unpushed ones',
      () async {
    await database
        .into(database.activities)
        .insert(activity('old', DateTime(2026, 10, 1)));
    await database.syncDao.enqueue(activity('new', DateTime(2026, 10, 2)));
    await database
        .into(database.activities)
        .insert(activity('other', DateTime(2026, 10, 3), group: 'g2'));
    // An action this version does not know is left out.
    await database
        .into(database.activities)
        .insert(activity('future', DateTime(2026, 10, 4), action: 'archive'));

    final entries = (await DriftActivityRepository(syncDao: database.syncDao)
            .watchActivity('g1')
            .first)
        .getOrElse((f) => throw StateError('$f'));

    expect(
        entries.map((e) => (e.id, e.synced)), [('new', false), ('old', true)]);
    expect(entries.last.action, ActivityAction.update);
    expect(entries.last.before, {'amountCents': 1});
    expect(entries.last.after, {'amountCents': 2});
  });
}
