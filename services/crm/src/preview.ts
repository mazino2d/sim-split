// Markdown for humans: `crm render` (every message) and `crm plan` (what a PR
// changes), posted as the PR comment (spec AC17).

import { describeAudience } from './audience.ts';
import { renderCopy, sampleValues, type SourceKind } from './templates.ts';
import type { Config, Template } from './config/schema.ts';

const KINDS = ['triggers', 'schedules', 'campaigns', 'audiences', 'templates'] as const;
type Kind = (typeof KINDS)[number];

const escapeCell = (s: string) => s.replaceAll('|', '\\|').replaceAll('\n', ' ');

const kindOf = (config: Config, templateId: string): SourceKind => {
  if (config.triggers.some((t) => t.template === templateId)) return 'trigger';
  const schedule = config.schedules.find((s) => s.template === templateId);
  return schedule ? schedule.kind : 'campaign';
};

export const templatePreview = (config: Config, template: Template): string => {
  const kind = kindOf(config, template.id);
  const rows: string[] = ['| Variant | EN | VI |', '| --- | --- | --- |'];
  for (const variant of ['push', 'push_batched', 'banner'] as const) {
    const copies = template[variant];
    if (!copies) continue;
    const cell = (locale: 'en' | 'vi') => {
      const values = Object.fromEntries(template.vars.map((v) => [v, sampleValues(kind, locale)[v] ?? v]));
      try {
        const r = renderCopy(copies[locale], locale, values);
        return `**${escapeCell(r.title)}**<br>${escapeCell(r.body)}`;
      } catch (e) {
        return `⚠️ ${escapeCell((e as Error).message)}`;
      }
    };
    rows.push(`| ${variant} | ${cell('en')} | ${cell('vi')} |`);
  }
  return rows.join('\n');
};

const itemsOf = (config: Config, kind: Kind) => config[kind] as { id: string }[];

const summary = (config: Config, kind: Kind, id: string): string => {
  const traits = new Map(config.traits.map((t) => [t.name, t]));
  switch (kind) {
    case 'triggers': {
      const t = config.triggers.find((x) => x.id === id)!;
      return `${t.enabled ? 'on' : 'off'} · ${t.category} · ${t.on.entities.join('/')} ${t.on.actions.join('/')} · batch ${t.batch_window} · rollout ${t.rollout}% · template \`${t.template}\``;
    }
    case 'schedules': {
      const s = config.schedules.find((x) => x.id === id)!;
      return `${s.enabled ? 'on' : 'off'} · ${s.category} · \`${s.cron}\` device time · audience \`${s.audience}\` · template \`${s.template}\``;
    }
    case 'campaigns': {
      const c = config.campaigns.find((x) => x.id === id)!;
      return `${c.enabled ? 'on' : 'off'} · ${c.category} · ${c.channels.join(' + ')} · ${c.send_at} → ${c.ends_at} · audience \`${c.audience}\` · template \`${c.template}\``;
    }
    case 'audiences': {
      const a = config.audiences.find((x) => x.id === id)!;
      return `${a.description}: ${describeAudience(a, traits)}`;
    }
    case 'templates':
      return '';
  }
};

const section = (config: Config, kind: Kind, id: string): string => {
  const lines = [`- \`${kind}/${id}\`${kind === 'templates' ? '' : `: ${summary(config, kind, id)}`}`];
  if (kind === 'templates') {
    lines.push('', templatePreview(config, config.templates.find((t) => t.id === id)!), '');
  }
  return lines.join('\n');
};

export const renderAll = (config: Config): string => {
  const out = ['## CRM config', '', policyLine(config), ''];
  for (const kind of KINDS) {
    const items = itemsOf(config, kind);
    if (!items.length) continue;
    out.push(`### ${kind}`, '', ...items.map((i) => section(config, kind, i.id)), '');
  }
  return out.join('\n');
};

const policyLine = (config: Config) => {
  const p = config.policy;
  return `Policy: kill switch **${p.kill_switch ? 'ON' : 'off'}** · quiet hours ${p.quiet_hours.from}–${p.quiet_hours.to} device time · at most ${p.caps.non_group_per_user_per_week} non-group push per user per week`;
};

const stable = (value: unknown) => JSON.stringify(value);

/** What changes between the config on main and this PR, with previews of changed messages. */
export const renderPlan = (base: Config | undefined, head: Config): string => {
  const out = ['## CRM plan', ''];
  let changes = 0;
  if (!base || stable(base.policy) !== stable(head.policy)) {
    out.push(`**Policy changed.** ${policyLine(head)}`, '');
    changes++;
  }
  if (!base || stable(base.categories) !== stable(head.categories)) {
    out.push('**Categories changed:** ' + head.categories.map((c) => `${c.id} (${c.default})`).join(', '), '');
    changes++;
  }
  if (!base || stable(base.traits) !== stable(head.traits)) {
    out.push('**Trait catalog changed:** ' + (head.traits.map((t) => `${t.name} (${t.type})`).join(', ') || 'empty'), '');
    changes++;
  }
  for (const kind of KINDS) {
    const before = new Map((base ? itemsOf(base, kind) : []).map((i) => [i.id, stable(i)]));
    const after = new Map(itemsOf(head, kind).map((i) => [i.id, stable(i)]));
    const lines: string[] = [];
    for (const [id, json] of after) {
      if (!before.has(id)) lines.push(section(head, kind, id).replace(/^- /, '- ➕ '));
      else if (before.get(id) !== json) lines.push(section(head, kind, id).replace(/^- /, '- ✏️ '));
    }
    for (const id of before.keys()) if (!after.has(id)) lines.push(`- ➖ \`${kind}/${id}\` removed`);
    if (lines.length) {
      out.push(`### ${kind}`, '', ...lines, '');
      changes += lines.length;
    }
  }
  if (changes === 0) out.push('No change to what is sent.');
  out.push('', '_Merging applies this to dev; production waits for approval in the `crm-prd` environment._');
  return out.join('\n');
};
