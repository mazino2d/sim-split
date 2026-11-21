// Cloud Run entry point for sim-split's crm service (R-9). See
// docs/implementations/R-9-notifications-crm.md. The config is compiled from
// crm/ at build time (config.json); the service refuses to start without it.

import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getMessaging } from 'firebase-admin/messaging';
import { createHandler } from './handler.ts';
import { createFirestoreStore } from './adapters/firestore.ts';
import { createFcmPusher } from './adapters/fcm.ts';
import { createTasksScheduler } from './adapters/tasks.ts';
import { createBigQuerySource } from './adapters/bigquery.ts';
import { createBigQuerySendLog } from './adapters/send_log.ts';
import type { Config } from './config/schema.ts';

const env = (name: string): string => {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set`);
  return value;
};

const { version, config } = JSON.parse(readFileSync(new URL('../config.json', import.meta.url), 'utf8')) as {
  version: string;
  config: Config;
};

const projectId = env('FIREBASE_PROJECT_ID');
const app = initializeApp({ projectId });
const isOn = (id: string) => config.categories.find((c) => c.id === id)?.default === 'on';
const MAX_BODY_BYTES = 16 * 1024;

// The service's own URL, learned from the first request (Cloud Run sets Host),
// for the flush tasks it schedules.
let serviceUrl = '';

const log = (entry: Record<string, unknown>) => console.log(JSON.stringify(entry));
const handle = createHandler({
  config,
  version,
  log,
  now: () => new Date(),
  store: createFirestoreStore(getFirestore(app), {
    groupActivity: isOn('group_activity'),
    settleReminder: isOn('settle_reminder'),
    updates: isOn('updates'),
  }),
  pusher: createFcmPusher(
    getMessaging(app),
    env('CRM_ENV') === 'prd' ? 'https://simsplit.web.app' : `https://${projectId}.web.app`,
  ),
  audiences: createBigQuerySource(projectId, env('CRM_TRAITS_TABLE')),
  traitsTable: env('CRM_TRAITS_TABLE'),
  sends: createBigQuerySendLog(env('CRM_SENDS_DATASET'), log),
  env: env('CRM_ENV') === 'prd' ? 'prd' : 'dev',
  startedAt: new Date(),
  scheduler: createTasksScheduler(env('CRM_TASKS_QUEUE'), `crm-sender@${projectId}.iam.gserviceaccount.com`, () => serviceUrl),
});
log({ severity: 'INFO', kind: 'start', version, kill_switch: config.policy.kill_switch });

createServer((req, res) => {
  if (!serviceUrl && req.headers.host) serviceUrl = `https://${req.headers.host}`;
  const chunks: Buffer[] = [];
  let size = 0;
  req.on('data', (chunk: Buffer) => {
    size += chunk.length;
    if (size <= MAX_BODY_BYTES) chunks.push(chunk);
  });
  req.on('end', async () => {
    const response = await handle({
      method: req.method ?? 'GET',
      path: (req.url ?? '/').split('?')[0],
      headers: req.headers as Record<string, string | undefined>,
      body: Buffer.concat(chunks),
    });
    res.writeHead(response.status).end();
  });
}).listen(Number(process.env.PORT ?? 8080));
