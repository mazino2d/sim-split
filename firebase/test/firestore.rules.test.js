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
  arrayUnion,
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
async function seedGroup(uids, { owner = uids[0], inviteToken } = {}) {
  await env.withSecurityRulesDisabled(async (admin) => {
    const fs = admin.firestore();
    await setDoc(doc(fs, 'groups/g1'), {
      name: 'Trip',
      currencyCode: 'VND',
      ownerUid: owner,
      memberUids: uids,
      updatedBy: owner,
      ...(inviteToken ? { inviteToken } : {}),
    });
    if (inviteToken) await setDoc(doc(fs, `invites/${inviteToken}`), { groupId: 'g1' });
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

const TOKEN = 'tok_aaaaaaaaaaaaaaaaaaaa';
const NEW_TOKEN = 'tok_bbbbbbbbbbbbbbbbbbbb';

/** Sets the group's invite token and writes its invite document, as the app does. */
function setInvite(fs, uid, token) {
  const batch = writeBatch(fs);
  batch.update(doc(fs, 'groups/g1'), { inviteToken: token, ...stamp(uid) });
  batch.set(doc(fs, `invites/${token}`), { groupId: 'g1' });
  return batch;
}

describe('invite links (AC9, AC13)', () => {
  test('any member creates the first link', async () => {
    await seedGroup(['alice', 'bob']);
    await assertSucceeds(setInvite(db('bob'), 'bob', TOKEN).commit());
  });

  test('a link needs its invite document, naming the right group', async () => {
    await seedGroup(['alice']);
    const fs = db('alice');
    await assertFails(updateDoc(doc(fs, 'groups/g1'), { inviteToken: TOKEN, ...stamp('alice') }));
    await assertFails(setDoc(doc(fs, `invites/${TOKEN}`), { groupId: 'g1' }));
  });

  test('a non-member cannot create a link', async () => {
    await seedGroup(['alice']);
    await assertFails(setInvite(db('mallory'), 'mallory', TOKEN).commit());
  });

  test('only the owner resets the link and removes the old one', async () => {
    await seedGroup(['alice', 'bob'], { inviteToken: TOKEN });
    await assertFails(setInvite(db('bob'), 'bob', NEW_TOKEN).commit());
    await assertFails(deleteDoc(doc(db('bob'), `invites/${TOKEN}`)));

    const fs = db('alice');
    const batch = setInvite(fs, 'alice', NEW_TOKEN);
    batch.delete(doc(fs, `invites/${TOKEN}`));
    await assertSucceeds(batch.commit());
  });

  test('anyone signed in reads a link by its token, but cannot list links', async () => {
    await seedGroup(['alice'], { inviteToken: TOKEN });
    await assertSucceeds(getDoc(doc(db('bob'), `invites/${TOKEN}`)));
    await assertFails(getDocs(collection(db('bob'), 'invites')));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), `invites/${TOKEN}`)));
  });
});

describe('joining a group (AC10, AC13)', () => {
  const join = (fs, uid, token = TOKEN) => {
    const batch = writeBatch(fs);
    batch.update(doc(fs, 'groups/g1'), { memberUids: arrayUnion(uid), joinToken: token, ...stamp(uid) });
    batch.set(doc(fs, 'groups/g1/activity/join'), activity(uid, { action: 'join', entityType: 'group', entityId: 'g1' }));
    return batch.commit();
  };

  test('a user with the current link joins as themselves', async () => {
    await seedGroup(['alice'], { inviteToken: TOKEN });
    await assertSucceeds(join(db('bob'), 'bob'));
    await assertSucceeds(getDoc(doc(db('bob'), 'groups/g1/expenses/e1')));
  });

  test('a reset link stops working', async () => {
    await seedGroup(['alice'], { inviteToken: NEW_TOKEN });
    await assertFails(join(db('bob'), 'bob', TOKEN));
  });

  test('a group without a link cannot be joined', async () => {
    await seedGroup(['alice']);
    await assertFails(join(db('bob'), 'bob', TOKEN));
  });

  test('joining adds only yourself and changes nothing else', async () => {
    await seedGroup(['alice'], { inviteToken: TOKEN });
    const fs = db('bob');
    await assertFails(updateDoc(doc(fs, 'groups/g1'), { memberUids: arrayUnion('carol'), joinToken: TOKEN, ...stamp('bob') }));
    await assertFails(updateDoc(doc(fs, 'groups/g1'), { memberUids: arrayUnion('bob'), joinToken: TOKEN, name: 'Mine', ...stamp('bob') }));
    await assertFails(updateDoc(doc(fs, 'groups/g1'), { memberUids: arrayUnion('bob'), joinToken: TOKEN, ownerUid: 'bob', ...stamp('bob') }));
  });

  test('a joined member claims an unclaimed name', async () => {
    await seedGroup(['alice'], { inviteToken: TOKEN });
    await join(db('bob'), 'bob');
    await assertSucceeds(updateDoc(doc(db('bob'), 'groups/g1/members/m2'), { linkedUid: 'bob', ...stamp('bob') }));
  });
});
