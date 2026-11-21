// Calm limits (R-9 spec, principle 1). These are code, not config: crm/policy.yaml
// may be stricter, never looser, and `crm validate` refuses a config that tries.

/** At most one push from settle reminders and updates together per user per week. */
export const MAX_NON_GROUP_PER_WEEK = 1;

/** Quiet hours must cover at least 21:00–08:00 on the device's clock. */
export const QUIET_FROM_LATEST = '21:00';
export const QUIET_TO_EARLIEST = '08:00';

/** Group activity is batched; the window keeps one message per burst. */
export const BATCH_WINDOW_MIN_MINUTES = 5;
export const BATCH_WINDOW_MAX_MINUTES = 60;

/** A scheduled message fires at most once a week. */
export const MIN_SCHEDULE_INTERVAL_DAYS = 7;

/** Lengths that fit an Android and a web notification without cutting. */
export const PUSH_TITLE_MAX = 65;
export const PUSH_BODY_MAX = 240;
export const BANNER_TITLE_MAX = 60;
export const BANNER_BODY_MAX = 160;

export const minutesOf = (clock: string): number => {
  const [h, m] = clock.split(':').map(Number);
  return h * 60 + m;
};

/** True if minute-of-day `t` falls inside the quiet window [from, to), which may wrap midnight. */
export const inQuietHours = (t: number, from: string, to: string): boolean => {
  const f = minutesOf(from);
  const e = minutesOf(to);
  return f <= e ? t >= f && t < e : t >= f || t < e;
};
