---
title: Examples
description: Every feature as a screen of the showcase app, against a real backend — and one whole small app that composes them.
---

{/* depth: todo */}

# Examples

The repository has two example apps, both runnable on the web and on a
device, both against a small backend of their own.

## The showcase

[`examples/showcase/`](https://github.com/KoTTi97/flutter_query/tree/main/examples/showcase)
has **every feature as its own screen** — thirty of them. Each screen shows
its cache entries' state as it changes, and has knobs to make the backend slow
or fail.

```bash
cd examples/showcase/server && npm install && npm run dev
```

```bash
cd examples/showcase && flutter run -d chrome
```

### Reading

| Screen | Shows | Guide |
|---|---|---|
| `simple` | one query, the three states | [Queries](../guides/queries.md) |
| `basic` | a list and a detail sharing a cache | [Quick start](../quick-start.md) |
| `default-query-function` | one function for a family of keys | [Default query function](../guides/default-query-function.md) |
| `dependent-queries` | a query waiting for another's result | [Dependent queries](../guides/dependent-queries.md) |
| `parallel-queries` | independent reads side by side | [Parallel queries](../guides/parallel-queries.md) |
| `query-collections` | a list of queries that grows, shrinks and reorders | [Parallel queries](../guides/parallel-queries.md) |
| `combine` | three queries of three types as one result | [Combining queries](../guides/combining-queries.md) |
| `prefetching` | fetching before the screen asks | [Prefetching](../guides/prefetching.md) |
| `select-and-sharing` | what `select` and structural sharing keep | [Structural sharing](../guides/structural-sharing.md) |
| `build-when` | every read with and without `buildWhen` | [What rebuilds, and when](../guides/render-optimizations.md) |
| `initial-and-placeholder` | initial data against placeholder data | [Placeholder query data](../guides/placeholder-query-data.md) |
| `stale-and-gc` | fresh, stale and collected entries | [Caching](../guides/caching.md) |

### Paging

| Screen | Shows | Guide |
|---|---|---|
| `pagination` | page numbers with the previous page kept | [Paginated queries](../guides/paginated-queries.md) |
| `load-more` | append on scroll, and the cache across navigation | [Infinite queries](../guides/infinite-queries.md) |
| `max-pages` | both directions with `maxPages: 3` | [Infinite queries](../guides/infinite-queries.md) |

### Writing

| Screen | Shows | Guide |
|---|---|---|
| `mutations` | a write, its states and the invalidation after it | [Mutations](../guides/mutations.md) |
| `optimistic-updates` | both optimistic shapes, with rollback | [Optimistic updates](../guides/optimistic-updates.md) |
| `mutation-state` | every write in flight, from the cache | [Mutation state](../guides/mutation-state.md) |
| `mutation-cancel` | cancelling a write, and what the rollback does | [Cancelling mutations](../guides/cancelling-mutations.md) |
| `playground` | every mutation option on one screen | [Optimistic updates](../guides/optimistic-updates.md) |
| `invalidation-and-filters` | prefix, exact and predicate filters | [Query invalidation](../guides/query-invalidation.md) |
| `global-callbacks` | the caches' callbacks and a toast | [Global callbacks](../guides/global-callbacks.md) |

### Runtime

| Screen | Shows | Guide |
|---|---|---|
| `auto-refetching` | polling, and stopping it | [Polling](../guides/polling.md) |
| `retry` | retries, backoff and `failureCount` | [Query retries](../guides/query-retries.md) |
| `cancellation` | a fetch cancelled mid-flight | [Query cancellation](../guides/query-cancellation.md) |
| `offline` | the online toggle, paused mutations and resuming | [Network mode](../guides/network-mode.md) |
| `focus-refetch` | every `RefetchOn` value on app focus | [App focus refetching](../guides/window-focus-refetching.md) |
| `four-call-styles` | the four ways to read, on one key | [Four ways to read a query](../guides/reading-queries-in-widgets.md) |
| `cache-inspector` | every cache entry and its state | [Debugging](../guides/debugging.md) |
| `diagnostics` | the errors and debug assertions the library raises | [Type safety in Dart](../dart-type-safety.md) |

No screen presents one of the four call styles as the default; across the
catalogue each is used in its turn.

## The task manager

[`examples/task_manager/`](https://github.com/KoTTi97/flutter_query/tree/main/examples/task_manager)
is one ordinary app — a small to-do list — against a deliberately slow
backend with scripted failures. Where the showcase lets you look a feature up,
this shows how six of them compose: a list two siblings share, a detail
screen, optimistic writes with rollback, and a reminder that is *accepted*
before it is *confirmed*, so a poll has to survive the wait.

```bash
cd examples/task_manager/server && npm install && npm run dev
```

```bash
cd examples/task_manager && flutter run -d chrome
```

## The one-file tour

[`packages/query_kit_flutter/example/`](https://github.com/KoTTi97/flutter_query/tree/main/packages/query_kit_flutter/example)
is a provider, one query read two ways and a mutation that invalidates it,
with no server at all. It is what pub.dev shows on the package page.

How all three are tested is on [how the examples are
built](../project/examples.md).
