import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { loadConfig } from '../src/config/load.ts';
import { checkConfig } from '../src/config/check.ts';
import { createHandler } from '../src/handler.ts';
import type { Device } from '../src/ports.ts';
import { FakeAudiences, FakePusher, FakeScheduler, FakeSendLog, FakeStore } from './fakes.ts';

const { config } = loadConfig(resolve(import.meta.dirname, '../../../crm'));

// 23:00 in Vietnam: quiet hours.
const NIGHT = new Date('2026-12-01T16:00:00Z');
const UID = 'uidAbc123';

const setup = () => {
  const logs: Record<string, unknown>[] = [];
  const store = new FakeStore();
  const pusher = new FakePusher();
  const sends = new FakeSendLog();
  let clock = NIGHT;
  const handle = createHandler({
    config: structuredClone(config!),
    version: 'abc',
    log: (e) => logs.push(e),
    now: () => clock,
    store,
    pusher,
    scheduler: new FakeScheduler(),
    audiences: new FakeAudiences(),
    sends,
    traitsTable: 'p.d.t',
    env: 'dev',
    startedAt: NIGHT,
  });
  // Every choice off, the weekly slot taken, paused: the test still goes out.
  store.prefs.set(UID, { groupActivity: false, settleReminder: false, updates: false, pausedUntil: new Date(NIGHT.getTime() + 86400_000) });
  store.ledger.set(UID, { at: NIGHT, messageId: 'other' });
  const device = (id: string, requestedAt?: Date, locale: 'en' | 'vi' = 'vi'): Device => ({
    id,
    token: `tok-${id}`,
    platform: 'android',
    locale,
    tzName: 'Asia/Ho_Chi_Minh',
    tzOffsetMinutes: 420,
    testRequestedAt: requestedAt,
  });
  const request = (deviceId: string) =>
    handle({ method: 'POST', path: '/events', headers: { 'ce-id': 'ev1', 'ce-document': `users/${UID}/devices/${deviceId}` }, body: Buffer.from('') });
  return { store, pusher, sends, logs, device, request, setNow: (d: Date) => (clock = d) };
};

test('a fresh request sends one push to that device, past quiet hours, prefs and the cap (AC33)', async () => {
  const s = setup();
  s.store.devices.set(UID, [s.device('d1', new Date(NIGHT.getTime() - 20_000)), s.device('d2')]);
  assert.equal((await s.request('d1')).status, 204);
  assert.equal(s.pusher.sent.length, 1);
  const { device, push } = s.pusher.sent[0];
  assert.equal(device.id, 'd1');
  assert.equal(push.title, 'Thông báo thử');
  assert.equal(push.body, 'SimSplit sẽ báo bạn như thế này.');
  assert.equal(push.category, 'group_activity');
  assert.equal(push.source, 'system:test-notification');
  assert.deepEqual(s.sends.rows.map((r) => [r.source, r.source_id, r.result]), [['system', 'test-notification', 'sent']]);
  // A registration write of the other device sends nothing.
  await s.request('d2');
  assert.equal(s.pusher.sent.length, 1);
});

test('at most one test per device every 10 minutes; a stale request is ignored', async () => {
  const s = setup();
  s.store.devices.set(UID, [s.device('d1', NIGHT, 'en')]);
  await s.request('d1');
  await s.request('d1'); // Eventarc retry
  s.setNow(new Date(NIGHT.getTime() + 5 * 60_000));
  s.store.devices.set(UID, [s.device('d1', new Date(NIGHT.getTime() + 5 * 60_000), 'en')]);
  await s.request('d1');
  assert.equal(s.pusher.sent.length, 1);
  assert.equal(s.pusher.sent[0].push.title, 'Test notification');

  s.setNow(new Date(NIGHT.getTime() + 11 * 60_000));
  await s.request('d1'); // the request is 6 minutes old
  assert.equal(s.pusher.sent.length, 1);
  s.store.devices.set(UID, [s.device('d1', new Date(NIGHT.getTime() + 11 * 60_000 - 5_000), 'en')]);
  await s.request('d1');
  assert.equal(s.pusher.sent.length, 2);
});

test('a deleted device and an invalid token are handled; logs never carry a uid or path', async () => {
  const s = setup();
  await s.request('gone');
  s.store.devices.set(UID, [s.device('d1', NIGHT)]);
  s.pusher.results.set('tok-d1', 'invalid_token');
  await s.request('d1');
  assert.deepEqual(s.store.devices.get(UID), []);
  const logged = JSON.stringify(s.logs);
  assert.equal(logged.includes(UID), false);
  assert.equal(logged.includes('d1'), false);
  assert.equal(logged.includes('users/'), false);
});

test('the test template is a system template: validated, not reported unused', () => {
  const { problems, warnings } = checkConfig(config!);
  assert.deepEqual(problems, []);
  assert.equal(warnings.some((w) => w.file.includes('test-notification')), false);
  const without = structuredClone(config!);
  without.templates = without.templates.filter((t) => t.id !== 'test-notification');
  assert.ok(checkConfig(without).problems.some((p) => /unknown template "test-notification"/.test(p.message)));
});
