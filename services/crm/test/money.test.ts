import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { formatMoney } from '../src/money.ts';

// The same vectors run against the app's formatMoney in
// test/core/utils/money_vectors_test.dart (spec AC10).
const vectors = JSON.parse(readFileSync(new URL('./money_vectors.json', import.meta.url), 'utf8')) as {
  cents: number;
  currency: string;
  text: string;
}[];

test('money reads exactly as the app shows it', () => {
  for (const v of vectors) assert.equal(formatMoney(v.cents, v.currency), v.text, `${v.cents} ${v.currency}`);
});
