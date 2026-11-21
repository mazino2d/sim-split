// HTTP routes of the crm service (R-9). Cloud Run IAM lets only the crm
// account in (Eventarc, Cloud Tasks, Cloud Scheduler), so no auth here.
// P1: the routes exist and honour the kill switch; sending comes in P3–P6.

import type { Config } from './config/schema.ts';

export interface Request {
  method: string;
  path: string;
  headers: Record<string, string | undefined>;
}

export interface Response {
  status: number;
}

export interface Deps {
  config: Config;
  version: string;
  log: (entry: Record<string, unknown>) => void;
}

const ROUTES = new Set(['/events', '/flush', '/tick']);

export const createHandler = ({ config, version, log }: Deps) => {
  return async (req: Request): Promise<Response> => {
    if (!ROUTES.has(req.path)) return { status: 404 };
    if (req.method !== 'POST') return { status: 405 };
    const route = req.path.slice(1);
    if (config.policy.kill_switch) {
      log({ severity: 'NOTICE', kind: 'kill_switch', route, version });
      return { status: 204 };
    }
    // The CloudEvent id only: document paths carry group IDs, which stay out of logs.
    log({ severity: 'INFO', kind: route, version, event_id: req.headers['ce-id'] });
    return { status: 204 };
  };
};
