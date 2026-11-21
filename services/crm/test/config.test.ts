import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { loadConfig } from '../src/config/load.ts';
import { checkConfig } from '../src/config/check.ts';
import { renderPlan } from '../src/preview.ts';
import { describeAudience } from '../src/audience.ts';
import { inQuietHours, minutesOf } from '../src/calm.ts';

const REPO_CRM = resolve(import.meta.dirname, '../../../crm');

/** A copy of the repo's crm/ with some files replaced. */
const fixture = (files: Record<string, string> = {}) => {
  const dir = mkdtempSync(join(tmpdir(), 'crm-'));
  cpSync(REPO_CRM, dir, { recursive: true });
  for (const [name, content] of Object.entries(files)) writeFileSync(join(dir, name), content);
  return dir;
};

const problemsOf = (files: Record<string, string>) => {
  const dir = fixture(files);
  try {
    const { config, problems } = loadConfig(dir);
    const all = config ? [...problems, ...checkConfig(config).problems] : problems;
    return all.map((p) => `${p.file}${p.line ? `:${p.line}` : ''} ${p.message}`);
  } finally {
    rmSync(dir, { recursive: true });
  }
};

const POLICY = (quiet = '"21:00"', to = '"08:00"', cap = 1) =>
  `kill_switch: false\nquiet_hours:\n  from: ${quiet}\n  to: ${to}\ncaps:\n  non_group_per_user_per_week: ${cap}\n`;

const TRAITS = `- name: platform
  type: choice
  column: platform
  label: Platform
  values: [android, web]
- name: unsettled_days
  type: days_ago
  column: oldest_unsettled_days
  label: Oldest unsettled debt
- name: has_push
  type: bool
  column: has_push_token
  label: Can get push
- name: owes_groups
  type: number
  column: owes_groups
  label: Groups where they owe money
- name: oldest_unsettled_days
  type: days_ago
  column: oldest_unsettled_days
  label: Oldest unsettled debt
`;

test('the config in the repo is valid', () => {
  const { config, problems } = loadConfig(REPO_CRM);
  assert.deepEqual(problems, []);
  assert.deepEqual(checkConfig(config!).problems, []);
});

test('quiet hours can widen but not narrow', () => {
  assert.deepEqual(problemsOf({ 'policy.yaml': POLICY('"20:00"', '"09:00"') }), []);
  assert.match(problemsOf({ 'policy.yaml': POLICY('"22:00"') })[0], /quiet_hours must cover/);
  assert.match(problemsOf({ 'policy.yaml': POLICY('"21:00"', '"07:30"') })[0], /quiet_hours must cover/);
});

test('the weekly cap cannot be raised', () => {
  assert.match(problemsOf({ 'policy.yaml': POLICY(undefined, undefined, 2) })[0], /at most 1/);
});

test('only per-group categories may default to on', () => {
  const categories = `- id: updates
  default: "on"
  per_group: false
  name: { en: Updates, vi: Cập nhật }
  description: { en: News, vi: Tin }
- id: group_activity
  default: "on"
  per_group: true
  name: { en: Group, vi: Nhóm }
  description: { en: Changes, vi: Thay đổi }
`;
  assert.match(problemsOf({ 'categories.yaml': categories }).join('\n'), /updates: only a per-group category/);
});

test('schema problems name the file and line', () => {
  const template = 'id: group-activity\nvars: [group]\npush:\n  en:\n    title: "{group}"\n    body: Hi\n';
  const problems = problemsOf({ 'templates/group-activity.yaml': template });
  assert.ok(problems.some((p) => /^templates\/group-activity\.yaml:4 push\.vi/.test(p)), problems.join('\n'));
});

test('a file name must match its id', () => {
  const dir = fixture();
  writeFileSync(join(dir, 'templates/other.yaml'), 'id: something\nvars: []\nbanner:\n  en: { title: a, body: b }\n  vi: { title: a, body: b }\n');
  const { problems } = loadConfig(dir);
  rmSync(dir, { recursive: true });
  assert.match(problems[0].message, /must match the file name/);
});

const TEMPLATE = (enBody: string, vars = '[actor, group, title, amount, count, entity, action]') => `id: group-activity
vars: ${vars}
push:
  en: { title: "{group}", body: "${enBody}" }
  vi: { title: "{group}", body: "{actor} đã thêm {title}" }
push_batched:
  en: { title: "{group}", body: "{count} changes" }
  vi: { title: "{group}", body: "{count} thay đổi" }
`;

test('templates use only declared variables that the source offers', () => {
  assert.match(
    problemsOf({ 'templates/group-activity.yaml': TEMPLATE('{actor} added {nope}') }).join('\n'),
    /undeclared variable "nope"/,
  );
  assert.match(
    problemsOf({ 'templates/group-activity.yaml': TEMPLATE('{actor} owes {total}', '[actor, group, title, count, total]') }).join('\n'),
    /"total" is not available for trigger messages/,
  );
});

test('rendered copy must fit a notification', () => {
  const long = 'x'.repeat(241);
  assert.match(problemsOf({ 'templates/group-activity.yaml': TEMPLATE(long) }).join('\n'), /body is longer than 240/);
});

test('a trigger needs batched copy and a sane batch window', () => {
  const trigger = (window: string) => `id: group-activity
enabled: true
category: group_activity
"on": { entities: [expense], actions: [create] }
recipients: group_members_except_actor
batch_window: ${window}
template: group-activity
channels: [push]
rollout: 100
`;
  assert.match(problemsOf({ 'triggers/group-activity.yaml': trigger('1m') }).join('\n'), /batch_window must be 5m–60m/);
  assert.deepEqual(problemsOf({ 'triggers/group-activity.yaml': trigger('15m') }), []);
});

const AUDIENCE = (rules: string) => `id: owes
description: Owes money
match: all
rules:
${rules}`;
const REMINDER = `id: vi
vars: [total, people]
push:
  en: { title: "You still owe {total}", body: "{people} people" }
  vi: { title: "Bạn còn nợ {total}", body: "{people} người" }
`;
const SCHEDULE = (cron: string, category = 'settle_reminder') => `id: weekly
enabled: true
kind: settle_reminder
category: ${category}
cron: "${cron}"
audience: owes
template: vi
channels: [push]
`;

test('schedules fire at most weekly, off-by-default categories only', () => {
  const base = {
    'traits.yaml': TRAITS,
    'audiences/owes.yaml': AUDIENCE('  - { trait: unsettled_days, op: gt, value: 14 }\n'),
    'templates/vi.yaml': REMINDER,
  };
  assert.deepEqual(problemsOf({ ...base, 'schedules/weekly.yaml': SCHEDULE('0 19 * * 0') }), []);
  assert.match(problemsOf({ ...base, 'schedules/weekly.yaml': SCHEDULE('0 19 * * *') }).join('\n'), /more than once every 7 days/);
  assert.match(
    problemsOf({ ...base, 'schedules/weekly.yaml': SCHEDULE('0 19 * * 0', 'group_activity') }).join('\n'),
    /cannot use per-group category/,
  );
});

test('audience rules are checked against the trait catalog', () => {
  const problems = problemsOf({
    'traits.yaml': TRAITS,
    'audiences/owes.yaml': AUDIENCE(
      '  - { trait: platform, op: gt, value: 3 }\n  - { trait: nope, op: eq, value: 1 }\n  - { trait: platform, op: in, value: [ios] }\n',
    ),
  }).join('\n');
  assert.match(problems, /"gt" does not apply to choice trait "platform"/);
  assert.match(problems, /unknown trait "nope"/);
  assert.match(problems, /one of android, web \(got ios\)/);
});

test('audiences read as plain words', () => {
  const dir = fixture({ 'traits.yaml': TRAITS });
  const { config } = loadConfig(dir);
  rmSync(dir, { recursive: true });
  const traits = new Map(config!.traits.map((t) => [t.name, t]));
  const words = describeAudience(
    {
      id: 'a',
      description: 'd',
      match: 'all',
      rules: [
        { trait: 'unsettled_days', op: 'gt', value: 14 },
        { match: 'any', rules: [{ trait: 'platform', op: 'eq', value: 'android' }, { trait: 'has_push', op: 'is', value: true }] },
      ],
    },
    traits,
  );
  assert.equal(words, 'Everyone where Oldest unsettled debt is more than 14 days ago and (Platform is android or Can get push is true)');
});

test('push campaigns need an off-by-default category', () => {
  const campaign = `id: hello
enabled: true
category: group_activity
send_at: "2026-12-01T10:00:00+07:00"
ends_at: "2026-12-08T10:00:00+07:00"
audience: owes
channels: [push]
template: hello
`;
  const problems = problemsOf({
    'traits.yaml': TRAITS,
    'audiences/owes.yaml': AUDIENCE('  - { trait: has_push, op: is, value: true }\n'),
    'templates/hello.yaml': 'id: hello\nvars: []\npush:\n  en: { title: Hi, body: New version }\n  vi: { title: Chào, body: Bản mới }\n',
    'campaigns/hello.yaml': campaign,
  }).join('\n');
  assert.match(problems, /cannot use per-group category/);
});

test('plan shows only what changed', () => {
  const { config } = loadConfig(REPO_CRM);
  assert.match(renderPlan(config, config!), /No change to what is sent/);
  const edited = structuredClone(config!);
  edited.triggers[0].rollout = 10;
  const plan = renderPlan(config, edited);
  assert.match(plan, /✏️ `triggers\/group-activity`: .*rollout 10%/);
  assert.doesNotMatch(plan, /Policy changed/);
});

test('quiet hours wrap midnight', () => {
  assert.equal(inQuietHours(minutesOf('23:30'), '21:00', '08:00'), true);
  assert.equal(inQuietHours(minutesOf('07:59'), '21:00', '08:00'), true);
  assert.equal(inQuietHours(minutesOf('08:00'), '21:00', '08:00'), false);
  assert.equal(inQuietHours(minutesOf('12:00'), '21:00', '08:00'), false);
});
