import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { loadConfig } from '../src/config/load.ts';
import { bucket, deliverDeferred, onActivity, onFlush, type ActivityDeps } from '../src/activity.ts';
import type { Device } from '../src/ports.ts';
import { FakePusher, FakeScheduler, FakeSendLog, FakeStore } from './fakes.ts';

const { config } = loadConfig(resolve(import.meta.dirname, '../../../crm'));

// 12:00 in Vietnam (UTC+7): outside quiet hours.
const NOON = new Date('2026-12-01T05:00:00Z');

const device = (id: string, locale: 'en' | 'vi' = 'en', tzName = 'Asia/Ho_Chi_Minh'): Device => ({
  id,
  token: `tok-${id}`,
  platform: 'android',
  locale,
  tzName,
  tzOffsetMinutes: 420,
});

const setup = (now = NOON) => {
  const store = new FakeStore();
  const pusher = new FakePusher();
  const scheduler = new FakeScheduler();
  let clock = now;
  const deps: ActivityDeps = {
    config: structuredClone(config!),
    store,
    pusher,
    scheduler,
    sends: new FakeSendLog(),
    log: () => {},
    now: () => clock,
  };
  store.groups.set('g1', { name: 'Đà Lạt', memberUids: ['ua', 'ub', 'uc'], isArchived: false, deleted: false });
  store.members.set('g1', new Map([['ua', 'An'], ['ub', 'Bình'], ['uc', 'Chi']]));
  store.devices.set('ua', [device('a1')]);
  store.devices.set('ub', [device('b1', 'vi')]);
  store.devices.set('uc', [device('c1')]);
  return { deps, store, pusher, scheduler, setNow: (d: Date) => (clock = d) };
};

const expense = (actorUid: string, title: string, amountCents: number, action = 'create') => ({
  actorUid,
  action,
  entityType: 'expense',
  entityId: `e-${title}`,
  after: { title, amountCents, currencyCode: 'VND', deleted: action === 'delete' },
});

const add = async (s: ReturnType<typeof setup>, id: string, entry: Record<string, unknown>) => {
  s.store.activity.set(`g1/${id}`, entry);
  await onActivity(s.deps, `groups/g1/activity/${id}`);
};

const flush = async (s: ReturnType<typeof setup>) => {
  const task = s.scheduler.scheduled.at(-1)!;
  await onFlush(s.deps, task.groupId, task.triggerId, task.windowEnd);
};

test('one change: the other members get it, the actor does not (AC6, AC8, AC10)', async () => {
  const s = setup();
  await add(s, 'x1', expense('ua', 'Ăn tối', 50000000));
  assert.equal(s.scheduler.scheduled.length, 1);
  assert.equal(s.scheduler.scheduled[0].windowEnd.getTime(), NOON.getTime() + 10 * 60_000);
  await flush(s);
  const byDevice = Object.fromEntries(s.pusher.sent.map((x) => [x.device.id, x.push]));
  assert.deepEqual(Object.keys(byDevice).sort(), ['b1', 'c1']);
  assert.equal(byDevice.b1.title, 'Đà Lạt');
  assert.equal(byDevice.b1.body, 'An đã thêm Ăn tối · 500.000 ₫');
  assert.equal(byDevice.c1.body, 'An added Ăn tối · 500.000 ₫');
  assert.equal(byDevice.c1.route, '/groups/g1/expenses/e-Ăn tối');
  assert.equal(byDevice.c1.category, 'group_activity');
  const rows = (s.deps.sends as FakeSendLog).rows;
  assert.deepEqual(
    rows.map((r) => [r.source, r.source_id, r.uid, r.result]).sort(),
    [['trigger', 'group-activity', 'ub', 'sent'], ['trigger', 'group-activity', 'uc', 'sent']],
  );
});

test('several changes in the window become one message (AC7)', async () => {
  const s = setup();
  await add(s, 'x1', expense('ua', 'A', 100));
  await add(s, 'x2', expense('ub', 'B', 200));
  await add(s, 'x2', expense('ub', 'B', 200)); // Eventarc retry
  assert.equal(s.scheduler.scheduled.length, 1);
  await flush(s);
  const byDevice = Object.fromEntries(s.pusher.sent.map((x) => [x.device.id, x.push]));
  assert.equal(byDevice.c1.body, '2 new changes');
  assert.equal(byDevice.c1.route, '/groups/g1');
  // Each actor only hears about the other's change.
  assert.equal(byDevice.a1.body, 'Bình added B · 2 ₫');
  assert.equal(byDevice.b1.body, 'An đã thêm A · 1 ₫');
});

test('settlements and deletes link to the group', async () => {
  const s = setup();
  await add(s, 'x1', {
    actorUid: 'ua',
    action: 'create',
    entityType: 'settlement',
    entityId: 's1',
    after: { amountCents: 35000000, currencyCode: 'VND' },
  });
  await flush(s);
  const c1 = s.pusher.sent.find((x) => x.device.id === 'c1')!.push;
  assert.equal(c1.body, 'An recorded a settlement · 350.000 ₫');
  assert.equal(c1.route, '/groups/g1');
});

test('muted groups, group activity off and archived groups get nothing (AC4, AC9)', async () => {
  const s = setup();
  s.store.prefs.set('ub', { mutedGroups: ['g1'] });
  s.store.prefs.set('uc', { groupActivity: false });
  await add(s, 'x1', expense('ua', 'A', 100));
  await flush(s);
  assert.equal(s.pusher.sent.length, 0);

  const t = setup();
  t.store.groups.get('g1')!.isArchived = true;
  await add(t, 'x1', expense('ua', 'A', 100));
  assert.equal(t.scheduler.scheduled.length, 0);
});

test('a removed member gets nothing', async () => {
  const s = setup();
  await add(s, 'x1', expense('ua', 'A', 100));
  s.store.groups.get('g1')!.memberUids = ['ua', 'ub'];
  await flush(s);
  assert.deepEqual(s.pusher.sent.map((x) => x.device.id), ['b1']);
});

test('a flush runs once even if the task is retried (AC19)', async () => {
  const s = setup();
  await add(s, 'x1', expense('ua', 'A', 100));
  await flush(s);
  await flush(s);
  assert.equal(s.pusher.sent.length, 2);
});

test('quiet hours hold the message until 08:00 device time, merged (AC14)', async () => {
  // 22:00 in Vietnam.
  const s = setup(new Date('2026-12-01T15:00:00Z'));
  await add(s, 'x1', expense('ua', 'A', 100));
  await flush(s);
  s.setNow(new Date('2026-12-01T15:30:00Z'));
  await add(s, 'x2', expense('ua', 'B', 200));
  await flush(s);
  assert.equal(s.pusher.sent.length, 0);
  assert.equal(s.store.deferred.size, 2);

  s.setNow(new Date('2026-12-02T00:45:00Z')); // 07:45
  await deliverDeferred(s.deps);
  assert.equal(s.pusher.sent.length, 0);

  s.setNow(new Date('2026-12-02T01:00:00Z')); // 08:00
  await deliverDeferred(s.deps);
  assert.deepEqual(
    s.pusher.sent.map((x) => [x.device.id, x.push.body]).sort(),
    [['b1', '2 thay đổi mới'], ['c1', '2 new changes']],
  );
  await deliverDeferred(s.deps);
  assert.equal(s.pusher.sent.length, 2);
});

test('an invalid token removes the device', async () => {
  const s = setup();
  s.pusher.results.set('tok-c1', 'invalid_token');
  await add(s, 'x1', expense('ua', 'A', 100));
  await flush(s);
  assert.deepEqual(s.store.devices.get('uc'), []);
});

test('rollout picks a stable share of users', async () => {
  const s = setup();
  s.deps.config.triggers[0].rollout = 0;
  await add(s, 'x1', expense('ua', 'A', 100));
  await flush(s);
  assert.equal(s.pusher.sent.length, 0);
  assert.equal(bucket('ub', 'group-activity'), bucket('ub', 'group-activity'));
});

test('a disabled trigger and unknown paths do nothing', async () => {
  const s = setup();
  s.deps.config.triggers[0].enabled = false;
  await add(s, 'x1', expense('ua', 'A', 100));
  await onActivity(s.deps, 'groups/g1/expenses/x1');
  await onActivity(s.deps, undefined);
  assert.equal(s.scheduler.scheduled.length, 0);
});
