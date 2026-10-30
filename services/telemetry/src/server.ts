// Cloud Run entry point for sim-split's telemetry endpoint (R-4). See
// docs/implementations/R-4-error-reports-and-usage-analytics.md.

import { createServer } from 'node:http';
import { initializeApp } from 'firebase-admin/app';
import { getAppCheck } from 'firebase-admin/app-check';
import { getAuth } from 'firebase-admin/auth';
import { createBigQuerySink } from './bigquery.ts';
import { createHandler } from './handler.ts';
import { MAX_BODY_BYTES } from './schema.ts';

const env = (name: string): string => {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is not set`);
  return value;
};

const app = initializeApp({ projectId: env('FIREBASE_PROJECT_ID') });
const appCheck = getAppCheck(app);
const auth = getAuth(app);

const handle = createHandler({
  verifier: {
    appCheck: async (token) => {
      await appCheck.verifyToken(token);
    },
    idToken: async (token) => (await auth.verifyIdToken(token)).uid,
  },
  sink: createBigQuerySink(env('BIGQUERY_PROJECT_ID'), env('BIGQUERY_DATASET')),
  // Cloud Run turns each JSON line on stdout into a structured log entry.
  log: (entry) => console.log(JSON.stringify(entry)),
  now: () => new Date(),
  // The web app of this environment's project (simsplit-as-se1-dev.web.app in
  // dev), plus the prd custom domain.
  allowedOrigins: ['https://simsplit.web.app', `https://${env('FIREBASE_PROJECT_ID')}.web.app`, 'http://localhost'],
});

createServer((req, res) => {
  const chunks: Buffer[] = [];
  let size = 0;
  req.on('data', (chunk: Buffer) => {
    size += chunk.length;
    // Stop buffering past the limit; the handler answers 413.
    if (size <= MAX_BODY_BYTES + 1) chunks.push(chunk);
  });
  req.on('end', async () => {
    const response = await handle({
      method: req.method ?? 'GET',
      path: (req.url ?? '/').split('?')[0],
      headers: req.headers as Record<string, string | undefined>,
      body: Buffer.concat(chunks),
    });
    res.writeHead(response.status, response.headers).end(response.body);
  });
}).listen(Number(process.env.PORT ?? 8080));
