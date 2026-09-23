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
| C4a–d | Guides & concepts content | every guide page complete, a live demo each where one exists, samples fenced (D6) | 3 | done |
| C5 | Examples section | one page per showcase feature + task manager, live demo + source | 3 | done |
| C6a–b | Cookbook R1–R20 | one recipe page each, compiled code | 3 | done |
| C7 | API reference pages, differences page, troubleshooting cleanup | merged into C4d | 3 | done |
| C10 | Landing page | editorial, AI notice, a live demo | 4 | done |
| C11 | Examples source cleanup | D3 in `examples/*/lib` (shown on the site), stale screen texts, `build_demos.sh` baseUrl, jargon guard covers example sources | 3 | done |
| F1 | Follow-ups | B22, B25, B27, leftover ranking words; fresh re-check of C4d's reference fact edits (query-client, query-options, widgets-and-controllers) | 4 | done |
| R | Repo URLs after the rename | every old-repo URL and `/flutter_query/` base path → `query_kit`, except historical records | 4 | done |
| X | Independent review by a Codex agent | after E; `codex exec -m gpt-6-sol -s read-only` (maintainer's model choice), findings reproduced before fixing | 6 | done |
| E | Final end-to-end pass | all gates green, site read in a browser, clean pass | 5 | done |

## Decisions

- **D1 — Name.** The product is `query_kit` in all prose (site title, README
  headings, landing page); the packages are `query_kit` and
  `query_kit_flutter`. The maintainer approved renaming the repository; it
  was renamed to `query_kit` on 2026-09-23 and, at the maintainer's
  request, transferred to the company organisation as
  **`dualmeta-gmbh/query_kit`** the same day (GitHub redirects both old
  URLs). The packages publish under the verified pub.dev publisher
  **dualmeta.io** (setup steps in `docs/releasing.md`). Chunk R replaces the URLs and the site's base path `/flutter_query/`
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
  be added. The maintainer approved Pages (free for the public repository);
  it was switched on with source *GitHub Actions* on 2026-09-23, so the
  site deploys to `https://dualmeta-gmbh.github.io/query_kit/` when `pages.yml`
  first runs on the default branch. Switching Pages on was the one exception; pushing, tagging and publishing stay with the
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
| B20 | C4d | `reading-queries-in-widgets.md`: implies `QueryMixin` throws for item-builder contexts (only `context.query`); ranking words "most explicit/predictable" (also `query_builder.dart:62`) | fixed `fc28fec` |
| B21 | C4d | `connectivity.md` gaps (swapped clients, reset timing); `queries.md` paused ≠ network only, disabled/static never stale; `combining-queries.md` refetch cancels only sources with data | fixed `80e6dfa`, `fc28fec` |
| B22 | C4d | dartdoc: `resetQueries` "all four bulk operations" misleads about `removeQueries`; throwing `select` → `QueryError` undocumented; `CombinedResult.isPaused` covers app-hidden wait | fixed `d29456b` |
| B23 | C5 review | `examples/index` renamed to .mdx broke 11 links (build failed); GitHub source links pinned to `main` instead of the built commit | fixed `4d6a791` |
| B24 | C5 review | 6 P2 + 7 P3 "what to try" bullets promised what the screens don't show | fixed `4d6a791` |
| B25 | C5 review | four-call-styles card 7 titled "two styles" but shows three panels | fixed `d29456b` |
| B26 | C6a | `guides/infinite-queries.md` shows a pixel-offset scroll guard the showcase's load_more code says fails | fixed `80e6dfa` |
| B28 | F1 | `QuerySelectOptions` dartdoc + options page: select was said to suppress notifications for unselected changes (it keeps only `data`'s instance); inline `queryFn` said to be no change | fixed `d29456b` |
| B29 | F1 | 3 broken anchors (`paginated-queries` → `placeholder-query-data#keeping-the-previous-page`, `prefetching#where-to-prefetch`, one more) | fixed `4ea460e` (`onBrokenAnchors: 'throw'`) |
| B30 | E | website e2e red (31/69): examples spec expected the full-screen link without `?theme=` | fixed `9cd13ed` |
| B31 | E review of F1 | a mutation in flight keeps `retry`/`retryDelay`/`networkMode`/`scope`; select keeps `data`'s instance only with sharing on; placeholder shows again on refetch after error; `pages` count replaced by any observer | fixed `8404745` |
| B32 | E | root README/CONTRIBUTING still said "case for case" | fixed `9ee6e5b` |
| B33 | X (Codex) | `connectivity.md` reachability sample: stale probe could report online after the link dropped; then (Codex re-passes) overlapping rechecks, resubscribe, hung/throwing probe | fixed `1c735ca`, `e27ede6`, `ff8c249`, `753ab95` |
| B34 | X (Codex) | `query-cancellation.md`: `refetch()` said to throw `CancelledError` (it never throws) | fixed `1c735ca` |
| B35 | X (Codex) | announcement bar not D2 verbatim | fixed `1c735ca` |
| B36 | X (Codex) | typed-data hash test compared a call with itself | fixed `1c735ca` |
| B27 | C6a | `QueryCancelToken` dartdoc says package:http has no cancellation; http ≥1.5 has `AbortableRequest` | fixed `d29456b` |

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
| 2026-09-23 | C4a | `c898d32`, `fc28fec` | getting started + 10 queries guides at depth; review fixed B20, B21 and 11 more (gcTime longest wins, maps/sets not walked, Enabled.when re-ask per style) |
| 2026-09-23 | C6a | `551ce17`, `ce2a092` | 10 recipes on one catalogue app; review fixed a P1 (token-refresh repeat through the queued interceptor could deadlock), 4 P2 (http base URL, timeout, cancellation fact, non-Dio refresh failure), tests for the claims; merge: one explicit 20-recipe sidebar list, dead generator/CSS removed |
| 2026-09-23 | C4d | `d50cc98`, `f3b978a` | tools guides + 8 reference pages (C7 folded in); four sub-reviews: ~40 fixes (missing members, throw sites, 11 missing divergences, dio adapter signature, pumpAndSettle advice), TanStack column moved into descriptions, no table scrolls at 1440px; wave 3 fully merged, 97 LiveDemos on the site |
| 2026-09-23 | R | `2b03d4a` | 87 files: repo URLs and base path → query_kit; GitHub Pages switched on (Actions source); Codex CLI smoke-tested with gpt-6-sol |
| 2026-09-23 | F1 | `d29456b` | B22/B25/B27; fresh re-check of three reference pages found 2 P1 wrong statements (select notifications, inline queryFn) + P2s, fixed in dartdoc and site; core 1157, binding 299 |
| 2026-09-23 | R2 | — | repo transferred to `dualmeta-gmbh/query_kit` (Pages carried over); every URL, site `url`/`organizationName`, wizard `REPO` updated; verified publisher dualmeta.io: wizard stage 7 + `docs/releasing.md` section. LICENSE holder: the maintainer's call, since settled (R3) |
| 2026-09-23 | R3 | — | maintainer: the name is `Dualmeta GmbH`, and the old personal account name appears nowhere in the tree. LICENSE holder (root and both packages) → Dualmeta GmbH; every old-account URL, historical records included, → `dualmeta-gmbh/query_kit` (issue numbers survive the transfer); a local absolute path dropped. Git history keeps the old author — it is pushed and is not rewritten |
| 2026-09-23 | E | `4ea460e`…`9ee6e5b` | clean pass: core 1157 VM/1153 Chrome, binding 299/298, showcase 256 + contract 50 + Playwright 177, task_manager 34 + contract 29 + Playwright 10, doc_snippets 42, site e2e 69, coverage 99.83/99.77 %, dry-runs and dart doc 0 warnings; browser read light/dark/375px clean; floors job (Flutter 3.27.4) not run locally |
| 2026-09-23 | X | `1c735ca`…`753ab95` | Codex (gpt-6-sol, read-only) over the whole branch: 1 P1, 1 P2, 2 P3, all reproduced and fixed; three further Codex passes over the fix converged (last finding was contract wording). Work complete; branch `release/1.0-docs` not pushed |
| 2026-09-23 | REL | `f6b163d`, `e7ded56` | **1.0.0 published** by the maintainer through `scripts/release.sh`: both packages on pub.dev under dualmeta.io, tags at `f6b163d`. Stage 9's EXIT trap died on bash 3.2 reading a UTF-8 ellipsis into `$PUBLISH_WORKFLOW` (unbound under `set -u`), leaving `publish.yml` disabled — re-enabled by hand, stage 10 checked by hand, fixed in `e7ded56`. The tag's Pages deploy was rejected by the `github-pages` environment (branch `main` only); tag pattern `query_kit-v*` added, re-run deployed the site. Release state, later releases and the Pages settings documented in `docs/releasing.md` |
| 2026-09-23 | X2 | — | Codex (gpt-6-sol, read-only) full audit after the release: no P1, nothing in the packages; REL-1 (P2, `publish.yml` did not check the tag against the pubspec) → a check step; SEC-1 (P2, actions on moving tags in an OIDC publish job) → all 25 `uses:` pinned to verified SHAs with version comments; SEC-2 (P3, example servers on every interface with open reset routes) → loopback by default, `HOST=0.0.0.0` opt-in, both READMEs say so. All three reproduced; task_manager contract 29 + Playwright 10 and showcase contract 50 green against the loopback servers |
