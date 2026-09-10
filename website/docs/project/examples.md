---
title: Examples
sidebar_position: 2
description: The showcase — every feature as a screen against a real backend — and the legacy acceptance demo.
---

# Examples

Three, of increasing size.

## The one-file tour

`packages/query_kit_flutter/example/` — a provider, one query read three ways
and a mutation that invalidates it, with no server at all. `flutter run` in
that directory. It is what pub.dev shows on the package page.

## The showcase

`examples/showcase/` — **every feature of the library as its own screen**, 26
of them, against a dummy backend built for the purpose, each with widget tests
and Playwright end-to-end tests in a real browser. The app is the catalogue;
the tests are the proof.

```bash
cd examples/showcase/server && npm install && npm run dev
```

```bash
cd examples/showcase && flutter run -d chrome
```

Each feature lives in `lib/features/<id>/`, imports only the package and
`lib/shared/`, and says at the top of its file what it shows, which upstream
example it mirrors, and how it is proven.

| Reading | Paging | Writing | Runtime |
|---|---|---|---|
| `simple` | `pagination` | `mutations` | `auto-refetching` |
| `basic` | `load-more` | `optimistic-updates` | `retry` |
| `default-query-function` | `max-pages` | `mutation-state` | `cancellation` |
| `dependent-queries` | | `playground` | `offline` |
| `parallel-queries` | | `invalidation-and-filters` | `focus-refetch` |
| `query-collections` | | `global-callbacks` | `four-call-styles` |
| `prefetching` | | | `cache-inspector` |
| `select-and-sharing` | | | |
| `initial-and-placeholder` | | | |
| `stale-and-gc` | | | |

**No screen presents one of the four call styles as the default**; across the
catalogue each is used in its turn.

### How it is tested

Three layers and nothing else:

- **Widget tests** run the real app against a `dio` `HttpClientAdapter` that
  mirrors the server route for route and loads the same seed file.
- **A contract test** runs one list of cases against the fake *and*, with the
  server up, against the server. That is what makes the fake trustworthy.
- **End-to-end tests** drive the real web build in Chromium against the real
  backend. Every test gets a backend scenario of its own, so the suite runs
  fully parallel and nothing one test does is visible to another.

Nothing in the browser suite asserts on a clock. To prove something shows
*before* the backend answers, the test holds the request in the browser and
releases it after the assertion; a poll is proven to stop by sampling a request
count, waiting, and sampling again. Flutter web paints to a canvas, so the
tests read the **semantics tree** — the same tree a screen reader gets.

### What building it found

Two bugs in the library that no ported upstream test could reach, because
neither is visible without a real widget: a read whose key changed lost
`keepPreviousData` in `QueryMixin` and `context.query`, and `structuralSharing`
was invisible to every reader because the observer re-shared the cache's data
against its own last result. Both were reproduced in the library's own suite
before anything was changed.

## The acceptance demo

`examples/sensor_demo/` — the legacy example, kept as it is. A sensor manager
against a deliberately slow gateway with scripted failures: renaming to `fail`
is rejected, every second delete fails, and a setting is *accepted* before it
is *applied*, so a poll has to survive a confirmation window without stomping
the value the user asked for.

It was built to match a React client written with TanStack Query itself,
feature for feature, so that "does the port behave the same?" was a question
you could click through. The React client is gone; the checklist it defined is
in the demo's README, one widget test per row.

It is also where the four call styles are each used once, in the place each one
genuinely fits — a controller for the list two siblings share, `context.query`
per row, the mixin on the already-stateful detail screen, a select builder for
the header badge.
