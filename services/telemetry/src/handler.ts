// Request handling for the telemetry endpoint, free of Firebase and BigQuery so
// it can be tested with fakes. server.ts wires the real dependencies.

import { DailyLimiter } from './limits.ts';
import {
  InvalidPayload,
  MAX_BODY_BYTES,
  parseErrorReports,
  parseUsageEvents,
  type ErrorReportRow,
  type UsageEventRow,
} from './schema.ts';
import { scrub } from './scrub.ts';

export interface Verifier {
  // Resolves when the App Check token is valid, rejects otherwise.
  appCheck(token: string): Promise<void>;
  // Resolves to the token's uid, rejects when the ID token is invalid.
  idToken(token: string): Promise<string>;
}

export interface Sink {
  writeErrorReports(rows: ErrorReportRow[]): Promise<void>;
  writeUsageEvents(rows: UsageEventRow[]): Promise<void>;
}

export interface Deps {
  verifier: Verifier;
  sink: Sink;
  log: (entry: Record<string, unknown>) => void;
  now: () => Date;
  allowedOrigins: string[];
}

export interface Request {
  method: string;
  path: string;
  headers: Record<string, string | undefined>;
  body: Buffer;
}

export interface Response {
  status: number;
  headers: Record<string, string>;
  body: string;
}

export const ERROR_REPORTS_PER_DAY = 50;
export const USAGE_EVENTS_PER_DAY = 5000;

export function createHandler(deps: Deps): (req: Request) => Promise<Response> {
  const reportLimiter = new DailyLimiter(ERROR_REPORTS_PER_DAY, deps.now);
  const eventLimiter = new DailyLimiter(USAGE_EVENTS_PER_DAY, deps.now);

  return async (req) => {
    const cors = corsHeaders(req.headers.origin, deps.allowedOrigins);
    const reply = (status: number, body: Record<string, unknown> = {}): Response => ({
      status,
      headers: { 'content-type': 'application/json', ...cors },
      body: JSON.stringify(body),
    });
    const reject = (status: number, reason: string): Response => {
      deps.log({ severity: 'WARNING', kind: 'rejected', path: req.path, status, reason });
      return reply(status, { error: reason });
    };

    if (req.method === 'OPTIONS') return { status: 204, headers: cors, body: '' };
    if (req.method === 'GET' && req.path === '/health') return reply(200, { ok: true });
    if (req.method !== 'POST' || (req.path !== '/v1/errors' && req.path !== '/v1/events')) {
      return reply(404, { error: 'not found' });
    }
    if (req.body.length > MAX_BODY_BYTES) return reject(413, 'body too large');

    const appCheckToken = req.headers['x-firebase-appcheck'];
    if (!appCheckToken) return reject(401, 'missing App Check token');
    try {
      await deps.verifier.appCheck(appCheckToken);
    } catch {
      return reject(401, 'invalid App Check token');
    }

    let body: unknown;
    try {
      body = JSON.parse(req.body.toString('utf8'));
    } catch {
      return reject(400, 'body is not JSON');
    }
    const receivedAt = deps.now();

    try {
      if (req.path === '/v1/errors') {
        const rows = parseErrorReports(body, receivedAt, scrub);
        const kept = rows.filter((row) => reportLimiter.take(row.report_id, 1) === 1);
        if (kept.length > 0) {
          await deps.sink.writeErrorReports(kept);
          for (const row of kept) deps.log(errorLogEntry(row));
        }
        return reply(202, { accepted: kept.length, dropped: rows.length - kept.length });
      }

      const bearer = /^Bearer (.+)$/.exec(req.headers.authorization ?? '')?.[1];
      if (!bearer) return reject(401, 'missing ID token');
      let uid: string;
      try {
        uid = await deps.verifier.idToken(bearer);
      } catch {
        return reject(401, 'invalid ID token');
      }
      const rows = parseUsageEvents(body, receivedAt);
      if (rows.some((row) => row.uid !== uid)) return reject(403, 'events belong to another account');
      const kept = rows.slice(0, eventLimiter.take(uid, rows.length));
      if (kept.length > 0) await deps.sink.writeUsageEvents(kept);
      return reply(202, { accepted: kept.length, dropped: rows.length - kept.length });
    } catch (e) {
      if (e instanceof InvalidPayload) return reject(400, e.message);
      deps.log({ severity: 'ERROR', kind: 'write_failed', path: req.path, error: String(e) });
      // The app keeps the items queued and retries later.
      return reply(503, { error: 'try again later' });
    }
  };
}

// One Cloud Logging entry per error report; the log-based alert matches
// kind="error_report" at severity ERROR (everything-as-code telemetry.tf).
function errorLogEntry(row: ErrorReportRow): Record<string, unknown> {
  return {
    severity: 'ERROR',
    kind: 'error_report',
    message: `${row.error_type}: ${row.message}`.slice(0, 500),
    report_id: row.report_id,
    session_id: row.session_id,
    platform: row.platform,
    os: row.os,
    app_version: row.app_version,
    error_type: row.error_type,
    count: row.count,
    signed_in: row.signed_in,
    online: row.online,
    stack: row.stack,
    breadcrumbs: row.breadcrumbs.map((b) => `${b.kind}:${b.name}`),
  };
}

function corsHeaders(origin: string | undefined, allowed: string[]): Record<string, string> {
  if (!origin || !allowed.some((a) => a === origin || (a === 'http://localhost' && origin.startsWith('http://localhost:')))) {
    return {};
  }
  return {
    'access-control-allow-origin': origin,
    'access-control-allow-methods': 'POST, OPTIONS',
    'access-control-allow-headers': 'content-type, authorization, x-firebase-appcheck',
    'access-control-max-age': '86400',
    vary: 'origin',
  };
}
