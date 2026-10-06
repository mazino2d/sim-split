# Docs style

The house style, taken from what the repo already does. Match it so every page reads
as if one person wrote it.

## Language

- **English** everywhere except `android/fastlane/metadata/android/vi/` and the VI ARB
  file. Converse with the user in their language.
- Plain words, short sentences, active voice. Say what the app or code *does*, not
  what it "aims to" or "is designed to" do.
- Name things the way the UI and code do: "group", "expense", "settlement",
  "activity history", "invite link". Don't invent synonyms ("ledger", "event").
- No marketing adjectives in technical docs ("powerful", "seamless", "robust").
  The landing page and store text may sell, but every claim must be true today.
- Dates are absolute (`2026-10-07`), never "last week" or "recently".
- Money in examples is integer cents in code and a formatted amount in prose.

## Markdown

- One `#` title per file, then `##` sections. Sentence case headings
  ("Before you open a pull request"), no trailing punctuation.
- Wrap prose at about 88 characters. Don't reflow paragraphs you didn't change —
  it bloats the diff.
- Tables use `| --- |` separators and a header row. Use a table when there are two or
  more attributes per item; a list otherwise.
- **Bold** a lead-in label in lists (`- **Bugs:** …`); don't bold random phrases.
- Code, paths, commands, identifiers and config keys in backticks. Commands that a
  reader runs go in a fenced block with a language (`bash`, `yaml`, `text`).
- Links are relative inside the repo (`[AGENTS.md](AGENTS.md)`); absolute only for
  GitHub UI pages (issues, advisories, community) and external sites.
- Link to a section with its GitHub anchor (`strategy.md#non-negotiable`); the
  checker verifies anchors exist, so renaming a heading means fixing its links.
- No emoji, except the PR attribution line.

## Structure by doc type

| Doc | Shape |
| --- | --- |
| `README.md` | What it is → where to use it → features → tech stack → getting started → architecture → CI/CD → releasing → privacy → contributing → license |
| `AGENTS.md` | Short: purpose, language policy, critical rules, commands, skills table. Detail belongs in skills. |
| `SKILL.md` | YAML front matter (`name`, `description` with trigger phrases incl. Vietnamese, optional `argument-hint`, `allowed-tools`) → one-paragraph role → sources of truth → workflow → output. Under ~150 lines; move detail to `references/`. |
| Spec (`docs/product/specs/`) | Owned by `product-owner`. |
| Plan (`docs/implementations/`) | `Status · Spec link · date` header → decisions (with why) → architecture → phases table → manual steps → risks. |
| `docs/*.html` | Hand-written HTML; tokens mirror `app_theme.dart`; no third-party requests. |
| Store text | `title` ≤ 30, `short_description` ≤ 80, `full_description` ≤ 4000 chars. EN and VI say the same thing. |

## Comments in code and config

Comments say *why*, in full sentences, at the density of the surrounding file.
A doc fix that renames a concept also fixes the comments that use the old name.
