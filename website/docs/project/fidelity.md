---
title: How fidelity is proven
description: TanStack Query's suite ported case by case, what porting found, what review and real use found, and where every omission is written down.
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

The port follows one fixed revision of TanStack Query, **`50680b98c`**, {/* jargon-ok */}
so the ported tests and the behaviour they check describe the same version.

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

Repeated rounds of external deep-dive review — each by a fresh reviewer with
no memory of the decisions, and each followed by a fresh review of its fixes
— found **more than 150** more. None was caught by a ported case, because a
ported case tests the port against upstream and these were about Dart and
Flutter:

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

**Every finding is reproduced before anything is changed**, and the reviews
of the fixes found defects the fixes had introduced, round after round — which
is why every fix gets a review of its own. Several reported findings could not
be reproduced at all. They are written down too, with the disproof, because an unreproduced report is worth knowing about — and
because "we checked, and here is what we found instead" is the only way that
information survives.

## What the examples found

Two library bugs that no ported test could reach, because neither is visible
without a real widget: a read whose key changed lost `keepPreviousData`, and
`structuralSharing` was invisible to every reader because the observer
re-shared the cache's data against its own last result. Both were reproduced in
the library's own suite before anything was changed.

That is what [the examples](examples.md) are for.

## What real use found

The first integration into a production Flutter app reported fourteen
findings. One was a defect — structural sharing handed an unmodifiable list
back growable — and was fixed with its regression tests. The rest were
behaviour the library shares with TanStack Query, or requests beyond it; the
ones that were built are `combine`, `mutationFnWithContext` and cancelling a
mutation, `consecutiveErrorCount`, typed mutation state and
`StructurallyShareable`, and the traps it hit opened the
[troubleshooting](../reference/troubleshooting.md) page.

## The numbers

Measured by running each suite, not by counting `test(` in the sources.

| | |
|---|---|
| core | **826** Dart VM tests; **822** also compiled to JavaScript (a few barrel checks are VM-only). 414 of them are ported upstream cases; the rest are the port-only files, the review regressions and the integration regressions |
| binding | **287** tests, widget tests behind one harness |
| examples | a widget test per showcase screen and per task-manager checklist row, Playwright end-to-end tests in Chromium against each example's real server, and contract cases run against both the fake backend and the real server |
| documentation | every Dart sample on this site is compiled, and held equal to its compiled twin by a test |

Every push runs all of it, plus the analyzer at `--fatal-infos`, the formatter,
`dart doc --validate-links`, both publish dry-runs, a web build of each example
— and the whole suite again on the declared Flutter floor, because a floor
nobody tests is a guess.

## Divergences

Closeness to upstream is a **tiebreaker, not a goal**. Where a Dart or Flutter
idiom is better, the port diverges and writes down why; the full table is at
the end of PORTING_NOTES, and [differences from TanStack
Query](../reference/differences-from-tanstack.md) lists the ones you can
notice, in user terms.
