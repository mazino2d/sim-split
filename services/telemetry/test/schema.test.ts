import assert from 'node:assert/strict';
import { test } from 'node:test';
import { InvalidPayload, parseErrorReports, parseUsageEvents } from '../src/schema.ts';

const now = new Date('2026-10-24T03:00:00Z');
const report = {
  report_id: '7KQ-4MZ',
  session_id: 'a1b2c3d4',
  client_time: Date.UTC(2026, 9, 24, 2, 59),
  platform: 'web',
  os: 'Chrome 141',
  app_version: '2026.10.22',
  language: 'vi',
  signed_in: false,
  online: true,
  error_type: 'FirebaseAuthException',
  message: 'popup-blocked for a@b.co',
  stack: 'at signIn (main.dart.js:10:2)',
  breadcrumbs: [{ time: Date.UTC(2026, 9, 24, 2, 58), kind: 'screen', name: '/sign-in' }, { kind: 'tap', name: 'tap_sign_in_google' }],
};

test('parses an error report and scrubs its free text', () => {
  const [row] = parseErrorReports({ reports: [report] }, now, (s) => s.replace('a@b.co', '<email>'));
  assert.equal(row.report_id, '7KQ-4MZ');
  assert.equal(row.message, 'popup-blocked for <email>');
  assert.equal(row.count, 1);
  assert.deepEqual(row.received_at, now);
  assert.equal(row.breadcrumbs[0].name, '/sign-in');
});

test('rejects breadcrumbs that are not route patterns or event names', () => {
  const bad = { ...report, breadcrumbs: [{ kind: 'tap', name: 'Paid 500k for Bob' }] };
  assert.throws(() => parseErrorReports({ reports: [bad] }, now, (s) => s), InvalidPayload);
});

test('rejects unknown platforms and empty batches', () => {
  assert.throws(() => parseErrorReports({ reports: [{ ...report, platform: 'desktop' }] }, now, (s) => s), InvalidPayload);
  assert.throws(() => parseErrorReports({ reports: [] }, now, (s) => s), InvalidPayload);
});

test('parses usage events and rejects free text in names', () => {
  const event = {
    uid: 'kT9mPq2Lr8Xs4Vw6Yz1Ab3Cd',
    session_id: 'a1b2c3d4',
    client_time: Date.UTC(2026, 9, 24, 2, 59),
    kind: 'op',
    name: 'op_save_expense',
    screen: '/groups/:id/expenses/new',
    result: 'success',
    duration_ms: 120,
    platform: 'android',
    app_version: '2026.10.22',
    language: 'en',
    online: true,
  };
  const [row] = parseUsageEvents({ events: [event] }, now);
  assert.equal(row.name, 'op_save_expense');
  assert.equal(row.duration_ms, 120);
  assert.throws(() => parseUsageEvents({ events: [{ ...event, screen: '/groups/aB3dE5fG7hJ9kL1mN2pQ ' }] }, now), InvalidPayload);
});
