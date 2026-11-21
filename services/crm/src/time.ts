// Device-local time for quiet hours and schedules. The IANA zone wins; the
// stored offset is the fallback when the zone is unknown to this runtime.

export const localMinutes = (now: Date, tzName: string | undefined, offsetMinutes: number): number => {
  if (tzName) {
    try {
      const parts = new Intl.DateTimeFormat('en-GB', {
        timeZone: tzName,
        hour: '2-digit',
        minute: '2-digit',
        hourCycle: 'h23',
      }).formatToParts(now);
      const get = (type: string) => Number(parts.find((p) => p.type === type)?.value);
      return get('hour') * 60 + get('minute');
    } catch {
      // Unknown zone: fall through to the offset.
    }
  }
  const utc = now.getUTCHours() * 60 + now.getUTCMinutes();
  return (((utc + offsetMinutes) % 1440) + 1440) % 1440;
};

/** The first instant at or after `now` when the device clock reads `clock` (HH:MM). */
export const nextLocalTime = (now: Date, clock: string, tzName: string | undefined, offsetMinutes: number): Date => {
  const [h, m] = clock.split(':').map(Number);
  const target = h * 60 + m;
  const current = localMinutes(now, tzName, offsetMinutes);
  const wait = (target - current + 1440) % 1440;
  const at = new Date(now.getTime() + wait * 60_000);
  at.setUTCSeconds(0, 0);
  return at;
};
