// Second line of defence for R-4 AC4: the app scrubs error messages and stack
// traces before queueing them, and the endpoint scrubs them again so a missed
// value never reaches Cloud Logging or BigQuery.

const RULES: Array<[RegExp, string]> = [
  // Emails.
  [/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, '<email>'],
  // Firestore document paths: groups/<id>/expenses/<id>, invites/<token>, users/<uid>.
  [/\b(groups|members|expenses|settlements|activity|invites|users)\/[^\s/'")\]]+/g, '$1/<id>'],
  // UUIDs.
  [/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi, '<uuid>'],
  // Firebase uids, Firestore auto IDs and invite tokens: long mixed-case runs.
  [/\b(?=[A-Za-z0-9_-]*[A-Za-z])(?=[A-Za-z0-9_-]*\d)[A-Za-z0-9_-]{16,}\b/g, '<id>'],
  // Amounts and other numbers of 3+ digits, with separators. Line and column
  // numbers in stack traces (file.dart:123:45) follow a colon and are kept.
  [/(?<![:\d.,])\d{1,3}(?:[.,]\d{3})+(?![\d:])|(?<![:\d.,])\d{3,}(?![\d:])/g, '<n>'],
];

export function scrub(text: string): string {
  let out = text;
  for (const [pattern, replacement] of RULES) out = out.replace(pattern, replacement);
  return out;
}
