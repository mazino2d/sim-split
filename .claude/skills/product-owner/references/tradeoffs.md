# Product trade-offs — teaching reference

Use these to explain *why* a question matters. Quote the one-line idea, then apply it to
the case at hand. Don't lecture the whole file.

## Core PO concepts

| Concept | One-line idea | Question it prompts |
| --- | --- | --- |
| Jobs to be done | People "hire" a product to make progress in a specific moment. | What moment is the user in, and what does "done" feel like? |
| Opportunity cost | Every yes is a no to everything else you could build with that time. | What gets delayed if we do this? |
| MVP slicing | Ship the thinnest version that tests the riskiest assumption. | What's the smallest thing that proves people want this? |
| One-way vs two-way doors | Reversible decisions should be fast; irreversible ones slow and careful. | Can we undo this cheaply (schema, data format, store promise)? |
| Kano model | Must-be features cause anger when missing but no delight when present; delighters are the reverse. | Is this a must-be users will punish us for lacking, or a delighter? |
| Scope creep | Each small addition is reasonable; their sum dilutes the product. | Would we still add this if it were the 10th such request? |
| Feature debt | Every feature costs maintenance, testing, l10n and UI space forever. | Who maintains this in a year and what does it cost? |
| North Star | One measure that captures delivered value aligns all decisions. | Which bar does this move, and by how much? |
| Vanity metric | A number that goes up without value going up. | Would this metric rise even if users were worse off? |
| Confidence | Unvalidated ideas are guesses; score them as guesses. | What evidence do we have — a tester request, our own use, or a hunch? |

## RICE-lite in practice

- **Impact** is relative to the North Star bars and core UC criteria, not to how cool the
  feature is. A 3 should be rare.
- **Confidence 0.5** is honest for most ideas from one person's head. Raise it with
  evidence: tester feedback, a timed run, a competitor review complaint.
- **Effort** includes tests, both ARB files, store screenshots and docs — not just code.
- Scores rank; they don't decide. If the ranking feels wrong, find which factor you
  mis-estimated rather than overriding silently.

## Recurring SimSplit trade-offs

### Multi-device / shared groups vs offline core and no account

- **Options:** (a) export/import a group file, (b) QR code / share-link carrying the data,
  (c) local P2P (Nearby, Bluetooth), (d) cloud sync with account.
- **Trade-off:** (a)–(c) keep offline and no-account but merge conflicts are hard and UX is
  clunky; (d) is smooth but breaks the non-negotiable for any flow that depends on it and
  the "no account" default. For the trip persona, one bookkeeper + shared summary (UC-5)
  usually covers the need at a fraction of the cost.
- **Decided 2026-10-03:** option (d) chosen — mandatory Google/Apple sign-in, Firebase
  sync, invite links; Drift stays local source of truth with an outbox so the app works
  offline after first sign-in (R-3). Revisit only if the free
  tier or sign-in friction proves wrong in testing.

### Analytics vs privacy

- **Options:** none (current), Play Console only, self-hosted privacy-preserving
  counters, third-party SDK.
- **Trade-off:** more data → better prioritisation, but each step up weakens the
  no-tracking default, adds a Data safety declaration, and may need consent UI (hurts
  Calm). For a craft objective, timed dogfooding + tester interviews are usually enough.
- **Decided 2026-10-08:** anonymous error reports (errors + breadcrumbs, no account, names
  or amounts) to the app's own Firestore, on by default with an off switch, 30-day
  retention (R-4). Usage analytics and third-party SDKs stay out. Revisit if reports ever
  need to identify a user — that requires opt-in.

### Smart defaults vs predictability

- A default that guesses (last payer, all members) saves taps (Fast capture) but a wrong
  guess silently records a wrong debt (money guardrail). Show the default clearly on the
  form so it's checked at a glance.

### Advanced split types vs fast capture

- Percentage / exact / shares serve real cases (someone didn't drink), but every option on
  the main form costs the default path. Keep the default path untouched; put advanced
  options one tap away.

### Asking for ratings vs calm

- In-app review prompts raise rating volume but interrupt. Calm wins: passive "Rate the
  app" in Settings, or the system review API triggered only after a clear success moment
  (e.g. a group fully settled), never on launch.

### Multi-currency trips

- Per-expense currency with conversion helps trips abroad, but exchange rates need the
  network (optional add-on only) and conversion rounding threatens exact totals. A
  manual rate entered by the user keeps offline and auditability.

### Recurring expenses

- High value for housemates (secondary persona), near zero for trips. Listed as a non-goal;
  revisit only if strategy's persona changes.

### Polish vs new features

- Product-over-profit makes polish first-class, but polish has no natural end. Tie each
  polish item to a core UC criterion or a North Star bar (fewer taps, clearer balance,
  fewer support-style questions from testers) so it is scored like any feature.

### Store promises

- The store listing is a promise. A claim the app doesn't fulfil risks bad reviews and
  Play policy issues; either ship the feature or edit the listing in the same release.
