// Validates request bodies against the R-4 payloads and turns them into the
// rows of simsplit_raw.error_reports and simsplit_raw.usage_events. Anything
// that does not match is rejected whole (AC20).

export const MAX_BODY_BYTES = 64 * 1024;
export const MAX_REPORTS_PER_REQUEST = 20;
export const MAX_EVENTS_PER_REQUEST = 500;

const PLATFORMS = ['android', 'ios', 'web'] as const;
const KINDS = ['screen', 'tap', 'form', 'dialog', 'gesture', 'op'] as const;
const NAME = /^[a-z][a-z0-9_]{0,63}$/;
const ROUTE = /^\/[A-Za-z0-9_:/-]{0,127}$/;
const ID = /^[A-Za-z0-9-]{4,64}$/;
const VERSION = /^[0-9A-Za-z.+-]{1,32}$/;
const LANGUAGE = /^[a-z]{2}(-[A-Za-z]{2})?$/;

export interface Breadcrumb {
  time: Date | null;
  kind: string;
  name: string;
}

export interface ErrorReportRow {
  received_at: Date;
  report_id: string;
  session_id: string | null;
  client_time: Date | null;
  platform: string;
  os: string | null;
  app_version: string;
  language: string | null;
  signed_in: boolean | null;
  online: boolean | null;
  error_type: string;
  message: string;
  stack: string | null;
  count: number;
  breadcrumbs: Breadcrumb[];
}

export interface UsageEventRow {
  received_at: Date;
  uid: string;
  session_id: string;
  client_time: Date | null;
  kind: string;
  name: string;
  screen: string | null;
  result: string | null;
  duration_ms: number | null;
  platform: string;
  app_version: string;
  language: string | null;
  online: boolean | null;
}

export class InvalidPayload extends Error {}

type Json = Record<string, unknown>;

function fail(message: string): never {
  throw new InvalidPayload(message);
}

function object(value: unknown, what: string): Json {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) fail(`${what} must be an object`);
  return value as Json;
}

function list(value: unknown, what: string, max: number): unknown[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > max) fail(`${what} must hold 1-${max} items`);
  return value;
}

function text(o: Json, key: string, pattern: RegExp | null, maxLength: number): string {
  const v = o[key];
  if (typeof v !== 'string' || v.length === 0 || v.length > maxLength) fail(`${key} is missing or too long`);
  if (pattern && !pattern.test(v)) fail(`${key} has an invalid format`);
  return v;
}

function optionalText(o: Json, key: string, pattern: RegExp | null, maxLength: number): string | null {
  return o[key] === undefined || o[key] === null ? null : text(o, key, pattern, maxLength);
}

function oneOf<T extends string>(o: Json, key: string, values: readonly T[]): T {
  const v = o[key];
  if (typeof v !== 'string' || !values.includes(v as T)) fail(`${key} must be one of ${values.join(', ')}`);
  return v as T;
}

function optionalBool(o: Json, key: string): boolean | null {
  const v = o[key];
  if (v === undefined || v === null) return null;
  if (typeof v !== 'boolean') fail(`${key} must be a boolean`);
  return v;
}

function optionalInt(o: Json, key: string, max: number): number | null {
  const v = o[key];
  if (v === undefined || v === null) return null;
  if (!Number.isInteger(v) || (v as number) < 0 || (v as number) > max) fail(`${key} must be an integer 0-${max}`);
  return v as number;
}

// Client times are epoch milliseconds; device clocks can be wrong, so they are
// kept as sent (within a sane range) next to the server's received_at.
function optionalTime(o: Json, key: string): Date | null {
  const v = o[key];
  if (v === undefined || v === null) return null;
  if (!Number.isInteger(v) || (v as number) < Date.UTC(2020, 0, 1) || (v as number) > Date.UTC(2100, 0, 1)) {
    fail(`${key} must be epoch milliseconds`);
  }
  return new Date(v as number);
}

export function parseErrorReports(body: unknown, receivedAt: Date, scrub: (s: string) => string): ErrorReportRow[] {
  const reports = list(object(body, 'body').reports, 'reports', MAX_REPORTS_PER_REQUEST);
  return reports.map((item) => {
    const r = object(item, 'report');
    const crumbs = r.breadcrumbs === undefined ? [] : r.breadcrumbs;
    if (!Array.isArray(crumbs) || crumbs.length > 30) fail('breadcrumbs must hold at most 30 items');
    return {
      received_at: receivedAt,
      report_id: text(r, 'report_id', ID, 64),
      session_id: optionalText(r, 'session_id', ID, 64),
      client_time: optionalTime(r, 'client_time'),
      platform: oneOf(r, 'platform', PLATFORMS),
      os: optionalText(r, 'os', null, 64),
      app_version: text(r, 'app_version', VERSION, 32),
      language: optionalText(r, 'language', LANGUAGE, 8),
      signed_in: optionalBool(r, 'signed_in'),
      online: optionalBool(r, 'online'),
      error_type: scrub(text(r, 'error_type', null, 128)),
      message: scrub(text(r, 'message', null, 2000)),
      stack: r.stack === undefined || r.stack === null ? null : scrub(text(r, 'stack', null, 16000)),
      count: optionalInt(r, 'count', 1_000_000) ?? 1,
      breadcrumbs: crumbs.map((c) => {
        const b = object(c, 'breadcrumb');
        const kind = oneOf(b, 'kind', KINDS);
        return { time: optionalTime(b, 'time'), kind, name: text(b, 'name', kind === 'screen' ? ROUTE : NAME, 128) };
      }),
    };
  });
}

export function parseUsageEvents(body: unknown, receivedAt: Date): UsageEventRow[] {
  const events = list(object(body, 'body').events, 'events', MAX_EVENTS_PER_REQUEST);
  return events.map((item) => {
    const e = object(item, 'event');
    const kind = oneOf(e, 'kind', KINDS);
    return {
      received_at: receivedAt,
      uid: text(e, 'uid', /^[A-Za-z0-9]{1,128}$/, 128),
      session_id: text(e, 'session_id', ID, 64),
      client_time: optionalTime(e, 'client_time'),
      kind,
      name: text(e, 'name', kind === 'screen' ? ROUTE : NAME, 128),
      screen: optionalText(e, 'screen', ROUTE, 128),
      result: optionalText(e, 'result', NAME, 64),
      duration_ms: optionalInt(e, 'duration_ms', 3_600_000),
      platform: oneOf(e, 'platform', PLATFORMS),
      app_version: text(e, 'app_version', VERSION, 32),
      language: optionalText(e, 'language', LANGUAGE, 8),
      online: optionalBool(e, 'online'),
    };
  });
}
