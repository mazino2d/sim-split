// Group activity (R-9 P3, P8; spec AC6–AC10, AC14, AC19, AC26–AC31): an
// activity entry joins its group's batch; when the batch window ends, every
// other member with group activity on gets the kinds of change they chose, one
// push per device. A push is held back (crm_deferred) until the latest of their
// bundle time, the end of their pause and the end of quiet hours; the tick
// delivers it once none of those still holds.

import { createHash } from 'node:crypto';
import { inQuietHours } from './calm.ts';
import { formatMoney } from './money.ts';
import { effectiveQuietHours, eventOf, groupMode, itemsFor, pausedAt, type Prefs } from './prefs.ts';
import { renderCopy } from './templates.ts';
import { localMinutes, nextLocalTime } from './time.ts';
import type { Config, Locale, Trigger } from './config/schema.ts';
import type { Device, FlushScheduler, Log, PendingItem, Pusher, SendLog, Store } from './ports.ts';

export interface ActivityDeps {
  config: Config;
  store: Store;
  pusher: Pusher;
  scheduler: FlushScheduler;
  sends: SendLog;
  log: Log;
  now: () => Date;
}

const ACTIVITY_PATH = /^groups\/([A-Za-z0-9_-]{1,128})\/activity\/([A-Za-z0-9_-]{1,128})$/;

const SOMEONE: Record<Locale, string> = { en: 'Someone', vi: 'Một thành viên' };

const str = (v: unknown, fallback = '') => (typeof v === 'string' ? v : fallback);
const int = (v: unknown) => (typeof v === 'number' && Number.isInteger(v) ? v : 0);

/** Member ids an expense or settlement snapshot names: payer, splits, both parties. */
const involvedIn = (snapshot: Record<string, unknown>): string[] => {
  const ids = new Set<string>();
  for (const key of ['paidByMemberId', 'fromMemberId', 'toMemberId']) {
    const v = snapshot[key];
    if (typeof v === 'string') ids.add(v);
  }
  if (Array.isArray(snapshot.splits)) {
    for (const split of snapshot.splits as { memberId?: unknown }[]) {
      if (typeof split?.memberId === 'string') ids.add(split.memberId);
    }
  }
  return [...ids];
};

/** The matching triggers' view of an activity entry, or undefined when none applies. */
export const toItem = (entryId: string, entry: Record<string, unknown>): PendingItem | undefined => {
  const snapshot = (entry.after ?? entry.before) as Record<string, unknown> | null | undefined;
  if (!snapshot || typeof entry.actorUid !== 'string') return undefined;
  return {
    id: entryId,
    actorUid: entry.actorUid,
    entity: str(entry.entityType),
    action: str(entry.action),
    entityId: str(entry.entityId),
    title: str(snapshot.title),
    amountCents: int(snapshot.amountCents),
    currencyCode: str(snapshot.currencyCode, 'VND'),
    deleted: entry.action === 'delete' || snapshot.deleted === true,
    involved: involvedIn(snapshot),
  };
};

const matches = (trigger: Trigger, item: PendingItem) =>
  trigger.enabled &&
  (trigger.on.entities as string[]).includes(item.entity) &&
  (trigger.on.actions as string[]).includes(item.action);

/** Stable 0–99 bucket per user and trigger, for `rollout`. */
export const bucket = (uid: string, triggerId: string) =>
  createHash('sha256').update(`${triggerId}:${uid}`).digest().readUInt16BE(0) % 100;

/** Eventarc: a new activity entry at `documentPath`. */
export const onActivity = async (deps: ActivityDeps, documentPath: string | undefined): Promise<void> => {
  const match = documentPath ? ACTIVITY_PATH.exec(documentPath) : null;
  if (!match) {
    deps.log({ severity: 'WARNING', kind: 'event_ignored', reason: 'path' });
    return;
  }
  const [, groupId, entryId] = match;
  const entry = await deps.store.getActivity(groupId, entryId);
  const item = entry && toItem(entryId, entry);
  // Only the kinds a user can switch on are batched (a group rename is not).
  if (!item || !eventOf(item)) return;
  const triggers = deps.config.triggers.filter((t) => matches(t, item));
  if (!triggers.length) return;
  const group = await deps.store.getGroup(groupId);
  if (!group || group.isArchived || group.deleted) return;
  for (const trigger of triggers) {
    const minutes = Number(trigger.batch_window.slice(0, -1));
    const proposed = new Date(deps.now().getTime() + minutes * 60_000);
    const { windowEnd, opened } = await deps.store.addPending(groupId, trigger.id, item, proposed);
    if (opened) await deps.scheduler.scheduleFlush(groupId, trigger.id, windowEnd);
  }
};

const BUNDLE_AFTER_WINDOW_MIN: Record<string, number> = { '30m': 20, '1h': 50 };
const DAILY_AT = '19:00';

/**
 * When a push to this device may go out, or undefined for now: the latest of
 * the end of the user's pause, the end of quiet hours and, at flush time,
 * their bundle time (AC28, AC30, AC31).
 */
export const holdUntil = (
  deps: Pick<ActivityDeps, 'config'>,
  prefs: Prefs,
  device: Device,
  now: Date,
  windowEnd?: Date,
): Date | undefined => {
  const holds: Date[] = [];
  const paused = pausedAt(prefs, now);
  if (paused) holds.push(paused);
  const quiet = effectiveQuietHours(deps.config.policy.quiet_hours, prefs);
  if (inQuietHours(localMinutes(now, device.tzName, device.tzOffsetMinutes), quiet.from, quiet.to)) {
    holds.push(nextLocalTime(now, quiet.to, device.tzName, device.tzOffsetMinutes));
  }
  if (windowEnd) {
    if (prefs.bundle === 'daily') holds.push(nextLocalTime(now, DAILY_AT, device.tzName, device.tzOffsetMinutes));
    const extra = BUNDLE_AFTER_WINDOW_MIN[prefs.bundle];
    if (extra) holds.push(new Date(windowEnd.getTime() + extra * 60_000));
  }
  const latest = holds.reduce<Date | undefined>((a, b) => (!a || b > a ? b : a), undefined);
  return latest && latest > now ? latest : undefined;
};

/** What this member hears about from these items, if anything (prefs, group mode, involvement). */
const forRecipient = async (deps: ActivityDeps, uid: string, groupId: string, items: PendingItem[]) => {
  const prefs = await deps.store.getPrefs(uid);
  if (!prefs.groupActivity) return undefined;
  const mode = groupMode(prefs, groupId, deps.now());
  if (mode === 'off') return undefined;
  const needsMember = prefs.onlyInvolvingMe || mode === 'involving';
  const memberId = needsMember ? (await deps.store.getMembers(groupId)).get(uid)?.memberId : undefined;
  const mine = itemsFor(prefs, mode, memberId, items.filter((i) => i.actorUid !== uid));
  return mine.length ? { prefs, items: mine } : undefined;
};

/** Cloud Tasks: the batch window of a group has ended. */
export const onFlush = async (deps: ActivityDeps, groupId: string, triggerId: string, windowEnd: Date): Promise<void> => {
  const trigger = deps.config.triggers.find((t) => t.id === triggerId);
  const items = await deps.store.takePending(groupId, triggerId, windowEnd);
  if (!trigger || !trigger.enabled || !items?.length) return;
  const group = await deps.store.getGroup(groupId);
  if (!group || group.isArchived || group.deleted) return;
  const messageId = `${trigger.id}-${groupId}-${windowEnd.getTime()}`;
  let sent = 0;
  let held = 0;
  for (const uid of group.memberUids) {
    if (bucket(uid, trigger.id) >= trigger.rollout) continue;
    const recipient = await forRecipient(deps, uid, groupId, items);
    if (!recipient) continue;
    for (const device of await deps.store.getDevices(uid)) {
      const until = holdUntil(deps, recipient.prefs, device, deps.now(), windowEnd);
      if (until) {
        await deps.store.defer({
          key: `${uid}_${device.id}_${groupId}_${trigger.id}`,
          uid,
          deviceId: device.id,
          groupId,
          triggerId: trigger.id,
          messageId,
          deliverAfter: until,
          items: recipient.items,
        });
        held++;
        continue;
      }
      if (await deliver(deps, trigger, uid, device, groupId, messageId, recipient.items)) sent++;
    }
  }
  deps.log({ severity: 'INFO', kind: 'flush', trigger: trigger.id, items: items.length, sent, held });
};

/** Tick: held-back messages that are due. One that is still paused or in quiet hours waits again. */
export const deliverDeferred = async (deps: ActivityDeps): Promise<void> => {
  for (const d of await deps.store.dueDeferred(deps.now())) {
    await deps.store.deleteDeferred(d.key);
    const trigger = deps.config.triggers.find((t) => t.id === d.triggerId);
    if (!trigger?.enabled) continue;
    const group = await deps.store.getGroup(d.groupId);
    if (!group || group.isArchived || group.deleted || !group.memberUids.includes(d.uid)) continue;
    // Choices changed while it waited apply too (AC34).
    const recipient = await forRecipient(deps, d.uid, d.groupId, d.items);
    if (!recipient) continue;
    const device = (await deps.store.getDevices(d.uid)).find((x) => x.id === d.deviceId);
    if (!device) continue;
    const until = holdUntil(deps, recipient.prefs, device, deps.now());
    if (until) {
      await deps.store.defer({ ...d, deliverAfter: until, items: recipient.items });
      continue;
    }
    await deliver(deps, trigger, d.uid, device, d.groupId, d.messageId, recipient.items);
  }
};

const deliver = async (
  deps: ActivityDeps,
  trigger: Trigger,
  uid: string,
  device: Device,
  groupId: string,
  messageId: string,
  items: PendingItem[],
): Promise<boolean> => {
  const template = deps.config.templates.find((t) => t.id === trigger.template);
  const group = await deps.store.getGroup(groupId);
  if (!template?.push || !group) return false;
  if (!(await deps.store.claimSend(messageId, uid, device.id))) return false;
  const members = await deps.store.getMembers(groupId);
  const locale = device.locale;
  const single = items.length === 1 ? items[0] : undefined;
  const copy = single || !template.push_batched ? template.push[locale] : template.push_batched[locale];
  const last = single ?? items[items.length - 1];
  const rendered = renderCopy(copy, locale, {
    group: group.name,
    actor: members.get(last.actorUid)?.name ?? SOMEONE[locale],
    title: last.title,
    amount: formatMoney(last.amountCents, last.currencyCode),
    count: items.length,
    entity: last.entity,
    action: last.action,
  });
  const route =
    single && single.entity === 'expense' && !single.deleted
      ? `/groups/${groupId}/expenses/${single.entityId}`
      : `/groups/${groupId}`;
  const result = await deps.pusher.send(device, {
    messageId,
    category: trigger.category,
    source: `trigger:${trigger.id}`,
    route,
    title: rendered.title,
    body: rendered.body,
    tag: `${trigger.id}-${groupId}`,
  });
  deps.sends.record({
    sent_at: deps.now().toISOString(),
    message_id: messageId,
    source: 'trigger',
    source_id: trigger.id,
    category: trigger.category,
    uid,
    platform: device.platform,
    locale: device.locale,
    result,
  });
  if (result === 'invalid_token') await deps.store.deleteDevice(uid, device.id);
  if (result !== 'sent') deps.log({ severity: 'WARNING', kind: 'send_failed', result, platform: device.platform });
  return result === 'sent';
};
