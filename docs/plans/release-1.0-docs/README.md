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
| C2 | Live-demo infrastructure | in-memory backend in `lib/` of both examples behind a define; embed mode; `tool/build_demos.sh`; `<LiveDemo>`; CI builds demos into the site; Playwright over the embedded demos; Pages workflow prepared (D5, D7) | 1 | done |
| C8a | Dartdoc, core | no internal history in any `///`; src-level rules moved onto public symbols; categories; examples on entry points; library doc with quick start and D2 notice | 1 | done |
| C8b | Dartdoc, binding | same for `query_kit_flutter` | 1 | done |
| C9 | Test gaps | core/binding coverage gaps from `audits/audit-demos-tests.md` §B closed; value-class table tests; binding on `--platform chrome`; jargon guard in CI (D3) | 1 | done |
| C3 | Site IA | new sidebar per `audits/audit-site.md` §2; existing content moved into the new slugs; internal history out; stub pages marked | 2 | done |
| C4a–d | Guides & concepts content | every guide page complete, a live demo each where one exists, samples fenced (D6) | 3 | C4b, C4c done; C4a, C4d in review |
| C5 | Examples section | one page per showcase feature + task manager, live demo + source | 3 | done |
| C6a–b | Cookbook R1–R20 | one recipe page each, compiled code | 3 | C6b done; C6a in review |
| C7 | API reference pages, differences page, troubleshooting cleanup | | 3 | open |
| C10 | Landing page | editorial, AI notice, a live demo | 4 | done |
| C11 | Examples source cleanup | D3 in `examples/*/lib` (shown on the site), stale screen texts, `build_demos.sh` baseUrl, jargon guard covers example sources | 3 | done |
| R | Repo URLs after the rename | every `KoTTi97/flutter_query` URL and `/flutter_query/` base path → `query_kit`, except historical records | 4 | open |
| X | Independent review by a Codex agent | after E; needs the Codex CLI installed and logged in by the maintainer | 6 | blocked |
| E | Final end-to-end pass | all gates green, site read in a browser, clean pass | 5 | open |

## Decisions

- **D1 — Name.** The product is `query_kit` in all prose (site title, README
  headings, landing page); the packages are `query_kit` and
  `query_kit_flutter`. The maintainer approved renaming the repository; it
  was renamed to `KoTTi97/query_kit` on 2026-09-23 (GitHub redirects the old
  URL). Chunk R replaces the URLs and the site's base path `/flutter_query/`
  → `/query_kit/` once wave 3 has merged. Historical records (`docs/research`,
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
| B6 | C8a review | 4 P2 wrong docs: `failureReason` lifetime, `CancelledError` cases, paused work resumes only on a mounted client, `RetryPolicy.times(n)` = n retries | fixed `9c590c9` |
| B7 | C8a review | 12 P3 imprecise docs (cancelRefetch, setDefaultOptions, onSettled skip, filters type, …) | fixed `9c590c9` |
| B8 | C8b review | 9 P3 binding docs overstated (options re-applied only on parent rebuild, `id` identity, onlineStatus `initial` exceptions, BuildWhen qualifier, …) | fixed `b78b8e3` |
| B9 | C9 review | `CombinedData ==` fields beyond data untested; jargon guard missed `L3-2`/`API-02` shapes and flagged prose | fixed `ab84027` |
| B10 | C2 review | LiveDemo overlay vanished before Flutter's first frame (blank box for seconds); overlay not announced; pages.yml permissions too broad | fixed `99b99a7` |
| B11 | C2 review | embedded demos stay light inside the dark site theme | fixed `98fb761` |
| B12 | C2 review | playground screen resets backend latency to 0 for the whole full-screen app (pre-existing, real server too) | fixed `98fb761`, race `8344491` |
| B13 | C3 review | every titled admonition rendered as plain `:::danger` text (Docusaurus v4 syntax) — AI notice box included | fixed `3b4eb53` |
| B14 | C3 review | `/docs/` 404; see-through mobile menu; 8 wrong facts in moved/new pages (StaleTime.static vs invalidation, cancelRefetch, NetworkMode is an enum, …) | fixed `3b4eb53` |
| B15 | C3 review | landing page shows stale test counts / bug count | fixed `98fb761` |
| B16 | C5 | `tool/build_demos.sh` can't read `baseUrl` since C1 made it a constant — CI demo build broken | fixed `617f9da` |
| B17 | C5 | showcase sources shown on the site carry review IDs/issue links, one on screen ("since C49") | fixed `617f9da` |
| B18 | C5 | stale showcase texts: "combine is not ported", missing spec reference, pagination/offline notices overpromise | fixed `617f9da` |
| B19 | C4d | `guides/filters.md`: `isMutating(filters:)` counts only pending, ignores `filters.status`; `isFetching` ignores `fetchStatus` | fixed `33b2662` |
| B20 | C4d | `reading-queries-in-widgets.md`: implies `QueryMixin` throws for item-builder contexts (only `context.query`); ranking words "most explicit/predictable" (also `query_builder.dart:62`) | open → C4a review / F1 |
| B21 | C4d | `connectivity.md` gaps (swapped clients, reset timing); `queries.md` paused ≠ network only, disabled/static never stale; `combining-queries.md` refetch cancels only sources with data | connectivity checked `80e6dfa`; rest open → C4a review |
| B22 | C4d | dartdoc: `resetQueries` "all four bulk operations" misleads about `removeQueries`; throwing `select` → `QueryError` undocumented; `CombinedResult.isPaused` covers app-hidden wait | open → F1 |
| B23 | C5 review | `examples/index` renamed to .mdx broke 11 links (build failed); GitHub source links pinned to `main` instead of the built commit | fixed `4d6a791` |
| B24 | C5 review | 6 P2 + 7 P3 "what to try" bullets promised what the screens don't show | fixed `4d6a791` |
| B25 | C5 review | four-call-styles card 7 titled "two styles" but shows three panels | open → F1 |
| B26 | C6a | `guides/infinite-queries.md` shows a pixel-offset scroll guard the showcase's load_more code says fails | fixed `80e6dfa` |
| B27 | C6a | `QueryCancelToken` dartdoc says package:http has no cancellation; http ≥1.5 has `AbortableRequest` | open → F1 |

## Log

| Date | Chunk | Commit | Note |
|---|---|---|---|
| 2026-09-23 | C1 | `37938ca`, `68ae3f1` | name, AI notice, READMEs, CHANGELOGs; binding `example/README.md` dropped so pub.dev's Example tab shows code |
| 2026-09-23 | C8a | `3564b9a`, `9c590c9` | core dartdoc: jargon 249→1 (the D2 notice), 70 examples, 15 categories |
| 2026-09-23 | C8b | `fa87b12`, `b78b8e3` | binding dartdoc: jargon 112→0 lines, 46 examples, 7 categories with pages |
| 2026-09-23 | C9 | `cb03ef8`, `ab84027` | +331 core, +12 binding tests; coverage 90.0→99.8 % / 97.4→99.8 %; binding on Chrome; coverage floors + jargon guard (non-blocking) in CI |
| 2026-09-23 | C2 | `bc0f72f`, `99b99a7` | in-memory backends, embed mode, `tool/build_demos.sh`, `<LiveDemo>`, website-e2e (36 specs), pages.yml (tag/manual only) |
| 2026-09-23 | C3 | `2c7a472`, `3b4eb53` | TanStack-style IA: 6 getting-started, 42 guides, examples/cookbook index, reference, project; `/docs` redirect; LiveDemo now on quick-start |
| 2026-09-23 | C11 | `617f9da` | example sources free of internal history, stale screen texts fixed, `build_demos.sh` reads templated baseUrl, jargon guard scans example sources (orchestrator spot-checked; comment/string-only) |
| 2026-09-23 | C5 | `f915e2f`, `4d6a791` | 33 example pages, live demo each, source imported at build time (`DartSource`), grouped gallery, e2e over every page |
| 2026-09-23 | C4b | `861ce26`, `80e6dfa` | 15 guide pages at depth (refetching, network mode, retries, cancellation, paging, infinite, scroll restoration, initial/placeholder data); review fixed 16 (6 P2: scroll guard, demo sentences, cancel-as-error) |
| 2026-09-23 | C4c | `711fd24`, `33b2662` | 16 mutation and cache guide pages at depth; review fixed B19 and 3 more (caching rebuild claim, prefetching demo steps, sharing counts) |
| 2026-09-23 | C10 | `98fb761`, `8344491` | editorial landing with live demo and D2 notice; demos follow site theme; task_manager dark palette; review fixed 5 P3; build_demos.sh conflict resolved to C11's parser |
| 2026-09-23 | C6b | `9a6f2c8`, `1a7a6b5` | 10 recipes (state libs, offline persistence, DI, go_router, websockets, poll-until-confirmed, IoT disconnect, sign-out, key design, freezed); review fixed 2 P2 (`QueryController.create` with select, removeQueries recreation) + 7 P3 |
