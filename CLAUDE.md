# flutter_query — working notes for agents

A Dart/Flutter port of [TanStack Query](https://github.com/TanStack/query)'s
`query-core`, with a Flutter binding on top. The differentiator is
**behavioural fidelity proven by porting the upstream test suite**, so fidelity
work is first-class here, not an add-on.

## Where the work stands (2026-09-09)

| Phase | State |
|---|---|
| **`packages/tanstack_query_core/`** — the pure-Dart core | **done, six times reviewed.** 541 tests, run on the VM and compiled to JavaScript, every applicable upstream suite ported, analyzer clean at `--fatal-infos`, every public member documented |
| **`packages/tanstack_query_flutter/`** — the Flutter binding | **done, four times reviewed.** 72 widget tests; four equal call styles for queries, infinite queries and mutations, no dependency beyond Flutter |
| **`examples/showcase/`** — every feature as a screen | **done (2026-09-09, #25).** 26 screens, 182 widget tests against a dio fake of the backend and 143 Playwright end-to-end tests against the real one; a scenario-isolated dummy backend under `server/`; a contract test running the same 17 cases against fake and server. It found two library bugs no ported test could reach |
| **`examples/sensor_demo/`** — the react-demo port, **legacy** | **done, kept as is.** 15 widget tests, one per row of the MVP checklist plus one regression, and 9 Playwright end-to-end tests in a real browser against the real gateway; iOS and web generated |

The core covers queries, mutations, infinite queries, the observers, the client
and the caches. Its fidelity audit — every ported case, every omission with its
reason — is
[`packages/tanstack_query_core/test/PORTING_NOTES.md`](packages/tanstack_query_core/test/PORTING_NOTES.md),
and it is the first thing to read before touching a ported suite. Six
external reviews (2026-09-08 and five on 2026-09-09) found some 70 bugs between
them, none caught by a ported case; their regressions live in
`port_specifics_test.dart` and `port_lifecycle_test.dart` (core) and
`review_regressions_test.dart` (binding),
and the notes' "Regressions found by review" section says what each one was. **A review's finding is verified by
reproducing it before anything is changed** — two of the second review's own
reproductions did not exercise the code they claimed to, and the notes record
why.

```bash
cd packages/tanstack_query_core && dart test
```

```bash
cd packages/tanstack_query_flutter && flutter test
```

```bash
cd examples/sensor_demo && flutter test
```

```bash
cd examples/showcase && flutter test
```

```bash
dart analyze --fatal-infos packages examples && dart format --set-exit-if-changed packages examples/showcase/lib examples/showcase/test
```

That is the per-module gate: tests, analyzer, formatter, and a PORTING_NOTES
entry, all in the same commit. `.github/workflows/ci.yml` runs the same gates
plus `dart doc`, both publish dry-runs and a web build of the demo on every
push; a `floors` job runs the four test suites on Flutter 3.27.4 (the declared
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
harness `showcaseTest` in `test/harness.dart`.

**Widget tests need one extra step.** A `QueryClient` outlives the tree and owns
`gcTime` timers; Flutter's test binding asserts no timer is pending when the
tree comes down, *before* any `tearDown` runs. So a widget test ends with
`await tester.pumpWidget(const SizedBox()); client.clear();` — see the
`widgetTest` helper in `packages/tanstack_query_flutter/test/binding_test.dart`
and `showcaseTest` in `examples/showcase/test/harness.dart`. And
`pumpAndSettle` only pumps while a frame is scheduled: a fake backend's latency
or a `refetchInterval` is a timer, stepped with `tester.pump(duration)`.

## The wayfinder map

The plan of record is [GitHub issue #1](https://github.com/KoTTi97/flutter_query/issues/1)
(label `wayfinder:map`); its decision tickets are the map's sub-issues, and the
frontier (open, unblocked, unassigned) is visible in GitHub's UI through native
blocked-by edges. **Start there.** The map's Notes are the standing rules for
every session; the wayfinding operations are in
[`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md).

What the map settles:

- **Destination:** a pure-Dart core (core set plus infinite queries and
  `placeholderData`) with upstream tests ported case-for-case, a Flutter
  binding, and the `react-demo` sensor app reproduced on it.
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
| `packages/tanstack_query_core/` | The pure-Dart core. | yes |
| `packages/tanstack_query_flutter/` | The Flutter binding. | yes |
| `examples/showcase/` | Every feature as a screen, its dummy backend (`server/`), its widget and end-to-end tests. | yes |
| `examples/sensor_demo/` | The react-demo port, and the MVP acceptance suite. Legacy, kept as is. | yes |
| `docs/agents/` | Tracker and domain-doc conventions the wayfinder sessions follow. | yes |
| `docs/research/` | Research findings behind the map's tickets. | yes |
| `query/` | Upstream TanStack Query, the reference implementation and the source of the ported tests. | **no** — nested clone, gitignored |
| `react-demo/` | The React sensor demo + the shared express gateway. Defines the MVP bar for the port. | yes — vendored (its own `.git` was removed); only `node_modules` is ignored |

`react-demo/` is tracked here, so a fresh checkout has the demo, the express
gateway under `react-demo/server/`, and the cache policy the Flutter app has to
reproduce (`react-demo/react/src/queries.ts` + `api.ts`). It originally lived in
its own repo (`KoTTi97/tanstack-query-demo`, branch `development`); that remote
is no longer the source of truth for this copy.

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

To run the demo gateway (port 5174), which the port targets:

```bash
cd react-demo/server && npm install && npm run dev
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
