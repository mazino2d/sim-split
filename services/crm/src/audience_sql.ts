// Audience rules → one parameterised BigQuery query over the traits table
// (R-9 P4, spec AC20). Columns come only from the trait catalog and values
// only travel as query parameters, so a rule cannot inject SQL.

import type { Audience, Rule, RuleGroup, Trait } from './config/schema.ts';

export interface CompiledQuery {
  sql: string;
  params: Record<string, string | number | boolean | (string | number)[]>;
}

const isRule = (r: Rule | RuleGroup): r is Rule => 'trait' in r;

const COMPARE: Record<string, string> = { eq: '=', neq: '!=', gt: '>', gte: '>=', lt: '<', lte: '<=', is: '=' };

/** CalVer as a sortable number: 2026.11.22 → 20261122. */
const versionKey = (column: string) =>
  `(SAFE_CAST(SPLIT(${column}, '.')[SAFE_OFFSET(0)] AS INT64) * 10000 + ` +
  `SAFE_CAST(SPLIT(${column}, '.')[SAFE_OFFSET(1)] AS INT64) * 100 + ` +
  `SAFE_CAST(SPLIT(${column}, '.')[SAFE_OFFSET(2)] AS INT64))`;

const versionValue = (v: string) => {
  const [y, m, d] = v.split('.').map(Number);
  return y * 10000 + m * 100 + d;
};

export const compileAudience = (audience: Audience, traits: Trait[], table: string): CompiledQuery => {
  if (!/^[a-z0-9-]+\.[a-z0-9_]+\.[a-z0-9_]+$/.test(table)) throw new Error(`bad traits table "${table}"`);
  const catalog = new Map(traits.map((t) => [t.name, t]));
  const params: CompiledQuery['params'] = {};
  let n = 0;
  const param = (value: CompiledQuery['params'][string]) => {
    const name = `p${n++}`;
    params[name] = value;
    return `@${name}`;
  };

  const rule = (r: Rule): string => {
    const trait = catalog.get(r.trait);
    if (!trait) throw new Error(`unknown trait "${r.trait}"`);
    const column = `\`${trait.column}\``;
    const v = r.value;
    if (trait.type === 'version') return `${versionKey(column)} ${COMPARE[r.op]} ${param(versionValue(String(v)))}`;
    if (r.op === 'in') return `${column} IN UNNEST(${param(v as (string | number)[])})`;
    if (r.op === 'between') {
      const [lo, hi] = v as number[];
      return `${column} BETWEEN ${param(lo)} AND ${param(hi)}`;
    }
    return `${column} ${COMPARE[r.op]} ${param(v as string | number | boolean)}`;
  };

  const join = (match: 'all' | 'any') => (match === 'all' ? ' AND ' : ' OR ');
  const where = audience.rules.length
    ? audience.rules
        .map((r) => (isRule(r) ? rule(r) : `(${r.rules.map(rule).join(join(r.match))})`))
        .join(join(audience.match))
    : 'TRUE';
  return { sql: `SELECT uid FROM \`${table}\` WHERE ${where}`, params };
};
