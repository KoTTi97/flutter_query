---
title: How fidelity is proven
sidebar_position: 1
description: Upstream's suite ported case for case, what porting found, what nine reviews found, and where every omission is written down.
---

# How fidelity is proven

Several Dart packages cover the *idea* of TanStack Query. The claim here is
narrower and checkable: **the behaviour is upstream's, and upstream's own tests
say so.**

## The method

Read the upstream module. Read its upstream test file. Write the Dart module.
Then port the test file case by case and let the failures tell you where the
port is wrong.

Three rules keep that honest:

1. **When a ported test fails, the port is wrong, not the test.** An assertion
   changes only when a design decision genuinely makes upstream's expectation
   inapplicable — and then the reason is written down.
2. **Port it, don't rewrite it.** Upstream's test names are kept, so the two
   files diff against each other. One Dart file maps to one upstream file
   everywhere; port-only behaviour goes in `smoke_test.dart`.
3. **Nothing is omitted silently.** Every case that is not ported is listed by
   name and category in
   [`PORTING_NOTES.md`](https://github.com/KoTTi97/flutter_query/blob/main/packages/query_kit/test/PORTING_NOTES.md),
   with its reason.

Upstream is pinned at **`50680b98c`**. The revision is load-bearing: test
counts and line references drift otherwise.

## What is ported

| upstream suite | ported | upstream suite | ported |
|---|---|---|---|
| `query` | 44 / 51 | `mutation` | 28 / 28 |
| `queryCache` | 14 / 16 | `mutationCache` | 16 / 16 |
| `queryObserver` | 64 / 75 | `mutationObserver` | 16 / 16 |
| `queryClient` | 106 / 156 | `infiniteQueryBehavior` | 7 / 9 |
| `retryer` | 13 / 13 | `infiniteQueryObserver` | 6 / 7 |
| `queriesObserver` | 12 / 23 | | |

The gap is almost entirely React-specific tests, JavaScript-helper tests with
no Dart counterpart, and features [deliberately not
ported](../reference/feature-matrix.md). Each is enumerated.

## What porting found

**23 bugs**, none of which a test written from the Dart side would have caught —
because each is a behaviour you only know to check if you know the original:

- the abort signal marked as consumed one `await` too late;
- a silent cancel dispatching an error nobody asked for;
- mutation callbacks running in the wrong order;
- a restored offline mutation that could never resume;
- a cancel token whose callbacks ran a microtask too late for an in-flight page
  loop.

## What review found

Nine rounds of external deep-dive review found roughly **100 more** — again, none caught
by a ported case, because a ported case tests the port against upstream and
these were about Dart and Flutter:

- a `Set` of listeners silently dropping a subscription, because Dart tear-offs
  compare equal and JavaScript closures never do;
- a `State` that never noticed its `QueryClient` had changed;
- an infinite query's direction change never reaching the widget;
- `unmount()` before `mount()` switching focus and reconnect refetches off
  permanently;
- `AppLifecycleState.inactive` meaning "interrupted" on a phone and "another
  window is in front" on a desktop.

Every one of them has a regression test —
`port_specifics_test.dart` and `port_lifecycle_test.dart` in the core,
`review_regressions_test.dart` in the binding — and PORTING_NOTES' "regressions
found by review" section says what each was.

**Six reported findings could not be reproduced** — four from the earlier
rounds, two from the ninth, one of those plausible on a later SDK. They are written down too,
with the disproof, because an unreproduced report is worth knowing about — and
because "we checked, and here is what we found instead" is the only way that
information survives.

## What the examples found

Two library bugs that no ported test could reach, because neither is visible
without a real widget: a read whose key changed lost `keepPreviousData`, and
`structuralSharing` was invisible to every reader because the observer
re-shared the cache's data against its own last result. Both were reproduced in
the library's own suite before anything was changed.

That is what [the examples](examples.md) are for.

## The numbers

Measured by running each suite, not by counting `test(` in the sources — which
is the same rule the landing page follows, and the reason these two agree. The
core row was re-measured on 2026-09-12 after the pre-release deep-dive review,
its final review and the bounded confidence assessment; the rows below it were measured earlier
the same day and only the task manager's has moved since.

| | |
|---|---|
| core | **741** Dart VM tests; **737** also compiled to JavaScript (four barrel checks are VM-only). Of those, 414 are ported upstream cases; the rest are the port-only files, the review regressions and 32 bounded confidence sequences |
| binding | **128** tests, widget tests behind one harness |
| showcase | **214** widget tests + **169** Playwright tests in Chromium |
| task manager | **16** widget tests + **9** Playwright tests |
| contract | **39** cases — 24 in the showcase, 15 in the task manager — each run against the fake backend *and* the real server |
| doc snippets | **9** tests — six that hold the site's fences level with their compiled twins, three that run the testing guide's teardown as code |

The showcase's `flutter test` reports 238: the 214 above plus the contract's
24, which run against the fake in every checkout and against the real server
only in the `e2e` job. The task manager's works the same way and now reports
**32 passing with 14 skipped** — the skipped ones are the contract cases that
wait for `TASK_MANAGER_SERVER`, which the `e2e` job sets.

Every push runs all of it, plus the analyzer at `--fatal-infos`, the formatter,
`dart doc --validate-links`, both publish dry-runs, a web build of each example
— and the whole suite again on the declared Flutter floor, because a floor
nobody tests is a guess. That job has already caught three dependency pins and
a `foundation` export that current stable hides.

## Divergences

Closeness to upstream is a **tiebreaker, not a goal**. Where a Dart or Flutter
idiom is better, the port diverges and writes down why; the table of
divergences is at the end of PORTING_NOTES, and each row names the ticket that
decided it. [The feature matrix](../reference/feature-matrix.md) lists the ones
you are most likely to notice.
