import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { loadConfig } from '../src/config/load.ts';
import { createHandler } from '../src/handler.ts';

const { config } = loadConfig(resolve(import.meta.dirname, '../../../crm'));

const setup = (killSwitch: boolean) => {
  const logs: Record<string, unknown>[] = [];
  const c = structuredClone(config!);
  c.policy.kill_switch = killSwitch;
  const handle = createHandler({ config: c, version: 'abc', log: (e) => logs.push(e) });
  return { handle, logs };
};

test('routes accept POST only', async () => {
  const { handle } = setup(false);
  assert.equal((await handle({ method: 'POST', path: '/nope', headers: {} })).status, 404);
  assert.equal((await handle({ method: 'GET', path: '/tick', headers: {} })).status, 405);
  for (const path of ['/events', '/flush', '/tick']) {
    assert.equal((await handle({ method: 'POST', path, headers: {} })).status, 204);
  }
});

test('the kill switch is logged and nothing else happens', async () => {
  const { handle, logs } = setup(true);
  await handle({ method: 'POST', path: '/tick', headers: {} });
  assert.deepEqual(logs, [{ severity: 'NOTICE', kind: 'kill_switch', route: 'tick', version: 'abc' }]);
});

test('events log only the CloudEvent id, never the document path', async () => {
  const { handle, logs } = setup(false);
  await handle({
    method: 'POST',
    path: '/events',
    headers: { 'ce-id': 'e1', 'ce-document': 'groups/g1/activity/a1' },
  });
  assert.equal(JSON.stringify(logs).includes('g1'), false);
  assert.equal(logs[0].event_id, 'e1');
});
