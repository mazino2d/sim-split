// What the core logic needs from the outside world. Firestore, FCM and Cloud
// Tasks implement these in src/adapters/; tests use in-memory fakes.

import type { Locale } from './config/schema.ts';

export interface GroupDoc {
  name: string;
  memberUids: string[];
  isArchived: boolean;
  deleted: boolean;
}

/** One change waiting in a group's batch (from an activity entry). */
export interface PendingItem {
  id: string; // activity entry id
  actorUid: string;
  entity: string;
  action: string;
  entityId: string;
  title: string;
  amountCents: number;
  currencyCode: string;
  deleted: boolean;
}

export interface Prefs {
  groupActivity: boolean;
  settleReminder: boolean;
  updates: boolean;
  mutedGroups: string[];
}

export interface Device {
  id: string;
  token: string;
  platform: 'android' | 'web';
  locale: Locale;
  tzName?: string;
  tzOffsetMinutes: number;
}

export interface Push {
  messageId: string;
  category: string;
  route: string;
  title: string;
  body: string;
  /** Same tag replaces the previous notification of the group on the device. */
  tag: string;
}

/** A push held back by quiet hours, re-rendered when it is delivered. */
export interface Deferred {
  key: string;
  uid: string;
  deviceId: string;
  groupId: string;
  triggerId: string;
  messageId: string;
  deliverAfter: Date;
  items: PendingItem[];
}

export interface Store {
  getActivity(groupId: string, entryId: string): Promise<Record<string, unknown> | undefined>;
  getGroup(groupId: string): Promise<GroupDoc | undefined>;
  /** linkedUid → member name, for members still in the group. */
  getMemberNames(groupId: string): Promise<Map<string, string>>;
  /**
   * Adds an item to the group's open batch, or opens one ending at `windowEnd`.
   * Returns the batch's end, and whether this call opened it (and must schedule its flush).
   */
  addPending(groupId: string, triggerId: string, item: PendingItem, windowEnd: Date): Promise<{ windowEnd: Date; opened: boolean }>;
  /** Removes and returns the batch if it still ends at `windowEnd`. */
  takePending(groupId: string, triggerId: string, windowEnd: Date): Promise<PendingItem[] | undefined>;
  getPrefs(uid: string): Promise<Prefs>;
  getDevices(uid: string): Promise<Device[]>;
  deleteDevice(uid: string, deviceId: string): Promise<void>;
  /** Records that a message goes to a device; false if it already did (AC19). */
  claimSend(messageId: string, uid: string, deviceId: string): Promise<boolean>;
  /** Adds items to the device's held-back message for the group (merging). */
  defer(entry: Deferred): Promise<void>;
  dueDeferred(now: Date): Promise<Deferred[]>;
  deleteDeferred(key: string): Promise<void>;
}

export type SendResult = 'sent' | 'invalid_token' | 'failed';

export interface Pusher {
  send(device: Device, push: Push): Promise<SendResult>;
}

export interface FlushScheduler {
  scheduleFlush(groupId: string, triggerId: string, windowEnd: Date): Promise<void>;
}

export type Log = (entry: Record<string, unknown>) => void;
