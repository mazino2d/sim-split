// crm CLI (R-9): validate, render, plan and compile the config in crm/.
//
//   node src/cli.ts validate [--dir ../../crm]
//   node src/cli.ts render   [--dir …]                 Markdown preview of every message
//   node src/cli.ts plan     [--dir …] --base <dir>    what changes against another copy (main)
//   node src/cli.ts compile  [--dir …] --out config.json --version <git sha>
//   node src/cli.ts check-traits [--dir …] --table <project.dataset.table>   catalog vs the dbt table

import { writeFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { loadConfig, type Problem } from './config/load.ts';
import { checkConfig } from './config/check.ts';
import { renderAll, renderPlan } from './preview.ts';
import { compareTraits } from './traits_check.ts';
import type { Config } from './config/schema.ts';

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: {
    dir: { type: 'string', default: resolve(import.meta.dirname, '../../../crm') },
    base: { type: 'string' },
    out: { type: 'string' },
    version: { type: 'string', default: 'local' },
    table: { type: 'string' },
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
  case 'check-traits': {
    if (!values.table) throw new Error('--table is required');
    const config = load(values.dir);
    const { BigQuery } = await import('@google-cloud/bigquery');
    const [project, dataset, name] = values.table.split('.');
    const table = new BigQuery({ projectId: project }).dataset(dataset).table(name);
    const [exists] = await table.exists();
    if (!exists) {
      // The first deploy can come before dbt's first run.
      console.log(`::warning::${values.table} does not exist yet; trait catalog not checked`);
      break;
    }
    const [meta] = await table.getMetadata();
    const columns = new Map<string, string>(
      (meta.schema?.fields ?? []).map((f: { name: string; type: string }) => [f.name, f.type]),
    );
    const problems = compareTraits(config.traits, columns);
    for (const p of problems) console.error(`error crm/traits.yaml: ${p}`);
    if (problems.length) process.exit(1);
    console.log(`trait catalog matches ${values.table}`);
    break;
  }
  default:
    console.error('usage: crm <validate|render|plan|compile|check-traits> [--dir crm] [--base dir] [--out file] [--version sha]');
    process.exit(2);
}
