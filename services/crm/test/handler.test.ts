import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { loadConfig } from '../src/config/load.ts';
import { createHandler } from '../src/handler.ts';
import { FakePusher, FakeScheduler, FakeStore } from './fakes.ts';

const { config } = loadConfig(resolve(import.meta.dirname, '../../../crm'));

const setup = (killSwitch: boolean) => {
  const logs: Record<string, unknown>[] = [];
  const c = structuredClone(config!);
  c.policy.kill_switch = killSwitch;
  const handle = createHandler({
    config: c,
    version: 'abc',
    log: (e) => logs.push(e),
    now: () => new Date('2026-12-01T05:00:00Z'),
    store: new FakeStore(),
    pusher: new FakePusher(),
    scheduler: new FakeScheduler(),
  });
  return { handle, logs };
};

const req = (method: string, path: string, headers: Record<string, string> = {}, body = '') => ({
  method,
  path,
  headers,
  body: Buffer.from(body),
});

test('routes accept POST only', async () => {
  const { handle } = setup(false);
  assert.equal((await handle(req('POST', '/nope'))).status, 404);
  assert.equal((await handle(req('GET', '/tick'))).status, 405);
  for (const path of ['/events', '/flush', '/tick']) {
    assert.equal((await handle(req('POST', path))).status, 204);
  }
});

test('the kill switch is logged and nothing else happens', async () => {
  const { handle, logs } = setup(true);
  await handle(req('POST', '/tick'));
  assert.deepEqual(logs, [{ severity: 'NOTICE', kind: 'kill_switch', route: 'tick', version: 'abc' }]);
});

test('events log only the CloudEvent id, never the document path', async () => {
  const { handle, logs } = setup(false);
  await handle(req('POST', '/events', { 'ce-id': 'e1', 'ce-document': 'groups/g1/activity/a1' }));
  assert.equal(JSON.stringify(logs).includes('g1'), false);
  assert.equal(logs[0].event_id, 'e1');
});

test('a malformed flush task is dropped, not retried', async () => {
  const { handle } = setup(false);
  assert.equal((await handle(req('POST', '/flush', {}, '{"groupId":1}'))).status, 204);
  assert.equal((await handle(req('POST', '/flush', {}, 'not json'))).status, 204);
});
