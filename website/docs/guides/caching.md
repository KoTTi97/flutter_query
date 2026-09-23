---
title: Caching
description: How long data is fresh (StaleTime), how long an unobserved entry is kept (GcTime), and what happens to a query from first read to garbage collection.
---

{/* depth: todo */}
{/* demo: stale-and-gc, cache-inspector */}

# Caching

Two options decide the life of a cache entry: how long its data counts as
**fresh**, and how long the entry is **kept** once nothing reads it.

## A query's life, with the defaults

1. A widget reads `['tasks']` for the first time. Nothing is cached: the
   result is `pending`, and the query function runs.
2. The data arrives and is cached under `['tasks']`. With the default
   `staleTime`, it is **stale at once**.
3. A second widget reads `['tasks']`. It gets the cached data immediately, and
   because the data is stale, a refetch runs behind it. Both widgets see the
   new data when it lands.
4. Both widgets go. The entry has no observers, so its **garbage-collection
   timer** starts: five minutes by default.
5. Another read within those five minutes gets the cached data at once, and a
   refetch behind it.
6. Nobody reads it for five minutes: the entry is dropped. The next read
   starts from step 1.

## Staleness

`StaleTime` decides whether cached data counts as fresh. Fresh data is
returned without a fetch; stale data is returned *and* refetched behind it —
on mount, on [app focus](window-focus-refetching.md) and on reconnect.

| | |
|---|---|
| `StaleTime.zero` | stale immediately — the default |
| `StaleTime.duration(d)` | fresh for `d` after it was fetched |
| `StaleTime.infinite` | never stale by time, still refetched when explicitly asked |
| `StaleTime.static` | never stale **and**, while an observer holds the query, skipped by every refetch trigger — mount, focus, reconnect, `invalidateQueries`, `refetchQueries` — but not by an observer's own `refetch()`, and not by an explicit `refetchInterval`. An entry nobody observes is refetched by `invalidateQueries` and `refetchQueries` like any other |
| `StaleTime.dynamic((query) => …)` | computed per query, from its current state |

`StaleTime.static` is the "fetch this once, ever" option. A dynamic stale time
is asked several times per operation; keep its function cheap and free of side
effects.

An [invalidation](query-invalidation.md) marks data stale whatever its
`staleTime` says.

## Garbage collection

`GcTime` is how long an entry with no observers is kept before it is dropped.

| | |
|---|---|
| `GcTime.duration(d)` | drop `d` after the last observer leaves |
| `GcTime.defaultValue` | five minutes |
| `GcTime.never` | keep forever |

A client owns its garbage-collection timers, which is why a widget test has to
[clear it](testing.md) before the test ends.

## Seeing it

The `stale-and-gc` screen shows fresh, stale and collected entries side by
side, and `cache-inspector` lists every entry of the cache with its status;
see [examples](../examples/index.md). For your own app, see
[debugging](debugging.md).
