import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { loadConfig } from '../src/config/load.ts';
import { compileAudience } from '../src/audience_sql.ts';

const { config } = loadConfig(resolve(import.meta.dirname, '../../../crm'));
const traits = config!.traits;
const TABLE = 'dataplatform-as-se1-dev.simsplit_crm.user_traits';

test('rules compile to one parameterised query', () => {
  const q = compileAudience(
    {
      id: 'owes',
      description: 'd',
      match: 'all',
      rules: [
        { trait: 'oldest_unsettled_days', op: 'gt', value: 14 },
        { trait: 'language', op: 'in', value: ['vi'] },
        {
          match: 'any',
          rules: [
            { trait: 'platform', op: 'eq', value: 'android' },
            { trait: 'sessions_30d', op: 'between', value: [1, 5] },
          ],
        },
      ],
    },
    traits,
    TABLE,
  );
  assert.equal(
    q.sql,
    'SELECT uid FROM `dataplatform-as-se1-dev.simsplit_crm.user_traits` WHERE `oldest_unsettled_days` > @p0' +
      ' AND `language` IN UNNEST(@p1) AND (`platform` = @p2 OR `sessions_30d` BETWEEN @p3 AND @p4)',
  );
  assert.deepEqual(q.params, { p0: 14, p1: ['vi'], p2: 'android', p3: 1, p4: 5 });
});

test('versions compare as numbers, not text', () => {
  const q = compileAudience(
    { id: 'old', description: 'd', match: 'all', rules: [{ trait: 'app_version', op: 'lt', value: '2026.11.22' }] },
    traits,
    TABLE,
  );
  assert.match(q.sql, /SAFE_CAST\(SPLIT\(`app_version`, '\.'\)\[SAFE_OFFSET\(0\)\] AS INT64\) \* 10000/);
  assert.deepEqual(q.params, { p0: 20261122 });
});

test('values never reach the SQL text', () => {
  const q = compileAudience(
    { id: 'x', description: 'd', match: 'all', rules: [{ trait: 'platform', op: 'eq', value: "web' OR TRUE --" }] },
    traits,
    TABLE,
  );
  assert.equal(q.sql.includes('OR TRUE'), false);
});

test('an empty audience is everyone; a bad table or trait is refused', () => {
  assert.match(compileAudience({ id: 'all', description: 'd', match: 'all', rules: [] }, traits, TABLE).sql, /WHERE TRUE$/);
  assert.throws(() => compileAudience({ id: 'a', description: 'd', match: 'all', rules: [] }, traits, 'x; DROP'), /bad traits table/);
  assert.throws(
    () => compileAudience({ id: 'a', description: 'd', match: 'all', rules: [{ trait: 'nope', op: 'eq', value: 1 }] }, traits, TABLE),
    /unknown trait/,
  );
});
