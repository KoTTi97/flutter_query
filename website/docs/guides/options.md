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

When supplied, `queryFn` anchors the raw data type; the required `select`
anchors the selected type. `queryFn` is optional for cached or defaulted
queries: without it or an expected type, supply an explicit type argument
such as `QueryObserverOptions<Task>` to avoid inferring `dynamic`.
A single type with an optional
`select` carried `TData` only in that one optional field, and a literal
without it silently became `Query<dynamic>` in the cache. A `select` that
keeps the type is still a select and still goes on `QuerySelectOptions`.

```dart snippet="guides/options.md#plain guides/options.md#select"
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

## Staleness

`StaleTime` decides whether cached data counts as fresh. Fresh data is
returned without a fetch; stale data is returned *and* refetched behind it.

| | |
|---|---|
| `StaleTime.zero` | stale immediately — the default, as upstream |
| `StaleTime.duration(d)` | fresh for `d` |
| `StaleTime.infinite` | never stale by time, still refetched when explicitly asked |
| `StaleTime.static` | never stale **and**, while an observer holds the query, skipped by every refetch trigger — mount, focus, reconnect, `invalidateQueries`, `refetchQueries` — but not by an observer's own `refetch()`, and not by an explicit `refetchInterval`, which polls a static query exactly as it polls any other. An entry nobody observes (fetched by `client.query`, say) is refetched by `invalidateQueries` and `refetchQueries` like any other, as upstream |
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

```dart snippet="guides/options.md#enabled"
QueryObserverOptions<List<Comment>> commentsQuery(
  String? postId,
) =>
    QueryObserverOptions(
      queryKey: QueryKey(<Object?>['posts', postId, 'comments']),
      queryFn: (context) => api.comments(postId!),
      enabled: postId == null ? Enabled.no : Enabled.yes,
    );
```

A disabled query does not fetch automatically and keeps its cached or initial
data. Without data it is `pending`; existing successful data stays successful.
Explicit `refetch()` can still fetch. `refetchQueries` and
`invalidateQueries(refetchType: RefetchType.all)` skip a query while a
disabled observer holds it, but once nothing observes a query that has
fetched before, they refetch it whatever `enabled` its last observer had — as
upstream does for `enabled: false`. Upstream's `skipToken` is `Enabled.no` too,
with `enabled: false`'s meaning where the two differ: upstream would skip an
unobserved `skipToken` query there, and this port does not.

## Retries

| | |
|---|---|
| `RetryPolicy.never` / `RetryPolicy.always` | constants |
| `RetryPolicy.times(n)` | |
| `RetryPolicy.when((failureCount, error, stackTrace) => …)` | |
| `RetryDelay.exponential()` | the default backoff: 1 s, 2 s, 4 s, … capped |
| `RetryDelay.fixed(d)` | |
| `RetryDelay.dynamic((failureCount, error) => …)` | computed per failure |

Retry policy, retry delay and network mode are captured when a fetch or
mutation run starts. Replacing an option during that run affects a later run;
a dynamic callback still reads its closed-over application state each time it
is invoked. A mutation's function is read per attempt, and its completion
callbacks are read when invoked. Its scope stays fixed through settlement.

An imperative `client.query` without an explicit or default retry policy makes
one attempt and preserves the cache entry's existing retry policy for later
refetches. An explicitly configured policy replaces it. Other query options
follow the last installed options; each observer owns its presentation options.

The computed forms come in three families, named by what they compute:
`.when(predicate)` decides yes or no (`Enabled`, `RetryPolicy`, `RefetchOn`),
`.dynamic(fn)` computes the value itself from the query or the attempt
(`StaleTime`, `RefetchInterval`, `RetryDelay`), and `.compute(fn)` produces
data (`InitialData`, `PlaceholderData`).

A computed form is equal to another when its function is. Two tear-offs of
one top-level, static or instance method compare equal, and a `const` value
is one value; a closure written inline in `build` is a new function on every
build, so options carrying one never compare as unchanged — every rebuild is
a `setOptions`.

**That costs one defaulting pass and nothing else.** The comparison that
decides whether anything happens is one layer down and is by value:
`setOptions` resolves the defaults first and compares the **defaulted**
options, and only a real difference emits an options-updated event or triggers
a fetch. Timers go further still — the observer compares the *resolved* values
before it touches one, so an inline `StaleTime.dynamic` or
`RefetchInterval.dynamic` does not reset a poll on every frame. So an options
literal written inline in `build` is not a leak and not a restart; hoisting it
to a `static final` is a real optimisation, and a small one. Keep the
functions stable when you want the options themselves to read as unchanged —
`select` and `queryFn` included.

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
| `RefetchInterval.dynamic((query) => …)` | return a `Duration`, or `null` to stop |

`refetchIntervalInBackground` keeps a poll running while the app is not
focused; by default it stops.

## Initial and placeholder data

Different things, and the difference is whether the cache believes it.

**`InitialData`** is written to the cache and is indistinguishable from a fetch
result. It has an age, so it can already be stale:

| | |
|---|---|
| `InitialData.value(v)` | |
| `InitialData.compute(() => …)` | returning `null` means "none"; `InitialData.value(null)` is a value *of* `null`. Asked again on every rebuild and every fetch until the entry holds data — as upstream — so a seed it finds later still lands; keep it cheap, or memoise it |
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

A set is compared by its members' `==` and `hashCode`, never by the
comparator or `equals:` it was built with, so a case-insensitive set still
reports `'Alpha'` becoming `'alpha'`. That costs about a millisecond and a half
a write for 10 000 members and roughly a frame for 100 000; for a set that
large, `noStructuralSharing()` skips the comparison.

To turn it off — upstream's `structuralSharing: false`:

```dart snippet="guides/options.md#structural-sharing"
structuralSharing: noStructuralSharing(), // upstream's `false`
```

That turns sharing off everywhere: for the cache write, for placeholder data
and for what `select` produces, so a selector that returns a fresh list every
time then counts as a change on every fetch.

A function of your own, `(previous, next) => …`, replaces the default for the
cache write and placeholder data only. It cannot be handed a selection —
it is typed for the query's data, and a selection can be another type — so
what `select` produces is still shared by the default comparison. That is
also true of `(_, next) => next`: it keeps every write, but it is not the
opt-out, and a selection over it stays shared. Use `noStructuralSharing()`
when you mean off.

## Where each one is on screen

Every option above has a screen in the [showcase](../project/examples.md) that
exercises it against a real backend — `stale-and-gc`, `retry`,
`focus-refetch`, `auto-refetching`, `initial-and-placeholder`,
`dependent-queries`, `offline`, `select-and-sharing`. The JavaScript name for
each is in [the name map](../reference/coming-from-react-query.md#options).
