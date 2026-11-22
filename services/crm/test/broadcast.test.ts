import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { loadConfig } from '../src/config/load.ts';
import { campaignDue, cronFor, reminderValues, runCampaigns, runSchedules, scheduleOccurrence, type BroadcastDeps } from '../src/broadcast.ts';
import type { Device } from '../src/ports.ts';
import { FakeAudiences, FakePusher, FakeSendLog, FakeStore } from './fakes.ts';

const { config } = loadConfig(resolve(import.meta.dirname, '../../../crm'));

// Sunday 2026-12-06 19:05 in Vietnam.
const SUNDAY_EVENING = new Date('2026-12-06T12:05:00Z');

const device = (id: string, locale: 'en' | 'vi' = 'en'): Device => ({
  id,
  token: `tok-${id}`,
  platform: 'android',
  locale,
  tzName: 'Asia/Ho_Chi_Minh',
  tzOffsetMinutes: 420,
});

const setup = (now = SUNDAY_EVENING, env: 'dev' | 'prd' = 'prd') => {
  const store = new FakeStore();
  const pusher = new FakePusher();
  const audiences = new FakeAudiences();
  audiences.updated = new Date(now.getTime() - 6 * 3600_000);
  let clock = now;
  const deps: BroadcastDeps = {
    config: structuredClone(config!),
    store,
    pusher,
    audiences,
    sends: new FakeSendLog(),
    traitsTable: 'dataplatform-as-se1-dev.simsplit_crm.user_traits',
    log: () => {},
    now: () => clock,
    env,
    startedAt: new Date(now.getTime() - 60_000),
  };
  return { deps, store, pusher, audiences, setNow: (d: Date) => (clock = d) };
};

const debts = [
  { groupId: 'g1', groupName: 'Đà Lạt', owesCents: 30000000, currencyCode: 'VND', creditors: 2, oldestDays: 20 },
  { groupId: 'g2', groupName: 'Nhà', owesCents: 5000000, currencyCode: 'VND', creditors: 1, oldestDays: 20 },
  { groupId: 'g3', groupName: 'Tokyo', owesCents: 1000, currencyCode: 'JPY', creditors: 1, oldestDays: 20 },
];

test('reminder numbers: total in the largest debt currency, link to its settle screen', () => {
  assert.deepEqual(reminderValues(debts), {
    values: { total: '350.000 ₫', people: 4, group: 'Đà Lạt' },
    route: '/groups/g1/settle',
  });
  assert.equal(reminderValues([]), undefined);
});

test('the weekly reminder goes to opted-in users in its device minute window (AC11)', async () => {
  const s = setup();
  s.audiences.uidsByQuery = ['u1', 'u2', 'u3'];
  s.store.prefs.set('u1', { settleReminder: true });
  s.store.prefs.set('u3', { settleReminder: true });
  s.store.devices.set('u1', [device('d1', 'vi')]);
  s.store.devices.set('u2', [device('d2')]); // reminders off (the default)
  s.store.devices.set('u3', [device('d3')]);
  s.store.debts.set('u1', debts);
  // u3 settled since the traits ran: nothing to remind.
  await runSchedules(s.deps);
  assert.equal(s.pusher.sent.length, 1);
  assert.equal(s.pusher.sent[0].push.title, 'Bạn còn nợ 350.000 ₫');
  assert.equal(s.pusher.sent[0].push.body, 'Cho 4 người, nhiều nhất ở Đà Lạt. Chạm để thanh toán.');
  assert.equal(s.pusher.sent[0].push.route, '/groups/g1/settle');
  assert.equal(s.pusher.sent[0].push.source, 'schedule:settle-reminder');
  assert.match(s.audiences.queries[0], /`owes_groups` >= @p0 AND `oldest_unsettled_days` > @p1/);
  // The next tick in the same window sends nothing more.
  s.setNow(new Date(SUNDAY_EVENING.getTime() + 5 * 60_000));
  await runSchedules(s.deps);
  assert.equal(s.pusher.sent.length, 1);
});

test('outside the cron window nothing is sent', async () => {
  const s = setup(new Date('2026-12-06T12:30:00Z')); // 19:30
  s.audiences.uidsByQuery = ['u1'];
  s.store.prefs.set('u1', { settleReminder: true });
  s.store.devices.set('u1', [device('d1')]);
  s.store.debts.set('u1', debts);
  await runSchedules(s.deps);
  assert.equal(s.pusher.sent.length, 0);
  assert.equal(scheduleOccurrence(s.deps.config.schedules[0], device('x'), SUNDAY_EVENING), '2026-12-06T12:00');
});

test('stale traits skip the send and log an error (AC21)', async () => {
  const s = setup();
  const logs: Record<string, unknown>[] = [];
  s.deps.log = (e) => logs.push(e);
  s.audiences.updated = new Date(SUNDAY_EVENING.getTime() - 40 * 3600_000);
  s.audiences.uidsByQuery = ['u1'];
  s.store.prefs.set('u1', { settleReminder: true });
  s.store.devices.set('u1', [device('d1')]);
  s.store.debts.set('u1', debts);
  await runSchedules(s.deps);
  assert.equal(s.pusher.sent.length, 0);
  assert.equal(logs[0].kind, 'traits_stale');
  assert.equal(logs[0].severity, 'ERROR');
});

const addCampaign = (s: ReturnType<typeof setup>, channels: ('push' | 'inapp')[]) => {
  s.deps.config.templates.push({
    id: 'news',
    vars: [],
    push: { en: { title: 'New version', body: 'Fixes sync' }, vi: { title: 'Bản mới', body: 'Sửa đồng bộ' } },
    banner: { en: { title: 'New version', body: 'Fixes sync' }, vi: { title: 'Bản mới', body: 'Sửa đồng bộ' } },
  });
  s.deps.config.audiences.push({ id: 'everyone', description: 'All', match: 'all', rules: [] });
  s.deps.config.campaigns.push({
    id: 'news',
    enabled: true,
    category: 'updates',
    send_at: '2026-12-06T09:00:00+07:00',
    ends_at: '2026-12-13T09:00:00+07:00',
    audience: 'everyone',
    channels,
    template: 'news',
  });
};

test('a campaign: banner for the audience, push only for Updates on, once per device', async () => {
  const s = setup(new Date('2026-12-06T05:00:00Z')); // 12:00
  addCampaign(s, ['inapp', 'push']);
  s.audiences.uidsByQuery = ['u1', 'u2'];
  s.store.prefs.set('u1', { updates: true });
  s.store.devices.set('u1', [device('d1'), device('d1b', 'vi')]);
  s.store.devices.set('u2', [device('d2')]);
  await runCampaigns(s.deps);
  await runCampaigns(s.deps);
  assert.deepEqual(s.store.announcements.get('news')?.audienceUids, ['u1', 'u2']);
  assert.deepEqual(s.pusher.sent.map((x) => [x.device.id, x.push.title]), [['d1', 'New version'], ['d1b', 'Bản mới']]);
});

test('settle reminders and updates share one push a week (AC13)', async () => {
  const s = setup();
  addCampaign(s, ['push']);
  s.audiences.uidsByQuery = ['u1'];
  s.store.prefs.set('u1', { updates: true, settleReminder: true });
  s.store.devices.set('u1', [device('d1')]);
  s.store.debts.set('u1', debts);
  await runSchedules(s.deps);
  await runCampaigns(s.deps);
  assert.equal(s.pusher.sent.length, 1);
  assert.equal(s.pusher.sent[0].push.category, 'settle_reminder');
});

test('quiet hours: the campaign waits for a later tick', async () => {
  const s = setup(new Date('2026-12-06T15:00:00Z')); // 22:00
  addCampaign(s, ['push']);
  s.audiences.uidsByQuery = ['u1'];
  s.store.prefs.set('u1', { updates: true });
  s.store.devices.set('u1', [device('d1')]);
  await runCampaigns(s.deps);
  assert.equal(s.pusher.sent.length, 0);
  s.setNow(new Date('2026-12-07T01:15:00Z')); // 08:15
  await runCampaigns(s.deps);
  assert.equal(s.pusher.sent.length, 1);
});

test('campaign timing: prd follows send_at; dev sends after deploy; nothing after ends_at', () => {
  const c = {
    id: 'c',
    enabled: true,
    category: 'updates',
    send_at: '2026-12-10T09:00:00+07:00',
    ends_at: '2026-12-13T09:00:00+07:00',
    audience: 'a',
    channels: ['push' as const],
    template: 't',
  };
  const started = new Date('2026-12-06T00:00:00Z');
  const before = new Date('2026-12-06T05:00:00Z');
  assert.equal(campaignDue(c, { env: 'prd', startedAt: started }, before), false);
  assert.equal(campaignDue(c, { env: 'dev', startedAt: started }, before), true);
  assert.equal(campaignDue(c, { env: 'prd', startedAt: started }, new Date('2026-12-11T00:00:00Z')), true);
  assert.equal(campaignDue(c, { env: 'dev', startedAt: started }, new Date('2026-12-14T00:00:00Z')), false);
});

// R-9 P8: settle reminder choices, pause and the user's quiet hours.

test('a settle reminder follows the user’s day and time instead of the cron (AC32)', async () => {
  const saturdayMorning = new Date('2026-12-05T02:05:00Z'); // Saturday 09:05 in Vietnam
  const s = setup(saturdayMorning);
  s.audiences.uidsByQuery = ['u1', 'u2'];
  s.store.prefs.set('u1', { settleReminder: true, settle: { day: 6, time: '09:00', minDays: 14 } });
  s.store.prefs.set('u2', { settleReminder: true });
  s.store.devices.set('u1', [device('d1')]);
  s.store.devices.set('u2', [device('d2')]);
  s.store.debts.set('u1', debts);
  s.store.debts.set('u2', debts);
  await runSchedules(s.deps);
  assert.deepEqual(s.pusher.sent.map((x) => x.device.id), ['d1']);
  // Sunday 19:05: only u2, on the config's cron.
  s.setNow(SUNDAY_EVENING);
  s.store.ledger.clear();
  s.audiences.updated = new Date(SUNDAY_EVENING.getTime() - 3600_000);
  await runSchedules(s.deps);
  assert.deepEqual(s.pusher.sent.map((x) => x.device.id), ['d1', 'd2']);
  assert.equal(cronFor(s.deps.config.schedules[0], { settle: { day: 3, time: '20:30', minDays: 7 } }), '30 20 * * 3');
  assert.equal(cronFor(s.deps.config.schedules[0], {}), '0 19 * * 0');
});

test('only debts older than the user’s minimum count (AC32)', async () => {
  const young = debts.map((d) => ({ ...d, oldestDays: 10 }));
  assert.equal(reminderValues(young), undefined);
  assert.equal(reminderValues(young, 7)?.values.total, '350.000 ₫');
  assert.equal(reminderValues([{ ...debts[0], oldestDays: 40 }, { ...debts[1], oldestDays: 20 }], 30)?.values.total, '300.000 ₫');
  const s = setup();
  s.audiences.uidsByQuery = ['u1', 'u2'];
  s.store.prefs.set('u1', { settleReminder: true, settle: { day: 0, time: '19:00', minDays: 7 } });
  s.store.prefs.set('u2', { settleReminder: true });
  s.store.devices.set('u1', [device('d1')]);
  s.store.devices.set('u2', [device('d2')]);
  s.store.debts.set('u1', young);
  s.store.debts.set('u2', young);
  await runSchedules(s.deps);
  assert.deepEqual(s.pusher.sent.map((x) => x.device.id), ['d1']);
});

test('paused: settle reminders and campaign pushes are dropped, banners still show (AC30)', async () => {
  const s = setup();
  addCampaign(s, ['inapp', 'push']);
  s.audiences.uidsByQuery = ['u1'];
  s.store.prefs.set('u1', { updates: true, settleReminder: true, pausedUntil: new Date(SUNDAY_EVENING.getTime() + 3600_000) });
  s.store.devices.set('u1', [device('d1')]);
  s.store.debts.set('u1', debts);
  await runSchedules(s.deps);
  await runCampaigns(s.deps);
  assert.equal(s.pusher.sent.length, 0);
  assert.deepEqual(s.store.announcements.get('news')?.audienceUids, ['u1']);
  assert.equal(s.store.ledger.size, 0, 'a dropped push takes no weekly slot');
  // After the pause the campaign is not sent late.
  s.setNow(new Date(SUNDAY_EVENING.getTime() + 2 * 3600_000));
  await runCampaigns(s.deps);
  assert.equal(s.pusher.sent.length, 0);
});

test('a user’s longer quiet hours hold a campaign too (AC31)', async () => {
  const s = setup(new Date('2026-12-06T13:30:00Z')); // 20:30
  addCampaign(s, ['push']);
  s.audiences.uidsByQuery = ['u1', 'u2'];
  s.store.prefs.set('u1', { updates: true, quietHours: { from: '20:00', to: '08:00' } });
  s.store.prefs.set('u2', { updates: true });
  s.store.devices.set('u1', [device('d1')]);
  s.store.devices.set('u2', [device('d2')]);
  await runCampaigns(s.deps);
  assert.deepEqual(s.pusher.sent.map((x) => x.device.id), ['d2']);
});
