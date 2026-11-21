// Reads crm/ into a Config, reporting every problem with its file and line.

import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join, relative, basename } from 'node:path';
import { LineCounter, parseDocument } from 'yaml';
import type { z } from 'zod';
import {
  audienceSchema,
  campaignSchema,
  categoriesSchema,
  policySchema,
  scheduleSchema,
  templateSchema,
  traitsSchema,
  triggerSchema,
  type Config,
} from './schema.ts';

export interface Problem {
  file: string;
  line?: number;
  message: string;
}

export interface LoadResult {
  config?: Config;
  problems: Problem[];
}

const parseFile = <T>(root: string, path: string, schema: z.ZodType<T>, problems: Problem[]): T | undefined => {
  const file = relative(root, path);
  const lineCounter = new LineCounter();
  const doc = parseDocument(readFileSync(path, 'utf8'), { lineCounter, prettyErrors: false });
  if (doc.errors.length) {
    for (const e of doc.errors) problems.push({ file, line: lineCounter.linePos(e.pos[0]).line, message: e.message });
    return undefined;
  }
  const result = schema.safeParse(doc.toJS());
  if (result.success) return result.data;
  for (const issue of result.error.issues) {
    // A missing key has no node: point at the nearest parent that exists.
    let line: number | undefined;
    for (let depth = issue.path.length; depth >= 0 && line === undefined; depth--) {
      const path = issue.path.slice(0, depth) as (string | number)[];
      const node = (depth ? doc.getIn(path, true) : doc.contents) as { range?: [number, number, number] } | undefined;
      if (node?.range) line = lineCounter.linePos(node.range[0]).line;
    }
    const where = issue.path.length ? `${issue.path.join('.')}: ` : '';
    problems.push({ file, line, message: `${where}${issue.message}` });
  }
  return undefined;
};

/** One item per file; the file name (without .yaml) must be the item's id. */
const parseDir = <T extends { id: string }>(
  root: string,
  dir: string,
  schema: z.ZodType<T>,
  problems: Problem[],
): T[] => {
  const path = join(root, dir);
  if (!existsSync(path)) return [];
  const items: T[] = [];
  for (const name of readdirSync(path).sort()) {
    if (name === '.gitkeep') continue;
    const filePath = join(path, name);
    if (!name.endsWith('.yaml')) {
      problems.push({ file: relative(root, filePath), message: 'only .yaml files belong here' });
      continue;
    }
    const item = parseFile(root, filePath, schema, problems);
    if (!item) continue;
    if (item.id !== basename(name, '.yaml')) {
      problems.push({ file: relative(root, filePath), message: `id "${item.id}" must match the file name` });
      continue;
    }
    items.push(item);
  }
  return items;
};

export const loadConfig = (root: string): LoadResult => {
  const problems: Problem[] = [];
  const need = (name: string) => {
    const path = join(root, name);
    if (!existsSync(path)) problems.push({ file: name, message: 'missing' });
    return path;
  };
  const policyPath = need('policy.yaml');
  const categoriesPath = need('categories.yaml');
  const traitsPath = need('traits.yaml');
  if (problems.length) return { problems };

  const policy = parseFile(root, policyPath, policySchema, problems);
  const categories = parseFile(root, categoriesPath, categoriesSchema, problems);
  const traits = parseFile(root, traitsPath, traitsSchema, problems);
  const triggers = parseDir(root, 'triggers', triggerSchema, problems);
  const schedules = parseDir(root, 'schedules', scheduleSchema, problems);
  const campaigns = parseDir(root, 'campaigns', campaignSchema, problems);
  const audiences = parseDir(root, 'audiences', audienceSchema, problems);
  const templates = parseDir(root, 'templates', templateSchema, problems);
  if (!policy || !categories || !traits) return { problems };
  return { config: { policy, categories, traits, triggers, schedules, campaigns, audiences, templates }, problems };
};
