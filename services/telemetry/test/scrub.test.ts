import assert from 'node:assert/strict';
import { test } from 'node:test';
import { scrub } from '../src/scrub.ts';

test('removes emails, document paths, IDs, tokens and amounts', () => {
  const input =
    'Sync failed for khoi.do@example.com at groups/aB3dE5fG7hJ9kL1mN2pQ/expenses/Zx9Yw8Vu7Ts6Rq5Po4Nm ' +
    'uid kT9mPq2Lr8Xs4Vw6Yz1Ab3Cd token 3f2b8c1e-9a4d-4e7b-8c6f-1a2b3c4d5e6f amount 1,500,000 and 250000';
  const out = scrub(input);
  for (const leaked of ['khoi.do@example.com', 'aB3dE5fG7hJ9kL1mN2pQ', 'Zx9Yw8Vu7Ts6Rq5Po4Nm', 'kT9mPq2Lr8Xs4Vw6Yz1Ab3Cd', '3f2b8c1e', '1,500,000', '250000']) {
    assert.ok(!out.includes(leaked), `${leaked} leaked into: ${out}`);
  }
  assert.match(out, /groups\/<id>/);
});

test('keeps line and column numbers in stack traces', () => {
  const stack = '#0      SyncPusher.push (package:simsplit/data/sync/pusher.dart:1234:17)';
  assert.equal(scrub(stack), stack);
});

test('keeps ordinary words and short numbers', () => {
  assert.equal(scrub('FirebaseException: permission-denied after 2 retries'), 'FirebaseException: permission-denied after 2 retries');
});
