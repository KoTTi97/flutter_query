# flutter_query — working notes for agents

A Dart/Flutter port of [TanStack Query](https://github.com/TanStack/query)'s
`query-core`, with a builder-first Flutter binding on top. The differentiator is
**behavioral fidelity proven by porting the upstream test suite**, so fidelity
work is first-class here, not an add-on.

**Read these three, in order, before changing anything under `flutter-port/`:**

1. [`flutter-port/DESIGN.md`](flutter-port/DESIGN.md) — the design doc of
   record. Decisions **D1–D13** are cited all over the source; §14 lists where
   implementation has since amended them.
2. [`flutter-port/PLAN.md`](flutter-port/PLAN.md) — the approved milestone plan
   (M0–M9) and the module map. Its header carries current status.
3. [`flutter-port/packages/query_core/test/PORTING_NOTES.md`](flutter-port/packages/query_core/test/PORTING_NOTES.md)
   — the fidelity audit: which upstream test is ported where, every omission
   with a reason, every port bug the suites caught, and the deliberate
   divergences from upstream.

## Repository layout

| Path | What it is | In git? |
|---|---|---|
| `flutter-port/` | **The port.** Dart pub workspace. | yes |
| `query/` | Upstream TanStack Query, the reference implementation and the source of the ported tests. | **no** — nested clone, gitignored |
| `react-demo/` | The React sensor demo + the shared express gateway. Defines the MVP bar. | yes — vendored (its own `.git` was removed); only `node_modules` is ignored |

`react-demo/` is tracked here, so a fresh checkout has the demo, the express
gateway under `react-demo/server/`, and the cache policy the Flutter app has to
reproduce (`react-demo/react/src/queries.ts` + `api.ts`). It originally lived in
its own repo (`KoTTi97/tanstack-query-demo`, branch `development`); that remote
is no longer the source of truth for this copy.

`query/` is a separate git checkout that this repo ignores. It is *required* to
work on the port — every ported test names its upstream source file — so if it is
missing, clone it before starting:

```bash
git clone https://github.com/TanStack/query.git query
```

**The upstream revision is load-bearing.** Every fidelity claim is against
`query/` at commit `5bb950be8` (`release-2026-08-24-1925-6-g5bb950be8`). Checking
out a different revision will make test counts and line references drift:

```bash
git -C query checkout 5bb950be8
```

## Current state

`query_core` is feature-complete for the MVP. **372 tests pass**; analyzer and
formatter are clean.

| Milestone | Scope | State |
|---|---|---|
| M0–M2 | Workspace, `QueryKey`, managers, `notifyManager`, options, `Retryer` | done |
| M3 | `Query`, `QueryCache`, `QueryState` | done |
| M4 | `QueryObserver`, sealed `QueryResult` | done |
| M5 | `QueryClient`, `QueryFilters` | done |
| M6 | `Mutation`, `MutationCache`, `MutationObserver`, sealed `MutationResult` | done |
| **M7** | **`flutter_query` binding: `QueryScope`, provider, `QueryBuilder`, `MutationBuilder`, scheduler-aware flush** | **next** |
| M8 | `sensor_demo` app + widget tests — this is the MVP release gate | not started |
| M9 | Polish: dartdoc, exports audit, per-package READMEs | not started |

Six upstream suites are ported: **279 of 355 cases**. The 76 unported ones are
enumerated by category with reasons in PORTING_NOTES.md — none is a silent
omission, and that property is worth preserving.

M7 and M8 are scaffolded but commented out in
[`flutter-port/pubspec.yaml`](flutter-port/pubspec.yaml); uncomment the workspace
entry when you start one.

## Commands

Everything runs from `flutter-port/packages/query_core`:

```bash
dart test
```

```bash
dart analyze --fatal-infos && dart format --set-exit-if-changed .
```

Those two are the per-milestone gate — the plan requires both green plus tests
passing before a milestone is called done.

To run the demo gateway the Flutter app will target (port 5174):

```bash
cd react-demo/server && npm install && npm run dev
```

## Conventions that are load-bearing

These are not style preferences; breaking them breaks tests or semantics.

- **Time goes through `package:clock`** (`clock.now()`), never `DateTime.now()`,
  and delays through plain `Timer` / `Future.delayed`. `fake_async` intercepts
  both at the zone level; a stray `DateTime.now()` silently desynchronizes from
  virtual time (D10).
- **Every internally-held future gets an explicit `.ignore()`** where nobody
  awaits it. A retryer's future rejects whether or not anyone is listening, and
  an unhandled async error fails the whole test file (D13).
- **Tests use `testFakeAsync` from `test/test_utils.dart`,** not bare
  `fakeAsync`. `FakeAsync.elapse` cannot be called re-entrantly, so
  `await time.advance(d)` hands control back to an outer driver. There is also
  `testFakeAsyncGuarded` for the cases that assert on errors reported to the
  zone.
- **Null means "unset" on every options field,** so merging defaults is a plain
  `??` per field. Options with a real "off" value say so with a sealed value
  type (`StaleDuration`, `GcDuration`, `Enabled`, `RetryOption`, `RefetchOn`,
  `RefetchInterval`) rather than a magic number or string (D9).
- **`Defaulted*Options` are distinct types**, not a flag. Only `QueryClient` can
  produce them, so nothing downstream can be handed half-resolved options.
- **When porting a test, port it — don't rewrite it.** Keep the upstream name so
  the two files diff against each other, and if the assertion has to change,
  record why in PORTING_NOTES.md. Port-only behavior (things with no upstream
  counterpart) goes in `test/port_specifics_test.dart`, so one Dart file maps to
  one upstream file everywhere else.

## Working on the port

The loop that has worked: read the upstream module, read its upstream test file,
write the Dart module, then port the test file case by case and let the failures
tell you where the port is wrong. That is how all nine port bugs listed in
PORTING_NOTES.md were found — several of them (the silent-cancel error dispatch,
the `setOptions` state clobber, `isDisabled` using AND for OR) would not have
been caught by tests written from the Dart side.

When a ported test fails, the default assumption should be that **the port is
wrong, not the test**. Change the assertion only when a design decision genuinely
makes upstream's expectation inapplicable — and then write it down.

## Known loose ends

- The design doc also lives as a published artifact. `DESIGN.md` is the
  canonical copy; if you change one, change the other.
