// What the core logic needs from the outside world. Firestore, FCM and Cloud
// Tasks implement these in src/adapters/; tests use in-memory fakes.

import type { Locale } from './config/schema.ts';
import type { Prefs } from './prefs.ts';

export type { Prefs } from './prefs.ts';

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
  /**
   * Member ids the change involves (AC27): payer, split members, settlement
   * parties. Missing on items batched before P8.
   */
  involved?: string[];
}

/** A member of a group linked to an account. */
export interface Member {
  memberId: string;
  name: string;
}

export interface Device {
  id: string;
  token: string;
  platform: 'android' | 'web';
  locale: Locale;
  tzName?: string;
  tzOffsetMinutes: number;
  /** Set by the app to ask for a test notification (AC33). */
  testRequestedAt?: Date;
}

export interface Push {
  messageId: string;
  category: string;
  /** `trigger:<id>`, `schedule:<id>`, `campaign:<id>` or `system:<id>`: config ids only, for open counts (AC24). */
  source: string;
  route: string;
  title: string;
  body: string;
  /** Same tag replaces the previous notification of the group on the device. */
  tag: string;
}

/** A push held back (quiet hours, bundling, pause), re-rendered when it is delivered. */
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
  /** linkedUid → member id and name, for members still in the group. */
  getMembers(groupId: string): Promise<Map<string, Member>>;
  /**
   * Adds an item to the group's open batch, or opens one ending at `windowEnd`.
   * Returns the batch's end, and whether this call opened it (and must schedule its flush).
   */
  addPending(groupId: string, triggerId: string, item: PendingItem, windowEnd: Date): Promise<{ windowEnd: Date; opened: boolean }>;
  /** Removes and returns the batch if it still ends at `windowEnd`. */
  takePending(groupId: string, triggerId: string, windowEnd: Date): Promise<PendingItem[] | undefined>;
  getPrefs(uid: string): Promise<Prefs>;
  getDevices(uid: string): Promise<Device[]>;
  getDevice(uid: string, deviceId: string): Promise<Device | undefined>;
  /**
   * Takes the device's test-notification slot (AC33): true, and records `now`,
   * if its last test was at least `minGapMs` ago.
   */
  claimTest(uid: string, deviceId: string, now: Date, minGapMs: number): Promise<boolean>;
  deleteDevice(uid: string, deviceId: string): Promise<void>;
  /** Records that a message goes to a device; false if it already did (AC19). */
  claimSend(messageId: string, uid: string, deviceId: string): Promise<boolean>;
  /**
   * Adds items to the device's held-back message for the group (merging). A
   * merge keeps the earlier `deliverAfter`; delivery re-checks what still holds.
   */
  defer(entry: Deferred): Promise<void>;
  dueDeferred(now: Date): Promise<Deferred[]>;
  deleteDeferred(key: string): Promise<void>;
}

/** What one account owes in one open group, from Firestore at send time. */
export interface Debt {
  groupId: string;
  groupName: string;
  owesCents: number;
  currencyCode: string;
  /** Members of the group with money to receive. */
  creditors: number;
  /** Whole days since the oldest non-deleted expense in the group was created (AC32). */
  oldestDays: number;
}

export interface Announcement {
  id: string;
  banner: { en: { title: string; body: string }; vi: { title: string; body: string } };
  /** Undefined: every signed-in user. */
  audienceUids?: string[];
  endsAt: Date;
}

export interface BroadcastStore {
  /**
   * Takes the user's weekly non-group slot for `messageId` (spec AC13): true
   * if the last non-group push was over 7 days ago or was this same message.
   */
  takeWeeklySlot(uid: string, messageId: string, now: Date): Promise<boolean>;
  debtsOf(uid: string, now: Date): Promise<Debt[]>;
  writeAnnouncement(announcement: Announcement): Promise<void>;
}

export type SendResult = 'sent' | 'invalid_token' | 'failed';

export interface Pusher {
  send(device: Device, push: Push): Promise<SendResult>;
}

export interface FlushScheduler {
  scheduleFlush(groupId: string, triggerId: string, windowEnd: Date): Promise<void>;
}

/** One row of simsplit_raw.crm_sends (spec AC24). */
export interface SendRow {
  sent_at: string;
  message_id: string;
  source: 'trigger' | 'schedule' | 'campaign' | 'system';
  source_id: string;
  category: string;
  uid: string;
  platform: string;
  locale: string;
  result: SendResult;
}

export interface SendLog {
  record(row: SendRow): void;
  /** Writes what was recorded; never throws. */
  flush(): Promise<void>;
}

export type Log = (entry: Record<string, unknown>) => void;
