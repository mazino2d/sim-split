// In-memory Store, Pusher and FlushScheduler for tests.

import type { Announcement, BroadcastStore, Debt, Deferred, Device, FlushScheduler, GroupDoc, PendingItem, Prefs, Push, Pusher, SendResult, Store } from '../src/ports.ts';

export class FakeStore implements Store, BroadcastStore {
  ledger = new Map<string, { at: Date; messageId: string }>();
  debts = new Map<string, Debt[]>();
  announcements = new Map<string, Announcement>();
  activity = new Map<string, Record<string, unknown>>();
  groups = new Map<string, GroupDoc>();
  members = new Map<string, Map<string, string>>();
  pending = new Map<string, { windowEnd: Date; items: PendingItem[] }>();
  prefs = new Map<string, Partial<Prefs>>();
  devices = new Map<string, Device[]>();
  sends = new Set<string>();
  deferred = new Map<string, Deferred>();

  async getActivity(g: string, a: string) {
    return this.activity.get(`${g}/${a}`);
  }
  async getGroup(g: string) {
    return this.groups.get(g);
  }
  async getMemberNames(g: string) {
    return this.members.get(g) ?? new Map();
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
    return { groupActivity: true, settleReminder: false, updates: false, mutedGroups: [], ...this.prefs.get(uid) };
  }
  async getDevices(uid: string) {
    return this.devices.get(uid) ?? [];
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
    this.deferred.set(entry.key, { ...entry, messageId: current?.messageId ?? entry.messageId, items });
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
  async debtsOf(uid: string) {
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
