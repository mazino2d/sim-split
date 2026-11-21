// Money as the app shows it: a port of lib/core/utils/money_formatter.dart
// (formatMoney), kept in step by test/money_vectors.json, which a Dart test
// checks against the app's formatter too (spec AC10).

const NO_DECIMALS = new Set(['VND', 'JPY', 'KRW', 'IDR', 'HUF', 'CLP', 'ISK']);

const SYMBOLS: Record<string, string> = {
  VND: '₫',
  USD: '$',
  EUR: '€',
  GBP: '£',
  JPY: '¥',
  KRW: '₩',
  THB: '฿',
  SGD: 'S$',
  AUD: 'A$',
  CAD: 'C$',
};

const truncDiv = (a: number, b: number) => Math.trunc(a / b);

const thousandsDots = (amount: number): string => {
  const s = Math.abs(amount).toString();
  const parts: string[] = [];
  const start = s.length % 3;
  if (start > 0) parts.push(s.slice(0, start));
  for (let i = start; i < s.length; i += 3) parts.push(s.slice(i, i + 3));
  const body = parts.join('.');
  return amount < 0 ? `-${body}` : body;
};

export const formatMoney = (amountCents: number, currencyCode: string): string => {
  const code = currencyCode.toUpperCase();
  const symbol = SYMBOLS[code] ?? currencyCode;
  if (!NO_DECIMALS.has(code)) {
    const whole = truncDiv(amountCents, 100);
    const frac = Math.abs(amountCents % 100);
    return `${thousandsDots(whole)},${frac.toString().padStart(2, '0')} ${symbol}`;
  }
  return `${thousandsDots(truncDiv(amountCents, 100))} ${symbol}`;
};
