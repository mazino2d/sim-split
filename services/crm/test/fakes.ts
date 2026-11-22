// In-memory Store, Pusher and FlushScheduler for tests.

import { parsePrefs, type PrefDefaults } from '../src/prefs.ts';
import type { Announcement, BroadcastStore, Debt, Deferred, Device, FlushScheduler, GroupDoc, PendingItem, Prefs, Push, Pusher, SendResult, Store } from '../src/ports.ts';

/** The defaults in crm/categories.yaml. */
export const DEFAULTS: PrefDefaults = {
  groupActivity: true,
  settleReminder: false,
  updates: false,
  activityEvents: { expenseCreate: true, expenseUpdate: true, expenseDelete: true, settlement: true, memberJoin: false },
};

export class FakeStore implements Store, BroadcastStore {
  ledger = new Map<string, { at: Date; messageId: string }>();
  debts = new Map<string, Debt[]>();
  announcements = new Map<string, Announcement>();
  activity = new Map<string, Record<string, unknown>>();
  groups = new Map<string, GroupDoc>();
  /** groupId → linkedUid → name. */
  members = new Map<string, Map<string, string>>();
  /** groupId → linkedUid → member id; `m-<uid>` when not set. */
  memberIds = new Map<string, Map<string, string>>();
  pending = new Map<string, { windowEnd: Date; items: PendingItem[] }>();
  /** notificationPrefs as stored (Dates stand in for Timestamps). */
  prefs = new Map<string, Record<string, unknown>>();
  /** uid → deviceId → when its last test notification went out. */
  tests = new Map<string, Map<string, Date>>();
  devices = new Map<string, Device[]>();
  sends = new Set<string>();
  deferred = new Map<string, Deferred>();

  async getActivity(g: string, a: string) {
    return this.activity.get(`${g}/${a}`);
  }
  async getGroup(g: string) {
    return this.groups.get(g);
  }
  async getMembers(g: string) {
    const names = this.members.get(g) ?? new Map<string, string>();
    return new Map([...names].map(([uid, name]) => [uid, { memberId: this.memberIds.get(g)?.get(uid) ?? `m-${uid}`, name }]));
  }
  async addPending(g: string, t: string, item: PendingItem, windowEnd: Date) {
    const key = `${g}_${t}`;
    const current = this.pending.get(key);
    if (current) {
      if (!current.items.some((i) => i.id === item.id)) current.items.push(item);
      return { windowEnd: current.windowEnd, opened: false };
    }
    this.pending.set(key, { windowEnd, items: [item] });
    return { windowEnd, opened: true };
  }
  async takePending(g: string, t: string, windowEnd: Date) {
    const key = `${g}_${t}`;
    const current = this.pending.get(key);
    if (!current || current.windowEnd.getTime() !== windowEnd.getTime()) return undefined;
    this.pending.delete(key);
    return current.items;
  }
  async getPrefs(uid: string): Promise<Prefs> {
    return parsePrefs(this.prefs.get(uid), DEFAULTS);
  }
  async getDevices(uid: string) {
    return this.devices.get(uid) ?? [];
  }
  async getDevice(uid: string, id: string) {
    return this.devices.get(uid)?.find((d) => d.id === id);
  }
  async claimTest(uid: string, id: string, now: Date, minGapMs: number) {
    const byDevice = this.tests.get(uid) ?? new Map<string, Date>();
    const last = byDevice.get(id);
    if (last && now.getTime() - last.getTime() < minGapMs) return false;
    this.tests.set(uid, byDevice.set(id, now));
    return true;
  }
  async deleteDevice(uid: string, id: string) {
    this.devices.set(uid, (this.devices.get(uid) ?? []).filter((d) => d.id !== id));
  }
  async claimSend(m: string, uid: string, d: string) {
    const key = `${m}/${uid}_${d}`;
    if (this.sends.has(key)) return false;
    this.sends.add(key);
    return true;
  }
  async defer(entry: Deferred) {
    const current = this.deferred.get(entry.key);
    const items = current ? [...current.items, ...entry.items.filter((i) => !current.items.some((x) => x.id === i.id))] : entry.items;
    const deliverAfter = current && current.deliverAfter < entry.deliverAfter ? current.deliverAfter : entry.deliverAfter;
    this.deferred.set(entry.key, { ...entry, messageId: current?.messageId ?? entry.messageId, deliverAfter, items });
  }
  async dueDeferred(now: Date) {
    return [...this.deferred.values()].filter((d) => d.deliverAfter <= now);
  }
  async deleteDeferred(key: string) {
    this.deferred.delete(key);
  }
  async takeWeeklySlot(uid: string, messageId: string, now: Date) {
    const last = this.ledger.get(uid);
    if (last?.messageId === messageId) return true;
    if (last && now.getTime() - last.at.getTime() < 7 * 24 * 3600_000) return false;
    this.ledger.set(uid, { at: now, messageId });
    return true;
  }
  async debtsOf(uid: string, _now: Date) {
    return this.debts.get(uid) ?? [];
  }
  async writeAnnouncement(a: Announcement) {
    this.announcements.set(a.id, a);
  }
}

export class FakePusher implements Pusher {
  sent: { device: Device; push: Push }[] = [];
  results = new Map<string, SendResult>();
  async send(device: Device, push: Push) {
    const result = this.results.get(device.token) ?? 'sent';
    if (result === 'sent') this.sent.push({ device, push });
    return result;
  }
}

export class FakeScheduler implements FlushScheduler {
  scheduled: { groupId: string; triggerId: string; windowEnd: Date }[] = [];
  async scheduleFlush(groupId: string, triggerId: string, windowEnd: Date) {
    this.scheduled.push({ groupId, triggerId, windowEnd });
  }
}

export class FakeAudiences {
  uidsByQuery: string[] = [];
  updated: Date | undefined = new Date('2026-12-01T05:00:00Z');
  queries: string[] = [];
  async uids(q: { sql: string }) {
    this.queries.push(q.sql);
    return this.uidsByQuery;
  }
  async updatedAt() {
    return this.updated;
  }
}

export class FakeSendLog {
  rows: import('../src/ports.ts').SendRow[] = [];
  flushed = 0;
  record(row: import('../src/ports.ts').SendRow) {
    this.rows.push(row);
  }
  async flush() {
    this.flushed++;
  }
}
