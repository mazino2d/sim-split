import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createHandler, ERROR_REPORTS_PER_DAY, type Deps, type Request } from '../src/handler.ts';
import type { ErrorReportRow, UsageEventRow } from '../src/schema.ts';

const UID = 'kT9mPq2Lr8Xs4Vw6Yz1Ab3Cd';

function setup(overrides: Partial<Deps> = {}) {
  const written = { reports: [] as ErrorReportRow[], events: [] as UsageEventRow[] };
  const logs: Record<string, unknown>[] = [];
  const handle = createHandler({
    verifier: {
      appCheck: async (token) => {
        if (token !== 'good-app-check') throw new Error('invalid');
      },
      idToken: async (token) => {
        if (token !== 'good-id-token') throw new Error('invalid');
        return UID;
      },
    },
    sink: {
      writeErrorReports: async (rows) => void written.reports.push(...rows),
      writeUsageEvents: async (rows) => void written.events.push(...rows),
    },
    log: (entry) => void logs.push(entry),
    now: () => new Date('2026-10-24T03:00:00Z'),
    allowedOrigins: ['https://simsplit.web.app', 'http://localhost'],
    ...overrides,
  });
  return { handle, written, logs };
}

const report = (id = '7KQ-4MZ') => ({ report_id: id, platform: 'android', app_version: '2026.10.22', error_type: 'StateError', message: 'Bad state' });
const event = (uid = UID) => ({ uid, session_id: 'a1b2c3d4', kind: 'tap', name: 'tap_add_expense', platform: 'web', app_version: '2026.10.22' });

function post(path: string, body: unknown, headers: Record<string, string> = {}): Request {
  return {
    method: 'POST',
    path,
    headers: { 'x-firebase-appcheck': 'good-app-check', ...headers },
    body: Buffer.from(typeof body === 'string' ? body : JSON.stringify(body)),
  };
}

test('accepts an error report: writes it to BigQuery and logs it at ERROR', async () => {
  const { handle, written, logs } = setup();
  const res = await handle(post('/v1/errors', { reports: [report()] }));
  assert.equal(res.status, 202);
  assert.equal(written.reports.length, 1);
  assert.equal(logs[0].severity, 'ERROR');
  assert.equal(logs[0].kind, 'error_report');
});

test('rejects requests without a valid App Check token and writes nothing', async () => {
  const { handle, written } = setup();
  assert.equal((await handle(post('/v1/errors', { reports: [report()] }, { 'x-firebase-appcheck': '' }))).status, 401);
  assert.equal((await handle(post('/v1/errors', { reports: [report()] }, { 'x-firebase-appcheck': 'forged' }))).status, 401);
  assert.equal(written.reports.length, 0);
});

test('rejects bodies over 64 KB and invalid payloads', async () => {
  const { handle, written } = setup();
  assert.equal((await handle(post('/v1/errors', 'x'.repeat(64 * 1024 + 1)))).status, 413);
  assert.equal((await handle(post('/v1/errors', 'not json'))).status, 400);
  assert.equal((await handle(post('/v1/errors', { reports: [{ ...report(), platform: 'desktop' }] }))).status, 400);
  assert.equal(written.reports.length, 0);
});

test('drops error reports past the daily cap for one install', async () => {
  const { handle, written } = setup();
  for (let i = 0; i < ERROR_REPORTS_PER_DAY + 5; i++) await handle(post('/v1/errors', { reports: [report()] }));
  assert.equal(written.reports.length, ERROR_REPORTS_PER_DAY);
});

test('usage events need an ID token whose uid matches every event', async () => {
  const { handle, written } = setup();
  assert.equal((await handle(post('/v1/events', { events: [event()] }))).status, 401);
  assert.equal((await handle(post('/v1/events', { events: [event()] }, { authorization: 'Bearer bad' }))).status, 401);
  assert.equal((await handle(post('/v1/events', { events: [event('someoneElse1')] }, { authorization: 'Bearer good-id-token' }))).status, 403);
  const ok = await handle(post('/v1/events', { events: [event(), event()] }, { authorization: 'Bearer good-id-token' }));
  assert.equal(ok.status, 202);
  assert.equal(written.events.length, 2);
});

test('answers 503 when BigQuery fails so the app retries', async () => {
  const { handle } = setup({
    sink: {
      writeErrorReports: async () => {
        throw new Error('unavailable');
      },
      writeUsageEvents: async () => {},
    },
  });
  assert.equal((await handle(post('/v1/errors', { reports: [report()] }))).status, 503);
});

test('allows CORS only from the web app and localhost', async () => {
  const { handle } = setup();
  const preflight = (origin: string) => handle({ method: 'OPTIONS', path: '/v1/errors', headers: { origin }, body: Buffer.alloc(0) });
  assert.equal((await preflight('https://simsplit.web.app')).headers['access-control-allow-origin'], 'https://simsplit.web.app');
  assert.equal((await preflight('http://localhost:5000')).headers['access-control-allow-origin'], 'http://localhost:5000');
  assert.equal((await preflight('https://evil.example')).headers['access-control-allow-origin'], undefined);
});
