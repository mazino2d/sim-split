// Cross-file checks and calm limits (spec AC16). A config that passes here is
// what the service runs.

import { CronExpressionParser } from 'cron-parser';
import {
  BANNER_BODY_MAX,
  BANNER_TITLE_MAX,
  BATCH_WINDOW_MAX_MINUTES,
  BATCH_WINDOW_MIN_MINUTES,
  MAX_NON_GROUP_PER_WEEK,
  MIN_SCHEDULE_INTERVAL_DAYS,
  PUSH_BODY_MAX,
  PUSH_TITLE_MAX,
  QUIET_FROM_LATEST,
  QUIET_TO_EARLIEST,
  minutesOf,
} from '../calm.ts';
import { checkAudience } from '../audience.ts';
import { argumentsOf, renderCopy, sampleValues, variantsOf, type SourceKind } from '../templates.ts';
import { ACTIVITY_EVENTS, type Config, type Template } from './schema.ts';
import type { Problem } from './load.ts';

const DAY_MS = 24 * 60 * 60 * 1000;

export interface CheckOptions {
  /** Campaigns that start before this are flagged (the PR is merged after it). */
  now?: Date;
}

export const checkConfig = (config: Config, options: CheckOptions = {}): { problems: Problem[]; warnings: Problem[] } => {
  const problems: Problem[] = [];
  const warnings: Problem[] = [];
  const add = (file: string, message: string) => problems.push({ file, message });

  // Policy: may be stricter than the calm limits, never looser.
  const { policy } = config;
  const quiet = policy.quiet_hours;
  const fromOk = minutesOf(quiet.from) >= 12 * 60 && minutesOf(quiet.from) <= minutesOf(QUIET_FROM_LATEST);
  const toOk = minutesOf(quiet.to) >= minutesOf(QUIET_TO_EARLIEST) && minutesOf(quiet.to) <= 12 * 60;
  if (!fromOk || !toOk) {
    add('policy.yaml', `quiet_hours must cover at least ${QUIET_FROM_LATEST}–${QUIET_TO_EARLIEST}`);
  }
  if (policy.caps.non_group_per_user_per_week > MAX_NON_GROUP_PER_WEEK) {
    add('policy.yaml', `caps.non_group_per_user_per_week can be at most ${MAX_NON_GROUP_PER_WEEK}`);
  }

  // Unique ids per kind.
  const unique = (kind: string, ids: string[]) => {
    const seen = new Set<string>();
    for (const id of ids) {
      if (seen.has(id)) add(kind, `"${id}" is defined twice`);
      seen.add(id);
    }
  };
  unique('categories.yaml', config.categories.map((c) => c.id));
  unique('traits.yaml', config.traits.map((t) => t.name));

  const categories = new Map(config.categories.map((c) => [c.id, c]));
  const traits = new Map(config.traits.map((t) => [t.name, t]));
  const audiences = new Map(config.audiences.map((a) => [a.id, a]));
  const templates = new Map(config.templates.map((t) => [t.id, t]));

  // Only per-group categories (group activity, which the user can mute per
  // group) may be on before the user turns them on.
  for (const c of config.categories) {
    if (c.default === 'on' && !c.per_group) {
      add('categories.yaml', `${c.id}: only a per-group category may default to on`);
    }
  }

  // Event switches (R-9 AC26): only within a per-group category, each one a
  // kind of change the sender knows (its camelCase id is the pref key).
  for (const c of config.categories) {
    if (!c.events) continue;
    if (!c.per_group) add('categories.yaml', `${c.id}: only a per-group category may have events`);
    const seen = new Set<string>();
    for (const e of c.events) {
      if (seen.has(e.id)) add('categories.yaml', `${c.id}: event "${e.id}" is defined twice`);
      seen.add(e.id);
      if (!(ACTIVITY_EVENTS as readonly string[]).includes(e.id)) {
        add('categories.yaml', `${c.id}: unknown event "${e.id}" (known: ${ACTIVITY_EVENTS.join(', ')})`);
      }
    }
  }

  for (const t of config.traits) {
    if (t.values && new Set(t.values).size !== t.values.length) add('traits.yaml', `${t.name}: values repeat`);
  }

  for (const a of config.audiences) {
    for (const message of checkAudience(a, traits)) add(`audiences/${a.id}.yaml`, message);
  }

  const usedTemplates = new Map<string, SourceKind[]>();
  const useTemplate = (file: string, id: string, kind: SourceKind, needs: ('push' | 'banner')[]) => {
    const template = templates.get(id);
    if (!template) return add(file, `unknown template "${id}"`);
    usedTemplates.set(id, [...(usedTemplates.get(id) ?? []), kind]);
    for (const variant of needs) {
      if (!template[variant]) add(file, `template "${id}" has no ${variant} copy`);
    }
  };
  const needCategory = (file: string, id: string) => {
    const category = categories.get(id);
    if (!category) add(file, `unknown category "${id}"`);
    return category;
  };
  const needAudience = (file: string, id: string) => {
    if (!audiences.has(id)) add(file, `unknown audience "${id}"`);
  };

  for (const t of config.triggers) {
    const file = `triggers/${t.id}.yaml`;
    const category = needCategory(file, t.category);
    if (category && !category.per_group) add(file, `a trigger's category must be per group (${t.category} is not)`);
    const minutes = Number(t.batch_window.slice(0, -1));
    if (minutes < BATCH_WINDOW_MIN_MINUTES || minutes > BATCH_WINDOW_MAX_MINUTES) {
      add(file, `batch_window must be ${BATCH_WINDOW_MIN_MINUTES}m–${BATCH_WINDOW_MAX_MINUTES}m`);
    }
    useTemplate(file, t.template, 'trigger', ['push']);
    const template = templates.get(t.template);
    if (template && !template.push_batched) add(file, `template "${t.template}" needs push_batched copy`);
  }

  for (const s of config.schedules) {
    const file = `schedules/${s.id}.yaml`;
    const category = needCategory(file, s.category);
    if (category?.per_group) add(file, `a schedule cannot use per-group category ${s.category}`);
    if (category?.default === 'on') add(file, `a schedule's category must be off until the user turns it on`);
    needAudience(file, s.audience);
    useTemplate(file, s.template, s.kind, ['push']);
    try {
      const it = CronExpressionParser.parse(s.cron, { currentDate: new Date('2026-01-05T00:00:00Z'), tz: 'UTC' });
      let previous = it.next().toDate().getTime();
      for (let i = 0; i < 8; i++) {
        const next = it.next().toDate().getTime();
        if (next - previous < MIN_SCHEDULE_INTERVAL_DAYS * DAY_MS - 1) {
          add(file, `cron fires more than once every ${MIN_SCHEDULE_INTERVAL_DAYS} days`);
          break;
        }
        previous = next;
      }
    } catch (e) {
      add(file, `cron: ${(e as Error).message}`);
    }
  }

  for (const c of config.campaigns) {
    const file = `campaigns/${c.id}.yaml`;
    const category = needCategory(file, c.category);
    if (category?.per_group) add(file, `a campaign cannot use per-group category ${c.category}`);
    if (category?.default === 'on' && c.channels.includes('push')) {
      add(file, `a push campaign's category must be off until the user turns it on`);
    }
    needAudience(file, c.audience);
    useTemplate(file, c.template, 'campaign', c.channels.map((ch) => (ch === 'inapp' ? 'banner' : 'push')));
    const start = Date.parse(c.send_at);
    const end = Date.parse(c.ends_at);
    if (end <= start) add(file, 'ends_at must be after send_at');
    if (options.now && c.enabled && end <= options.now.getTime()) {
      warnings.push({ file, message: 'ends_at has passed; it will never be sent' });
    } else if (options.now && c.enabled && start - options.now.getTime() < 60 * 60 * 1000) {
      warnings.push({ file, message: 'send_at is less than an hour away; it goes out at the first tick after `crm apply`' });
    }
  }

  for (const t of config.templates) {
    const file = `templates/${t.id}.yaml`;
    const kinds = usedTemplates.get(t.id);
    if (!kinds) warnings.push({ file, message: 'not used by any trigger, schedule or campaign' });
    problems.push(...checkTemplate(t, kinds ?? []).map((message) => ({ file, message })));
  }

  return { problems, warnings };
};

/** Variables declared and used match; every copy renders and fits. */
export const checkTemplate = (template: Template, kinds: SourceKind[]): string[] => {
  const problems: string[] = [];
  const declared = new Set(template.vars);
  for (const kind of kinds) {
    const offered = Object.keys(sampleValues(kind, 'en'));
    for (const v of declared) {
      if (!offered.includes(v)) problems.push(`variable "${v}" is not available for ${kind} messages`);
    }
  }
  for (const { variant, locale, copy } of variantsOf(template)) {
    const where = `${variant}.${locale}`;
    try {
      for (const part of [copy.title, copy.body]) {
        for (const name of argumentsOf(part)) {
          if (!declared.has(name)) problems.push(`${where}: uses undeclared variable "${name}"`);
        }
      }
      const kind = kinds[0] ?? 'campaign';
      const values = Object.fromEntries(template.vars.map((v) => [v, sampleValues(kind, locale)[v] ?? v]));
      const rendered = renderCopy(copy, locale, values);
      const [titleMax, bodyMax] = variant === 'banner' ? [BANNER_TITLE_MAX, BANNER_BODY_MAX] : [PUSH_TITLE_MAX, PUSH_BODY_MAX];
      if (rendered.title.length > titleMax) problems.push(`${where}: title is longer than ${titleMax} characters`);
      if (rendered.body.length > bodyMax) problems.push(`${where}: body is longer than ${bodyMax} characters`);
    } catch (e) {
      problems.push(`${where}: ${(e as Error).message}`);
    }
  }
  return problems;
};
