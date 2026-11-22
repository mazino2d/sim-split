import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { loadConfig } from '../src/config/load.ts';
import { effectiveQuietHours, eventOf, eventPrefKey, groupMode, itemsFor, parsePrefs, pausedAt, prefDefaults } from '../src/prefs.ts';
import type { PendingItem } from '../src/ports.ts';
import { DEFAULTS } from './fakes.ts';

const { config } = loadConfig(resolve(import.meta.dirname, '../../../crm'));
const NOW = new Date('2026-12-01T05:00:00Z');

test('defaults come from crm/categories.yaml (AC26)', () => {
  assert.deepEqual(prefDefaults(config!), DEFAULTS);
  assert.equal(eventPrefKey('expense_create'), 'expenseCreate');
  assert.equal(eventPrefKey('member_join'), 'memberJoin');
});

test('a missing or malformed field is its default', () => {
  const empty = parsePrefs(undefined, DEFAULTS);
  assert.deepEqual(empty, {
    ...DEFAULTS,
    mutedGroups: [],
    onlyInvolvingMe: false,
    bundle: '10m',
    groups: {},
    pausedUntil: undefined,
  });
  const bad = parsePrefs(
    {
      groupActivity: 'yes',
      activityEvents: { memberJoin: 1, expenseDelete: false },
      bundle: 'weekly',
      groups: { g1: { mode: 'loud' }, g2: 'off' },
      pausedUntil: 'tomorrow',
      quietHours: { from: '22:00', to: '08:00' }, // shorter than the policy
      settle: { day: 9, time: '22:00', minDays: 10 },
    },
    DEFAULTS,
  );
  assert.equal(bad.groupActivity, true);
  assert.deepEqual(bad.activityEvents, { ...DEFAULTS.activityEvents, expenseDelete: false });
  assert.equal(bad.bundle, '10m');
  assert.deepEqual(bad.groups, {});
  assert.equal(bad.pausedUntil, undefined);
  assert.equal(bad.quietHours, undefined);
  assert.deepEqual(bad.settle, { day: 0, time: '19:00', minDays: 14 });
});

test('every v2 field is read; Timestamps become Dates', () => {
  const until = new Date('2026-12-02T01:00:00Z');
  const timestamp = { toDate: () => until };
  const p = parsePrefs(
    {
      onlyInvolvingMe: true,
      bundle: 'daily',
      groups: { g1: { mode: 'off', offUntil: timestamp }, g2: { mode: 'involving' } },
      pausedUntil: timestamp,
      quietHours: { from: '20:00', to: '09:30' },
      settle: { day: 6, time: '09:00', minDays: 7 },
    },
    DEFAULTS,
  );
  assert.equal(p.onlyInvolvingMe, true);
  assert.equal(p.bundle, 'daily');
  assert.deepEqual(p.groups, { g1: { mode: 'off', offUntil: until }, g2: { mode: 'involving', offUntil: undefined } });
  assert.equal(p.pausedUntil, until);
  assert.deepEqual(p.quietHours, { from: '20:00', to: '09:30' });
  assert.deepEqual(p.settle, { day: 6, time: '09:00', minDays: 7 });
  assert.equal(pausedAt(p, NOW), until);
  assert.equal(pausedAt(p, new Date(until.getTime() + 1)), undefined);
});

test('group mode: groups wins over mutedGroups; off until a past time is all (AC29)', () => {
  const later = new Date(NOW.getTime() + 3600_000);
  const earlier = new Date(NOW.getTime() - 1);
  const p = parsePrefs(
    {
      mutedGroups: ['g1', 'g2'],
      groups: { g2: { mode: 'all' }, g3: { mode: 'off', offUntil: later }, g4: { mode: 'off', offUntil: earlier }, g5: { mode: 'involving' } },
    },
    DEFAULTS,
  );
  assert.equal(groupMode(p, 'g1', NOW), 'off');
  assert.equal(groupMode(p, 'g2', NOW), 'all');
  assert.equal(groupMode(p, 'g3', NOW), 'off');
  assert.equal(groupMode(p, 'g4', NOW), 'all');
  assert.equal(groupMode(p, 'g5', NOW), 'involving');
  assert.equal(groupMode(p, 'g6', NOW), 'all');
});

test('quiet hours: the wider of policy and user, never narrower (AC31)', () => {
  const policy = { from: '20:00', to: '08:00' };
  assert.deepEqual(effectiveQuietHours(policy, {}), policy);
  assert.deepEqual(effectiveQuietHours(policy, { quietHours: { from: '21:00', to: '10:00' } }), { from: '20:00', to: '10:00' });
  assert.deepEqual(effectiveQuietHours(policy, { quietHours: { from: '18:30', to: '08:00' } }), { from: '18:30', to: '08:00' });
});

const item = (entity: string, action: string, involved: string[] = []): PendingItem => ({
  id: `${entity}-${action}`,
  actorUid: 'ux',
  entity,
  action,
  entityId: 'e',
  title: '',
  amountCents: 0,
  currencyCode: 'VND',
  deleted: false,
  involved,
});

test('each change maps to its switch; other changes to none', () => {
  assert.equal(eventOf(item('expense', 'create')), 'expenseCreate');
  assert.equal(eventOf(item('expense', 'update')), 'expenseUpdate');
  assert.equal(eventOf(item('expense', 'delete')), 'expenseDelete');
  assert.equal(eventOf(item('settlement', 'update')), 'settlement');
  assert.equal(eventOf(item('group', 'join')), 'memberJoin');
  assert.equal(eventOf(item('member', 'join')), 'memberJoin');
  assert.equal(eventOf(item('group', 'update')), undefined);
  assert.equal(eventOf(item('member', 'create')), undefined);
});

test('involving only keeps the member’s expenses and settlements; joins pass (AC27)', () => {
  const items = [item('expense', 'create', ['m1']), item('settlement', 'create', ['m2']), item('group', 'join'), { ...item('expense', 'update'), involved: undefined }];
  const p = parsePrefs({ activityEvents: { memberJoin: true } }, DEFAULTS);
  assert.equal(itemsFor(p, 'all', undefined, items).length, 4);
  assert.deepEqual(itemsFor(p, 'involving', 'm1', items).map((i) => i.id), ['expense-create', 'group-join']);
  assert.deepEqual(itemsFor({ ...p, onlyInvolvingMe: true }, 'all', 'm2', items).map((i) => i.id), ['settlement-create', 'group-join']);
  assert.deepEqual(itemsFor(p, 'involving', undefined, items).map((i) => i.id), ['group-join']);
});
