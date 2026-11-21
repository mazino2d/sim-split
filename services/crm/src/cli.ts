// crm CLI (R-9): validate, render, plan and compile the config in crm/.
//
//   node src/cli.ts validate [--dir ../../crm]
//   node src/cli.ts render   [--dir …]                 Markdown preview of every message
//   node src/cli.ts plan     [--dir …] --base <dir>    what changes against another copy (main)
//   node src/cli.ts compile  [--dir …] --out config.json --version <git sha>

import { writeFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { loadConfig, type Problem } from './config/load.ts';
import { checkConfig } from './config/check.ts';
import { renderAll, renderPlan } from './preview.ts';
import type { Config } from './config/schema.ts';

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: {
    dir: { type: 'string', default: resolve(import.meta.dirname, '../../../crm') },
    base: { type: 'string' },
    out: { type: 'string' },
    version: { type: 'string', default: 'local' },
  },
});

const print = (label: string, list: Problem[]) => {
  for (const p of list) {
    console.error(`${label} ${p.file}${p.line ? `:${p.line}` : ''}: ${p.message}`);
  }
};

const load = (dir: string): Config => {
  const { config, problems } = loadConfig(dir);
  const checked = config ? checkConfig(config, { now: new Date() }) : { problems: [], warnings: [] };
  print('warning', checked.warnings);
  const all = [...problems, ...checked.problems];
  if (all.length || !config) {
    print('error', all);
    console.error(`${all.length} problem(s) in ${dir}`);
    process.exit(1);
  }
  return config;
};

const command = positionals[0];
switch (command) {
  case 'validate':
    load(values.dir);
    console.log('crm config OK');
    break;
  case 'render':
    console.log(renderAll(load(values.dir)));
    break;
  case 'plan': {
    const head = load(values.dir);
    // A base without crm/ (the first PR) plans everything as new.
    const base = values.base && existsSync(resolve(values.base, 'policy.yaml')) ? loadConfig(values.base).config : undefined;
    console.log(renderPlan(base, head));
    break;
  }
  case 'compile': {
    if (!values.out) throw new Error('--out is required');
    const config = load(values.dir);
    writeFileSync(values.out, JSON.stringify({ version: values.version, config }));
    console.log(`wrote ${values.out} (${values.version})`);
    break;
  }
  default:
    console.error('usage: crm <validate|render|plan|compile> [--dir crm] [--base dir] [--out file] [--version sha]');
    process.exit(2);
}
