---
title: Describing a query once
description: Options functions, the two observer options shapes, withSelect, what null means, and why options built in build are fine.
---

{/* depth: todo */}
{/* demo: select-and-sharing */}

# Describing a query once

A query is described by an options object: its key, its function and
whatever it configures. Put that object behind a function and every widget
that reads the query reads the same description — the Dart counterpart of
TanStack Query's `queryOptions()` helper.

## Two rules

**`null` means "not configured"** on every option field, so merging defaults
is a plain `??` per field: an option you leave unset is decided by the next
level down — the key's defaults, then the client's, then the built-in value.
See [important defaults](../important-defaults.md).

**An option with a real "off" value is a sealed value type**, never a magic
number, string or boolean — `StaleTime`, `GcTime`, `Enabled`, `RetryPolicy`,
`RetryDelay`, `RefetchOn`, `RefetchInterval`, `NetworkMode`. Each has its own
page: [caching](caching.md), [dependent queries](dependent-queries.md),
[retries](query-retries.md), [app focus](window-focus-refetching.md),
[polling](polling.md), [network mode](network-mode.md).

The computed forms come in three families, named by what they compute:
`.when(predicate)` decides yes or no (`Enabled`, `RetryPolicy`, `RefetchOn`),
`.dynamic(fn)` computes the value itself from the query or the attempt
(`StaleTime`, `RefetchInterval`, `RetryDelay`), and `.compute(fn)` produces
data (`InitialData`, `PlaceholderData`).

## Two shapes

Observer options — what every reading style takes — come in two shapes over
one sealed base:

| | type arguments | `select` |
|---|---|---|
| `QueryObserverOptions<TData>` | one: the query's data | none — the observer reports the query's data |
| `QuerySelectOptions<TQueryData, TData>` | two: the cache's data and the selection | **required** — it is what anchors `TData` |

When supplied, `queryFn` anchors the raw data type; the required `select`
anchors the selected type. `queryFn` is optional for cached or defaulted
queries: without it or an expected type, supply an explicit type argument
such as `QueryObserverOptions<Task>` to avoid inferring `dynamic` (see [type
safety in Dart](../dart-type-safety.md)). A `select` that keeps the type is
still a select and still goes on `QuerySelectOptions`.

```dart snippet="guides/query-options.md#plain guides/query-options.md#select"
QueryObserverOptions<Task> taskQuery(String id) => QueryObserverOptions(
      queryKey: taskKey(id),
      queryFn: (context) => api.getTask(id, signal: context.signal),
    );

QuerySelectOptions<Task, String> taskNameQuery(String id) => QuerySelectOptions(
      queryKey: taskKey(id),
      queryFn: (context) => api.getTask(id, signal: context.signal),
      select: (task) => task.name,
    );
```

The plain entry points (`QueryBuilder`, `context.query`, `watchQuery`,
`QueryController.create`) take the first; the select ones
(`QuerySelectBuilder`, `context.selectQuery`, `watchSelectQuery`) the second;
the general `QueryController(client, options)` takes either. Infinite queries
mirror this — see [infinite queries](infinite-queries.md).

`QueryOptions<TData>` — no observer, no `select` — is what the imperative
`client.query` takes; see [prefetching](prefetching.md).

## `withSelect`

A factory that builds the plain shape serves a projecting reader too:
`taskQuery(id).withSelect((task) => task.name)` is a `QuerySelectOptions`
with every other field kept — no copying fields by hand, and no field
forgotten when one is added. `InfiniteQueryObserverOptions.withSelect` does
the same for the paged shape. What a `select` does to rebuilds is in [what
rebuilds, and when](render-optimizations.md).

## Options built in `build` are fine

A computed option — `Enabled.when`, `StaleTime.dynamic`, a `select` — is
equal to another when its function is. Two tear-offs of one top-level, static
or instance method compare equal, and a `const` value is one value; a closure
written inline in `build` is a new function on every build, so options
carrying one never compare as unchanged.

**That costs one defaulting pass and nothing else.** The observer resolves
the defaults and compares the **defaulted** options by value; only a real
difference emits an options-updated event or triggers a fetch, and timers are
compared by their resolved values before one is touched, so an inline
`RefetchInterval.dynamic` does not reset a poll on every frame. An options
literal in `build` is not a leak and not a restart; hoisting it to a
`static final` is a small optimisation. Keep the functions stable when you
want the options themselves to read as unchanged — `select` and `queryFn`
included.

## When options are read

Retry policy, retry delay and network mode are captured when a fetch or
mutation run starts; replacing them during that run affects the next one. A
dynamic callback still reads whatever it closes over each time it is called.

An imperative `client.query` hands its options to the cache entry, as an
observer does: an explicit `retry` in them stays with the query for later
refetches. See [prefetching](prefetching.md).
