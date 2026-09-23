---
title: Describing a query once
description: Options functions, the two observer options shapes, withSelect, what null means, and why options built in build are fine.
---

# Describing a query once

A query read in three places is easy to describe three ways: one screen
forgets the `staleTime`, another spells the key slightly differently, a
prefetch uses a function the screen has since stopped using. Each difference
is a second cache entry or a refetch nobody asked for.

So a query is described by an options object — its key, its function and
whatever it configures — and that object lives behind a function. Every
widget that reads the query, every prefetch and every test calls the same
function and gets the same description.

## Two rules

**`null` means "not configured"** on every option field, so merging defaults
is a plain `??` per field: an option you leave unset is decided by the next
level down — the key's defaults, then the client's, then the built-in value.
See [important defaults](../important-defaults.md).

**An option with modes is a sealed value type**, never a magic number,
string or boolean — `StaleTime`, `GcTime`, `Enabled`, `RetryPolicy`,
`RetryDelay`, `RefetchOn`, `RefetchInterval`; `NetworkMode`, a closed set
of three, is an enum. Each has its own
page: [caching](caching.md), [dependent queries](dependent-queries.md),
[retries](query-retries.md), [app focus](window-focus-refetching.md),
[polling](polling.md), [network mode](network-mode.md).

The computed forms come in three families, named by what they compute:
`.when(fn)` decides per query or per failure — yes or no for `Enabled` and
`RetryPolicy`, a `RefetchOn` value for `RefetchOn` —
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

A factory that builds the plain shape serves a projecting reader too.
`withSelect` turns it into a `QuerySelectOptions` with every other field
kept — no copying fields by hand, and no field forgotten when one is added:

```dart snippet="guides/query-options.md#with-select"
// The name only: this label rebuilds when the name changes, not when the
// device is switched on or off.
final name = context.selectQuery(
  deviceQuery(id).withSelect((device) => device.name),
);
```

Both readers share one cache entry and one request; only what each is told
about differs. `InfiniteQueryObserverOptions.withSelect` does the same for
the paged shape. What a `select` does to rebuilds is in [what rebuilds, and
when](render-optimizations.md).

The showcase's *select and sharing* screen puts five readers on one list of
todos — four with a `select`, one without — each with a `data builds` count.
Press *Refetch*: the server sends the same list, and no `data builds` count
moves. *Toggle todo 1* moves only the reader that selects done and open
counts, and the one without a `select`. Switch *Structural sharing off* and
press *Refetch* again: now the reader without a `select` gets a new list
every time:

<LiveDemo feature="select-and-sharing" height={720} />

## One description, many uses

The same function that a screen reads is what the client takes for a
prefetch — `QueryObserverOptions` is a `QueryOptions`, so no second
description is needed:

```dart snippet="guides/query-options.md#prefetch"
// The same options, handed to the client: warm the detail before the
// detail screen opens. A second reader within staleTime fetches nothing.
Future<void> prefetchDevice(QueryClient client, String id) =>
    client.query(deviceQuery(id));
```

And its key is what a mutation invalidates, so the three can never disagree
about which entry they mean. See [prefetching](prefetching.md) and
[invalidations from mutations](invalidations-from-mutations.md).

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

## Traps

- **A literal per widget.** Two widgets that build their own options for one
  key share an entry, but whichever mounted last set its `gcTime`, and each
  refetches by its own `staleTime`. One function per query ends that.
- **The same key with two data types.** A projection of a key's data is a
  `select`, not a second options function that fetches into the same key
  with another type — that one throws `QueryDataTypeError`.
- **Expecting an inline `select` to be skipped.** A new closure is a new
  function, so it runs again on the next result. That is correct and cheap
  for a projection; hoist it to a top-level or static function only when it
  is expensive.

:::note[In React Query]
This is the `queryOptions()` helper, made the only way: there is no
positional `useQuery(key, fn)` form. `select` moves into its own options
shape so its second type argument can be inferred, and `withSelect` adds one
to an existing description. See [differences from TanStack
Query](../reference/differences-from-tanstack.md).
:::
