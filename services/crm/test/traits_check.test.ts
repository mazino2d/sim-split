import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { loadConfig } from '../src/config/load.ts';
import { compareTraits, traitsFresh } from '../src/traits_check.ts';

const { config } = loadConfig(resolve(import.meta.dirname, '../../../crm'));

const contract = new Map([
  ['uid', 'STRING'],
  ['platform', 'STRING'],
  ['language', 'STRING'],
  ['app_version', 'STRING'],
  ['signup_days', 'INTEGER'],
  ['last_active_days', 'INTEGER'],
  ['sessions_30d', 'INTEGER'],
  ['open_groups', 'INTEGER'],
  ['shared_groups', 'INTEGER'],
  ['owes_groups', 'INTEGER'],
  ['owed_groups', 'INTEGER'],
  ['oldest_unsettled_days', 'INTEGER'],
]);

test('the catalog matches the dbt contract', () => {
  assert.deepEqual(compareTraits(config!.traits, contract), []);
});

test('a missing or retyped column is reported', () => {
  const broken = new Map(contract);
  broken.delete('owes_groups');
  broken.set('platform', 'INTEGER');
  assert.deepEqual(compareTraits(config!.traits, broken), [
    'platform: column platform is INTEGER, expected STRING',
    'owes_groups: column owes_groups is missing',
  ]);
});

test('traits older than 36 hours are stale', () => {
  const now = new Date('2026-12-02T12:00:00Z');
  assert.equal(traitsFresh(new Date('2026-12-01T05:00:00Z'), now), true);
  assert.equal(traitsFresh(new Date('2026-11-30T23:00:00Z'), now), false);
});
