// Audiences: rules over the trait catalog (crm/traits.yaml). Checked here and
// described in plain words for the PR comment; the BigQuery compiler comes in P4.

import type { Audience, Operator, Rule, RuleGroup, Trait } from './config/schema.ts';

/** Operators each trait type accepts, and what each value must look like. */
export const OPERATORS_BY_TYPE: Record<Trait['type'], Operator[]> = {
  choice: ['eq', 'neq', 'in'],
  number: ['eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'between'],
  days_ago: ['gt', 'gte', 'lt', 'lte', 'between'],
  bool: ['is'],
  version: ['lt', 'gte'],
};

const VERSION = /^\d{4}\.\d{1,2}\.\d{1,2}$/;

const isRule = (r: Rule | RuleGroup): r is Rule => 'trait' in r;

/** Problems with one rule against the catalog; empty when it is fine. */
export const checkRule = (rule: Rule, traits: Map<string, Trait>): string[] => {
  const trait = traits.get(rule.trait);
  if (!trait) return [`unknown trait "${rule.trait}"`];
  if (!OPERATORS_BY_TYPE[trait.type].includes(rule.op)) {
    return [`"${rule.op}" does not apply to ${trait.type} trait "${trait.name}"`];
  }
  const v = rule.value;
  const fail = (what: string) => [`${trait.name} ${rule.op}: value must be ${what}`];
  switch (trait.type) {
    case 'choice': {
      const values = rule.op === 'in' ? v : [v];
      if (!Array.isArray(values) || values.length === 0) return fail('a non-empty list');
      const unknown = values.filter((x) => !trait.values!.includes(String(x)));
      return unknown.length ? fail(`one of ${trait.values!.join(', ')} (got ${unknown.join(', ')})`) : [];
    }
    case 'number':
    case 'days_ago':
      if (rule.op === 'between') {
        return Array.isArray(v) && v.length === 2 && v.every((x) => typeof x === 'number') && v[0] <= v[1]
          ? []
          : fail('[min, max] numbers');
      }
      return typeof v === 'number' ? [] : fail('a number');
    case 'bool':
      return typeof v === 'boolean' ? [] : fail('true or false');
    case 'version':
      return typeof v === 'string' && VERSION.test(v) ? [] : fail('a version like 2026.11.22');
  }
};

export const checkAudience = (audience: Audience, traits: Map<string, Trait>): string[] =>
  audience.rules.flatMap((r) => (isRule(r) ? checkRule(r, traits) : r.rules.flatMap((x) => checkRule(x, traits))));

const OP_WORDS: Record<Operator, string> = {
  eq: 'is',
  neq: 'is not',
  in: 'is one of',
  gt: 'is more than',
  gte: 'is at least',
  lt: 'is less than',
  lte: 'is at most',
  between: 'is between',
  is: 'is',
};

const describeRule = (rule: Rule, traits: Map<string, Trait>): string => {
  const trait = traits.get(rule.trait);
  const label = trait?.label ?? rule.trait;
  const v = rule.value;
  const shown = Array.isArray(v)
    ? rule.op === 'between'
      ? `${v[0]} and ${v[1]}`
      : v.join(', ')
    : String(v);
  const unit = trait?.type === 'days_ago' ? ' days ago' : '';
  return `${label} ${OP_WORDS[rule.op]} ${shown}${unit}`;
};

/** "Everyone where: A and B and (C or D)", for the PR comment. */
export const describeAudience = (audience: Audience, traits: Map<string, Trait>): string => {
  if (audience.rules.length === 0) return 'Everyone';
  const join = (match: 'all' | 'any') => (match === 'all' ? ' and ' : ' or ');
  const parts = audience.rules.map((r) =>
    isRule(r) ? describeRule(r, traits) : `(${r.rules.map((x) => describeRule(x, traits)).join(join(r.match))})`,
  );
  return `Everyone where ${parts.join(join(audience.match))}`;
};
