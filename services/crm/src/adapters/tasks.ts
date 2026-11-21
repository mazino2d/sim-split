// FlushScheduler on Cloud Tasks: one task per group batch, due when the
// window ends, calling /flush with an OIDC token for the crm account.

import { CloudTasksClient } from '@google-cloud/tasks';
import type { FlushScheduler } from '../ports.ts';

const ALREADY_EXISTS = 6;

export const createTasksScheduler = (
  queue: string,
  serviceAccountEmail: string,
  serviceUrl: () => string,
): FlushScheduler => {
  const client = new CloudTasksClient();
  return {
    async scheduleFlush(groupId, triggerId, windowEnd) {
      const url = serviceUrl();
      const body = JSON.stringify({ groupId, triggerId, windowEnd: windowEnd.toISOString() });
      try {
        await client.createTask({
          parent: queue,
          task: {
            // Named by batch, so a repeated event cannot schedule a second flush.
            name: `${queue}/tasks/${triggerId}-${groupId}-${windowEnd.getTime()}`.replace(/[^A-Za-z0-9_/.-]/g, '_'),
            scheduleTime: { seconds: Math.ceil(windowEnd.getTime() / 1000) },
            httpRequest: {
              httpMethod: 'POST',
              url: `${url}/flush`,
              headers: { 'Content-Type': 'application/json' },
              body: Buffer.from(body).toString('base64'),
              oidcToken: { serviceAccountEmail, audience: url },
            },
          },
        });
      } catch (e) {
        if ((e as { code?: number }).code !== ALREADY_EXISTS) throw e;
      }
    },
  };
};
