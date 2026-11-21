// Daily caps (R-4 AC16, R-8 P3), enforced server-side as well as in the app.
// The service never runs more than one instance, so in-memory counters are
// exact; a restart resets them, which only ever lets a little more in.

import { createHash, randomBytes } from 'node:crypto';

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

// The client address a cap is counted against, as a salted hash that lives
// only in this instance's memory: never logged, never stored, and a new salt
// on every start. Cloud Run appends the address it saw to X-Forwarded-For, so
// the last entry is the one a client can't choose.
export class AddressKey {
  private readonly salt: Buffer;

  constructor(salt: Buffer = randomBytes(16)) {
    this.salt = salt;
  }

  of(forwardedFor: string | undefined): string {
    const address = (forwardedFor ?? '').split(',').map((s) => s.trim()).filter(Boolean).pop() ?? 'unknown';
    return createHash('sha256').update(this.salt).update(address).digest('base64url').slice(0, 22);
  }
}
