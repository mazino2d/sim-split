// Message templates: ICU MessageFormat strings (the same syntax as the app's ARB
// files), one per locale. Each source kind offers a fixed set of variables.

import { IntlMessageFormat } from 'intl-messageformat';
import { parse, TYPE, type MessageFormatElement } from '@formatjs/icu-messageformat-parser';
import type { Locale, Template } from './config/schema.ts';

export type SourceKind = 'trigger' | 'settle_reminder' | 'campaign' | 'system';

/** Variables each source kind fills in, with the sample values `crm render` uses. */
export const SOURCE_VARS: Record<SourceKind, Record<string, Record<Locale, string | number>>> = {
  trigger: {
    actor: { en: 'Tuấn', vi: 'Tuấn' },
    group: { en: 'Đà Lạt trip', vi: 'Đi Đà Lạt' },
    title: { en: 'Dinner', vi: 'Ăn tối' },
    amount: { en: '500.000 ₫', vi: '500.000 ₫' },
    count: { en: 3, vi: 3 },
    entity: { en: 'expense', vi: 'expense' },
    action: { en: 'create', vi: 'create' },
  },
  settle_reminder: {
    total: { en: '350.000 ₫', vi: '350.000 ₫' },
    people: { en: 2, vi: 2 },
    group: { en: 'Đà Lạt trip', vi: 'Đi Đà Lạt' },
  },
  campaign: {},
  system: {},
};

/** Names of the arguments a message uses, including those inside select/plural branches. */
export const argumentsOf = (message: string): Set<string> => {
  const names = new Set<string>();
  const walk = (elements: MessageFormatElement[]) => {
    for (const el of elements) {
      if (el.type === TYPE.literal || el.type === TYPE.pound) continue;
      if (el.type === TYPE.tag) {
        walk(el.children);
        continue;
      }
      names.add(el.value);
      if (el.type === TYPE.select || el.type === TYPE.plural) {
        for (const option of Object.values(el.options)) walk(option.value);
      }
    }
  };
  walk(parse(message));
  return names;
};

export type Copy = { title: string; body: string };

export const formatMessage = (
  message: string,
  locale: Locale,
  values: Record<string, string | number>,
): string => String(new IntlMessageFormat(message, locale).format(values));

export const renderCopy = (copy: Copy, locale: Locale, values: Record<string, string | number>): Copy => ({
  title: formatMessage(copy.title, locale, values),
  body: formatMessage(copy.body, locale, values),
});

export const sampleValues = (kind: SourceKind, locale: Locale): Record<string, string | number> =>
  Object.fromEntries(Object.entries(SOURCE_VARS[kind]).map(([name, byLocale]) => [name, byLocale[locale]]));

/** Every (variant, locale, copy) of a template, for checks and previews. */
export const variantsOf = (template: Template) =>
  (['push', 'push_batched', 'banner'] as const).flatMap((variant) => {
    const copies = template[variant];
    if (!copies) return [];
    return (['en', 'vi'] as const).map((locale) => ({ variant, locale, copy: copies[locale] }));
  });
