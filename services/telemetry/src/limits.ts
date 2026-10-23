// Per-install daily caps (R-4 AC16), enforced server-side as well as in the
// app. The service never runs more than one instance, so in-memory counters
// are exact; a restart resets them, which only ever lets a little more in.

export class DailyLimiter {
  private day = '';
  private readonly counts = new Map<string, number>();
  private readonly limit: number;
  private readonly now: () => Date;

  constructor(limit: number, now: () => Date = () => new Date()) {
    this.limit = limit;
    this.now = now;
  }

  // Returns how many of `wanted` items `key` may still send today and counts them.
  take(key: string, wanted: number): number {
    const today = this.now().toISOString().slice(0, 10);
    if (today !== this.day) {
      this.day = today;
      this.counts.clear();
    }
    const used = this.counts.get(key) ?? 0;
    const granted = Math.max(0, Math.min(wanted, this.limit - used));
    this.counts.set(key, used + granted);
    return granted;
  }
}
