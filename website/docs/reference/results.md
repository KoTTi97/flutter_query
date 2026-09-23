---
title: Results
description: Every field of what a reader is handed — QueryResult and its cases, QueryState, InfiniteData and the paging flags, MutationResult and MutationState, and CombinedResult.
---

# Results

A reader never gets a bag of booleans. It gets a sealed value: a
`QueryResult<T>` for a query, a `MutationResult<TData, TVariables>` for a
mutation, a `CombinedResult<T>` for several queries read together. A
`switch` over one is exhaustive, and each case carries exactly the fields
that exist in it. This page lists every field and getter and which case carries
it. A TanStack Query name is given only where it differs from the Dart one,
and a member with no counterpart there says so.

Where a result comes from — an observer's `currentResult`, a controller's
`value`, a builder's argument — is on [widgets and
controllers](widgets-and-controllers.md) and [caches and
observers](caches-and-observers.md). For where the two libraries behave
differently, see [differences from
TanStack Query](/docs/reference/differences-from-tanstack).

## QueryResult

[`QueryResult<TData>`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult-class.html)
is what every query observer hands out, and a new one whenever something it
reports changes. It is sealed, with three cases:

| Case | When |
|---|---|
| [`QueryPending`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryPending-class.html) | Nothing has resolved: no data, no error. The first load; a query without data fetching again after a failure; a query after a reset; a disabled query that has never fetched (then `fetchStatus` is `idle`). |
| [`QuerySuccess`](https://pub.dev/documentation/query_kit/latest/query_kit/QuerySuccess-class.html) | The query holds `data`: fetched, seeded with `initialData`, written with `setQueryData`, or a placeholder. May be fetching at the same time — a background refresh. |
| [`QueryError`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryError-class.html) | The last fetch failed after its retries, or the observer's `select` threw. Data from an earlier success stays in `staleData`. |

What the query *holds* is the case. What it is *doing* is `fetchStatus` and
the flags derived from it, which vary independently of the case. See
[queries](../guides/queries.md) for how the two axes combine.

### Fields and getters

"All" means the field is declared on `QueryResult` and every case carries it.

| Name | Type | On which cases | Meaning |
|---|---|---|---|
| [`status`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/status.html) | `QueryStatus` | all | The case, as an enum: `pending`, `success` or `error`. For storing or comparing rather than matching. |
| [`fetchStatus`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/fetchStatus.html) | `FetchStatus` | all | What the query is doing: `fetching`, `paused` or `idle`. |
| [`isPending`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/isPending.html) | `bool` | all | This is a `QueryPending`. |
| [`isSuccess`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/isSuccess.html) | `bool` | all | This is a `QuerySuccess`, whether or not a refresh is running. |
| [`isError`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/isError.html) | `bool` | all | This is a `QueryError`. |
| [`isFetching`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/isFetching.html) | `bool` | all | `fetchStatus` is `fetching`: a first load or a refetch is in flight. |
| [`isPaused`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/isPaused.html) | `bool` | all | `fetchStatus` is `paused`: a fetch wants to run but waits for the network (per `networkMode`) or for the app to return to the foreground before its next retry. |
| [`isLoading`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/isLoading.html) | `bool` | all | Pending **and** fetching: the first load. False for a pending query that is not fetching, such as a disabled one. |
| [`isRefetching`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/isRefetching.html) | `bool` | all | Fetching and **not** pending: a background refresh of data on screen, including data still held after a failed refetch. A query without data that fetches again is pending, so this is false. |
| [`dataOrNull`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/dataOrNull.html) | `TData?` | all | `data` on a success, `staleData` on an error, `null` when pending. TanStack: `data`. |
| [`errorOrNull`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/errorOrNull.html) | `Object?` | all | `error` on a `QueryError`, `null` otherwise. TanStack: `error`. |
| [`data`](https://pub.dev/documentation/query_kit/latest/query_kit/QuerySuccess/data.html) | `TData` | `QuerySuccess` | The data, after `select` when the observer has one. A placeholder when `isPlaceholderData` is true. |
| [`error`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryError/error.html) | `Object` | `QueryError` | What the last attempt of the failed fetch threw, or what `select` threw. A cancelled fetch that was not reverted fails with a `CancelledError`. |
| [`stackTrace`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryError/stackTrace.html) | `StackTrace` | `QueryError` | Where `error` was thrown. No TanStack counterpart. |
| [`staleData`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryError/staleData.html) | `TData?` | `QueryError` | The data from the last successful fetch or write, kept through the error; `null` when there was none. TanStack: `data`, in the error state. |
| [`hasStaleData`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryError/hasStaleData.html) | `bool` | `QueryError` | Whether `staleData` means anything. Tells a real `null` from none when `TData` is nullable. No TanStack counterpart. |
| [`isLoadingError`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryError/isLoadingError.html) | `bool` | `QueryError` | The first load failed; there is nothing to show (`!hasStaleData`). |
| [`isRefetchError`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryError/isRefetchError.html) | `bool` | `QueryError` | A refetch failed over data that is still on screen (`hasStaleData`). |
| [`dataUpdatedAt`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/dataUpdatedAt.html) | `DateTime?` | all | When the data was last written, by a fetch or by hand — what `staleTime` counts from. `null` until something has been. |
| [`errorUpdatedAt`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/errorUpdatedAt.html) | `DateTime?` | all | When the query last ended in an error (or `select` last threw). Not cleared by a later success. |
| [`failureCount`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/failureCount.html) | `int` | all | Failed attempts within the current fetch. Reset when a new fetch starts. |
| [`failureReason`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/failureReason.html) | `Object?` | all | What the latest failed attempt threw. Kept while retries continue and after the fetch finally fails; cleared when the next fetch starts or an attempt succeeds. |
| [`failureStackTrace`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/failureStackTrace.html) | `StackTrace?` | all | The stack trace of `failureReason`; `null` whenever it is. No TanStack counterpart. |
| [`errorUpdateCount`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/errorUpdateCount.html) | `int` | all | How many times the query has ended in an error over its whole life. Never goes down. |
| [`consecutiveErrorCount`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/consecutiveErrorCount.html) | `int` | all | Fetches in a row that ended in an error. Back to zero with the next *fetched* data; a manual write and a cancelled fetch leave it alone. See [polling](../guides/polling.md). No TanStack counterpart. |
| [`isStale`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/isStale.html) | `bool` | all | The data is older than this observer's `staleTime`, or was invalidated. A query with no data is stale; a disabled one never is. `StaleTime.static` data is never stale, invalidated or not. |
| [`isEnabled`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/isEnabled.html) | `bool` | all | This observer's `enabled` currently lets the query fetch on its own. `refetch` runs regardless. |
| [`isFetched`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/isFetched.html) | `bool` | all | Anything has ever been fetched or written, successfully or not. |
| [`isFetchedAfterMount`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/isFetchedAfterMount.html) | `bool` | all | A fetch or write has completed since this observer attached, as opposed to data already in the cache. |
| [`isPlaceholderData`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/isPlaceholderData.html) | `bool` | all (true only on `QuerySuccess`) | `data` is the observer's `placeholderData`, not cached data. See [placeholder data](../guides/placeholder-query-data.md). |
| [`refetch`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult/refetch.html) | [`QueryRefetch<TData>`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryRefetch.html) | all | `refetch({bool cancelRefetch = true})`: fetches again regardless of `enabled` and `staleTime`, and completes with the result that follows — never with an error. `cancelRefetch: true` cancels a fetch in flight on a query that holds data and starts over; a first load is joined. `false` joins the fetch in flight. |

TanStack Query's `isInitialLoading` (a deprecated alias of `isLoading`) and
`promise` have no counterpart.

:::note[A throwing select]
When the observer's `select` throws, the result is a `QueryError` carrying
what it threw, with the last value `select` produced, if any, kept in `staleData`.
The cached data is untouched, and the next successful selection clears the
error.
:::

### Equality

Results compare by value. Two results are equal when they are the same case
and carry equal data, error and fields; `refetch` and the stack traces take no
part. An unchanged result therefore compares equal to the previous one, which
is what a `buildWhen` or a `ValueListenable` relies on.

### QueryStatus and FetchStatus

[`QueryStatus`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryStatus.html)
is what the query holds; [`FetchStatus`](https://pub.dev/documentation/query_kit/latest/query_kit/FetchStatus.html)
is what it is doing. Any status combines with any fetch status.

| Enum | Value | Meaning |
|---|---|---|
| `QueryStatus` | `pending` | No data and no error: before the first fetch settles (unless `initialData` seeded the query), after a reset, and while a query without data fetches again after a failure. |
| `QueryStatus` | `success` | The query holds data, fetched or seeded. |
| `QueryStatus` | `error` | The last fetch failed and its retries are spent. Data from an earlier success is kept alongside. |
| `FetchStatus` | `fetching` | A fetch is in flight. |
| `FetchStatus` | `paused` | A fetch wants to run but cannot: offline under a `networkMode` that waits, or a retry waiting for the app to return to the foreground. See [network mode](../guides/network-mode.md). |
| `FetchStatus` | `idle` | Nothing is happening. |

TanStack Query uses the same values as strings.

## QueryState

[`QueryState<TQueryData>`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState-class.html)
is what the cache entry itself holds, before any observer's `select`,
`placeholderData` or `staleTime` applies. Read it from `Query.state` — in a
cache listener, a `QueryFilters` predicate, or a `RefetchInterval.dynamic` or
`StaleTime.dynamic` callback. It is flat rather than sealed, because the
counters survive every transition.

It is publicly constructible so that a persistence layer can restore an
entry (`QueryCache.build`, `Query.setState`). A `success` state must have
`hasData: true`, or it is rejected with an `ArgumentError`. The no-argument
constructor is the initial state: pending, idle, no data, every counter at
zero.

| Name | Type | Default | Meaning |
|---|---|---|---|
| [`status`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState/status.html) | `QueryStatus` | `pending` | What the query holds. |
| [`fetchStatus`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState/fetchStatus.html) | `FetchStatus` | `idle` | What the query is doing. |
| [`hasData`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState/hasData.html) | `bool` | `false` | Whether `data` is meaningful: true once the query has resolved to data, even `null` data; stays true through a later error. No TanStack counterpart. |
| [`data`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState/data.html) | `TQueryData?` | `null` | The cached data. Meaningful only while `hasData` is true. |
| [`dataUpdateCount`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState/dataUpdateCount.html) | `int` | `0` | How many times data has been written, by fetches and `setQueryData` alike. |
| [`dataUpdatedAt`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState/dataUpdatedAt.html) | `DateTime?` | `null` | When `data` was last written. |
| [`error`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState/error.html) | `Object?` | `null` | Why the last fetch failed. Cleared by the next success, and by the start of a new fetch on a query without data; a query with data keeps it alongside the error while it refetches. |
| [`errorStackTrace`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState/errorStackTrace.html) | `StackTrace?` | `null` | The stack trace of `error`. No TanStack counterpart. |
| [`errorUpdateCount`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState/errorUpdateCount.html) | `int` | `0` | Errors over the query's whole life. Never goes down. |
| [`consecutiveErrorCount`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState/consecutiveErrorCount.html) | `int` | `0` | Fetches in a row that failed, retries exhausted. Back to zero with the next fetched data; unchanged by a manual write or a cancelled fetch. No TanStack counterpart. |
| [`errorUpdatedAt`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState/errorUpdatedAt.html) | `DateTime?` | `null` | When the query last ended in an error. Not cleared with `error`. |
| [`fetchFailureCount`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState/fetchFailureCount.html) | `int` | `0` | Failed attempts inside the current fetch; reset when a new fetch starts. Surfaces as `QueryResult.failureCount`. |
| [`fetchFailureReason`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState/fetchFailureReason.html) | `Object?` | `null` | What the latest failed attempt threw. Surfaces as `QueryResult.failureReason`. |
| [`fetchFailureStackTrace`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState/fetchFailureStackTrace.html) | `StackTrace?` | `null` | The stack trace of `fetchFailureReason`. No TanStack counterpart. |
| [`fetchMeta`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState/fetchMeta.html) | `Object?` | `null` | Whatever the fetch behaviour attached to the current fetch. Infinite queries carry the page direction here. |
| [`isInvalidated`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState/isInvalidated.html) | `bool` | `false` | Stale regardless of `staleTime`: set by `invalidateQueries` and by a fetch that finally fails; reset by the next successful fetch or data write. |
| [`isFetched`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState/isFetched.html) | `bool` (getter) | — | `dataUpdateCount + errorUpdateCount > 0`. No TanStack counterpart. |
| [`copyWith`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState/copyWith.html) | method | — | This state with fields replaced. Pass `hasData` whenever you pass `data`; `clearData`, `clearError`, `clearFetchFailure` and `clearFetchMeta` set fields back to nothing. No TanStack counterpart. |

`QueryState` compares by value; the stack traces take no part.

## Infinite queries

An infinite query is an ordinary query whose data is an `InfiniteData`, so
its result is an ordinary `QueryResult<InfiniteData<TPageData, TPageParam>>`
(or whatever `select` makes of it). There is no separate infinite result
type. See [infinite queries](../guides/infinite-queries.md).

### InfiniteData

[`InfiniteData<TPageData, TPageParam>`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteData-class.html)

| Name | Type | Meaning |
|---|---|---|
| [`pages`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteData/pages.html) | `List<TPageData>` | The pages in order. A forward fetch appends, a backward fetch prepends, `maxPages` drops from the far end. |
| [`pageParams`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteData/pageParams.html) | `List<TPageParam>` | The param each page was fetched with, index for index with `pages`. |
| [`isEmpty`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteData/isEmpty.html) | `bool` | `pages.isEmpty`. A fetched value always holds at least one page; an empty one comes from `initialData` or `setQueryData`. No TanStack counterpart. |
| [`flatten`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteData/flatten.html) | `Iterable<TItem> flatten<TItem>()` | Every item of every page, when each page is an `Iterable<TItem>`. A page that is not throws an `ArgumentError` before iteration starts. Name the item type: without it the result is `Iterable<dynamic>`. No TanStack counterpart. |
| [`copyWith`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteData/copyWith.html) | method | This value with either list replaced. A replacement list is copied into an unmodifiable one; a list passed back unchanged keeps its identity. No TanStack counterpart. |

The constructor refuses lists of different lengths with an `ArgumentError`.
A value built by a fetch or by `copyWith` holds unmodifiable lists, so
`pages.add(…)` on fetched data read back from the cache throws
`UnsupportedError`. A value you build yourself and pass in — as `initialData` or through
`setQueryData` — can keep the growable lists you gave it until the next
fetch replaces it. Either way, write a new value with `setQueryData` rather than changing
the lists in place. Equality is element by
element over both lists.

### Paging members

`hasNextPage`, `fetchNextPage` and the direction flags are **not** on the
result. The result has one shape for every kind of query, so the paging
surface lives on
[`InfiniteQueryObserver`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryObserver-class.html)
and, in Flutter, on
[`InfiniteQueryController`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/InfiniteQueryController-class.html),
which every infinite read style hands you. A change in any of these flags
notifies listeners even when the result itself is unchanged. (TanStack Query
puts them on its infinite result object.)

| Name | Type | Meaning |
|---|---|---|
| `hasNextPage` | `bool` | `getNextPageParam` returns a param for the last page held. False before the first page arrives. |
| `hasPreviousPage` | `bool` | `getPreviousPageParam` is set and returns a param for the first page held. False before the first page arrives. |
| `isFetchingNextPage` | `bool` | The fetch in flight is a `fetchNextPage`. |
| `isFetchingPreviousPage` | `bool` | The fetch in flight is a `fetchPreviousPage`. |
| `isFetchNextPageError` | `bool` | The result is a `QueryError` that came from a `fetchNextPage`. |
| `isFetchPreviousPageError` | `bool` | The result is a `QueryError` that came from a `fetchPreviousPage`. |
| `isRefetching` | `bool` | The pages already held are being refetched. Unlike the result's own `isRefetching`, a page being added does not count. |
| `isRefetchError` | `bool` | A refetch of the held pages failed, as opposed to a page fetch. |
| `fetchNextPage` | `Future<QueryResult<TData>> fetchNextPage({bool cancelRefetch = true})` | Fetches the page after the last one and appends it. Does nothing when `hasNextPage` is false; on a query with no pages it loads the first one. Completes with the result, never with an error. |
| `fetchPreviousPage` | `Future<QueryResult<TData>> fetchPreviousPage({bool cancelRefetch = true})` | The mirror of `fetchNextPage`, prepending. |

With `cancelRefetch: true` a fetch already running on a query that holds
pages is cancelled; with `false`, or while the first page is loading, the
call joins it and adds no page. Check `isFetchingNextPage` first so a scroll
listener firing repeatedly does not cancel its own page fetch.

## MutationResult

[`MutationResult<TData, TVariables>`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationResult-class.html)
is what a `MutationObserver` reports and what every mutation read style in
Flutter hands a widget. It is sealed, with one case per `MutationStatus`:

| Case | When |
|---|---|
| [`MutationIdle`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationIdle-class.html) | Nothing submitted yet, or `reset` since. |
| [`MutationPending`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationPending-class.html) | A run is in flight — `onMutate`, the mutation function, or the settling callbacks — or paused (`isPaused`). |
| [`MutationSuccess`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationSuccess-class.html) | The last run returned, and its success callbacks have run. |
| [`MutationError`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationError-class.html) | The last run failed for good, and its error callbacks have run. A cancelled run fails with a `CancelledError`. |

See [mutations](../guides/mutations.md).

| Name | Type | On which cases | Meaning |
|---|---|---|---|
| [`status`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationResult/status.html) | `MutationStatus` | all | The case, as an enum. |
| [`isIdle`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationResult/isIdle.html) | `bool` | all | This is a `MutationIdle`. |
| [`isPending`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationResult/isPending.html) | `bool` | all | This is a `MutationPending`. Handy for disabling a submit button. |
| [`isSuccess`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationResult/isSuccess.html) | `bool` | all | This is a `MutationSuccess`. |
| [`isError`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationResult/isError.html) | `bool` | all | This is a `MutationError`. |
| [`dataOrNull`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationResult/dataOrNull.html) | `TData?` | all | `data` on a success, `null` otherwise. TanStack: `data`. |
| [`errorOrNull`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationResult/errorOrNull.html) | `Object?` | all | `error` on an error, `null` otherwise. TanStack: `error`. |
| [`data`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationSuccess/data.html) | `TData` | `MutationSuccess` | What the mutation function returned. |
| [`error`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationError/error.html) | `Object` | `MutationError` | What the last attempt threw — or what a success callback threw, which counts the same. |
| [`stackTrace`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationError/stackTrace.html) | `StackTrace` | `MutationError` | Where `error` was thrown. No TanStack counterpart. |
| [`variables`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationResult/variables.html) | `TVariables?` | all | The variables of the run in flight or last finished — what an optimistic UI shows while pending. |
| [`hasVariables`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationResult/hasVariables.html) | `bool` | all | Whether `variables` means anything: false while idle; tells a real `null` from none. No TanStack counterpart. |
| [`failureCount`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationResult/failureCount.html) | `int` | all | Failed attempts of the current run. Reset when a new run starts. |
| [`failureReason`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationResult/failureReason.html) | `Object?` | all | What the latest failed attempt threw. `null` once an attempt succeeds or a new run starts. |
| [`isPaused`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationResult/isPaused.html) | `bool` | all (set only while pending) | The run is parked: offline under `NetworkMode.online`, a retry waiting for the foreground, or queued behind another mutation in its `MutationScope`. |
| [`submittedAt`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationResult/submittedAt.html) | `DateTime?` | all | When the current run was submitted. `null` while idle. |
| [`mutate`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationResult/mutate.html) | `void Function(TVariables)` | all | Starts a new run and returns at once. Errors go to the callbacks and the next result, never to the caller. Takes only the variables, so it passes as a plain callback. |
| [`mutateAsync`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationResult/mutateAsync.html) | `Future<TData> Function(TVariables)` | all | Starts a new run; completes with its data or throws its error, once its callbacks have run. |
| [`reset`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationResult/reset.html) | `void Function()` | all | Detaches from the mutation and goes back to `MutationIdle`. The mutation keeps running and still fires its callbacks. |

Not on the result:

- **What `onMutate` returned.** It is `MutationState.onMutateResult` (below),
  handed to the `onSuccess`, `onError` and `onSettled` callbacks. TanStack
  Query's result spreads the state and so also carries it as `context`.
- **Per-call callbacks.** `MutateCallbacks` go through
  `MutationObserver.mutate(variables, callbacks: …)` or
  `MutationController.mutate`.
- **`cancel`.** It is on `MutationObserver` and `MutationController`; see
  [cancelling mutations](../guides/cancelling-mutations.md).

Results compare by value; `mutate`, `mutateAsync`, `reset` and the stack
trace take no part.

### MutationStatus

[`MutationStatus`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationStatus.html)

| Value | Meaning |
|---|---|
| `idle` | Never run, or reset since. No data, no error, no variables. |
| `pending` | Running or paused. Lasts until the run has finished, callbacks included: the cache's and the options' `onSuccess`/`onError` and `onSettled`, and the future `onSettled` returns. The per-call callbacks run after it. |
| `success` | The last run resolved; `data` holds what it returned. |
| `error` | The last run failed for good; `error` holds why. |

## MutationState

[`MutationState<TData, TVariables, TOnMutateResult>`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationState-class.html)
is what a `Mutation` in the cache holds. Read it from `Mutation.state` — in a
`MutationStateObserver`'s `select` (see [mutation
state](../guides/mutation-state.md)), a `MutationCache` listener, or
`MutationCache.findAll`. A persistence layer builds one to restore an offline
mutation through `MutationCache.build`. The no-argument constructor is the
idle state.

| Name | Type | Default | Meaning |
|---|---|---|---|
| [`status`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationState/status.html) | `MutationStatus` | `idle` | Where the mutation is in its life. |
| [`hasData`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationState/hasData.html) | `bool` | `false` | Whether `data` is authoritative, so a function that returned `null` still reads as having data. No TanStack counterpart. |
| [`data`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationState/data.html) | `TData?` | `null` | What the last successful run returned. Cleared when a new run starts and when a run fails. |
| [`error`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationState/error.html) | `Object?` | `null` | Why the last run failed; `null` unless `status` is `error`. |
| [`errorStackTrace`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationState/errorStackTrace.html) | `StackTrace?` | `null` | The stack trace of `error`. No TanStack counterpart. |
| [`variables`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationState/variables.html) | `TVariables?` | `null` | The variables of the run in flight or last finished. |
| [`hasVariables`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationState/hasVariables.html) | `bool` | `false` | Whether a run has set `variables`; a `null` value is real once this is true. No TanStack counterpart. |
| [`onMutateResult`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationState/onMutateResult.html) | `TOnMutateResult?` | `null` | What `onMutate` returned for the run in flight or last finished — the rollback handle of an optimistic update. TanStack: `context`. |
| [`failureCount`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationState/failureCount.html) | `int` | `0` | Failed attempts of the current run. Reset on success and when a new run starts; one more when the run settles in error. |
| [`failureReason`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationState/failureReason.html) | `Object?` | `null` | What the last failed attempt threw. Kept while retries continue and after the run fails; cleared on success and when a new run starts. |
| [`isPaused`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationState/isPaused.html) | `bool` | `false` | The run is parked: network, foreground, or its scope. |
| [`submittedAt`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationState/submittedAt.html) | `DateTime?` | `null` | When the current or last run was submitted. |
| [`copyWith`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationState/copyWith.html) | method | — | A copy with fields replaced; `clearData`, `clearError` and `clearFailureReason` set fields back to nothing. No TanStack counterpart. |

A restored `pending` state needs variables unless `TVariables` is nullable,
and a `success` state needs `hasData` unless `TData` is nullable or `void`;
anything else is rejected with an `ArgumentError`. `MutationState` compares
by value; `errorStackTrace` takes no part.

## CombinedResult

[`CombinedResult<T>`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedResult-class.html)
is what several `QueryResult`s amount to together, with every source's data
run through a combiner you supply. It is sealed, with three cases, decided by
these rules in order:

1. A source that is a `QueryError` **without stale data** makes the whole a
   [`CombinedError`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedError-class.html)
   — the first such source, in order. It wins over a source that is still
   loading.
2. Otherwise a `QueryPending` source makes the whole a
   [`CombinedPending`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedPending-class.html).
3. Otherwise every source has data — a success's, or the stale data of a
   failed refetch — and the whole is a
   [`CombinedData`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedData-class.html).
   A failed refetch shows up as `refetchError`, not as an error state.

The combiner runs only in the third case. See [combining
queries](../guides/combining-queries.md). TanStack Query offers the same idea
as `useQueries({ combine })`, whose return value is whatever the combiner
builds; none of the fields below has a TanStack name.

| Name | Type | On which cases | Meaning |
|---|---|---|---|
| [`isFetching`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedResult/isFetching.html) | `bool` | all | Any source is fetching. |
| [`isPaused`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedResult/isPaused.html) | `bool` | all | Any source is paused. |
| [`isPending`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedResult/isPending.html) | `bool` | all | This is a `CombinedPending`. |
| [`isError`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedResult/isError.html) | `bool` | all | This is a `CombinedError`. |
| [`hasData`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedResult/hasData.html) | `bool` | all | This is a `CombinedData`. |
| [`dataOrNull`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedResult/dataOrNull.html) | `T?` | all | The combiner's result on a `CombinedData`, `null` otherwise. |
| [`refetch`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedResult/refetch.html) | `Future<void> refetch({bool cancelRefetch = true})` | all | Refetches every source through its own `refetch`, passing `cancelRefetch` on. Two combinations sharing a source each refetch it; pass `false` to one of them to join instead. |
| [`retry`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedResult/retry.html) | `Future<void> retry({bool cancelRefetch = true})` | all | Refetches only the sources in error, an `optional()` source whose query failed included. |
| [`error`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedError/error.html) | `Object` | `CombinedError` | What the first failed source threw. |
| [`stackTrace`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedError/stackTrace.html) | `StackTrace` | `CombinedError` | The stack trace that came with `error`. |
| [`data`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedData/data.html) | `T` | `CombinedData` | What the combiner returned. |
| [`refetchError`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedData/refetchError.html) | `Object?` | `CombinedData` | What the first source whose background refetch failed threw; its stale data is part of `data`. `null` when none did. |
| [`refetchErrorStackTrace`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedData/refetchErrorStackTrace.html) | `StackTrace?` | `CombinedData` | The stack trace that came with `refetchError`. |
| [`isPlaceholderData`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedData/isPlaceholderData.html) | `bool` | `CombinedData` | Any source is showing placeholder data. |
| [`isStale`](https://pub.dev/documentation/query_kit/latest/query_kit/CombinedData/isStale.html) | `bool` | `CombinedData` | Any source's data is stale by its own `staleTime`. |

Two combined results are equal when they are the same case with equal
`isFetching`, `isPaused` and payload (the error; or the data, `refetchError`,
`isPlaceholderData` and `isStale`). The sources' `refetch` closures take no
part.

### Building one

A `CombinedResult` is never constructed directly. It comes from these
extensions, which only read the results you already have — from observers,
controllers or any read style.

| Name | On | Signature | Meaning |
|---|---|---|---|
| [`combine`](https://pub.dev/documentation/query_kit/latest/query_kit/CombineQueryResults2.html) | a record of two to six `QueryResult`s (`CombineQueryResults2` … `CombineQueryResults6`) | `combine<R>(R Function(A a, B b, …) combiner, {CombineMemo<R>? memo, List<Object?>? keys})` | Each source keeps its own data type; the combiner gets each source's data in record order. |
| [`combine`](https://pub.dev/documentation/query_kit/latest/query_kit/CombineQueryResultList.html) | `List<QueryResult<T>>` (`CombineQueryResultList`) | `combine<R>(R Function(List<T> values) combiner, {CombineMemo<R>? memo, List<Object?>? keys})` | The same rules over a list of one type, such as a `QueriesObserver`'s results. An empty list is data. |
| [`combineWith`](https://pub.dev/documentation/query_kit/latest/query_kit/CombineQueryResultList/combineWith.html) | `List<QueryResult<T>>` | `combineWith<A, R>(QueryResult<A> other, R Function(List<T> values, A other) combiner, {CombineMemo<R>? memo, List<Object?>? keys})` | The list plus one source of another type — typically the query the list was derived from — as one combination, `other` first in order. |
| [`optional`](https://pub.dev/documentation/query_kit/latest/query_kit/OptionalQueryResult/optional.html) | `QueryResult<T>` (`OptionalQueryResult`) | `QueryResult<T?> optional()` | Marks a source the combination must neither wait for nor fail with. With data it is the result itself; without, a `QuerySuccess` holding `null` with the same `fetchStatus` and `refetch`, so `isFetching` and `retry()` still see it. |

Past six sources, combine a list typed by what the sources have in common —
`<QueryResult<Object?>>[…]` at worst — and cast in the combiner. A
`CombinedResult` is not itself a source, so combinations do not nest.

### CombineMemo and keys

[`CombineMemo<T>`](https://pub.dev/documentation/query_kit/latest/query_kit/CombineMemo-class.html)
remembers the last combination. Keep one per call site (a `State` field, for
example) and pass it as `memo:`. The combiner is then skipped while every
source's data is the **identical** instance it was last time — the normal case
for a refetch that changed nothing, thanks to [structural
sharing](../guides/structural-sharing.md) — and when it does run, its output is
structurally shared with the previous one.

A memo cannot see what the combiner captures. With a memo, the combiner must
be a function of the sources and of `keys` alone: name everything else it
reads in `keys:` (compared with `==`), or do that work after `combine`.
`keys` without a `memo` does nothing.
