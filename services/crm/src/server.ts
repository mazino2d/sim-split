// Cloud Run entry point for sim-split's crm service (R-9). See
// docs/implementations/R-9-notifications-crm.md. The config is compiled from
// crm/ at build time (config.json); the service refuses to start without it.

import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { createHandler } from './handler.ts';
import type { Config } from './config/schema.ts';

const { version, config } = JSON.parse(readFileSync(new URL('../config.json', import.meta.url), 'utf8')) as {
  version: string;
  config: Config;
};

const log = (entry: Record<string, unknown>) => console.log(JSON.stringify(entry));
const handle = createHandler({ config, version, log });
log({ severity: 'INFO', kind: 'start', version, kill_switch: config.policy.kill_switch });

createServer((req, res) => {
  // Bodies are not read in P1; drain them so the connection is reused.
  req.resume();
  req.on('end', async () => {
    const response = await handle({
      method: req.method ?? 'GET',
      path: (req.url ?? '/').split('?')[0],
      headers: req.headers as Record<string, string | undefined>,
    });
    res.writeHead(response.status).end();
  });
}).listen(Number(process.env.PORT ?? 8080));
