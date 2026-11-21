// Campaigns and schedules (R-9 P5, P6; spec AC11–AC13, AC21, AC22). Both run
// on the tick: candidates come from an audience over the traits table, then
// preferences, devices, quiet hours and the weekly cap decide who gets it now.
// A device that is in quiet hours is tried again at a later tick.

import { CronExpressionParser } from 'cron-parser';
import { compileAudience } from './audience_sql.ts';
import { inQuietHours } from './calm.ts';
import { formatMoney } from './money.ts';
import { renderCopy } from './templates.ts';
import { localMinutes } from './time.ts';
import { traitsFresh } from './traits_check.ts';
import type { AudienceSource } from './adapters/bigquery.ts';
import type { Campaign, Config, Schedule, Template } from './config/schema.ts';
import type { BroadcastStore, Debt, Device, Log, Prefs, Pusher, Store } from './ports.ts';

export interface BroadcastDeps {
  config: Config;
  store: Store & BroadcastStore;
  pusher: Pusher;
  audiences: AudienceSource;
  traitsTable: string;
  log: Log;
  now: () => Date;
  /** dev sends a campaign at the first tick after deploy, whatever its send_at. */
  env: 'dev' | 'prd';
  /** When this revision started (dev campaigns are due from then). */
  startedAt: Date;
}

const TICK_MS = 15 * 60_000;

const PREF_OF: Record<string, keyof Prefs> = {
  group_activity: 'groupActivity',
  settle_reminder: 'settleReminder',
  updates: 'updates',
};

export const campaignDue = (c: Campaign, deps: Pick<BroadcastDeps, 'env' | 'startedAt'>, now: Date) => {
  if (!c.enabled || now.getTime() >= Date.parse(c.ends_at)) return false;
  return deps.env === 'dev' ? now >= deps.startedAt : now.getTime() >= Date.parse(c.send_at);
};

/** The schedule's occurrence in the device's clock within the last tick, if any (as a key). */
export const scheduleOccurrence = (s: Schedule, device: Device, now: Date): string | undefined => {
  const tz = device.tzName ?? 'UTC';
  try {
    const it = CronExpressionParser.parse(s.cron, { currentDate: now, tz });
    const prev = it.prev().toDate();
    return now.getTime() - prev.getTime() < TICK_MS ? prev.toISOString().slice(0, 16) : undefined;
  } catch {
    return undefined;
  }
};

const candidates = async (deps: BroadcastDeps, audienceId: string): Promise<string[] | undefined> => {
  const audience = deps.config.audiences.find((a) => a.id === audienceId);
  if (!audience) return undefined;
  const updatedAt = await deps.audiences.updatedAt();
  if (!updatedAt) {
    // Before data-platform's first run in this environment: nothing to pick from yet.
    deps.log({ severity: 'WARNING', kind: 'traits_missing', audience: audienceId });
    return undefined;
  }
  if (!traitsFresh(updatedAt, deps.now())) {
    deps.log({ severity: 'ERROR', kind: 'traits_stale', audience: audienceId });
    return undefined;
  }
  return deps.audiences.uids(compileAudience(audience, deps.config.traits, deps.traitsTable));
};

const quietNow = (deps: BroadcastDeps, device: Device) => {
  const q = deps.config.policy.quiet_hours;
  return inQuietHours(localMinutes(deps.now(), device.tzName, device.tzOffsetMinutes), q.from, q.to);
};

/** One push to one device: prefs, cap, ledger, send. */
const sendOne = async (
  deps: BroadcastDeps,
  uid: string,
  device: Device,
  messageId: string,
  category: string,
  template: Template,
  values: Record<string, string | number>,
  route: string,
): Promise<boolean> => {
  if (!template.push || quietNow(deps, device)) return false;
  if (!(await deps.store.takeWeeklySlot(uid, messageId, deps.now()))) return false;
  if (!(await deps.store.claimSend(messageId, uid, device.id))) return false;
  const copy = renderCopy(template.push[device.locale], device.locale, values);
  const result = await deps.pusher.send(device, { messageId, category, route, ...copy, tag: messageId });
  if (result === 'invalid_token') await deps.store.deleteDevice(uid, device.id);
  return result === 'sent';
};

export const runCampaigns = async (deps: BroadcastDeps): Promise<void> => {
  const now = deps.now();
  for (const c of deps.config.campaigns.filter((x) => campaignDue(x, deps, now))) {
    const template = deps.config.templates.find((t) => t.id === c.template)!;
    const uids = await candidates(deps, c.audience);
    if (!uids) continue;
    if (c.channels.includes('inapp') && template.banner) {
      await deps.store.writeAnnouncement({ id: c.id, banner: template.banner, audienceUids: uids, endsAt: new Date(c.ends_at) });
    }
    if (!c.channels.includes('push')) continue;
    let sent = 0;
    for (const uid of uids) {
      const prefs = await deps.store.getPrefs(uid);
      if (!prefs[PREF_OF[c.category] ?? 'updates']) continue;
      for (const device of await deps.store.getDevices(uid)) {
        if (await sendOne(deps, uid, device, `campaign-${c.id}`, c.category, template, {}, '/')) sent++;
      }
    }
    deps.log({ severity: 'INFO', kind: 'campaign', campaign: c.id, candidates: uids.length, sent });
  }
};

/** The reminder's numbers: the group with the largest debt names the currency and the screen. */
export const reminderValues = (debts: Debt[]) => {
  const owing = debts.filter((d) => d.owesCents > 0);
  if (!owing.length) return undefined;
  const top = owing.reduce((a, b) => (b.owesCents > a.owesCents ? b : a));
  const sameCurrency = owing.filter((d) => d.currencyCode === top.currencyCode);
  return {
    values: {
      total: formatMoney(sameCurrency.reduce((sum, d) => sum + d.owesCents, 0), top.currencyCode),
      people: owing.reduce((n, d) => n + d.creditors, 0),
      group: top.groupName,
    },
    route: `/groups/${top.groupId}/settle`,
  };
};

export const runSchedules = async (deps: BroadcastDeps): Promise<void> => {
  const now = deps.now();
  for (const s of deps.config.schedules.filter((x) => x.enabled)) {
    const template = deps.config.templates.find((t) => t.id === s.template)!;
    const uids = await candidates(deps, s.audience);
    if (!uids) continue;
    let sent = 0;
    for (const uid of uids) {
      const prefs = await deps.store.getPrefs(uid);
      if (!prefs[PREF_OF[s.category] ?? 'updates']) continue;
      const devices = await deps.store.getDevices(uid);
      const due = devices.flatMap((d) => {
        const key = scheduleOccurrence(s, d, now);
        return key ? [{ device: d, key }] : [];
      });
      if (!due.length) continue;
      // Live numbers: the traits only chose the candidates.
      const reminder = s.kind === 'settle_reminder' ? reminderValues(await deps.store.debtsOf(uid)) : undefined;
      if (!reminder) continue;
      for (const { device, key } of due) {
        if (await sendOne(deps, uid, device, `${s.id}-${uid}-${key}`, s.category, template, reminder.values, reminder.route)) sent++;
      }
    }
    deps.log({ severity: 'INFO', kind: 'schedule', schedule: s.id, candidates: uids.length, sent });
  }
};
