// Store on Firestore (firebase-admin). Server-only collections (crm_*) are
// out of reach for clients: no rule in firebase/firestore.rules matches them.

import { FieldValue, Timestamp, type DocumentData, type Firestore } from 'firebase-admin/firestore';
import { parsePrefs, type PrefDefaults } from '../prefs.ts';
import type { BroadcastStore, Debt, Deferred, Device, GroupDoc, Member, PendingItem, Store } from '../ports.ts';

const STALE_BATCH_MS = 5 * 60_000;
const ALREADY_EXISTS = 6;

const DAY_MS = 24 * 60 * 60_000;
const WEEK_MS = 7 * DAY_MS;

const toDevice = (id: string, d: DocumentData): Device | undefined => {
  if (typeof d.token !== 'string' || (d.platform !== 'android' && d.platform !== 'web')) return undefined;
  return {
    id,
    token: d.token,
    platform: d.platform,
    locale: d.locale === 'vi' ? 'vi' : 'en',
    tzName: typeof d.tzName === 'string' ? d.tzName : undefined,
    tzOffsetMinutes: typeof d.tzOffsetMinutes === 'number' ? d.tzOffsetMinutes : 420,
    testRequestedAt: d.testRequestedAt instanceof Timestamp ? d.testRequestedAt.toDate() : undefined,
  };
};

/** Epoch milliseconds (as the app writes them) or a Timestamp. */
const millis = (v: unknown): number | undefined =>
  typeof v === 'number' ? v : v instanceof Timestamp ? v.toMillis() : undefined;

export const createFirestoreStore = (db: Firestore, defaults: PrefDefaults): Store & BroadcastStore => {
  const pendingRef = (groupId: string, triggerId: string) => db.doc(`crm_pending/${groupId}_${triggerId}`);
  return {
    async getActivity(groupId, entryId) {
      const snap = await db.doc(`groups/${groupId}/activity/${entryId}`).get();
      return snap.exists ? snap.data() : undefined;
    },

    async getGroup(groupId) {
      const snap = await db.doc(`groups/${groupId}`).get();
      if (!snap.exists) return undefined;
      const d = snap.data()!;
      const group: GroupDoc = {
        name: typeof d.name === 'string' ? d.name : '',
        memberUids: Array.isArray(d.memberUids) ? d.memberUids.filter((u) => typeof u === 'string') : [],
        isArchived: d.isArchived === true,
        deleted: d.deleted === true,
      };
      return group;
    },

    async getMembers(groupId) {
      const snap = await db.collection(`groups/${groupId}/members`).get();
      const members = new Map<string, Member>();
      for (const doc of snap.docs) {
        const d = doc.data();
        if (d.deleted !== true && typeof d.linkedUid === 'string') {
          members.set(d.linkedUid, { memberId: doc.id, name: typeof d.name === 'string' ? d.name : '' });
        }
      }
      return members;
    },

    addPending(groupId, triggerId, item, windowEnd) {
      const ref = pendingRef(groupId, triggerId);
      return db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const current = snap.exists ? snap.data()! : undefined;
        const end = current?.windowEnd instanceof Timestamp ? current.windowEnd.toDate() : undefined;
        if (current && end && end.getTime() > Date.now() - STALE_BATCH_MS) {
          const items = current.items as PendingItem[];
          // Eventarc may deliver an event twice: the entry id dedupes it.
          if (!items.some((i) => i.id === item.id)) tx.update(ref, { items: FieldValue.arrayUnion(item) });
          return { windowEnd: end, opened: false };
        }
        tx.set(ref, { windowEnd: Timestamp.fromDate(windowEnd), items: [item] });
        return { windowEnd, opened: true };
      });
    },

    takePending(groupId, triggerId, windowEnd) {
      const ref = pendingRef(groupId, triggerId);
      return db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) return undefined;
        const d = snap.data()!;
        if (!(d.windowEnd instanceof Timestamp) || d.windowEnd.toMillis() !== windowEnd.getTime()) return undefined;
        tx.delete(ref);
        return d.items as PendingItem[];
      });
    },

    async getPrefs(uid) {
      const snap = await db.doc(`users/${uid}`).get();
      return parsePrefs(snap.data()?.notificationPrefs, defaults);
    },

    async getDevices(uid) {
      const snap = await db.collection(`users/${uid}/devices`).get();
      return snap.docs.flatMap((doc) => toDevice(doc.id, doc.data()) ?? []);
    },

    async getDevice(uid, deviceId) {
      const snap = await db.doc(`users/${uid}/devices/${deviceId}`).get();
      return snap.exists ? toDevice(snap.id, snap.data()!) : undefined;
    },

    claimTest(uid, deviceId, now, minGapMs) {
      // crm_ledger/{uid}.tests.<deviceId>: when each device last got a test push.
      const ref = db.doc(`crm_ledger/${uid}`);
      return db.runTransaction(async (tx) => {
        const last = (await tx.get(ref)).data()?.tests?.[deviceId];
        if (last instanceof Timestamp && now.getTime() - last.toMillis() < minGapMs) return false;
        tx.set(ref, { tests: { [deviceId]: Timestamp.fromDate(now) } }, { merge: true });
        return true;
      });
    },

    async deleteDevice(uid, deviceId) {
      await db.doc(`users/${uid}/devices/${deviceId}`).delete();
    },

    async claimSend(messageId, uid, deviceId) {
      try {
        await db.doc(`crm_sends/${messageId}/devices/${uid}_${deviceId}`).create({ at: FieldValue.serverTimestamp() });
        return true;
      } catch (e) {
        if ((e as { code?: number }).code === ALREADY_EXISTS) return false;
        throw e;
      }
    },

    defer(entry) {
      const ref = db.doc(`crm_deferred/${entry.key}`);
      return db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const items = snap.exists ? (snap.data()!.items as PendingItem[]) : [];
        const held = snap.exists && snap.data()!.deliverAfter instanceof Timestamp ? (snap.data()!.deliverAfter as Timestamp).toDate() : undefined;
        const merged = [...items, ...entry.items.filter((i) => !items.some((x) => x.id === i.id))];
        tx.set(ref, {
          uid: entry.uid,
          deviceId: entry.deviceId,
          groupId: entry.groupId,
          triggerId: entry.triggerId,
          // The first held-back message names the delivery, so a retry stays one send.
          messageId: snap.exists ? snap.data()!.messageId : entry.messageId,
          // The earlier time wins; the tick holds it again if it is still too early.
          deliverAfter: Timestamp.fromDate(held && held < entry.deliverAfter ? held : entry.deliverAfter),
          items: merged,
        });
      });
    },

    async dueDeferred(now) {
      const snap = await db.collection('crm_deferred').where('deliverAfter', '<=', Timestamp.fromDate(now)).limit(500).get();
      return snap.docs.map((doc): Deferred => {
        const d = doc.data();
        return {
          key: doc.id,
          uid: d.uid,
          deviceId: d.deviceId,
          groupId: d.groupId,
          triggerId: d.triggerId,
          messageId: d.messageId,
          deliverAfter: (d.deliverAfter as Timestamp).toDate(),
          items: d.items,
        };
      });
    },

    async deleteDeferred(key) {
      await db.doc(`crm_deferred/${key}`).delete();
    },

    takeWeeklySlot(uid, messageId, now) {
      const ref = db.doc(`crm_ledger/${uid}`);
      return db.runTransaction(async (tx) => {
        const d = (await tx.get(ref)).data();
        const last = d?.lastNonGroupAt instanceof Timestamp ? d.lastNonGroupAt.toMillis() : 0;
        if (d?.lastMessageId === messageId) return true;
        if (now.getTime() - last < WEEK_MS) return false;
        tx.set(ref, { lastNonGroupAt: Timestamp.fromDate(now), lastMessageId: messageId }, { merge: true });
        return true;
      });
    },

    async debtsOf(uid, now) {
      const groups = await db.collection('groups').where('memberUids', 'array-contains', uid).get();
      const debts: Debt[] = [];
      for (const g of groups.docs) {
        const gd = g.data();
        if (gd.isArchived === true || gd.deleted === true) continue;
        const [members, expenses, settlements] = await Promise.all(
          ['members', 'expenses', 'settlements'].map((c) => db.collection(`groups/${g.id}/${c}`).get()),
        );
        const net = new Map<string, number>();
        let oldest = Infinity;
        const add = (memberId: unknown, cents: unknown) => {
          if (typeof memberId === 'string' && typeof cents === 'number') net.set(memberId, (net.get(memberId) ?? 0) + cents);
        };
        for (const e of expenses.docs.map((x) => x.data())) {
          if (e.deleted === true) continue;
          oldest = Math.min(oldest, millis(e.createdAt) ?? Infinity);
          add(e.paidByMemberId, e.amountCents);
          for (const split of (e.splits ?? []) as { memberId?: unknown; amountCents?: unknown }[]) {
            add(split.memberId, -(Number(split.amountCents) || 0));
          }
        }
        for (const st of settlements.docs.map((x) => x.data())) {
          if (st.deleted === true) continue;
          add(st.fromMemberId, st.amountCents);
          add(st.toMemberId, -(Number(st.amountCents) || 0));
        }
        const mine = members.docs.find((m) => m.data().linkedUid === uid && m.data().deleted !== true);
        const balance = mine ? (net.get(mine.id) ?? 0) : 0;
        if (balance <= -1) {
          debts.push({
            groupId: g.id,
            groupName: typeof gd.name === 'string' ? gd.name : '',
            owesCents: -balance,
            currencyCode: typeof gd.currencyCode === 'string' ? gd.currencyCode : 'VND',
            creditors: [...net.values()].filter((v) => v >= 1).length,
            oldestDays: Number.isFinite(oldest) ? Math.max(0, Math.floor((now.getTime() - oldest) / DAY_MS)) : 0,
          });
        }
      }
      return debts;
    },

    async writeAnnouncement(a) {
      await db.doc(`announcements/${a.id}`).set({
        banner: a.banner,
        all: a.audienceUids === undefined,
        audienceUids: a.audienceUids ?? [],
        endsAt: Timestamp.fromDate(a.endsAt),
      });
    },
  };
};
