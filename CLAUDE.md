# flutter_query — working notes for agents

A Dart/Flutter port of [TanStack Query](https://github.com/TanStack/query)'s
`query-core`, with a Flutter binding on top. The differentiator is
**behavioral fidelity proven by porting the upstream test suite**, so fidelity
work is first-class here, not an add-on.

**This repo holds two things, and they must not be confused:**

| | Where | Status |
|---|---|---|
| **The plan of record** — a fresh port, planned as a wayfinder map of decision tickets | [GitHub issue #1](https://github.com/KoTTi97/flutter_query/issues/1) and its sub-issues; supporting files under `docs/` | **active** — this is what to work on |
| **The previous attempt** — a `query_core` implementation with its design doc and milestone plan | `flutter-port/` | **prior art** — frozen, reusable after evaluation, not the plan |

## The plan of record: the wayfinder map (2026-09-08)

The port is being re-planned from scratch. The map is
[GitHub issue #1](https://github.com/KoTTi97/flutter_query/issues/1)
(label `wayfinder:map`); its decision tickets are the map's sub-issues, and the
frontier (open, unblocked, unassigned) is visible in GitHub's UI through native
blocked-by edges. **Start there.** The map's Notes are the standing rules for
every session; the wayfinding operations are in
[`docs/agents/issue-tracker.md`](docs/agents/issue-tracker.md).

What the map settles:

- **Destination:** a pure-Dart core (core set plus infinite queries and
  `placeholderData`) with upstream tests ported case-for-case, a Flutter binding,
  and the `react-demo` sensor app reproduced on it.
- **Standing rule:** closeness to upstream is a tiebreaker, not a goal. The best
  Flutter-world result wins; diverge wherever a Dart/Flutter idiom is better and
  record why.
- **The existing `flutter-port/` code is prior art, not the plan of record.** It
  may be reused wherever a ticket evaluates it as good and suitable; the
  evaluation is recorded on that ticket, nothing carries over silently.
- **Upstream pin for the fresh port:** `query/` at `50680b98c` (`main`,
  2026-09-08). The `5bb950be8` pin below is what the *existing* code was built
  against; the inventory research found only two behaviour changes between them.
- **Research findings** from charting live under [`docs/research/`](docs/research/)
  (upstream inventory, Dart library survey, adapter contract, runtime facts,
  naming and affiliation). Each is linked from its resolved ticket.

The wayfinder, grilling, prototype and research flows come from the
`mattpocock-skills` plugin; the map's Notes name which skill each ticket type
uses.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues (`KoTTi97/flutter_query`, via the
`gh` CLI). See `docs/agents/issue-tracker.md` — its "Wayfinding operations"
section is what `/wayfinder` sessions follow. The current wayfinder map is the
issue labelled `wayfinder:map`.

### Domain docs

Single-context: `CONTEXT.md` and `docs/adr/` at the repo root, created lazily
by `/domain-modeling` when the first term or decision is resolved. See
`docs/agents/domain.md`.

## The previous attempt: `flutter-port/` (prior art)

Everything from here to the end of this file describes the previous attempt.
It is accurate for that code, frozen as of 2026-09-08, and the right
orientation when a ticket evaluates one of its modules for reuse. Do not
continue its milestones.

**Its three documents, in reading order:**

1. [`flutter-port/DESIGN.md`](flutter-port/DESIGN.md) — its design doc.
   Decisions **D1–D13** are cited all over that source; §14 lists where
   implementation amended them. They are inputs to the map's tickets, not
   decisions of the new plan.
2. [`flutter-port/PLAN.md`](flutter-port/PLAN.md) — its milestone plan (M0–M9)
   and module map; M0–M6 were built, M7–M9 never started.
3. [`flutter-port/packages/query_core/test/PORTING_NOTES.md`](flutter-port/packages/query_core/test/PORTING_NOTES.md)
   — the fidelity audit: which upstream test is ported where, every omission
   with a reason, every port bug the suites caught, and the deliberate
   divergences from upstream.

## Repository layout

| Path | What it is | In git? |
|---|---|---|
| `flutter-port/` | **The previous attempt** (prior art). Dart pub workspace with `query_core`. | yes |
| `docs/agents/` | Tracker and domain-doc conventions the wayfinder sessions follow. | yes |
| `docs/research/` | Research findings behind the map's tickets. | yes |
| `query/` | Upstream TanStack Query, the reference implementation and the source of the ported tests. | **no** — nested clone, gitignored |
| `react-demo/` | The React sensor demo + the shared express gateway. Defines the MVP bar for both attempts. | yes — vendored (its own `.git` was removed); only `node_modules` is ignored |

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

**The upstream revision is load-bearing.** The existing code's fidelity claims
are against `query/` at commit `5bb950be8` (`release-2026-08-24-1925-6-g5bb950be8`);
the fresh port pins `50680b98c`. Both are on upstream `main`, so one clone serves
both; check out the one you are working against, because test counts and line
references drift otherwise:

```bash
git -C query checkout 50680b98c
```

## Where the previous attempt stopped

`query_core` is feature-complete for its MVP. **372 tests pass**; analyzer and
formatter are clean. Nothing below M6 was started.

| Milestone | Scope | State |
|---|---|---|
| M0–M2 | Workspace, `QueryKey`, managers, `notifyManager`, options, `Retryer` | done |
| M3 | `Query`, `QueryCache`, `QueryState` | done |
| M4 | `QueryObserver`, sealed `QueryResult` | done |
| M5 | `QueryClient`, `QueryFilters` | done |
| M6 | `Mutation`, `MutationCache`, `MutationObserver`, sealed `MutationResult` | done |
| M7 | `flutter_query` binding: `QueryScope`, provider, `QueryBuilder`, `MutationBuilder`, scheduler-aware flush | never started |
| M8 | `sensor_demo` app + widget tests | never started |
| M9 | Polish: dartdoc, exports audit, per-package READMEs | never started |

Six upstream suites are ported: **279 of 355 cases**. The 76 unported ones are
enumerated by category with reasons in PORTING_NOTES.md — none is a silent
omission, and that property is worth preserving.

M7 and M8 are scaffolded but commented out in
[`flutter-port/pubspec.yaml`](flutter-port/pubspec.yaml).

## Commands for the previous attempt's code

Everything runs from `flutter-port/packages/query_core`:

```bash
dart test
```

```bash
dart analyze --fatal-infos && dart format --set-exit-if-changed .
```

Those two were its per-milestone gate.

To run the demo gateway (port 5174), which both attempts target:

```bash
cd react-demo/server && npm install && npm run dev
```

## Conventions the previous attempt settled on

These are not style preferences; breaking them breaks that code's tests or
semantics. Several are candidate answers for the map's tickets (the harness,
options and fidelity tickets in particular).

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

## What the previous attempt learned about porting

The loop that worked: read the upstream module, read its upstream test file,
write the Dart module, then port the test file case by case and let the failures
tell you where the port is wrong. That is how all nine port bugs listed in
PORTING_NOTES.md were found — several of them (the silent-cancel error dispatch,
the `setOptions` state clobber, `isDisabled` using AND for OR) would not have
been caught by tests written from the Dart side.

When a ported test fails, the default assumption should be that **the port is
wrong, not the test**. Change the assertion only when a design decision genuinely
makes upstream's expectation inapplicable — and then write it down.

## Known loose ends of the previous attempt

- Its design doc also lives as a published artifact. `DESIGN.md` is the
  canonical copy; if you change one, change the other.
