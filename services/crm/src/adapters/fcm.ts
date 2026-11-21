// Pusher on Firebase Cloud Messaging (HTTP v1 through firebase-admin).

import type { Messaging } from 'firebase-admin/messaging';
import type { Pusher } from '../ports.ts';

const INVALID_TOKEN = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

/** webOrigin: the web app of this environment, for the notification click link. */
export const createFcmPusher = (messaging: Messaging, webOrigin: string): Pusher => ({
  async send(device, push) {
    try {
      await messaging.send({
        token: device.token,
        notification: { title: push.title, body: push.body },
        data: { messageId: push.messageId, category: push.category, route: push.route, source: push.source },
        android: {
          priority: 'normal',
          collapseKey: push.tag,
          notification: { channelId: push.category, tag: push.tag },
        },
        webpush: {
          notification: { tag: push.tag },
          fcmOptions: { link: `${webOrigin}${push.route}` },
        },
      });
      return 'sent';
    } catch (e) {
      const code = (e as { code?: string }).code ?? '';
      return INVALID_TOKEN.has(code) ? 'invalid_token' : 'failed';
    }
  },
});
