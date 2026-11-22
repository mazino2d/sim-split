// HTTP routes of the crm service (R-9). Cloud Run IAM lets only the crm
// account in (Eventarc, Cloud Tasks, Cloud Scheduler), so no auth here.
//   POST /events  Eventarc (header ce-document): a new activity entry, or a
//                 device write (a test notification request)
//   POST /flush   Cloud Tasks: a group's batch window ended (JSON body)
//   POST /tick    Cloud Scheduler, every 15 min: held-back messages, schedules, campaigns

import { deliverDeferred, onActivity, onFlush, type ActivityDeps } from './activity.ts';
import { runCampaigns, runSchedules, type BroadcastDeps } from './broadcast.ts';
import { DEVICE_PATH, onDeviceWrite } from './test_notification.ts';

export interface Request {
  method: string;
  path: string;
  headers: Record<string, string | undefined>;
  body: Buffer;
}

export interface Response {
  status: number;
}

export interface Deps extends ActivityDeps, BroadcastDeps {
  store: BroadcastDeps['store'];
  version: string;
}

const ROUTES = new Set(['/events', '/flush', '/tick']);

const parseFlush = (body: Buffer) => {
  try {
    const b = JSON.parse(body.toString('utf8')) as Record<string, unknown>;
    const windowEnd = new Date(String(b.windowEnd));
    if (typeof b.groupId !== 'string' || typeof b.triggerId !== 'string' || Number.isNaN(windowEnd.getTime())) {
      return undefined;
    }
    return { groupId: b.groupId, triggerId: b.triggerId, windowEnd };
  } catch {
    return undefined;
  }
};

export const createHandler = (deps: Deps) => {
  const { config, version, log } = deps;
  return async (req: Request): Promise<Response> => {
    if (!ROUTES.has(req.path)) return { status: 404 };
    if (req.method !== 'POST') return { status: 405 };
    const route = req.path.slice(1);
    if (config.policy.kill_switch) {
      log({ severity: 'NOTICE', kind: 'kill_switch', route, version });
      return { status: 204 };
    }
    try {
      switch (route) {
        case 'events': {
          // Only the CloudEvent id is logged: document paths carry group IDs and uids.
          log({ severity: 'INFO', kind: 'events', version, event_id: req.headers['ce-id'] });
          const document = req.headers['ce-document'];
          const device = document ? DEVICE_PATH.exec(document) : null;
          if (device) await onDeviceWrite(deps, device[1], device[2]);
          else await onActivity(deps, document);
          await deps.sends.flush();
          return { status: 204 };
        }
        case 'flush': {
          const flush = parseFlush(req.body);
          // A malformed task would retry forever: drop it.
          if (!flush) return { status: 204 };
          await onFlush(deps, flush.groupId, flush.triggerId, flush.windowEnd);
          await deps.sends.flush();
          return { status: 204 };
        }
        default:
          log({ severity: 'INFO', kind: 'tick', version });
          await deliverDeferred(deps);
          await runSchedules(deps);
          await runCampaigns(deps);
          await deps.sends.flush();
          return { status: 204 };
      }
    } catch (e) {
      await deps.sends.flush();
      // 500 lets Eventarc and Cloud Tasks retry; sends already made are in the ledger.
      log({ severity: 'ERROR', kind: 'error', route, version, message: (e as Error).message });
      return { status: 500 };
    }
  };
};
