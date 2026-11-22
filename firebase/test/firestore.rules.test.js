// Firestore security rules tests. They run against the emulator:
//   npx firebase-tools emulators:exec --only firestore --project demo-simsplit \
//     "npm --prefix firebase/test test"
import assert from 'node:assert/strict';
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
  deleteField,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  Timestamp,
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

// Accounts that signed in after R-4 have a profile; the rules require it for
// every group read and write. 'newcomer' signs in during the profile tests.
const AGREED = ['alice', 'bob', 'carol', 'mallory'];

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (admin) => {
    for (const uid of AGREED) {
      await setDoc(doc(admin.firestore(), `users/${uid}`), {
        displayName: uid,
        email: `${uid}@example.com`,
        createdAt: 1,
        consent: { agreedAt: 1, policyVersion: '2026-10-24' },
      });
    }
  });
});

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
async function seedGroup(uids, { owner = uids[0], inviteToken, isArchived } = {}) {
  await env.withSecurityRulesDisabled(async (admin) => {
    const fs = admin.firestore();
    await setDoc(doc(fs, 'groups/g1'), {
      name: 'Trip',
      currencyCode: 'VND',
      ownerUid: owner,
      memberUids: uids,
      updatedBy: owner,
      ...(inviteToken ? { inviteToken } : {}),
      ...(isArchived === undefined ? {} : { isArchived }),
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

describe('user profiles and the privacy policy agreement (R-4 AC7)', () => {
  const profile = (extra = {}) => ({
    displayName: 'Alice',
    email: 'alice@example.com',
    createdAt: serverTimestamp(),
    consent: { agreedAt: serverTimestamp(), policyVersion: '2026-10-24' },
    ...extra,
  });

  test('an account creates, reads and deletes only its own profile', async () => {
    const fs = db('newcomer');
    await assertSucceeds(setDoc(doc(fs, 'users/newcomer'), profile()));
    await assertSucceeds(getDoc(doc(fs, 'users/newcomer')));
    await assertFails(getDoc(doc(db('bob'), 'users/newcomer')));
    await assertFails(deleteDoc(doc(db('bob'), 'users/newcomer')));
    await assertFails(setDoc(doc(db('bob'), 'users/newcomer2'), profile()));
    await assertSucceeds(deleteDoc(doc(fs, 'users/newcomer')));
  });

  test('the agreement carries the server time and cannot change later', async () => {
    const fs = db('newcomer');
    await assertFails(setDoc(doc(fs, 'users/newcomer'), profile({ consent: { agreedAt: 1, policyVersion: 'v' } })));
    await assertFails(setDoc(doc(fs, 'users/newcomer'), profile({ extra: true })));
    await setDoc(doc(fs, 'users/newcomer'), profile());
    await assertFails(updateDoc(doc(fs, 'users/newcomer'), { 'consent.policyVersion': 'other' }));
  });

  test('profiles cannot be listed', async () => {
    await assertFails(getDocs(collection(db('alice'), 'users')));
  });

  test('an account without a profile cannot read or write any group', async () => {
    await seedGroup(['alice', 'newcomer']);
    await assertFails(getDoc(doc(db('newcomer'), 'groups/g1')));
    await assertFails(getDoc(doc(db('newcomer'), 'groups/g1/expenses/e1')));
    await assertFails(setDoc(doc(db('newcomer'), 'groups/g2'), { ...group('newcomer'), ...stamp('newcomer') }));
    await assertSucceeds(getDoc(doc(db('alice'), 'groups/g1')));
  });

  test('once it agrees, the same account can read its group', async () => {
    await seedGroup(['alice', 'newcomer']);
    await setDoc(doc(db('newcomer'), 'users/newcomer'), profile());
    await assertSucceeds(getDoc(doc(db('newcomer'), 'groups/g1')));
  });
});

describe('settlement mode (R-7 #116)', () => {
  test('a member sets the mode and a collector who is a member of the group', async () => {
    await seedGroup(['alice', 'bob']);
    const fs = db('bob');
    await assertSucceeds(updateDoc(doc(fs, 'groups/g1'), { settlementMode: 'hub', settlementHubMemberId: 'm2', ...stamp('bob') }));
    await assertSucceeds(updateDoc(doc(fs, 'groups/g1'), { settlementMode: 'simplified', settlementHubMemberId: null, ...stamp('bob') }));
  });

  test('a new group starts in hub mode', async () => {
    await assertSucceeds(setDoc(doc(db('alice'), 'groups/g1'), group('alice', { settlementMode: 'hub', settlementHubMemberId: null })));
  });

  test('an unknown mode or a collector outside the group is refused', async () => {
    await seedGroup(['alice', 'bob']);
    const fs = db('bob');
    await assertFails(updateDoc(doc(fs, 'groups/g1'), { settlementMode: 'random', ...stamp('bob') }));
    await assertFails(updateDoc(doc(fs, 'groups/g1'), { settlementHubMemberId: 'm9', ...stamp('bob') }));
    await assertFails(updateDoc(doc(fs, 'groups/g1'), { settlementHubMemberId: 42, ...stamp('bob') }));
  });

  test('a group created with its collector in the same batch', async () => {
    const fs = db('alice');
    const batch = writeBatch(fs);
    batch.set(doc(fs, 'groups/g1'), group('alice', { settlementMode: 'hub', settlementHubMemberId: 'm1' }));
    batch.set(doc(fs, 'groups/g1/members/m1'), { name: 'An', linkedUid: 'alice', ...stamp('alice') });
    await assertSucceeds(batch.commit());
  });
});

describe('archiving a group (R-7 #117)', () => {
  const archive = (uid, isArchived = true) =>
    updateDoc(doc(db(uid), 'groups/g1'), { isArchived, ...stamp(uid) });

  test('only the owner archives and reopens', async () => {
    await seedGroup(['alice', 'bob'], { isArchived: false });
    await assertFails(archive('bob'));
    await assertSucceeds(archive('alice'));
    await assertFails(archive('bob', false));
    await assertSucceeds(archive('alice', false));
  });

  test('a group without the field counts as not archived', async () => {
    await seedGroup(['alice', 'bob']);
    await assertSucceeds(updateDoc(doc(db('bob'), 'groups/g1'), { name: 'Da Lat', isArchived: false, ...stamp('bob') }));
    await assertFails(archive('bob'));
  });

  test('nothing in an archived group can be added or changed', async () => {
    await seedGroup(['alice', 'bob'], { isArchived: true });
    for (const uid of ['alice', 'bob']) {
      const fs = db(uid);
      await assertFails(setDoc(doc(fs, 'groups/g1/expenses/e2'), { amountCents: 1, splits: [], ...stamp(uid) }));
      await assertFails(setDoc(doc(fs, 'groups/g1/expenses/e1'), { amountCents: 2, splits: [], ...stamp(uid) }, { merge: true }));
      await assertFails(setDoc(doc(fs, 'groups/g1/settlements/s1'), { amountCents: 100, ...stamp(uid) }));
      await assertFails(setDoc(doc(fs, 'groups/g1/members/m3'), { name: 'Chi', ...stamp(uid) }));
    }
    await assertFails(updateDoc(doc(db('bob'), 'groups/g1/members/m2'), { linkedUid: 'bob', ...stamp('bob') }));
  });

  test('the owner reopens it, and then it can be edited again', async () => {
    await seedGroup(['alice', 'bob'], { isArchived: true });
    await assertSucceeds(archive('alice', false));
    await assertSucceeds(setDoc(doc(db('bob'), 'groups/g1/expenses/e2'), { amountCents: 1, splits: [], ...stamp('bob') }));
  });

  test('the history records archiving, and members can still leave or delete', async () => {
    await seedGroup(['alice', 'bob'], { isArchived: false });
    const fs = db('alice');
    const batch = writeBatch(fs);
    batch.update(doc(fs, 'groups/g1'), { isArchived: true, ...stamp('alice') });
    batch.set(doc(fs, 'groups/g1/activity/arch'), activity('alice', { action: 'update', entityType: 'group', entityId: 'g1' }));
    await assertSucceeds(batch.commit());

    const leave = writeBatch(fs);
    leave.update(doc(fs, 'groups/g1/members/m1'), { linkedUid: null, ...stamp('alice') });
    leave.update(doc(fs, 'groups/g1'), { memberUids: arrayRemove('alice'), ownerUid: 'bob', ...stamp('alice') });
    await assertSucceeds(leave.commit());

    for (const path of ['members/m1', 'members/m2', 'expenses/e1', 'activity/a1']) {
      await assertSucceeds(deleteDoc(doc(db('bob'), `groups/g1/${path}`)));
    }
    await assertSucceeds(deleteDoc(doc(db('bob'), 'groups/g1')));
  });

  test('an archived group cannot be joined', async () => {
    await seedGroup(['alice'], { inviteToken: TOKEN, isArchived: true });
    const fs = db('bob');
    await assertFails(updateDoc(doc(fs, 'groups/g1'), { memberUids: arrayUnion('bob'), joinToken: TOKEN, ...stamp('bob') }));
  });
});

describe('the name an account goes by (R-7 #112)', () => {
  test('an account sets its own name, and only that field', async () => {
    const fs = db('alice');
    await assertSucceeds(updateDoc(doc(fs, 'users/alice'), { memberName: 'An' }));
    await assertFails(updateDoc(doc(fs, 'users/alice'), { memberName: '' }));
    await assertFails(updateDoc(doc(fs, 'users/alice'), { memberName: 'x'.repeat(81) }));
    await assertFails(updateDoc(doc(fs, 'users/alice'), { memberName: 7 }));
    await assertFails(updateDoc(doc(fs, 'users/alice'), { memberName: 'An', displayName: 'Other' }));
    await assertFails(updateDoc(doc(fs, 'users/alice'), { 'consent.policyVersion': 'other' }));
    await assertFails(updateDoc(doc(fs, 'users/alice'), { email: 'x@example.com' }));
  });

  test("nobody sets someone else's name", async () => {
    await assertFails(updateDoc(doc(db('bob'), 'users/alice'), { memberName: 'Bob' }));
  });
});

describe('hardening (R-8 P2)', () => {
  test("an archived group's own document is read-only", async () => {
    await seedGroup(['alice', 'bob'], { isArchived: true });
    for (const uid of ['alice', 'bob']) {
      await assertFails(updateDoc(doc(db(uid), 'groups/g1'), { name: 'Renamed', ...stamp(uid) }));
      await assertFails(updateDoc(doc(db(uid), 'groups/g1'), { settlementMode: 'hub', ...stamp(uid) }));
    }
    // Reopening is the owner's only change, on its own.
    await assertFails(updateDoc(doc(db('alice'), 'groups/g1'), { isArchived: false, name: 'Renamed', ...stamp('alice') }));
    await assertSucceeds(updateDoc(doc(db('alice'), 'groups/g1'), { isArchived: false, ...stamp('alice') }));
  });

  test('a member still leaves an archived group', async () => {
    await seedGroup(['alice', 'bob'], { isArchived: true });
    await assertSucceeds(updateDoc(doc(db('bob'), 'groups/g1'), { memberUids: ['alice'], ...stamp('bob') }));
  });

  test('free text is bounded', async () => {
    await seedGroup(['alice', 'bob']);
    const fs = db('bob');
    const expense = (extra) => setDoc(doc(fs, 'groups/g1/expenses/big'), { amountCents: 1, splits: [], ...extra, ...stamp('bob') });
    await assertFails(expense({ title: 'x'.repeat(201) }));
    await assertFails(expense({ title: 'Taxi', note: 'x'.repeat(2001) }));
    await assertSucceeds(expense({ title: 'x'.repeat(200), note: 'x'.repeat(2000) }));
    await assertFails(setDoc(doc(fs, 'groups/g1/settlements/s9'), { amountCents: 1, note: 'x'.repeat(2001), ...stamp('bob') }));
    await assertSucceeds(setDoc(doc(fs, 'groups/g1/settlements/s9'), { amountCents: 1, note: 'Cash', ...stamp('bob') }));
  });

  test('a record over a limit from before the limit can still be edited or deleted', async () => {
    await seedGroup(['alice', 'bob']);
    await env.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'groups/g1/expenses/old'), { amountCents: 1, splits: [], title: 'x'.repeat(500) });
    });
    await assertSucceeds(updateDoc(doc(db('bob'), 'groups/g1/expenses/old'), { amountCents: 2, ...stamp('bob') }));
    await assertSucceeds(updateDoc(doc(db('bob'), 'groups/g1/expenses/old'), { deleted: true, ...stamp('bob') }));
  });

  test('activity entries have the shape the app writes', async () => {
    await seedGroup(['alice', 'bob']);
    const fs = db('bob');
    const entry = (id, extra) => setDoc(doc(fs, `groups/g1/activity/${id}`), activity('bob', extra));
    await assertSucceeds(entry('ok1', { after: { title: 'Taxi', amountCents: 100 } }));
    await assertSucceeds(entry('ok2', { action: 'join', entityType: 'group', entityId: 'g1', after: {} }));
    await assertFails(entry('bad1', { action: 'forge' }));
    await assertFails(entry('bad2', { entityType: 'invite' }));
    await assertFails(entry('bad3', { extra: 'field' }));
    await assertFails(entry('bad4', { after: { title: 'x'.repeat(201) } }));
    await assertFails(entry('bad5', { after: { note: 'x'.repeat(2001) } }));
  });
});

describe('notification preferences (R-9 AC3, AC4)', () => {
  test('an account sets its own choices, with the right keys and types', async () => {
    const fs = db('alice');
    await assertSucceeds(updateDoc(doc(fs, 'users/alice'), { 'notificationPrefs.settleReminder': true }));
    await assertSucceeds(updateDoc(doc(fs, 'users/alice'), { 'notificationPrefs.groupActivity': false, 'notificationPrefs.updates': true }));
    await assertSucceeds(updateDoc(doc(fs, 'users/alice'), { 'notificationPrefs.mutedGroups': arrayUnion('g1') }));
    await assertSucceeds(updateDoc(doc(fs, 'users/alice'), { 'notificationPrefs.mutedGroups': arrayRemove('g1') }));
    // Together with the name, as long as each is valid.
    await assertSucceeds(updateDoc(doc(fs, 'users/alice'), { memberName: 'An', 'notificationPrefs.updates': false }));
    await assertFails(updateDoc(doc(fs, 'users/alice'), { memberName: '', 'notificationPrefs.updates': false }));

    await assertFails(updateDoc(doc(fs, 'users/alice'), { 'notificationPrefs.updates': 'yes' }));
    await assertFails(updateDoc(doc(fs, 'users/alice'), { 'notificationPrefs.marketing': true }));
    await assertFails(updateDoc(doc(fs, 'users/alice'), { 'notificationPrefs.mutedGroups': 'g1' }));
    await assertFails(updateDoc(doc(fs, 'users/alice'), { notificationPrefs: true }));
    await assertFails(updateDoc(doc(fs, 'users/alice'), { 'notificationPrefs.updates': true, email: 'x@example.com' }));
  });

  test('an account mutes at most 200 groups', async () => {
    const fs = db('alice');
    const ids = (n) => Array.from({ length: n }, (_, i) => `g${i}`);
    await assertSucceeds(updateDoc(doc(fs, 'users/alice'), { 'notificationPrefs.mutedGroups': ids(200) }));
    await assertFails(updateDoc(doc(fs, 'users/alice'), { 'notificationPrefs.mutedGroups': arrayUnion('one-more') }));
  });

  test("nobody changes someone else's choices", async () => {
    await assertFails(updateDoc(doc(db('bob'), 'users/alice'), { 'notificationPrefs.groupActivity': false }));
  });

  test('setting the name still works without any choices', async () => {
    await assertSucceeds(updateDoc(doc(db('alice'), 'users/alice'), { memberName: 'An' }));
  });
});

describe('notification preferences v2 (R-9 AC26–AC32)', () => {
  const set = (changes, uid = 'alice') => updateDoc(doc(db(uid), 'users/alice'), changes);
  const inHours = (h) => Timestamp.fromMillis(Date.now() + h * 3600 * 1000);

  test('event switches: the five known events, as bools', async () => {
    await assertSucceeds(set({ 'notificationPrefs.activityEvents.expenseDelete': false }));
    await assertSucceeds(set({ 'notificationPrefs.activityEvents.memberJoin': true }));
    await assertSucceeds(set({
      'notificationPrefs.activityEvents': {
        expenseCreate: true, expenseUpdate: false, expenseDelete: true, settlement: false, memberJoin: true,
      },
    }));
    await assertFails(set({ 'notificationPrefs.activityEvents.expenseRename': true }));
    await assertFails(set({ 'notificationPrefs.activityEvents.settlement': 'off' }));
    await assertFails(set({ 'notificationPrefs.activityEvents': true }));
  });

  test('only involving me is a bool and the bundle one of four', async () => {
    await assertSucceeds(set({ 'notificationPrefs.onlyInvolvingMe': true }));
    for (const bundle of ['10m', '30m', '1h', 'daily']) {
      await assertSucceeds(set({ 'notificationPrefs.bundle': bundle }));
    }
    await assertFails(set({ 'notificationPrefs.onlyInvolvingMe': 'yes' }));
    await assertFails(set({ 'notificationPrefs.bundle': '5m' }));
    await assertFails(set({ 'notificationPrefs.bundle': 10 }));
  });

  test('a group is all, involving or off, optionally until a time', async () => {
    await assertSucceeds(set({ 'notificationPrefs.groups.g1': { mode: 'involving' } }));
    await assertSucceeds(set({ 'notificationPrefs.groups.g2': { mode: 'off' } }));
    await assertSucceeds(set({ 'notificationPrefs.groups.g3': { mode: 'off', offUntil: inHours(20) } }));
    await assertSucceeds(set({ 'notificationPrefs.groups.g1': { mode: 'all' } }));
    // Back to All activity removes the entry.
    await assertSucceeds(set({ 'notificationPrefs.groups.g1': deleteField() }));

    await assertFails(set({ 'notificationPrefs.groups.g4': { mode: 'mute' } }));
    await assertFails(set({ 'notificationPrefs.groups.g4': { mode: 'off', offUntil: '08:00' } }));
    await assertFails(set({ 'notificationPrefs.groups.g4': { mode: 'off', offUntil: inHours(24 * 3) } }));
    await assertFails(set({ 'notificationPrefs.groups.g4': { mode: 'off', extra: true } }));
    await assertFails(set({ 'notificationPrefs.groups.g4': { offUntil: inHours(1) } }));
    await assertFails(set({ 'notificationPrefs.groups.g4': 'off' }));
    await assertFails(set({ 'notificationPrefs.groups': ['g1'] }));
    // Changing an existing group to a bad value fails too.
    await assertFails(set({ 'notificationPrefs.groups.g2': { mode: 'loud' } }));
    // Two different new values in one write can't be checked, so they fail.
    await assertFails(set({
      'notificationPrefs.groups.g5': { mode: 'all' },
      'notificationPrefs.groups.g6': { mode: 'involving' },
    }));
  });

  test('legacy mutedGroups move to groups as off in one write', async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      await updateDoc(doc(admin.firestore(), 'users/alice'), {
        'notificationPrefs.mutedGroups': ['g1', 'g2', 'g3'],
        'notificationPrefs.groups': { g9: { mode: 'involving' } },
      });
    });
    await assertSucceeds(set({
      'notificationPrefs.groups.g1': { mode: 'off' },
      'notificationPrefs.groups.g2': { mode: 'off' },
      'notificationPrefs.groups.g3': { mode: 'off' },
      'notificationPrefs.mutedGroups': deleteField(),
    }));
    // Documents that still have the old list stay writable.
    await env.withSecurityRulesDisabled(async (admin) => {
      await updateDoc(doc(admin.firestore(), 'users/alice'), { 'notificationPrefs.mutedGroups': ['g7'] });
    });
    await assertSucceeds(set({ 'notificationPrefs.bundle': '1h' }));
  });

  test('at most 200 groups', async () => {
    const groups = Object.fromEntries(Array.from({ length: 200 }, (_, i) => [`g${i}`, { mode: 'off' }]));
    await assertSucceeds(set({ 'notificationPrefs.groups': groups }));
    await assertFails(set({ 'notificationPrefs.groups.one-more': { mode: 'off' } }));
    await assertSucceeds(set({ 'notificationPrefs.groups.g0': { mode: 'involving' } }));
  });

  test('a pause ends at a time at most a week (and a day) away; resume deletes it', async () => {
    await assertSucceeds(set({ 'notificationPrefs.pausedUntil': inHours(1) }));
    await assertSucceeds(set({ 'notificationPrefs.pausedUntil': inHours(24 * 7) }));
    await assertSucceeds(set({ 'notificationPrefs.pausedUntil': deleteField() }));
    await assertFails(set({ 'notificationPrefs.pausedUntil': inHours(24 * 9) }));
    await assertFails(set({ 'notificationPrefs.pausedUntil': '2026-12-01' }));
    await assertFails(set({ 'notificationPrefs.pausedUntil': Date.now() }));
  });

  test('quiet hours can only be longer than 21:00–08:00', async () => {
    await assertSucceeds(set({ 'notificationPrefs.quietHours': { from: '21:00', to: '08:00' } }));
    await assertSucceeds(set({ 'notificationPrefs.quietHours': { from: '19:00', to: '10:00' } }));
    await assertSucceeds(set({ 'notificationPrefs.quietHours': { from: '12:00', to: '12:00' } }));
    await assertSucceeds(set({ 'notificationPrefs.quietHours': { from: '20:30', to: '09:45' } }));
    await assertSucceeds(set({ 'notificationPrefs.quietHours': deleteField() }));

    await assertFails(set({ 'notificationPrefs.quietHours': { from: '22:00', to: '08:00' } }));
    await assertFails(set({ 'notificationPrefs.quietHours': { from: '21:30', to: '08:00' } }));
    await assertFails(set({ 'notificationPrefs.quietHours': { from: '21:00', to: '07:00' } }));
    await assertFails(set({ 'notificationPrefs.quietHours': { from: '11:59', to: '08:00' } }));
    await assertFails(set({ 'notificationPrefs.quietHours': { from: '21:00', to: '12:30' } }));
    await assertFails(set({ 'notificationPrefs.quietHours': { from: '9:00 pm', to: '08:00' } }));
    await assertFails(set({ 'notificationPrefs.quietHours': { from: '21:00' } }));
    await assertFails(set({ 'notificationPrefs.quietHours': { from: '21:00', to: '08:00', tz: 'UTC' } }));
    await assertFails(set({ 'notificationPrefs.quietHours': { from: 2100, to: 800 } }));
  });

  test('settle reminders: a day, a time 08:00–21:00 and 7, 14 or 30 days', async () => {
    await assertSucceeds(set({ 'notificationPrefs.settle': { day: 0, time: '19:00', minDays: 14 } }));
    await assertSucceeds(set({ 'notificationPrefs.settle': { day: 6, time: '08:00', minDays: 7 } }));
    await assertSucceeds(set({ 'notificationPrefs.settle': { day: 3, time: '21:00', minDays: 30 } }));
    await assertSucceeds(set({ 'notificationPrefs.settle': { day: 3, time: '20:30', minDays: 30 } }));

    await assertFails(set({ 'notificationPrefs.settle': { day: 7, time: '19:00', minDays: 14 } }));
    await assertFails(set({ 'notificationPrefs.settle': { day: -1, time: '19:00', minDays: 14 } }));
    await assertFails(set({ 'notificationPrefs.settle': { day: 1.5, time: '19:00', minDays: 14 } }));
    await assertFails(set({ 'notificationPrefs.settle': { day: 0, time: '07:59', minDays: 14 } }));
    await assertFails(set({ 'notificationPrefs.settle': { day: 0, time: '21:01', minDays: 14 } }));
    await assertFails(set({ 'notificationPrefs.settle': { day: 0, time: '19:00', minDays: 10 } }));
    await assertFails(set({ 'notificationPrefs.settle': { day: 0, time: '19:00' } }));
    await assertFails(set({ 'notificationPrefs.settle': { day: 0, time: '19:00', minDays: 14, extra: 1 } }));
  });

  test("nobody changes someone else's v2 choices", async () => {
    await assertFails(set({ 'notificationPrefs.bundle': 'daily' }, 'bob'));
    await assertFails(set({ 'notificationPrefs.groups.g1': { mode: 'off' } }, 'bob'));
  });
});

describe('push devices (R-9 AC23)', () => {
  const device = (extra = {}) => ({
    token: 'fcm-token',
    platform: 'android',
    locale: 'vi',
    tzName: 'Asia/Ho_Chi_Minh',
    tzOffsetMinutes: 420,
    appVersion: '2026.11.21+8',
    updatedAt: serverTimestamp(),
    ...extra,
  });

  test('only the account registers, reads and removes its devices', async () => {
    const fs = db('alice');
    await assertSucceeds(setDoc(doc(fs, 'users/alice/devices/d1'), device()));
    await assertSucceeds(setDoc(doc(fs, 'users/alice/devices/d1'), device({ locale: 'en', token: 'new' })));
    await assertSucceeds(getDoc(doc(fs, 'users/alice/devices/d1')));
    await assertSucceeds(getDocs(collection(fs, 'users/alice/devices')));

    const bob = db('bob');
    await assertFails(getDoc(doc(bob, 'users/alice/devices/d1')));
    await assertFails(getDocs(collection(bob, 'users/alice/devices')));
    await assertFails(setDoc(doc(bob, 'users/alice/devices/d2'), device()));
    await assertFails(deleteDoc(doc(bob, 'users/alice/devices/d1')));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'users/alice/devices/d1')));

    await assertSucceeds(deleteDoc(doc(fs, 'users/alice/devices/d1')));
  });

  test('a device has exactly the fields the sender reads, bounded', async () => {
    const fs = db('alice');
    const put = (data) => setDoc(doc(fs, 'users/alice/devices/d1'), data);
    await assertSucceeds(put(device({ platform: 'web', locale: 'en', tzName: 'Etc/UTC', tzOffsetMinutes: 0 })));
    await assertSucceeds(put(device({ tzOffsetMinutes: -720 })));
    await assertSucceeds(put(device({ tzOffsetMinutes: 840 })));
    await assertSucceeds(put(device({ token: 'x'.repeat(4096), tzName: 'x'.repeat(64), appVersion: 'x'.repeat(40) })));

    await assertFails(put(device({ extra: true })));
    const { token, ...withoutToken } = device();
    await assertFails(put(withoutToken));
    await assertFails(put(device({ token: '' })));
    await assertFails(put(device({ token: 'x'.repeat(4097) })));
    await assertFails(put(device({ platform: 'ios' })));
    await assertFails(put(device({ locale: 'fr' })));
    await assertFails(put(device({ tzName: '' })));
    await assertFails(put(device({ tzName: 'x'.repeat(65) })));
    await assertFails(put(device({ tzOffsetMinutes: 7.5 })));
    await assertFails(put(device({ tzOffsetMinutes: '420' })));
    await assertFails(put(device({ tzOffsetMinutes: -721 })));
    await assertFails(put(device({ tzOffsetMinutes: 841 })));
    await assertFails(put(device({ appVersion: 'x'.repeat(41) })));
    await assertFails(put(device({ updatedAt: 1 })));
    await assertFails(setDoc(doc(fs, `users/alice/devices/${'d'.repeat(65)}`), device()));
  });

  test('a test notification request stamps only testRequestedAt with the server time (AC33)', async () => {
    const fs = db('alice');
    const ref = doc(fs, 'users/alice/devices/d1');
    await assertSucceeds(setDoc(ref, device()));
    await assertSucceeds(updateDoc(ref, { testRequestedAt: serverTimestamp() }));
    await assertSucceeds(updateDoc(ref, { testRequestedAt: serverTimestamp() }));
    // Registering again replaces the document, without the stamp.
    await assertSucceeds(setDoc(ref, device({ locale: 'en' })));

    await assertFails(updateDoc(ref, { testRequestedAt: Timestamp.now() }));
    await assertFails(updateDoc(ref, { testRequestedAt: 1 }));
    await assertFails(updateDoc(ref, { testRequestedAt: serverTimestamp(), token: 'other' }));
    await assertFails(updateDoc(doc(db('bob'), 'users/alice/devices/d1'), { testRequestedAt: serverTimestamp() }));
    // Only on a registered device.
    await assertFails(setDoc(doc(fs, 'users/alice/devices/d2'), { testRequestedAt: serverTimestamp() }));
    await assertSucceeds(setDoc(doc(fs, 'users/alice/devices/d3'), device({ testRequestedAt: serverTimestamp() })));
    await assertFails(setDoc(doc(fs, 'users/alice/devices/d4'), device({ testRequestedAt: 1 })));
    await assertFails(setDoc(doc(fs, 'users/alice/devices/d5'), device({ testRequestedAt: Timestamp.fromMillis(Date.now() - 60000) })));
  });

  test('the account deletes its devices before its profile', async () => {
    const fs = db('alice');
    await setDoc(doc(fs, 'users/alice/devices/d1'), device());
    await setDoc(doc(fs, 'users/alice/devices/d2'), device({ platform: 'web' }));
    const batch = writeBatch(fs);
    for (const d of (await getDocs(collection(fs, 'users/alice/devices'))).docs) batch.delete(d.ref);
    await assertSucceeds(batch.commit());
    await assertSucceeds(deleteDoc(doc(fs, 'users/alice')));
  });
});

describe('in-app banners (R-9 AC12)', () => {
  const banner = { en: { title: 'New version', body: 'Fixes sync.' }, vi: { title: 'Bản mới', body: 'Sửa đồng bộ.' } };
  const future = new Date(Date.now() + 86_400_000);

  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (admin) => {
      const fs = admin.firestore();
      await setDoc(doc(fs, 'announcements/everyone'), { banner, all: true, audienceUids: [], endsAt: future });
      await setDoc(doc(fs, 'announcements/for-alice'), { banner, all: false, audienceUids: ['alice'], endsAt: future });
    });
  });

  test('an account reads banners for everyone or for itself, nothing else', async () => {
    const alice = db('alice');
    const bob = db('bob');
    await assertSucceeds(getDoc(doc(alice, 'announcements/everyone')));
    await assertSucceeds(getDoc(doc(alice, 'announcements/for-alice')));
    await assertSucceeds(getDoc(doc(bob, 'announcements/everyone')));
    await assertFails(getDoc(doc(bob, 'announcements/for-alice')));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'announcements/everyone')));
  });

  test('the two queries the app runs are allowed, a plain list is not', async () => {
    const alice = collection(db('alice'), 'announcements');
    const mine = await assertSucceeds(getDocs(query(alice, where('audienceUids', 'array-contains', 'alice'), where('endsAt', '>', new Date()))));
    assert.deepEqual(mine.docs.map((d) => d.id), ['for-alice']);
    const all = await assertSucceeds(getDocs(query(alice, where('all', '==', true), where('endsAt', '>', new Date()))));
    assert.deepEqual(all.docs.map((d) => d.id), ['everyone']);
    await assertFails(getDocs(alice));
    await assertFails(getDocs(query(alice, where('audienceUids', 'array-contains', 'bob'))));
  });

  test('clients never write banners', async () => {
    const fs = db('alice');
    await assertFails(setDoc(doc(fs, 'announcements/mine'), { banner, all: true, audienceUids: [], endsAt: future }));
    await assertFails(updateDoc(doc(fs, 'announcements/for-alice'), { endsAt: new Date(Date.now() + 2 * 86_400_000) }));
    await assertFails(deleteDoc(doc(fs, 'announcements/for-alice')));
  });

  test('an account keeps at most 100 dismissed banners, as a list', async () => {
    const fs = db('alice');
    const ids = (n) => Array.from({ length: n }, (_, i) => `c-${i}`);
    await assertSucceeds(updateDoc(doc(fs, 'users/alice'), { dismissedAnnouncements: arrayUnion('everyone') }));
    await assertSucceeds(updateDoc(doc(fs, 'users/alice'), { dismissedAnnouncements: ids(100) }));
    await assertFails(updateDoc(doc(fs, 'users/alice'), { dismissedAnnouncements: arrayUnion('one-more') }));
    await assertFails(updateDoc(doc(fs, 'users/alice'), { dismissedAnnouncements: 'everyone' }));
    await assertFails(updateDoc(doc(db('bob'), 'users/alice'), { dismissedAnnouncements: ['x'] }));
  });
});
