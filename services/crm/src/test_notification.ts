// Test notification (R-9 P8, spec AC33): the app sets `testRequestedAt` on its
// device document; Eventarc (crm-devices) reports the write and this sends one
// push to that device. It skips quiet hours, the weekly cap and the user's
// choices, but a device gets at most one every 10 minutes. Nothing here logs a
// uid or a document path.

import { renderCopy } from './templates.ts';
import type { ActivityDeps } from './activity.ts';

export const TEST_TEMPLATE = 'test-notification';
/** Shown on Android in the channel every user has on by default. */
const TEST_CATEGORY = 'group_activity';
const FRESH_MS = 60_000;
const MIN_GAP_MS = 10 * 60_000;

export const DEVICE_PATH = /^users\/([A-Za-z0-9_-]{1,128})\/devices\/([A-Za-z0-9_-]{1,128})$/;

export const onDeviceWrite = async (deps: ActivityDeps, uid: string, deviceId: string): Promise<void> => {
  const ignore = (reason: string) => deps.log({ severity: 'INFO', kind: 'test_ignored', reason });
  const now = deps.now();
  const device = await deps.store.getDevice(uid, deviceId);
  const requested = device?.testRequestedAt;
  // Most device writes are registrations, not test requests.
  if (!device || !requested) return;
  const age = now.getTime() - requested.getTime();
  if (age > FRESH_MS || age < -FRESH_MS) return ignore('stale');
  const template = deps.config.templates.find((t) => t.id === TEST_TEMPLATE);
  if (!template?.push) return ignore('template');
  if (!(await deps.store.claimTest(uid, deviceId, now, MIN_GAP_MS))) return ignore('too_soon');
  const messageId = `test-${requested.getTime()}`;
  if (!(await deps.store.claimSend(messageId, uid, deviceId))) return;
  const copy = renderCopy(template.push[device.locale], device.locale, {});
  const result = await deps.pusher.send(device, {
    messageId,
    category: TEST_CATEGORY,
    source: `system:${TEST_TEMPLATE}`,
    route: '/',
    ...copy,
    tag: TEST_TEMPLATE,
  });
  deps.sends.record({
    sent_at: now.toISOString(),
    message_id: messageId,
    source: 'system',
    source_id: TEST_TEMPLATE,
    category: TEST_CATEGORY,
    uid,
    platform: device.platform,
    locale: device.locale,
    result,
  });
  if (result === 'invalid_token') await deps.store.deleteDevice(uid, deviceId);
  deps.log({ severity: result === 'sent' ? 'INFO' : 'WARNING', kind: 'test_notification', result, platform: device.platform });
};
