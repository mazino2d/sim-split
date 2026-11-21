// Group activity (R-9 P3, spec AC6–AC10, AC14, AC19): an activity entry joins
// its group's batch; when the batch window ends, every other member with group
// activity on gets one push per device, held back during quiet hours.

import { createHash } from 'node:crypto';
import { inQuietHours } from './calm.ts';
import { formatMoney } from './money.ts';
import { renderCopy } from './templates.ts';
import { localMinutes, nextLocalTime } from './time.ts';
import type { Config, Locale, Trigger } from './config/schema.ts';
import type { Device, FlushScheduler, Log, PendingItem, Pusher, Store } from './ports.ts';

export interface ActivityDeps {
  config: Config;
  store: Store;
  pusher: Pusher;
  scheduler: FlushScheduler;
  log: Log;
  now: () => Date;
}

const ACTIVITY_PATH = /^groups\/([A-Za-z0-9_-]{1,128})\/activity\/([A-Za-z0-9_-]{1,128})$/;

const SOMEONE: Record<Locale, string> = { en: 'Someone', vi: 'Một thành viên' };

const str = (v: unknown, fallback = '') => (typeof v === 'string' ? v : fallback);
const int = (v: unknown) => (typeof v === 'number' && Number.isInteger(v) ? v : 0);

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
  if (!item) return;
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

/** Cloud Tasks: the batch window of a group has ended. */
export const onFlush = async (deps: ActivityDeps, groupId: string, triggerId: string, windowEnd: Date): Promise<void> => {
  const trigger = deps.config.triggers.find((t) => t.id === triggerId);
  const items = await deps.store.takePending(groupId, triggerId, windowEnd);
  if (!trigger || !trigger.enabled || !items?.length) return;
  const group = await deps.store.getGroup(groupId);
  if (!group || group.isArchived || group.deleted) return;
  const messageId = `${trigger.id}-${groupId}-${windowEnd.getTime()}`;
  let sent = 0;
  for (const uid of group.memberUids) {
    const forUid = items.filter((i) => i.actorUid !== uid);
    if (!forUid.length || bucket(uid, trigger.id) >= trigger.rollout) continue;
    const prefs = await deps.store.getPrefs(uid);
    if (!prefs.groupActivity || prefs.mutedGroups.includes(groupId)) continue;
    for (const device of await deps.store.getDevices(uid)) {
      const quiet = deps.config.policy.quiet_hours;
      const now = deps.now();
      if (inQuietHours(localMinutes(now, device.tzName, device.tzOffsetMinutes), quiet.from, quiet.to)) {
        await deps.store.defer({
          key: `${uid}_${device.id}_${groupId}_${trigger.id}`,
          uid,
          deviceId: device.id,
          groupId,
          triggerId: trigger.id,
          messageId,
          deliverAfter: nextLocalTime(now, quiet.to, device.tzName, device.tzOffsetMinutes),
          items: forUid,
        });
        continue;
      }
      if (await deliver(deps, trigger, uid, device, groupId, messageId, forUid)) sent++;
    }
  }
  deps.log({ severity: 'INFO', kind: 'flush', trigger: trigger.id, items: items.length, sent });
};

/** Tick: held-back messages whose quiet hours are over. */
export const deliverDeferred = async (deps: ActivityDeps): Promise<void> => {
  for (const d of await deps.store.dueDeferred(deps.now())) {
    await deps.store.deleteDeferred(d.key);
    const trigger = deps.config.triggers.find((t) => t.id === d.triggerId);
    if (!trigger?.enabled) continue;
    const group = await deps.store.getGroup(d.groupId);
    if (!group || group.isArchived || group.deleted || !group.memberUids.includes(d.uid)) continue;
    const prefs = await deps.store.getPrefs(d.uid);
    if (!prefs.groupActivity || prefs.mutedGroups.includes(d.groupId)) continue;
    const device = (await deps.store.getDevices(d.uid)).find((x) => x.id === d.deviceId);
    if (device) await deliver(deps, trigger, d.uid, device, d.groupId, d.messageId, d.items);
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
  const names = await deps.store.getMemberNames(groupId);
  const locale = device.locale;
  const single = items.length === 1 ? items[0] : undefined;
  const copy = single || !template.push_batched ? template.push[locale] : template.push_batched[locale];
  const last = single ?? items[items.length - 1];
  const rendered = renderCopy(copy, locale, {
    group: group.name,
    actor: names.get(last.actorUid) ?? SOMEONE[locale],
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
    route,
    title: rendered.title,
    body: rendered.body,
    tag: `${trigger.id}-${groupId}`,
  });
  if (result === 'invalid_token') await deps.store.deleteDevice(uid, device.id);
  if (result !== 'sent') deps.log({ severity: 'WARNING', kind: 'send_failed', result, platform: device.platform });
  return result === 'sent';
};
