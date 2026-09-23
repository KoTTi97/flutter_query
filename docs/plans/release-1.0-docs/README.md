# Release 1.0.0 — documentation, demos and tests

Master file for the pre-publication pass requested on 2026-09-23: every API
documented, TanStack-style docs with many use cases, live interactive demos in
the browser, clean READMEs and site, broad tests, a clear "AI-coded" notice
everywhere, final name `query_kit`. Worked in orchestrator mode on branch
`release/1.0-docs`; nothing is pushed, published or deployed by the agents.

Start every session by reading this file and comparing the log with
`git log --oneline release/1.0-docs`.

## Status

The audits behind the chunks are in [`audits/`](audits/) (site vs TanStack,
API dartdoc, demos/tests/naming). Wave 1 runs in parallel worktrees; wave 2
starts once C3 has fixed the sidebar and slugs.

| # | Chunk | Acceptance | Wave | Status |
|---|---|---|---|---|
| A | Audits | three reports in `audits/` | 0 | done |
| C1 | Name, AI disclosure, READMEs, CHANGELOGs, pubspecs | D1/D2 everywhere listed; package READMEs install-first, no maintainer history (D3); CHANGELOG 1.0.0 is a feature summary; `coverage/` ignored | 1 | done |
| C2 | Live-demo infrastructure | in-memory backend in `lib/` of both examples behind a define; embed mode; `tool/build_demos.sh`; `<LiveDemo>`; CI builds demos into the site; Playwright over the embedded demos; Pages workflow prepared (D5, D7) | 1 | open |
| C8a | Dartdoc, core | no internal history in any `///`; src-level rules moved onto public symbols; categories; examples on entry points; library doc with quick start and D2 notice | 1 | open |
| C8b | Dartdoc, binding | same for `query_kit_flutter` | 1 | open |
| C9 | Test gaps | core/binding coverage gaps from `audits/audit-demos-tests.md` §B closed; value-class table tests; binding on `--platform chrome`; jargon guard in CI (D3) | 1 | open |
| C3 | Site IA | new sidebar per `audits/audit-site.md` §2; existing content moved into the new slugs; internal history out; stub pages marked | 2 | open |
| C4a–d | Guides & concepts content | every guide page complete, a live demo each where one exists, samples fenced (D6) | 3 | open |
| C5 | Examples section | one page per showcase feature + task manager, live demo + source | 3 | open |
| C6a–b | Cookbook R1–R20 | one recipe page each, compiled code | 3 | open |
| C7 | API reference pages, differences page, troubleshooting cleanup | | 3 | open |
| C10 | Landing page | editorial, AI notice, a live demo | 4 | open |
| E | Final end-to-end pass | all gates green, site read in a browser, clean pass | 5 | open |

## Decisions

- **D1 — Name.** The product is `query_kit` in all prose (site title, README
  headings, landing page); the packages are `query_kit` and
  `query_kit_flutter`. The GitHub repository stays `KoTTi97/flutter_query`
  in URLs until its owner renames it: renaming is an outward-facing action the
  agents do not take (GitHub redirects the old URL afterwards, and a rename is
  one search-and-replace over the URLs). Historical records (`docs/research`,
  `docs/reviews`, PORTING_NOTES) are not rewritten.
- **D2 — AI disclosure.** One wording, used everywhere a user can land first:
  *"query_kit is an entirely AI-coded project: all code, tests and
  documentation were written by AI coding agents (Anthropic's Claude). A human
  maintainer set the goals and reviews releases, but did not write the code."*
  Places: root README, both package READMEs (top, before anything else), both
  pubspec descriptions (short form), both CHANGELOGs' 1.0.0 entry, the site
  landing page, the site intro, a site-wide announcement bar, CONTRIBUTING,
  both library-level dartdocs, the examples' READMEs.
- **D3 — User docs are for users.** Review rounds, ticket numbers, C-IDs, map
  numbers and fix history belong in PORTING_NOTES, `docs/` and the CHANGELOG's
  history, not in the site's guides, the package READMEs or dartdoc. Where a
  divergence from upstream matters to a user it is stated as behaviour, with
  a link to the fidelity page, not as a ticket.
- **D4 — Site structure follows TanStack's.** Getting started (Overview,
  Installation, Quick start, Important defaults), Guides & concepts (one page
  per concept), Examples (one page per live demo), Cookbook (real-project
  recipes), API reference, Project. Details fixed after the audit (chunk B).
- **D5 — Live demos are the showcase in the browser, no server.** A Flutter
  web build of `examples/showcase` in a demo mode that runs its backend in
  memory, deep-linkable to one feature with the app chrome hidden, embedded in
  the site through a click-to-load `<LiveDemo>` iframe with "open full screen"
  and "view source". Built by a script into the site's static output in CI;
  never committed.
- **D6 — Every code sample compiles.** A Dart sample on the site or in a
  README is either fenced under `examples/doc_snippets` (as today) or imported
  from compiled source; no free-floating sample.
- **D7 — Deployment is prepared, not performed.** A GitHub Pages workflow may
  be added; switching Pages on, pushing, tagging and publishing stay with the
  maintainer (`scripts/release.sh`).
- **D8 — Gates per chunk.** The repo's gates from CLAUDE.md (the five test
  suites touched, `dart analyze --fatal-infos`, `dart format`, `npm run build`
  for the site) stand in for the orchestrator template's `pnpm verify`.

## Site slugs promised by the READMEs

C3 must create exactly these under `/docs/`: `overview`, `quick-start`,
`important-defaults`, `coming-from-react-query`, `guides/pure-dart`,
`guides/queries`, `guides/query-keys`, `guides/mutations`,
`guides/optimistic-updates`, `guides/infinite-queries`,
`guides/reading-queries-in-widgets`, `guides/render-optimizations`,
`guides/window-focus-refetching`, `guides/connectivity`, `guides/testing`,
`reference/differences-from-tanstack`, `reference/troubleshooting`.

## Bug list

| ID | Found in | Bug | Status |
|---|---|---|---|
| B1 | C1 review | READMEs claimed the suite is ported "case for case" (414/536) | fixed `68ae3f1` |
| B2 | C1 review | core README: `QueryCancelToken` handed to dio directly (needs `onCancel` bridge) | fixed `68ae3f1` |
| B3 | C1 review | core README: pure-Dart client reacts to focus/connectivity by itself | fixed `68ae3f1` |
| B4 | C1 review | binding README lost the connectivity section its dartdoc points to | fixed `68ae3f1` |
| B5 | C1 review | five P3 overstatements/jargon in READMEs and binding CHANGELOG | fixed `68ae3f1` |

## Log

| Date | Chunk | Commit | Note |
|---|---|---|---|
| 2026-09-23 | C1 | `37938ca`, `68ae3f1` | name, AI notice, READMEs, CHANGELOGs; binding `example/README.md` dropped so pub.dev's Example tab shows code |
