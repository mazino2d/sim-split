import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { loadConfig } from '../src/config/load.ts';
import { bucket, deliverDeferred, onActivity, onFlush, toItem, type ActivityDeps } from '../src/activity.ts';
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
  assert.equal(byDevice.c1.source, 'trigger:group-activity');
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

// R-9 P8: notification settings v2.

const byDevice = (s: ReturnType<typeof setup>) => Object.fromEntries(s.pusher.sent.map((x) => [x.device.id, x.push.body]));

test('only the kinds of change a user has on are sent (AC26)', async () => {
  const s = setup();
  s.store.prefs.set('ub', { activityEvents: { expenseUpdate: false } });
  await add(s, 'x1', expense('ua', 'A', 100, 'update'));
  await flush(s);
  assert.deepEqual(byDevice(s), { c1: 'An edited A · 1 ₫' });
});

test('a join is sent only to members who turned it on; other group changes never batch', async () => {
  const s = setup();
  s.store.prefs.set('ub', { activityEvents: { memberJoin: true } });
  await add(s, 'x0', { actorUid: 'ua', action: 'update', entityType: 'group', entityId: 'g1', after: { name: 'Đà Lạt 2' } });
  assert.equal(s.scheduler.scheduled.length, 0);
  await add(s, 'x1', { actorUid: 'ua', action: 'join', entityType: 'group', entityId: 'g1', before: null, after: {} });
  await flush(s);
  assert.deepEqual(byDevice(s), { b1: 'An đã vào nhóm' });
  const en = setup();
  en.store.prefs.set('uc', { activityEvents: { memberJoin: true } });
  await add(en, 'x1', { actorUid: 'ua', action: 'join', entityType: 'group', entityId: 'g1', before: null, after: {} });
  await flush(en);
  assert.deepEqual(byDevice(en), { c1: 'An joined the group' });
});

test('the item carries who the change involves, from after or before (AC27)', () => {
  const e = toItem('x', {
    actorUid: 'ua',
    action: 'create',
    entityType: 'expense',
    entityId: 'e1',
    after: { paidByMemberId: 'm1', splits: [{ memberId: 'm1' }, { memberId: 'm2' }, { memberId: 3 }] },
  });
  assert.deepEqual(e?.involved, ['m1', 'm2']);
  const st = toItem('y', {
    actorUid: 'ua',
    action: 'delete',
    entityType: 'settlement',
    entityId: 's1',
    after: null,
    before: { fromMemberId: 'm3', toMemberId: 'm4' },
  });
  assert.deepEqual(st?.involved, ['m3', 'm4']);
});

const involving = (actorUid: string, title: string, paidBy: string, splits: string[]) => ({
  ...expense(actorUid, title, 100),
  after: { title, amountCents: 100, currencyCode: 'VND', paidByMemberId: paidBy, splits: splits.map((memberId) => ({ memberId, amountCents: 50 })) },
});

test('"only changes that involve me": payer or a share, globally or per group (AC27, AC29)', async () => {
  const s = setup();
  s.store.prefs.set('ub', { onlyInvolvingMe: true });
  s.store.prefs.set('uc', { groups: { g1: { mode: 'involving' } } });
  await add(s, 'x1', involving('ua', 'Taxi', 'm-ua', ['m-ua', 'm-uc']));
  await flush(s);
  assert.deepEqual(byDevice(s), { c1: 'An added Taxi · 1 ₫' });

  const t = setup();
  t.store.prefs.set('ub', { onlyInvolvingMe: true });
  t.store.memberIds.set('g1', new Map([['ub', 'member-b']]));
  await add(t, 'x1', {
    actorUid: 'ua',
    action: 'create',
    entityType: 'settlement',
    entityId: 's1',
    after: { amountCents: 100, currencyCode: 'VND', fromMemberId: 'm-ua', toMemberId: 'member-b' },
  });
  await flush(t);
  assert.deepEqual(Object.keys(byDevice(t)).sort(), ['b1', 'c1']);
});

test('group modes: off, off until a past time, and groups over the legacy mutedGroups (AC29)', async () => {
  const s = setup();
  s.store.prefs.set('ua', { groups: { g1: { mode: 'off', offUntil: new Date(NOON.getTime() + 3600_000) } } });
  s.store.prefs.set('ub', { groups: { g1: { mode: 'off', offUntil: new Date(NOON.getTime() - 60_000) } } });
  s.store.prefs.set('uc', { mutedGroups: ['g1'], groups: { g1: { mode: 'all' } } });
  s.store.groups.get('g1')!.memberUids.push('ux');
  await add(s, 'x1', expense('ux', 'A', 100));
  await flush(s);
  assert.deepEqual(Object.keys(byDevice(s)).sort(), ['b1', 'c1']);
});

test('bundling every 30 minutes holds and merges until the window, then the tick delivers (AC28)', async () => {
  const s = setup();
  s.store.prefs.set('uc', { bundle: '30m' });
  await add(s, 'x1', expense('ua', 'A', 100));
  await flush(s); // window ends 12:10
  assert.deepEqual(Object.keys(byDevice(s)), ['b1']);
  const held = s.store.deferred.get('uc_c1_g1_group-activity')!;
  assert.equal(held.deliverAfter.toISOString(), '2026-12-01T05:30:00.000Z');
  s.setNow(new Date('2026-12-01T05:12:00Z'));
  await add(s, 'x2', expense('ua', 'B', 200));
  await flush(s); // window ends 12:22, would deliver 12:42: the earlier time stays
  assert.equal(s.store.deferred.get('uc_c1_g1_group-activity')!.deliverAfter.toISOString(), '2026-12-01T05:30:00.000Z');
  s.setNow(new Date('2026-12-01T05:25:00Z'));
  await deliverDeferred(s.deps);
  assert.equal(s.pusher.sent.filter((x) => x.device.id === 'c1').length, 0);
  s.setNow(new Date('2026-12-01T05:30:00Z'));
  await deliverDeferred(s.deps);
  assert.equal(byDevice(s).c1, '2 new changes');
});

test('hourly and daily bundles: window + 50 minutes, the next 19:00 on the device (AC28)', async () => {
  const s = setup();
  s.store.prefs.set('ub', { bundle: '1h' });
  s.store.prefs.set('uc', { bundle: 'daily' });
  await add(s, 'x1', expense('ua', 'A', 100));
  await flush(s);
  assert.equal(s.pusher.sent.length, 0);
  assert.equal(s.store.deferred.get('ub_b1_g1_group-activity')!.deliverAfter.toISOString(), '2026-12-01T06:00:00.000Z');
  assert.equal(s.store.deferred.get('uc_c1_g1_group-activity')!.deliverAfter.toISOString(), '2026-12-01T12:00:00.000Z');
});

test('a pause holds group activity until it ends, or later if that is in quiet hours (AC30)', async () => {
  const s = setup();
  s.store.prefs.set('ub', { pausedUntil: new Date('2026-12-01T07:00:00Z') }); // 14:00
  s.store.prefs.set('uc', { pausedUntil: new Date('2026-12-01T15:00:00Z'), bundle: '30m' }); // 22:00
  await add(s, 'x1', expense('ua', 'A', 100));
  await flush(s);
  assert.equal(s.pusher.sent.length, 0);
  assert.equal(s.store.deferred.get('ub_b1_g1_group-activity')!.deliverAfter.toISOString(), '2026-12-01T07:00:00.000Z');
  s.setNow(new Date('2026-12-01T07:00:00Z'));
  await deliverDeferred(s.deps);
  assert.deepEqual(Object.keys(byDevice(s)), ['b1']);
  // uc's pause ends at 22:00, in quiet hours: it goes out at 08:00.
  s.setNow(new Date('2026-12-01T15:00:00Z'));
  await deliverDeferred(s.deps);
  assert.deepEqual(Object.keys(byDevice(s)), ['b1']);
  assert.equal(s.store.deferred.get('uc_c1_g1_group-activity')!.deliverAfter.toISOString(), '2026-12-02T01:00:00.000Z');
  s.setNow(new Date('2026-12-02T01:00:00Z'));
  await deliverDeferred(s.deps);
  assert.deepEqual(Object.keys(byDevice(s)).sort(), ['b1', 'c1']);
});

test('delivery re-checks quiet hours and a pause set after the hold', async () => {
  const s = setup(new Date('2026-12-01T13:30:00Z')); // 20:30
  s.store.prefs.set('ub', { bundle: '1h' });
  s.store.prefs.set('uc', { bundle: '30m' });
  await add(s, 'x1', expense('ua', 'A', 100));
  await flush(s); // window ends 20:40
  s.store.prefs.set('uc', { bundle: '30m', pausedUntil: new Date('2026-12-01T16:00:00Z') });
  s.setNow(new Date('2026-12-01T14:30:00Z')); // 21:30: quiet hours for ub, uc paused
  await deliverDeferred(s.deps);
  assert.equal(s.pusher.sent.length, 0);
  assert.equal(s.store.deferred.get('ub_b1_g1_group-activity')!.deliverAfter.toISOString(), '2026-12-02T01:00:00.000Z');
  assert.equal(s.store.deferred.get('uc_c1_g1_group-activity')!.deliverAfter.toISOString(), '2026-12-02T01:00:00.000Z');
});

test('a user’s longer quiet hours hold the push until their end (AC31)', async () => {
  const s = setup(new Date('2026-12-01T13:30:00Z')); // 20:30
  s.store.prefs.set('uc', { quietHours: { from: '20:00', to: '09:00' } });
  await add(s, 'x1', expense('ua', 'A', 100));
  await flush(s);
  assert.deepEqual(Object.keys(byDevice(s)), ['b1']);
  assert.equal(s.store.deferred.get('uc_c1_g1_group-activity')!.deliverAfter.toISOString(), '2026-12-02T02:00:00.000Z');
});

test('choices changed while held apply at delivery (AC34)', async () => {
  const s = setup();
  s.store.prefs.set('uc', { bundle: '30m' });
  await add(s, 'x1', expense('ua', 'A', 100));
  await flush(s);
  s.store.prefs.set('uc', { bundle: '30m', groups: { g1: { mode: 'off' } } });
  s.setNow(new Date('2026-12-01T05:30:00Z'));
  await deliverDeferred(s.deps);
  assert.deepEqual(Object.keys(byDevice(s)), ['b1']);
  assert.equal(s.store.deferred.size, 0);
});
