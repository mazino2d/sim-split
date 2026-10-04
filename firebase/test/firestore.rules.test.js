// Firestore security rules tests. They run against the emulator:
//   npx firebase-tools emulators:exec --only firestore --project demo-simsplit \
//     "npm --prefix firebase/test test"
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-simsplit',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
    },
  });
});

after(() => env.cleanup());

beforeEach(() => env.clearFirestore());

// Until co-worked groups ship (R-3 P3–P5) nobody may read or write anything.
describe('deny-all ruleset', () => {
  for (const [who, context] of [
    ['a signed-out user', () => env.unauthenticatedContext()],
    ['a signed-in user', () => env.authenticatedContext('alice')],
  ]) {
    test(`${who} cannot read a group`, async () => {
      await env.withSecurityRulesDisabled((admin) =>
        setDoc(doc(admin.firestore(), 'groups/g1'), { name: 'Trip' }),
      );
      await assertFails(getDoc(doc(context().firestore(), 'groups/g1')));
    });

    test(`${who} cannot write a group`, async () => {
      await assertFails(
        setDoc(doc(context().firestore(), 'groups/g1'), { name: 'Trip' }),
      );
    });
  }
});
