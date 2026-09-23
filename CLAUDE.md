# flutter_query — working notes for agents

A Dart/Flutter port of [TanStack Query](https://github.com/TanStack/query)'s
`query-core`, with a Flutter binding on top. The differentiator is
**behavioural fidelity proven by porting the upstream test suite**, so fidelity
work is first-class here, not an add-on.

The [bounded core confidence assessment](docs/research/core-confidence-assessment.md)
is complete: 32 additional core sequence cases, 680 VM / 677 browser tests,
a real-backend consumer flow and a historical negative control. No production
code changed and no confirmed core blocker remains from this assessment.
The added tests run in the normal CI workflow. The real-backend E2E flow supplies
the planned consumer integration evidence; additional practical use is optional,
not another acceptance gate. Its limits do not expand the feature contract.

The [2026-09-13 test follow-up](docs/research/release-test-follow-up.md) adds
one foreground-mutation ordering case and repairs the task-manager E2E focus
wait. It changes no production code and does not reopen the general review.

The [2026-09-18 final functional review](packages/query_kit/test/PORTING_NOTES.md)
— eight lenses against upstream at the pin, functional only — found no P1 and
one P2: `setQueryData`'s inferred type argument was binding, so the ordinary
optimistic-update spellings threw. An existing entry now takes any value its
own type can hold. It also batched the focus/reconnect resume as upstream
does and added `IsFetchingController` (upstream's `useIsFetching`). Core
744 VM / 740 browser tests, binding 138; a fresh pass over the fixes found two
defects in them, both fixed. The notes' "Final functional review"
section lists what was reproduced and deliberately left (ADR-0003's scope
lock among them).

The [2026-09-19 first real integration](docs/research/br64-integration-findings.md)
(Eltako Connect, BR64) reported fourteen findings. One was a defect — structural
sharing handed an unmodifiable list back growable — fixed with its regressions
in `integration_findings_test.dart` (core 752 VM / 748 browser). The fix was decided twice — strict immutability
first, which switched element sharing off for sealed lists and broke
infinite-query page sharing unseen by 750 tests; then instance identity with a
fixed-length copy, which PORTING_NOTES' I1 argues. One was a
packaging gap in the docs. The rest are upstream-faithful or beyond upstream,
and they were charted as map [#81](https://github.com/KoTTi97/flutter_query/issues/81)
and worked off on 2026-09-20 — PORTING_NOTES' "After the first integration"
has a row per ticket: `(a, b).combine(…)` over a record of results (#82);
`mutationFnWithContext` and `Mutation.cancel`, a failure and not a revert
(#83, a row in ADR-0003); `setOptions` compares `enabled` against the
observer's last result, so a rebuild re-evaluates a callback over outside
state (#84, a divergence); `QueryState.consecutiveErrorCount` and
`MutationStateObserver.typed` built, closing a prefix and a scope-deadlock
assertion declined (#85). The integrator's second report, against `87bc25b`,
found two defects in that work — a `CombineMemo` blind to what its combiner
captures (now `keys:`), and a manual write resetting `consecutiveErrorCount`
— and one claim that did not reproduce; PORTING_NOTES' "Second integration
report". A third report, against `9c5066a` — the app now runs on the new
surface, its nine-step simulator pass clean — measured that a value class
wrapping a list is a leaf to structural sharing (0 of 25 instances kept) and
answered [#86](https://github.com/KoTTi97/flutter_query/issues/86):
`StructurallyShareable`, `optional()` sources and `combine` over a list
followed, and a fourth round confirmed them by measurement (24 of 25 with no
hook) and brought the one case `combine` still lacked: `combineWith`, a list
plus the query it was derived from. Core 783 VM / 779 browser, binding 144.
The app has replaced six of its own building blocks, some 450 lines; what is
untested is the real BR64 — the 202 confirmation with cancel, and giving up
after five failures. The sharing
trade-off stays discussable on [#86](https://github.com/KoTTi97/flutter_query/issues/86);
the traps opened the site's `reference/troubleshooting.md`.

The **2026-09-23 release review** was a deep dive over both repositories —
library line by line against upstream at the pin (L1–L5, B1–B2), the BR64
app's use of it (E1–E4), a release-readiness lens (REL-1–21) — and it set the
version at **1.0.0**, not 0.1.0: a breaking change is now a major. Fifty-six
findings were worked in three passes, each reproduced first: 21 on the core's
query side, 20 on client, keys and mutations, 15 in the binding (REL-13 did
not reproduce) — PORTING_NOTES' three "Release review 2026-09-23" sections, a
row each. What users meet: `withSelect`, `QueryResult.consecutiveErrorCount`,
`CombinedResult.refetch(cancelRefetch:)`; `combineWith2`, the `canFetch`
export and `typedMutationSelection` gone; #84 holding in all four call styles;
reads in nested builders additive (a list's item-builder context refused in debug
builds, after the second pass). The docs pass put the README samples under
`site_fences_test.dart`, took the binding's example out of the workspace
(`docs/releasing.md`, "What the archives hold") and gave `publish.yml` a
Flutter SDK. Then a fresh verifier per package read the fixes against
upstream and against their pre-fix parent — each section's "Second pass" —
and, as every earlier round, found defects the fixes had introduced. Core
(V-C-1–7): three introduced — a same-key `setOptions` running the old
`select` on a new seed, a typed mutation selection's predicate seeing other
types, cancelling a restored scope's tail starting its head — and four older
or cosmetic ones fixed: the `StructurallyShareable` debug assertion removed
(returning `previous` is correct when nothing changed), `setQueries`'s throw
path notifying, the L2-2 divergence recorded, dead `trySetData` gone.
Binding (V-B-1–5): three P2 — a `LayoutBuilder`'s own context never releasing,
a `ListView.builder` item context holding every row ever built (now a debug
`FlutterError`: a widget per row), a replacement provider's online verdict
overwritten by the old one's dispose (now only the last provider resets) —
and two P3: the keyed-mutation assertion narrowed to different functions in
the reader's own build, and `MutationController.observer`'s bypass
documented. A third pass (V3-1–7) found the binding's element-bound release
edge moved a third time — reads through a `LayoutBuilder`'s context, from a
nested builder or an item builder, released data still on screen — and
replaced the per-case rules with one: only a `StatelessWidget`'s or `State`'s
provable own build (dirty, or a new widget from its parent) opens a
generation; every other read, every read through a `LayoutBuilder` or a
list's sliver included, is additive and goes at the next generation that does
not read it, at the parent's next rebuild, or at unmount. Nothing on screen
loses its subscription; a key a `LayoutBuilder` stopped reading stays until it
is rebuilt (the docs: read constraint-dependent keys below it). A table over
ten reader shapes × four frames (`reader_shapes_test.dart`) holds it. Also: the
keyed-mutation assertion compares callbacks too and skips non-own-build reads,
a provider whose `initState` threw no longer counts as a connectivity speaker,
and a restored scope head cancelled and removed hands on again (core).
Core **826 VM / 822 browser**, binding **231**.

## Where the work stands (2026-09-23)

| Phase | State |
|---|---|
| **`packages/query_kit/`** — the pure-Dart core | **1.0.0, release review done (2026-09-23), not published** — 826 VM / 822 browser tests since; the rest of this cell is the 2026-09-12 state. **Pre-release deep-dive review done (2026-09-12).** Eight independent lenses, every P1/P2 reproduced and verified by a second fresh agent, then fresh passes over each round of fixes — which found defects the fixes themselves introduced (six in round 1, three in round 2, one in round 3), all fixed, and one older hashing defect those passes surfaced. 742 VM tests / 738 compiled-JavaScript tests, green on the Dart 3.6.2 floor; 414 of 536 upstream cases ported; original ported assertions unchanged. See PORTING_NOTES' "Pre-release deep-dive review" and "Final review" sections; test counts alone are not a release verdict. |
| **`packages/query_kit_flutter/`** — the Flutter binding | **1.0.0, done, nine times reviewed, restructured by map #49, release-reviewed 2026-09-23.** 231 tests behind one harness (`test/harness.dart`); four call styles for queries, infinite queries and mutations — **equal, and proven so** (C49): every one of them takes a `buildWhen` and none rebuilds for a notification that carries nothing. No dependency beyond Flutter — `flutter_test` is a dev dependency, and the widget-test teardown a user writes is a documented snippet (ADR-0002) |
| **`examples/showcase/`** — every feature as a screen | **done (2026-09-09, #25; catalogue gaps closed 2026-09-11, #46; deduplicated 2026-09-12, map #49).** 30 screens (`combine` and `mutation-cancel` joined on 2026-09-20), 247 widget tests against a dio fake of the backend and 177 Playwright end-to-end tests against the real one; a scenario-isolated dummy backend under `server/`; a contract test running the same 25 cases against fake and server, and `catalogue_test.dart`, which holds the **five** per-feature artefact sets level. It found two library bugs no ported test could reach |
| **`examples/task_manager/`** — the acceptance demo, one whole app | **done.** A small to-do app: 16 widget tests, one per row of the MVP checklist plus two regressions found by review, **15 contract cases** run against its fake and its real server (map #49 — twelve of the fourteen were red against the fake), and 10 Playwright end-to-end tests in a real browser against that server; iOS and web generated |

The core covers queries, mutations, infinite queries, the observers, the client
and the caches. Its fidelity audit — every ported case, every omission with its
reason — is
[`packages/query_kit/test/PORTING_NOTES.md`](packages/query_kit/test/PORTING_NOTES.md),
and it is the first thing to read before touching a ported suite. Nine
review rounds — one on 2026-09-08, four on 2026-09-09, three on 2026-09-10,
and the ninth of `f6a9ddd`, four reviews consolidated as C1–C59 and worked
off by map #33 (C1–C46, 2026-09-11) and map #49 (C47–C59, 2026-09-12) —
found some 100 bugs between them, none caught
by a ported case; their regressions live in
`port_specifics_test.dart` and `port_lifecycle_test.dart` (core) and
`review_regressions_test.dart` (binding),
and the notes' "Regressions found by review" section says what each one was. **A review's finding is verified by
reproducing it before anything is changed** — two of the second review's own
reproductions did not exercise the code they claimed to, four claims of
2026-09-10 could not be reproduced at all, and the ninth round's C15 and C29
joined them; the notes record why, because an unreproduced report is worth
writing down too. Map #49 went further and **re-measured every finding it
worked**: most of §8's counts were wrong in one direction or the other — one
was a third too high, one understated a problem by a factor of six, one added
two unrelated things together, one named a duplicate in an example that has
none — so a structural row is a hypothesis, not a measurement, and its own row
in the notes says what was actually counted.

```bash
cd packages/query_kit && dart test
```

```bash
cd packages/query_kit_flutter && flutter test
```

```bash
cd examples/task_manager && flutter test
```

```bash
cd examples/showcase && flutter test
```

```bash
cd examples/doc_snippets && flutter test
```

The binding's example is outside the workspace (it ships; see
`docs/releasing.md`), so after a fresh clone run `flutter pub get` in
`packages/query_kit_flutter/example` once before the analyzer:

```bash
dart analyze --fatal-infos packages examples tool && dart format --set-exit-if-changed packages examples/showcase/lib examples/showcase/test examples/doc_snippets/lib examples/doc_snippets/test tool
```

```bash
cd website && npm ci && npm run build
```

That is the per-module gate: tests, analyzer, formatter, and a PORTING_NOTES
entry, all in the same commit. `.github/workflows/ci.yml` runs the same gates
plus `dart doc`, both publish dry-runs, a web build of the demo and the
documentation site on every push; a `floors` job runs the four test suites on Flutter 3.27.4 (the declared
floor — it caught three dependency pins and a `foundation` export that current
stable hides); and an `e2e` matrix job runs each example's Playwright
end-to-end suite (the real web build in Chromium against the real express
backend — read the example's README before touching one; they read Flutter's
semantics tree, not the canvas, and nothing in them asserts on a clock). The
showcase leg also runs `backend_contract_test.dart` against the real server.
Nothing is published yet; the order, tags and the pub.dev-side switch are in
[`docs/releasing.md`](docs/releasing.md).

**The showcase's rules** are in [`examples/showcase/README.md`](examples/showcase/README.md):
one self-contained directory per feature under `lib/features/`, a
`QueryDebugStrip` per cache entry a test reads, no clock in any assertion,
one backend scenario per end-to-end test (`x-scenario`), and the widget-test
harness `showcaseTest` in `test/harness.dart`. Since map #49 it also says what
earns a file a place in `lib/shared/` — one subject, more than one feature
calling it, and a member with a single caller belongs with that caller — and
the four modules there are the vocabulary a new screen composes rather than
copies: `fact_group.dart` (what a test **reads**), `controls.dart` (what a
test **presses**), `chrome.dart` (neither) and `cache_listener.dart`.

**Widget tests need one extra step.** A `QueryClient` outlives the tree and owns
`gcTime` timers; Flutter's test binding asserts no timer is pending when the
tree comes down, *before* any `tearDown` runs. So a widget test ends with
`pumpWidget(const SizedBox())`, `pumpAndSettle()`, `client.clear()`, then one
more `pump()` and `clear()` for what a dropped mutation's callbacks wrote
(C11). That teardown is a **documented snippet, not an export**
([ADR-0002](docs/adr/0002-widget-test-teardown-is-a-documented-snippet.md)):
`flutter_test` is a dev dependency of the binding, the snippet is the first
section of the site's testing guide and the binding README, it is compiled and
run in `examples/doc_snippets/test/teardown_snippet_test.dart`, and the
binding's suite (`packages/query_kit_flutter/test/harness.dart`) and both
examples (`showcaseTest`, `demoTest`) wrap the same shape. And
`pumpAndSettle` only pumps while a frame is scheduled: a fake backend's latency
or a `refetchInterval` is a timer, stepped with `tester.pump(duration)`.

## The wayfinder map

Work is planned as **wayfinder maps** — one issue labelled `wayfinder:map`,
its decision tickets as sub-issues, the frontier (open, unblocked, unassigned)
visible in GitHub's UI through native blocked-by edges. The wayfinding
operations are in
[`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md).

**Three maps have been charted and all three reached their destination**, so
**all three are closed** — a map is closed when its last ticket is, the same
as any other issue, and `gh issue list --state open --label wayfinder:map`
is therefore the honest answer to "is a map running". Closed does not mean
spent: **the Notes and Decisions of all three remain in force**, they are
cited by number throughout this file, and a closed issue reads and links
exactly like an open one.

- [#1](https://github.com/KoTTi97/flutter_query/issues/1) — the fresh port.
  Its Notes are the oldest standing rules (AFK, the upstream pin, no
  third-party dependency, the four equal call styles); **start there** when
  you need to know why something is the way it is.
- [#33](https://github.com/KoTTi97/flutter_query/issues/33) — release 0.1.0
  (the version became 1.0.0 at the 2026-09-23 release review).
  Worked off the ninth review's findings C1–C46, two of them as ADRs under
  [`docs/adr/`](docs/adr/), and ended at the wizard's door with the release
  commit (#47).
- [#49](https://github.com/KoTTi97/flutter_query/issues/49) — the structural
  findings **C47–C59** that #33 ruled out of its own scope. Nineteen tickets,
  all worked through on 2026-09-12 (`60173bb`, state docs in `15dd9a0`). Its
  *Not yet specified* section holds the seeds for the next map.

**Charting the next one** starts from #49's fog, not from a reopened map: a
new map is a new issue, as #33 was to #1 and #49 to #33.

**What map #49 changed, in one paragraph**, because it touched almost every
module: the binding's two reader registries are one `ReadSet` and its six
rebuild decisions one `ReadEntry`; the four call styles are equal *in fact* —
every read takes a `buildWhen` and no controller notifies for a notification
that carries nothing (`NotifyGate`); one `ListenerRegistry` and one
`ControllerLifetime` replace the hand-written ones; `QueryCacheRef` gained the
observer pair its mutation twin already had, so a `Query` has one path to its
cache; the refetch rules live on the options as `_RefetchRules`; the
provider's connectivity pair is one sealed `OnlineStatus`; and both examples
grew a **contract test run against their real server**, which found ten drifts
between a fake and the backend it stands in for. Its audit trail is the
"Structural work after the ninth review (C47–C59)" section of PORTING_NOTES,
one row per ticket, and its rule was that a suite may not be rewritten to fit
a refactor — so **every count below only went up**.

What the map settles:

- **Destination:** a pure-Dart core (core set plus infinite queries and
  `placeholderData`) with upstream tests ported case-for-case, a Flutter
  binding, and one whole small app built on it, not just a feature catalogue.
- **Standing rule:** closeness to upstream is a tiebreaker, not a goal. The best
  Flutter-world result wins; diverge wherever a Dart/Flutter idiom is better and
  record why. Every divergence so far is in PORTING_NOTES.md's table.
- **AFK: nobody is in the loop (Christian, 2026-09-08).** Every ticket,
  grilling ones included, is decided by the agent — never ask which option to
  take, never stop for an answer. What replaces the live exchange: the
  resolution comment states the options, the answer, and why it beats the
  alternatives, so the decision can be reopened from the record alone.
- **Decide, then build.** Production Dart lands as soon as the decisions
  covering it are closed.
- **The binding's API shape was Christian's call, and he made it (2026-09-08).**
  [#21](https://github.com/KoTTi97/flutter_query/issues/21) and
  [#23](https://github.com/KoTTi97/flutter_query/issues/23) are closed. What he
  ruled: **no third-party package required by the main package** — not
  `flutter_hooks`, not signals, and by the same reasoning not
  `connectivity_plus`; hooks and signals may come later as opt-in packages. And
  **no default in the documentation**: the four call styles are presented as
  equal alternatives. Both rules hold for anything built on top, including the
  demo.
- **Upstream pin:** `query/` at `50680b98c` (`main`, 2026-09-08).
- **Research findings** from charting live under [`docs/research/`](docs/research/)
  (upstream inventory, Dart library survey, adapter contract, runtime facts,
  naming and affiliation). Each is linked from its resolved ticket.

The wayfinder, grilling, prototype and research flows come from the
`mattpocock-skills` plugin; the map's Notes name which skill each ticket type
uses.

Names, layout and licence are settled on
[#13](https://github.com/KoTTi97/flutter_query/issues/13); every module cites
the ticket that decided its shape in its dartdoc.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues (`KoTTi97/flutter_query`, via the
`gh` CLI). See `docs/agents/issue-tracker.md` — its "Wayfinding operations"
section is what `/wayfinder` sessions follow. The current wayfinder map is the
issue labelled `wayfinder:map`.

**Always pass `--repo KoTTi97/flutter_query`.** The nested `query/` clone points
at `TanStack/query`, and `gh` infers the repo from the working directory.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root, created lazily
by `/domain-modeling` when the first term or decision is resolved. See
`docs/agents/domain.md`.

## Repository layout

| Path | What it is | In git? |
|---|---|---|
| `packages/query_kit/` | The pure-Dart core. | yes |
| `packages/query_kit_flutter/` | The Flutter binding. | yes |
| `examples/showcase/` | Every feature as a screen, its dummy backend (`server/`), its widget and end-to-end tests. | yes |
| `examples/task_manager/` | The acceptance demo — one small to-do app — its dummy backend (`server/`) and the acceptance suite. | yes |
| `website/` | The documentation site (Docusaurus). Built in CI, deployed nowhere. | yes — its `build/` and `.docusaurus/` are ignored |
| `examples/doc_snippets/` | Every Dart sample on the site, as code the analyzer sees. Not an app; its job is to fail when a sample stops compiling. | yes |
| `tool/` | `rename_packages.dart`: the one pass that renames both packages everywhere. The names are settled (`query_kit`, `query_kit_flutter`); this is what set them. | yes |
| `docs/agents/` | Tracker and domain-doc conventions the wayfinder sessions follow. | yes |
| `docs/research/` | Research findings behind the map's tickets. | yes |
| `query/` | Upstream TanStack Query, the reference implementation and the source of the ported tests. | **no** — nested clone, gitignored |

`query/` is a separate git checkout that this repo ignores. It is *required* to
work on the port — every ported test names its upstream source file — so if it
is missing, clone it before starting:

```bash
git clone https://github.com/TanStack/query.git query
```

**The upstream revision is load-bearing.** Test counts and line references drift
otherwise:

```bash
git -C query checkout 50680b98c
```

To run the task manager's backend (port 5174):

```bash
cd examples/task_manager/server && npm install && npm run dev
```

## The previous attempt (deleted, in history)

A first `query_core` implementation lived at `flutter-port/` until the fresh
core's ported suites went green.
[#13](https://github.com/KoTTi97/flutter_query/issues/13) settled that it would
be removed then, because the same information now lives in a better place and an
out-of-date copy is a trap for readers. It is still reachable:

```bash
git show 69c71d4:flutter-port/DESIGN.md
git show 69c71d4:flutter-port/packages/query_core/test/PORTING_NOTES.md
```

Its design decisions **D1–D13** are cited by the map's tickets as inputs, and
its own porting notes recorded nine port bugs — several of which the fresh port
hit again and fixed the same way. Nothing in it is the plan.

## Conventions the port runs on

These are not style preferences; breaking them breaks the tests or the
semantics.

- **Time goes through `package:clock`** (`clock.now()`), never `DateTime.now()`,
  and delays through plain `Timer` / `Future.delayed`. `fake_async` intercepts
  both at the zone level; a stray `DateTime.now()` silently desynchronizes from
  virtual time (#9).
- **Every internally-held future gets an explicit `.ignore()`** where nobody
  awaits it. A retryer's future rejects whether or not anyone is listening, and
  an unhandled async error fails the whole test file (#9).
- **Tests use `testFakeAsync` from `test/test_utils.dart`,** not bare
  `fakeAsync`. `FakeAsync.elapse` cannot be called re-entrantly, so
  `await time.advance(d)` hands control back to an outer driver. There is also
  `testFakeAsyncGuarded` for the cases that assert on errors reported to the
  zone.
- **Null means "unset" on every options field,** so merging defaults is a plain
  `??` per field. Options with a real "off" value say so with a sealed value
  type (`StaleTime`, `GcTime`, `Enabled`, `RetryPolicy`, `RefetchOn`,
  `RefetchInterval`) rather than a magic number or string (#10).
- **`Defaulted*Options` are distinct types**, not a flag. Only `QueryClient` can
  produce them, so nothing downstream can be handed half-resolved options. They
  carry value equality, which is what tells a rebuild that nothing changed.
- **An option field costs about forty lines, in nine places.** There is no
  macro and no code-generation package (neither published package may require
  one), so each field is written out per class and per role, and a missed one
  is a silent bug — an option that does not survive a `copyWith`, or a rebuild
  that never happens because `==` does not see it. Adding one means all of:
  (1) the base's constructor parameter, (2) its field, (3) its `toString`
  entry, (4) its `copyWith` parameter and (5) body, (6) the `super.` parameter
  and `copyWith` of *each* subclass — plain and select, and again on the
  infinite side, (7) the `Defaulted*` constructor, field, `==` and `hashCode`,
  (8) the client's defaulting, and (9) the copy in
  `QueryObserverOptions.withSelect` and `InfiniteQueryObserverOptions.withSelect`
  (LIB-3's test fails for a forgotten field only if it sets that field).
  Explored and kept as the price of const value classes
  ([#62](https://github.com/KoTTi97/flutter_query/issues/62)).
- **When porting a test, port it — don't rewrite it.** Keep the upstream name so
  the two files diff against each other, and if the assertion has to change,
  record why in PORTING_NOTES.md. Port-only behaviour goes in `smoke_test.dart`,
  so one Dart file maps to one upstream file everywhere else.

## What porting has taught, twice

The loop that works: read the upstream module, read its upstream test file,
write the Dart module, then port the test file case by case and let the failures
tell you where the port is wrong.

**The fresh port found 22 bugs this way** — the abort signal marked as consumed
one await too late, a silent cancel dispatching an error nobody asked for,
mutation callbacks running in the wrong order, a restored offline mutation that
could never resume, a cancel token whose callbacks ran a microtask too late for
an in-flight page loop. Not one of them would have been caught by a test written
from the Dart side.

When a ported test fails, the default assumption is that **the port is wrong,
not the test**. Change the assertion only when a design decision genuinely makes
upstream's expectation inapplicable — and then write it down.
