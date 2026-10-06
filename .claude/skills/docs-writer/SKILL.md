---
name: docs-writer
description: Keep SimSplit's documentation consistent with the code and with itself — README, AGENTS.md, CONTRIBUTING, SECURITY, the GitHub Pages site (docs/index.html, privacy policy, docs/product/index.md), implementation plans, skill files and the Play store listing (EN and VI). Maps each changed file to every doc that repeats the same fact, updates all of them together, checks links and store text limits, and audits for drift. Use whenever a change affects what the docs say (a feature, workflow, command, data collected, release status), when the user asks to "write/update docs", "sync the docs", "check the docs are consistent", "viết docs", "cập nhật tài liệu", "docs có bị lệch không", before opening a PR that changes behaviour, or invokes /docs-writer. Not for specs, strategy or the roadmap backlog (product-owner) or implementation plans' technical content (software-engineer).
argument-hint: "[sync [base]|audit|write <doc>]"
allowed-tools: Read, Edit, Write, Grep, Glob, AskUserQuestion, Bash(git:*), Bash(gh:*), Bash(python3 .claude/skills/docs-writer/scripts/*), Bash(python3 scripts/play_metadata.py check)
---

# SimSplit docs writer

You keep every document in the repo telling the same, true story. The same fact —
a feature, a workflow trigger, a command, what data is collected — usually appears
in three to six places. Your job is to make sure a change lands in all of them at
once, in one voice.

## Read first

| File | Why |
| --- | --- |
| [references/doc-map.md](references/doc-map.md) | Each fact's source of truth, its mirrors, and which paths affect which docs |
| [references/style.md](references/style.md) | Language, Markdown and per-doc-type conventions |
| `AGENTS.md` | Critical rules and commands — the most-mirrored facts |

**Facts come from code, not from other docs.** When a doc describes a workflow,
read the `.yml`; when it lists features, read `lib/` and `docs/product/use-cases.md`;
when it describes data collected, read `lib/data/` and `firebase/firestore.rules`.
Docs copied from docs is how drift spreads.

## Ownership

- `docs/product/strategy.md`, `principles.md`, `use-cases.md`, `roadmap.md` and
  `specs/` belong to the **product-owner** skill. Fix links, typos and status mirrors
  there; never change criteria, non-goals or priorities — tell the user instead.
- The technical content of `docs/implementations/` plans belongs to
  **software-engineer**. You may update the phase table's status and keep its
  wording in house style.
- Everything else in the doc map is yours.

## Mode: sync (default)

Bring docs in line with a change. Run it on the current branch before a PR.

1. **Diff.** `git fetch origin <base> --quiet` (base defaults to `main`), then
   `git diff --name-only origin/<base>...HEAD` plus uncommitted changes. Read the
   actual diff, not just file names.
2. **Map.** Use "Changed path → docs to check" in the doc map to list the facts that
   may have changed. For each one, read its source of truth and decide whether the
   fact really changed. A refactor that changes no behaviour usually needs nothing.
3. **Update every mirror** of each changed fact, following the style guide. Keep
   edits minimal: change the sentence that's wrong, don't rewrite the section.
   - User-visible changes on Android also change both store descriptions, EN and VI
     together; `python3 scripts/play_metadata.py check` enforces their length limits.
   - A change to what data is collected or who can see it needs the privacy policy,
     the landing page privacy section and the README — and tell the user to check the
     Play Data safety form by hand.
4. **Check** (below). Then list for the user, per fact: the source, every file you
   changed, and any mirror you deliberately left alone and why.

## Mode: audit

Sweep the whole doc map for drift, without a diff.

1. For each row in the doc map, read the source of truth, then each mirror. Note
   every disagreement with file and line, quoting both sides.
2. Also flag: dead links (run the checker), stale dates or statuses ("coming soon"
   for shipped work), claims the code no longer backs, and EN/VI store text that
   says different things.
3. Report a table — *fact · source says · mirror says · file:line · proposed fix* —
   most user-visible first (store, site, privacy), contributor docs next, agent docs
   last. Ask which to fix (AskUserQuestion, multi-select); fix only those.

## Mode: write

A new doc (a guide, a README section, a page on the site).

1. Ask who reads it and what they need to do afterwards, unless obvious.
2. Check the doc map: if the content already has a home, extend that doc or link to
   it instead of creating a second copy. A new doc that repeats facts gets a row in
   the doc map in the same PR.
3. Write it in house style, link it from where readers will look (README, `AGENTS.md`,
   `docs/product/index.md`), and run the checks.

## Checks

Run all that apply before handing back:

```bash
python3 .claude/skills/docs-writer/scripts/check_docs.py   # relative links and #anchors
python3 scripts/play_metadata.py check                     # if store metadata changed
```

Then re-read every edited mirror next to its source once more — the checker catches
broken links, not wrong facts.

## Hand-off

- Commit docs-only work as `docs(<area>): …` (areas in the `pr-writer` skill); when
  syncing a feature branch, commit the doc changes on that branch so code and docs
  merge together.
- Open PRs with the `pr-writer` skill. Mention in the PR body which facts changed and
  where they are mirrored, so the reviewer can check the set is complete.
- If you changed the doc map's structure (a new doc, a new mirror), say so — it is how
  the next sync finds it.
