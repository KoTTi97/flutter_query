---
title: Options
sidebar_position: 2
description: Sealed option value types — StaleTime, GcTime, Enabled, RetryPolicy, RefetchOn, RefetchInterval — and what null means.
---

# Options

Two rules explain nearly the whole surface.

**`null` means "not configured"** on every option field, so merging defaults is
a plain `??` per field. That frees `null` from ever meaning "off".

**An option with a real "off" value is a sealed value type**, never a magic
number, string or boolean. `staleTime: 0`, `staleTime: Infinity` and
`staleTime: 'static'` are three different ideas that JavaScript squeezes into
one field; here they are three constructors on one sealed class, and a
`switch` over them is exhaustive.

## Two shapes

Observer options — what every reading style takes — come in two shapes over
one sealed base (ADR-0001):

| | type arguments | `select` |
|---|---|---|
| `QueryObserverOptions<TData>` | one: the query's data | none — the observer reports the query's data |
| `QuerySelectOptions<TQueryData, TData>` | two: the cache's data and the selection | **required** — it is what anchors `TData` |

Each argument is anchored by a required parameter, so an options literal
written inline infers its types: from `queryFn` on the plain shape, from
`queryFn` and `select` on the select shape. A single type with an optional
`select` carried `TData` only in that one optional field, and a literal
without it silently became `Query<dynamic>` in the cache. A `select` that
keeps the type is still a select and still goes on `QuerySelectOptions`.

```dart
QueryObserverOptions<Task> taskQuery(String id) => QueryObserverOptions(
      queryKey: taskKey(id),
      queryFn: (context) => api.getTask(id, signal: context.signal),
    );

QuerySelectOptions<Task, String> taskNameQuery(String id) =>
    QuerySelectOptions(
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

## Staleness

`StaleTime` decides whether cached data counts as fresh. Fresh data is
returned without a fetch; stale data is returned *and* refetched behind it.

| | |
|---|---|
| `StaleTime.zero` | stale immediately — the default, as upstream |
| `StaleTime.duration(d)` | fresh for `d` |
| `StaleTime.infinite` | never stale by time, still refetched when explicitly asked |
| `StaleTime.static` | never stale **and** skipped by every refetch trigger — mount, focus, reconnect, `invalidateQueries`, `refetchQueries` — but not by an observer's own `refetch()`, and not by an explicit `refetchInterval`, which polls a static query exactly as it polls any other |
| `StaleTime.dynamic((query) => …)` | computed per query |

`StaleTime.static` is the "fetch this once, ever" option — it is what
`prefetch only if nothing is cached` means.

## Garbage collection

`GcTime` is how long an entry with no observers is kept before it is dropped.

| | |
|---|---|
| `GcTime.duration(d)` | drop `d` after the last observer leaves |
| `GcTime.defaultValue` | five minutes, as upstream |
| `GcTime.never` | keep forever |

A client owns its gc timers, which is why a widget test has to
[clear it](testing.md).

## Enabled

| | |
|---|---|
| `Enabled.yes` / `Enabled.no` | constants, not constructors |
| `Enabled.when((query) => …)` | computed — this is the dependent-query tool |

```dart
QueryObserverOptions<List<Comment>>(
  queryKey: QueryKey(<Object?>['posts', postId, 'comments']),
  queryFn: (context) => api.comments(postId!),
  enabled: postId == null ? Enabled.no : Enabled.yes,
)
```

A disabled query does not fetch, stays `pending`, and keeps whatever it has
cached. Upstream's `skipToken` is `Enabled.no`.

## Retries

| | |
|---|---|
| `RetryPolicy.never` / `RetryPolicy.always` | constants |
| `RetryPolicy.times(n)` | |
| `RetryPolicy.when((failureCount, error, stackTrace) => …)` | |
| `RetryDelay.exponential()` | the default backoff: 1 s, 2 s, 4 s, … capped |
| `RetryDelay.fixed(d)` | |
| `RetryDelay.dynamic((failureCount, error) => …)` | computed per failure |

The computed forms come in three families, named by what they compute:
`.when(predicate)` decides yes or no (`Enabled`, `RetryPolicy`, `RefetchOn`),
`.dynamic(fn)` computes the value itself from the query or the attempt
(`StaleTime`, `RefetchInterval`, `RetryDelay`), and `.compute(fn)` produces
data (`InitialData`, `PlaceholderData`).

A computed form is equal to another when its function is. Two tear-offs of
one top-level, static or instance method compare equal, and a `const` value
is one value; a closure written inline in `build` is a new function on every
build, so options carrying one never compare as unchanged — every rebuild is
a `setOptions`. That costs an options-updated event, not a restart: the
observer compares the *resolved* values before it touches a timer, so an
inline `StaleTime.dynamic` or `RefetchInterval.dynamic` does not reset a poll
on every frame. Keep the functions stable when you want the options to read
as unchanged — `select` and `queryFn` included.

While a query is retrying, `failureCount` and `failureReason` are on the
result, so the UI can say "attempt 2 of 3" without owning a counter. A
`MissingQueryFunctionError` is never retried — there is nothing to retry.

## Refetch triggers

`RefetchOn` covers `refetchOnMount`, `refetchOnWindowFocus` and
`refetchOnReconnect`:

| | |
|---|---|
| `RefetchOn.never` | |
| `RefetchOn.ifStale` | upstream's `true` |
| `RefetchOn.always` | upstream's `'always'` |
| `RefetchOn.when((query) => …)` | |

`RefetchInterval` is polling:

| | |
|---|---|
| `RefetchInterval.off` | |
| `RefetchInterval.every(d)` | |
| `RefetchInterval.dynamic((query) => …)` | stop by returning `off` |

`refetchIntervalInBackground` keeps a poll running while the app is not
focused; by default it stops.

## Initial and placeholder data

Different things, and the difference is whether the cache believes it.

**`InitialData`** is written to the cache and is indistinguishable from a fetch
result. It has an age, so it can already be stale:

| | |
|---|---|
| `InitialData.value(v)` | |
| `InitialData.compute(() => …)` | returning `null` means "none"; `InitialData.value(null)` is a value *of* `null` |
| `initialDataUpdatedAt: DateTime?` | how old it is; `null` means now |
| `initialDataUpdatedAtCompute: () => DateTime?` | the lazy form, evaluated only when the data is actually seeded. Give one form or the other, never both |

**`PlaceholderData`** is never written to the cache. It is what a reader sees
while the real fetch runs, and `result.isPlaceholderData` says so:

| | |
|---|---|
| `PlaceholderData.value(v)` | |
| `PlaceholderData.compute((previous, previousQuery) => …)` | |
| `const PlaceholderData.keepPrevious()` | upstream's `keepPreviousData` |

`keepPrevious` needs the observer to survive the key change — in the mixin and
context styles that means giving the read an
[`id:`](reading-a-query.md#querymixin).

## Network mode

`NetworkMode.online` (the default), `always`, `offlineFirst`. See
[offline](lifecycle-and-connectivity.md#network-mode).

## Structural sharing

On by default, and it is what makes `select` and `buildWhen` worth having: if
a refetch brings back data equal to what is cached, the *same instances* are
kept, so `==` downstream stays true and nothing rebuilds unnecessarily.

Lists are shared element by element; maps and sets are kept whole when deeply
equal; everything else is compared with `==`. **A typed model therefore needs
`==` and `hashCode`** — without them every fetch produces a new value.

```dart
structuralSharing: (previous, next) => next,   // upstream's `false`
```

## Where each one is on screen

Every option above has a screen in the [showcase](../project/examples.md) that
exercises it against a real backend — `stale-and-gc`, `retry`,
`focus-refetch`, `auto-refetching`, `initial-and-placeholder`,
`dependent-queries`, `offline`, `select-and-sharing`. The JavaScript name for
each is in [the name map](../reference/coming-from-react-query.md#options).
