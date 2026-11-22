// Schemas for the files in crm/ (R-9). One schema per file kind; cross-file
// references and the calm limits are checked in check.ts.

import { z } from 'zod';

const id = z.string().regex(/^[a-z0-9][a-z0-9_-]{1,62}$/, 'lowercase letters, digits, - and _');
const clock = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'HH:MM');
const duration = z.string().regex(/^\d+m$/, 'minutes, like 10m');
const localized = z.object({ en: z.string().min(1), vi: z.string().min(1) }).strict();

export const LOCALES = ['en', 'vi'] as const;
export type Locale = (typeof LOCALES)[number];

export const policySchema = z
  .object({
    kill_switch: z.boolean(),
    quiet_hours: z.object({ from: clock, to: clock }).strict(),
    caps: z.object({ non_group_per_user_per_week: z.number().int().min(0) }).strict(),
  })
  .strict();

/** A kind of change within a category, with its own switch (R-9 AC26). */
export const categoryEventSchema = z
  .object({
    id,
    default: z.enum(['on', 'off']),
    name: localized,
  })
  .strict();

export const categorySchema = z
  .object({
    id,
    default: z.enum(['on', 'off']),
    per_group: z.boolean(),
    name: localized,
    description: localized,
    events: z.array(categoryEventSchema).min(1).optional(),
  })
  .strict();
export const categoriesSchema = z.array(categorySchema).min(1);

export const TRAIT_TYPES = ['choice', 'number', 'days_ago', 'bool', 'version'] as const;
export const traitSchema = z
  .object({
    name: id,
    type: z.enum(TRAIT_TYPES),
    column: z.string().regex(/^[a-z][a-z0-9_]*$/),
    label: z.string().min(1),
    values: z.array(z.string().min(1)).min(1).optional(),
  })
  .strict()
  .refine((t) => (t.type === 'choice') === (t.values !== undefined), {
    message: 'values is required for choice traits and only for them',
  });
export const traitsSchema = z.array(traitSchema);

export const ENTITIES = ['group', 'member', 'expense', 'settlement'] as const;
export const ACTIONS = ['create', 'update', 'delete', 'join'] as const;
/**
 * Kinds of group activity a user can switch on or off (R-9 AC26), as ids in
 * crm/categories.yaml. The pref key in `notificationPrefs.activityEvents` is
 * the camelCase id (`expense_create` → `expenseCreate`).
 */
export const ACTIVITY_EVENTS = ['expense_create', 'expense_update', 'expense_delete', 'settlement', 'member_join'] as const;
export type ActivityEvent = (typeof ACTIVITY_EVENTS)[number];

export const CHANNELS = ['push', 'inapp'] as const;

export const triggerSchema = z
  .object({
    id,
    enabled: z.boolean(),
    category: id,
    on: z
      .object({
        entities: z.array(z.enum(ENTITIES)).min(1),
        actions: z.array(z.enum(ACTIONS)).min(1),
      })
      .strict(),
    recipients: z.literal('group_members_except_actor'),
    batch_window: duration,
    template: id,
    channels: z.array(z.literal('push')).min(1),
    rollout: z.number().int().min(0).max(100),
  })
  .strict();

export const SCHEDULE_KINDS = ['settle_reminder'] as const;
export const scheduleSchema = z
  .object({
    id,
    enabled: z.boolean(),
    kind: z.enum(SCHEDULE_KINDS),
    category: id,
    cron: z.string().min(9),
    audience: id,
    template: id,
    channels: z.array(z.literal('push')).min(1),
  })
  .strict();

export const campaignSchema = z
  .object({
    id,
    enabled: z.boolean(),
    category: id,
    send_at: z.iso.datetime({ offset: true }),
    ends_at: z.iso.datetime({ offset: true }),
    audience: id,
    channels: z.array(z.enum(CHANNELS)).min(1),
    template: id,
  })
  .strict();

export const OPERATORS = ['eq', 'neq', 'in', 'gt', 'gte', 'lt', 'lte', 'between', 'is'] as const;
export type Operator = (typeof OPERATORS)[number];
const value = z.union([z.string(), z.number(), z.boolean(), z.array(z.union([z.string(), z.number()]))]);
export const ruleSchema = z.object({ trait: id, op: z.enum(OPERATORS), value }).strict();
export const groupSchema = z.object({ match: z.enum(['all', 'any']), rules: z.array(ruleSchema).min(1) }).strict();
export const audienceSchema = z
  .object({
    id,
    description: z.string().min(1),
    match: z.enum(['all', 'any']),
    rules: z.array(z.union([ruleSchema, groupSchema])),
  })
  .strict();

const pushCopy = z.object({ title: z.string().min(1), body: z.string().min(1) }).strict();
const byLocale = <T extends z.ZodType>(schema: T) => z.object({ en: schema, vi: schema }).strict();
export const templateSchema = z
  .object({
    id,
    vars: z.array(z.string().regex(/^[a-z][a-z_]*$/)),
    push: byLocale(pushCopy).optional(),
    push_batched: byLocale(pushCopy).optional(),
    banner: byLocale(pushCopy).optional(),
  })
  .strict()
  .refine((t) => t.push || t.banner, { message: 'a template needs push or banner copy' });

export type Policy = z.infer<typeof policySchema>;
export type Category = z.infer<typeof categorySchema>;
export type CategoryEvent = z.infer<typeof categoryEventSchema>;
export type Trait = z.infer<typeof traitSchema>;
export type Trigger = z.infer<typeof triggerSchema>;
export type Schedule = z.infer<typeof scheduleSchema>;
export type Campaign = z.infer<typeof campaignSchema>;
export type Rule = z.infer<typeof ruleSchema>;
export type RuleGroup = z.infer<typeof groupSchema>;
export type Audience = z.infer<typeof audienceSchema>;
export type Template = z.infer<typeof templateSchema>;

export interface Config {
  policy: Policy;
  categories: Category[];
  traits: Trait[];
  triggers: Trigger[];
  schedules: Schedule[];
  campaigns: Campaign[];
  audiences: Audience[];
  templates: Template[];
}
