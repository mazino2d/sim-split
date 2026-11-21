// Store on Firestore (firebase-admin). Server-only collections (crm_*) are
// out of reach for clients: no rule in firebase/firestore.rules matches them.

import { FieldValue, Timestamp, type Firestore } from 'firebase-admin/firestore';
import type { Deferred, Device, GroupDoc, PendingItem, Prefs, Store } from '../ports.ts';

const STALE_BATCH_MS = 5 * 60_000;
const ALREADY_EXISTS = 6;

export const createFirestoreStore = (db: Firestore, defaults: Omit<Prefs, 'mutedGroups'>): Store => {
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

    async getMemberNames(groupId) {
      const snap = await db.collection(`groups/${groupId}/members`).get();
      const names = new Map<string, string>();
      for (const doc of snap.docs) {
        const d = doc.data();
        if (d.deleted !== true && typeof d.linkedUid === 'string' && typeof d.name === 'string') {
          names.set(d.linkedUid, d.name);
        }
      }
      return names;
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
      const p = (snap.data()?.notificationPrefs ?? {}) as Partial<Prefs>;
      const bool = (v: unknown, fallback: boolean) => (typeof v === 'boolean' ? v : fallback);
      return {
        groupActivity: bool(p.groupActivity, defaults.groupActivity),
        settleReminder: bool(p.settleReminder, defaults.settleReminder),
        updates: bool(p.updates, defaults.updates),
        mutedGroups: Array.isArray(p.mutedGroups) ? p.mutedGroups.filter((g) => typeof g === 'string') : [],
      };
    },

    async getDevices(uid) {
      const snap = await db.collection(`users/${uid}/devices`).get();
      return snap.docs.flatMap((doc): Device[] => {
        const d = doc.data();
        if (typeof d.token !== 'string' || (d.platform !== 'android' && d.platform !== 'web')) return [];
        return [
          {
            id: doc.id,
            token: d.token,
            platform: d.platform,
            locale: d.locale === 'vi' ? 'vi' : 'en',
            tzName: typeof d.tzName === 'string' ? d.tzName : undefined,
            tzOffsetMinutes: typeof d.tzOffsetMinutes === 'number' ? d.tzOffsetMinutes : 420,
          },
        ];
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
        const merged = [...items, ...entry.items.filter((i) => !items.some((x) => x.id === i.id))];
        tx.set(ref, {
          uid: entry.uid,
          deviceId: entry.deviceId,
          groupId: entry.groupId,
          triggerId: entry.triggerId,
          // The first held-back message names the delivery, so a retry stays one send.
          messageId: snap.exists ? snap.data()!.messageId : entry.messageId,
          deliverAfter: Timestamp.fromDate(entry.deliverAfter),
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
  };
};
