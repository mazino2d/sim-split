// Notification preferences v2 (R-9 P8, spec AC26–AC34): `users/{uid}.notificationPrefs`
// as the sender reads it at send time. Every field is optional and a missing or
// malformed one is its default, so old app builds and old documents keep working.

import { minutesOf } from './calm.ts';
import { ACTIVITY_EVENTS, type ActivityEvent, type Config } from './config/schema.ts';
import type { PendingItem } from './ports.ts';

export const ACTIVITY_EVENT_KEYS = ['expenseCreate', 'expenseUpdate', 'expenseDelete', 'settlement', 'memberJoin'] as const;
export type ActivityEventKey = (typeof ACTIVITY_EVENT_KEYS)[number];

/** `expense_create` → `expenseCreate`: an event id in crm/categories.yaml → its pref key. */
export const eventPrefKey = (id: ActivityEvent): ActivityEventKey =>
  id.replace(/_([a-z])/g, (_, c: string) => c.toUpperCase()) as ActivityEventKey;

export const BUNDLES = ['10m', '30m', '1h', 'daily'] as const;
export type Bundle = (typeof BUNDLES)[number];
export const GROUP_MODES = ['all', 'involving', 'off'] as const;
export type GroupMode = (typeof GROUP_MODES)[number];
export const SETTLE_MIN_DAYS = [7, 14, 30] as const;

export interface SettlePrefs {
  /** 0 = Sunday … 6 = Saturday. */
  day: number;
  time: string;
  minDays: number;
}

export interface Prefs {
  groupActivity: boolean;
  settleReminder: boolean;
  updates: boolean;
  /** Legacy (P2): listed groups are off. `groups` wins when both name a group. */
  mutedGroups: string[];
  activityEvents: Record<ActivityEventKey, boolean>;
  onlyInvolvingMe: boolean;
  bundle: Bundle;
  groups: Record<string, { mode: GroupMode; offUntil?: Date }>;
  pausedUntil?: Date;
  quietHours?: { from: string; to: string };
  /** Undefined: the schedule's cron and a 14-day minimum. */
  settle?: SettlePrefs;
}

export type PrefDefaults = Pick<Prefs, 'groupActivity' | 'settleReminder' | 'updates' | 'activityEvents'>;

export const SETTLE_DEFAULTS: SettlePrefs = { day: 0, time: '19:00', minDays: 14 };

/** The defaults come from crm/categories.yaml, like the app's. */
export const prefDefaults = (config: Pick<Config, 'categories'>): PrefDefaults => {
  const isOn = (id: string) => config.categories.find((c) => c.id === id)?.default === 'on';
  const events = config.categories.find((c) => c.id === 'group_activity')?.events ?? [];
  const activityEvents = Object.fromEntries(
    ACTIVITY_EVENTS.map((id) => [eventPrefKey(id), events.find((e) => e.id === id)?.default !== 'off']),
  ) as Record<ActivityEventKey, boolean>;
  return {
    groupActivity: isOn('group_activity'),
    settleReminder: isOn('settle_reminder'),
    updates: isOn('updates'),
    activityEvents,
  };
};

export const defaultPrefs = (defaults: PrefDefaults): Prefs => ({
  ...defaults,
  activityEvents: { ...defaults.activityEvents },
  mutedGroups: [],
  onlyInvolvingMe: false,
  bundle: '10m',
  groups: {},
});

const CLOCK = /^([01]\d|2[0-3]):[0-5]\d$/;
const isRecord = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);
const bool = (v: unknown, fallback: boolean) => (typeof v === 'boolean' ? v : fallback);
const within = (clock: unknown, from: string, to: string): clock is string =>
  typeof clock === 'string' && CLOCK.test(clock) && minutesOf(clock) >= minutesOf(from) && minutesOf(clock) <= minutesOf(to);

/** A Firestore Timestamp (anything with toDate()) or a Date; anything else is undefined. */
export const toDate = (v: unknown): Date | undefined => {
  if (v instanceof Date) return Number.isNaN(v.getTime()) ? undefined : v;
  if (isRecord(v) && typeof v.toDate === 'function') {
    const d = (v.toDate as () => unknown)();
    return d instanceof Date && !Number.isNaN(d.getTime()) ? d : undefined;
  }
  return undefined;
};

/** `notificationPrefs` as stored → what the sender uses. */
export const parsePrefs = (raw: unknown, defaults: PrefDefaults): Prefs => {
  const p = isRecord(raw) ? raw : {};
  const prefs = defaultPrefs(defaults);
  prefs.groupActivity = bool(p.groupActivity, defaults.groupActivity);
  prefs.settleReminder = bool(p.settleReminder, defaults.settleReminder);
  prefs.updates = bool(p.updates, defaults.updates);
  if (Array.isArray(p.mutedGroups)) prefs.mutedGroups = p.mutedGroups.filter((g): g is string => typeof g === 'string');
  if (isRecord(p.activityEvents)) {
    for (const key of ACTIVITY_EVENT_KEYS) prefs.activityEvents[key] = bool(p.activityEvents[key], defaults.activityEvents[key]);
  }
  prefs.onlyInvolvingMe = bool(p.onlyInvolvingMe, false);
  if ((BUNDLES as readonly unknown[]).includes(p.bundle)) prefs.bundle = p.bundle as Bundle;
  if (isRecord(p.groups)) {
    for (const [groupId, g] of Object.entries(p.groups)) {
      if (!isRecord(g) || !(GROUP_MODES as readonly unknown[]).includes(g.mode)) continue;
      prefs.groups[groupId] = { mode: g.mode as GroupMode, offUntil: toDate(g.offUntil) };
    }
  }
  prefs.pausedUntil = toDate(p.pausedUntil);
  // Only ranges at least as long as the policy's floor are offered (AC31).
  if (isRecord(p.quietHours) && within(p.quietHours.from, '12:00', '21:00') && within(p.quietHours.to, '08:00', '12:00')) {
    prefs.quietHours = { from: p.quietHours.from, to: p.quietHours.to };
  }
  if (isRecord(p.settle)) {
    const s = p.settle;
    prefs.settle = {
      day: typeof s.day === 'number' && Number.isInteger(s.day) && s.day >= 0 && s.day <= 6 ? s.day : SETTLE_DEFAULTS.day,
      time: within(s.time, '08:00', '21:00') ? s.time : SETTLE_DEFAULTS.time,
      minDays: (SETTLE_MIN_DAYS as readonly unknown[]).includes(s.minDays) ? (s.minDays as number) : SETTLE_DEFAULTS.minDays,
    };
  }
  return prefs;
};

/** The group's mode for this user now (AC29): `groups` wins over the legacy `mutedGroups`. */
export const groupMode = (prefs: Prefs, groupId: string, now: Date): GroupMode => {
  const g = prefs.groups[groupId];
  if (g) return g.mode === 'off' && g.offUntil && g.offUntil <= now ? 'all' : g.mode;
  return prefs.mutedGroups.includes(groupId) ? 'off' : 'all';
};

export const pausedAt = (prefs: Prefs, now: Date): Date | undefined =>
  prefs.pausedUntil && prefs.pausedUntil > now ? prefs.pausedUntil : undefined;

/** Policy and user together: the earlier start and the later end, never shorter than the policy (AC31). */
export const effectiveQuietHours = (policy: { from: string; to: string }, prefs: Pick<Prefs, 'quietHours'>) => {
  const user = prefs.quietHours;
  if (!user) return policy;
  return {
    from: minutesOf(user.from) < minutesOf(policy.from) ? user.from : policy.from,
    to: minutesOf(user.to) > minutesOf(policy.to) ? user.to : policy.to,
  };
};

const EXPENSE_EVENTS: Record<string, ActivityEventKey | undefined> = {
  create: 'expenseCreate',
  update: 'expenseUpdate',
  delete: 'expenseDelete',
};

/** The switch an activity item falls under (AC26), or undefined when it is not a notified kind. */
export const eventOf = (item: Pick<PendingItem, 'entity' | 'action'>): ActivityEventKey | undefined => {
  if (item.entity === 'expense') return EXPENSE_EVENTS[item.action];
  if (item.entity === 'settlement') return 'settlement';
  // The app records a join as group/join; member/join is accepted too.
  if ((item.entity === 'group' || item.entity === 'member') && item.action === 'join') return 'memberJoin';
  return undefined;
};

/**
 * The items this user hears about: switched-on kinds and, when they asked for
 * it (AC27, or the group's "involving" mode), only expenses and settlements
 * their member is part of. A join involves nobody, so it is not filtered.
 */
export const itemsFor = (prefs: Prefs, mode: GroupMode, memberId: string | undefined, items: PendingItem[]): PendingItem[] => {
  const involvingOnly = prefs.onlyInvolvingMe || mode === 'involving';
  return items.filter((item) => {
    const event = eventOf(item);
    if (!event || !prefs.activityEvents[event]) return false;
    if (!involvingOnly || event === 'memberJoin') return true;
    return memberId !== undefined && (item.involved ?? []).includes(memberId);
  });
};
