// Firestore security rules tests. They run against the emulator:
//   npx firebase-tools emulators:exec --only firestore --project demo-simsplit \
//     "npm --prefix firebase/test test"
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  arrayRemove,
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

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

const db = (uid) => env.authenticatedContext(uid).firestore();

const stamp = (uid) => ({ updatedBy: uid, updatedAt: serverTimestamp() });

const group = (uid, extra = {}) => ({
  name: 'Trip',
  currencyCode: 'VND',
  ownerUid: uid,
  memberUids: [uid],
  deleted: false,
  ...stamp(uid),
  ...extra,
});

const activity = (uid, extra = {}) => ({
  actorUid: uid,
  action: 'create',
  entityType: 'expense',
  entityId: 'e1',
  before: null,
  after: {},
  clientTime: 1759550000000,
  syncedAt: serverTimestamp(),
  ...extra,
});

/** Seeds a group shared by [uids] (the first one owns it), bypassing rules. */
async function seedGroup(uids, { owner = uids[0] } = {}) {
  await env.withSecurityRulesDisabled(async (admin) => {
    const fs = admin.firestore();
    await setDoc(doc(fs, 'groups/g1'), {
      name: 'Trip',
      currencyCode: 'VND',
      ownerUid: owner,
      memberUids: uids,
      updatedBy: owner,
    });
    await setDoc(doc(fs, 'groups/g1/members/m1'), { name: 'An', linkedUid: uids[0] });
    await setDoc(doc(fs, 'groups/g1/members/m2'), { name: 'Binh', linkedUid: null });
    await setDoc(doc(fs, 'groups/g1/expenses/e1'), { amountCents: 100, splits: [] });
    await setDoc(doc(fs, 'groups/g1/activity/a1'), { actorUid: owner, action: 'create' });
  });
}

describe('creating a group', () => {
  test('a signed-in user creates a group with its first records in one batch', async () => {
    const fs = db('alice');
    const batch = writeBatch(fs);
    batch.set(doc(fs, 'groups/g1'), group('alice'));
    batch.set(doc(fs, 'groups/g1/members/m1'), { name: 'An', linkedUid: 'alice', ...stamp('alice') });
    batch.set(doc(fs, 'groups/g1/activity/a1'), activity('alice'));
    await assertSucceeds(batch.commit());
  });

  test('a group must start with only its creator as member and owner', async () => {
    await assertFails(setDoc(doc(db('alice'), 'groups/g1'), group('alice', { memberUids: ['alice', 'bob'] })));
    await assertFails(setDoc(doc(db('alice'), 'groups/g1'), group('alice', { ownerUid: 'bob' })));
  });

  test('a write must name its author and carry the server time', async () => {
    await assertFails(setDoc(doc(db('alice'), 'groups/g1'), group('alice', { updatedBy: 'bob' })));
    await assertFails(setDoc(doc(db('alice'), 'groups/g1'), group('alice', { updatedAt: 1 })));
  });

  test('a signed-out user cannot create a group', async () => {
    await assertFails(
      setDoc(doc(env.unauthenticatedContext().firestore(), 'groups/g1'), group('alice')),
    );
  });
});

describe('members of a group (AC23)', () => {
  test('a member reads the group and everything in it', async () => {
    await seedGroup(['alice', 'bob']);
    const fs = db('bob');
    await assertSucceeds(getDoc(doc(fs, 'groups/g1')));
    await assertSucceeds(getDoc(doc(fs, 'groups/g1/expenses/e1')));
    await assertSucceeds(getDoc(doc(fs, 'groups/g1/activity/a1')));
    await assertSucceeds(getDocs(query(collection(fs, 'groups'), where('memberUids', 'array-contains', 'bob'))));
  });

  test('a non-member can neither read nor write the group', async () => {
    await seedGroup(['alice']);
    const fs = db('mallory');
    await assertFails(getDoc(doc(fs, 'groups/g1')));
    await assertFails(getDoc(doc(fs, 'groups/g1/expenses/e1')));
    await assertFails(getDoc(doc(fs, 'groups/g1/activity/a1')));
    await assertFails(setDoc(doc(fs, 'groups/g1/expenses/e2'), { amountCents: 1, splits: [], ...stamp('mallory') }));
    await assertFails(updateDoc(doc(fs, 'groups/g1'), { name: 'Mine', ...stamp('mallory') }));
  });

  test('any member edits anything in the group', async () => {
    await seedGroup(['alice', 'bob']);
    const fs = db('bob');
    await assertSucceeds(updateDoc(doc(fs, 'groups/g1'), { name: 'Da Lat', ...stamp('bob') }));
    await assertSucceeds(
      setDoc(doc(fs, 'groups/g1/expenses/e1'), { amountCents: 250, splits: [], deleted: true, ...stamp('bob') }, { merge: true }),
    );
  });

  test('a member cannot add someone else or take ownership', async () => {
    await seedGroup(['alice', 'bob']);
    const fs = db('bob');
    await assertFails(updateDoc(doc(fs, 'groups/g1'), { memberUids: ['alice', 'bob', 'carol'], ...stamp('bob') }));
    await assertFails(updateDoc(doc(fs, 'groups/g1'), { ownerUid: 'bob', ...stamp('bob') }));
  });

  test('money must be integer cents (AC21)', async () => {
    await seedGroup(['alice']);
    const fs = db('alice');
    await assertFails(setDoc(doc(fs, 'groups/g1/expenses/e2'), { amountCents: 1.5, splits: [], ...stamp('alice') }));
    await assertFails(setDoc(doc(fs, 'groups/g1/settlements/s1'), { amountCents: '100', ...stamp('alice') }));
    await assertSucceeds(setDoc(doc(fs, 'groups/g1/settlements/s1'), { amountCents: 100, ...stamp('alice') }));
  });
});

describe('claiming a member', () => {
  test('a member claims an unclaimed name for themselves only', async () => {
    await seedGroup(['alice', 'bob']);
    await assertFails(updateDoc(doc(db('bob'), 'groups/g1/members/m2'), { linkedUid: 'carol', ...stamp('bob') }));
    await assertSucceeds(updateDoc(doc(db('bob'), 'groups/g1/members/m2'), { linkedUid: 'bob', ...stamp('bob') }));
  });

  test("nobody takes or releases someone else's claim", async () => {
    await seedGroup(['alice', 'bob']);
    await assertFails(updateDoc(doc(db('bob'), 'groups/g1/members/m1'), { linkedUid: 'bob', ...stamp('bob') }));
    await assertFails(updateDoc(doc(db('bob'), 'groups/g1/members/m1'), { linkedUid: null, ...stamp('bob') }));
    await assertSucceeds(updateDoc(doc(db('alice'), 'groups/g1/members/m1'), { linkedUid: null, ...stamp('alice') }));
  });
});

describe('activity history (AC28, AC29)', () => {
  test('a member creates entries in their own name', async () => {
    await seedGroup(['alice', 'bob']);
    await assertSucceeds(setDoc(doc(db('bob'), 'groups/g1/activity/a2'), activity('bob')));
    await assertFails(setDoc(doc(db('bob'), 'groups/g1/activity/a3'), activity('alice')));
  });

  test('nobody edits or deletes an entry of a shared group', async () => {
    await seedGroup(['alice', 'bob']);
    for (const uid of ['alice', 'bob']) {
      await assertFails(updateDoc(doc(db(uid), 'groups/g1/activity/a1'), { action: 'delete' }));
      await assertFails(setDoc(doc(db(uid), 'groups/g1/activity/a1'), activity(uid)));
      await assertFails(deleteDoc(doc(db(uid), 'groups/g1/activity/a1')));
    }
  });
});

describe('deleting an account (AC6)', () => {
  test('the only member deletes the group and everything in it', async () => {
    await seedGroup(['alice']);
    const fs = db('alice');
    for (const path of ['members/m1', 'members/m2', 'expenses/e1', 'activity/a1']) {
      await assertSucceeds(deleteDoc(doc(fs, `groups/g1/${path}`)));
    }
    await assertSucceeds(deleteDoc(doc(fs, 'groups/g1')));
  });

  test('a group with other members cannot be deleted', async () => {
    await seedGroup(['alice', 'bob']);
    const fs = db('alice');
    await assertFails(deleteDoc(doc(fs, 'groups/g1/expenses/e1')));
    await assertFails(deleteDoc(doc(fs, 'groups/g1')));
  });

  test('the owner leaves: releases their member, logs it and hands over the group', async () => {
    await seedGroup(['alice', 'bob']);
    const fs = db('alice');
    const batch = writeBatch(fs);
    batch.update(doc(fs, 'groups/g1/members/m1'), { linkedUid: null, ...stamp('alice') });
    batch.set(doc(fs, 'groups/g1/activity/leave'), activity('alice', { action: 'update', entityType: 'member', entityId: 'm1' }));
    batch.update(doc(fs, 'groups/g1'), { memberUids: arrayRemove('alice'), ownerUid: 'bob', ...stamp('alice') });
    await assertSucceeds(batch.commit());
    await assertFails(getDoc(doc(fs, 'groups/g1')));
  });

  test('a member leaving cannot remove others or keep ownership', async () => {
    await seedGroup(['alice', 'bob', 'carol']);
    await assertFails(updateDoc(doc(db('bob'), 'groups/g1'), { memberUids: ['bob'], ...stamp('bob') }));
    await assertFails(updateDoc(doc(db('alice'), 'groups/g1'), { memberUids: arrayRemove('alice'), ...stamp('alice') }));
    await assertSucceeds(updateDoc(doc(db('bob'), 'groups/g1'), { memberUids: arrayRemove('bob'), ...stamp('bob') }));
  });
});
