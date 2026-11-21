// The trait catalog must match the dbt model's columns (plan: "Traits").

import type { Trait } from './config/schema.ts';

const BQ_TYPE: Record<Trait['type'], string> = {
  choice: 'STRING',
  version: 'STRING',
  number: 'INT64',
  days_ago: 'INT64',
  bool: 'BOOL',
};

/** Problems between the catalog and the table's columns (name → BigQuery type). */
export const compareTraits = (traits: Trait[], columns: Map<string, string>): string[] => {
  const problems: string[] = [];
  if (!columns.has('uid')) problems.push('the table has no uid column');
  for (const t of traits) {
    const actual = columns.get(t.column);
    // The REST API reports INT64 as INTEGER and BOOL as BOOLEAN.
    const normal = actual === 'INTEGER' ? 'INT64' : actual === 'BOOLEAN' ? 'BOOL' : actual;
    if (!actual) problems.push(`${t.name}: column ${t.column} is missing`);
    else if (normal !== BQ_TYPE[t.type]) problems.push(`${t.name}: column ${t.column} is ${actual}, expected ${BQ_TYPE[t.type]}`);
  }
  return problems;
};

/** Spec AC21: scheduled sends skip traits older than this. */
export const MAX_TRAITS_AGE_MS = 36 * 60 * 60 * 1000;

export const traitsFresh = (updatedAt: Date, now: Date) => now.getTime() - updatedAt.getTime() <= MAX_TRAITS_AGE_MS;
