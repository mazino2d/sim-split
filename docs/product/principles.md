# Design principles

Ordered. When two principles conflict, the higher one wins. Every principle has a cost —
it is listed so the trade-off is visible when deciding.

## Guiding stance — product over profit

SimSplit is a product-first app. The goal is the best possible UI/UX for the core use cases,
not revenue. Every principle below serves that goal.

- Decisions are judged by how much they improve the user's experience, never by how much
  they could earn.
- Polish counts as real work: smoothing a flow, improving copy, motion, spacing or
  accessibility belongs on the roadmap next to features.
- Monetisation mechanics (paywalls, upsells, ads, artificial limits, engagement hooks) are
  rejected by default — they cost UX and serve no objective.
- **Cost:** no revenue to fund the app; effort goes into polish that is hard to measure, so
  the North Star quality bars are the check against polishing the wrong thing.

## 1. Calm and frictionless

The app never interrupts. No pop-ups, nag screens, rating prompts on launch, multi-step
onboarding, coach marks or notifications the user did not ask for.

- Prefer **empty states that teach** over tutorials: an empty group explains the next step
  in one line with one button.
- Confirm only destructive, irreversible actions; everything else is undoable or editable.
- Errors are short, specific, and say what to do next.
- **Cost:** new features are harder to discover; asking for a store rating must be passive
  (e.g. a row in Settings), which slows rating growth.

## 2. Fast capture

Logging an expense is the core loop and must take ≤ 10 s / ≤ 4 taps for an equal split.

- Smart defaults: payer = last payer in this group, split = equal among all members,
  currency = group currency, date = today.
- The amount field is focused with the numeric keyboard on open.
- Advanced options (percentage, exact, shares, partial participants) are reachable but
  never in the way of the default path.
- One-handed use: primary actions in the bottom half of the screen.
- **Cost:** advanced split types are one level deeper; power users pay a tap or two.

### Resolving the conflict

Calm wins over Fast capture. A hint that would speed up a new user is acceptable only if it
is inline, dismisses itself, and never blocks input — otherwise drop it and find a better
default instead.

## Always-on constraints (not traded off)

- **Offline core** — see [strategy](strategy.md#non-negotiable).
- **Trust in numbers** — see [strategy](strategy.md#baseline-guardrail--trust-in-numbers).
- **Bilingual** — every user-facing string exists in English and Vietnamese; Vietnamese
  copy is written natively, not translated word for word.
