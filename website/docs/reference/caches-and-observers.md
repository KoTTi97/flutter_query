---
title: Caches and observers
description: The query and mutation caches, their entries and events, the five observers, the filters that select entries, and the three managers — every public member a user touches.
---

# Caches and observers

A `QueryClient` owns two caches — one `Query` per key, one `Mutation` per
run — and three managers that tell it about focus, connectivity and when to
deliver notifications. Observers are what follow an entry and report it as a
result. Most code reaches all of this through the client and the widgets;
this page is for when you go underneath them: global callbacks, logging,
devtools of your own, a [pure-Dart](../guides/pure-dart.md) program.

A TanStack Query name is given only where it differs from the Dart one, and
a member with no counterpart there says so. Where a member behaves
differently, the row says how; the full list is in [differences from TanStack Query](/docs/reference/differences-from-tanstack).

## `QueryCache`

[`QueryCache`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryCache-class.html)
holds every query of one client under its `QueryKey`. `QueryClient()` makes
an empty one; pass your own as `QueryClient(queryCache: …)` to install the
cache-wide callbacks. It is reachable as `client.queryCache`.

### Constructor

`QueryCache({onSuccess, onError, onSettled})`. All three are optional and
final — there is no setter to swap one later. A handler that has to change
while the app runs closes over something you own. See
[global callbacks](../guides/global-callbacks.md).

| Callback | Signature | Default | Meaning |
|---|---|---|---|
| `onSuccess` | `void Function(Object? data, Query<Object?> query)` | unset | Runs once per successful fetch, however many observers share it, after the data is in the cache. A manual write (`setQueryData`) does not run it. |
| `onError` | `void Function(Object error, StackTrace stackTrace, Query<Object?> query)` | unset | Runs once per fetch that fails for good (retries exhausted), after the error is in the query's state. Data from an earlier success is still in `query.state.data`, which tells a failed background refresh from a failed first load. A cancel that is neither silent nor reverting runs it with a `CancelledError`. |
| `onSettled` | `void Function(Object? data, Object? error, StackTrace? stackTrace, Query<Object?> query)` | unset | Runs right after `onSuccess` or `onError`, once per fetch. After a failure `data` is what the query still holds, or `null`. Skipped when the hook before it threw; a cancel that records no error runs neither. |

A throw from any of the three is reported to the current zone and does not
change the fetch's outcome.

### Members

| Member | Signature | Meaning |
|---|---|---|
| [`subscribe`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryCache/subscribe.html) | `void Function() subscribe(void Function(QueryCacheEvent event) listener)` | Calls `listener` with every [event](#query-cache-events); returns the function that unsubscribes. Each listener is isolated: a throw is reported to the zone and the others still run. |
| `hasListeners` | `bool` | Whether any listener is subscribed. |
| `queries` | `List<Query<Object?>>` | Every query, as a copy — safe to iterate while removing. TanStack: `getAll()`. |
| [`findAll`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryCache/findAll.html) | `List<Query<Object?>> findAll({QueryFilters filters = const QueryFilters()})` | Every query matching `filters`, in insertion order. The key matches as a **prefix** unless `exact: true`. |
| [`find`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryCache/find.html) | `Query<Object?>? find({required QueryFilters filters})` | The first match, or `null`. An unset `exact` means an **exact** key match here. |
| `get` | `Query<T>? get<T>(QueryKey queryKey)` | The query stored under exactly this key, or `null`. Throws `QueryDataTypeError` when it holds a different type — a subtype or the nullable type included. TanStack: `get(queryHash)`, by hash rather than key. |
| `build` | `Query<T> build<T>(QueryClient client, DefaultedQueryOptions<T> options, {QueryState<T>? state})` | The query for the key, created if missing. `state` restores a saved entry and is used only on creation; a restored `fetchStatus` is set back to `idle`, since no fetch survives the process it ran in. A `success` state without data throws `ArgumentError`. |
| `add` | `void add(Query<Object?> query)` | Puts a hand-built query in and emits `QueryAdded`; a key that already has a query keeps it. A query that was removed throws `StateError`. |
| `remove` | `void remove(Query<Object?> query)` | Takes the query out, cancels its fetch silently, stops its collection timer, emits `QueryRemoved`. |
| `clear` | `void clear()` | Removes every query, one `QueryRemoved` each. Prefer `client.clear()`, which also clears the mutation cache inside one batch. |
| `notify` | `void notify(QueryCacheEvent event)` | Delivers an event to every listener. The cache calls it; rarely useful from outside. |
| `onFocus` | `void onFocus({bool refetchQueries = true})` | Every query reacts to the app returning to the foreground. A mounted client calls it. `refetchQueries: false` lets paused fetches continue without starting new ones. |
| `onOnline` | `void onOnline()` | Every query reacts to the device coming back online. A mounted client calls it. |
| `onSuccess`, `onError`, `onSettled` | see above | The constructor's hooks, readable. TanStack: read from `config`. |

### Query cache events

[`QueryCacheEvent`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryCacheEvent-class.html)
is sealed, so a listener can `switch` over it exhaustively. Every event
carries `query`, typed `Query<Object?>` because a cache listener sees every
key. The observer an event names is a
[`QueryObserverRef`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserverRef-class.html):
an identity to hold and compare, not something to drive.

| Event | Carries | Emitted when |
|---|---|---|
| `QueryAdded` | `query` | A query was created — `build` or `add`, the first time anything used its key. TanStack: `type: 'added'`. |
| `QueryRemoved` | `query` | A query left the cache: collected after `gcTime` without observers, or removed by `removeQueries`, `remove` or `clear`. TanStack: `type: 'removed'`. |
| `QueryUpdated` | `query`, `action` | The query's state changed. Emitted for every [action](#query-actions). TanStack: `type: 'updated'`. |
| `QueryObserverAdded` | `query`, `observer` | An observer attached. This is also what cancels the query's pending garbage collection. TanStack: `type: 'observerAdded'`. |
| `QueryObserverRemoved` | `query`, `observer` | An observer detached. When it was the last one, the fetch in flight has already been told to stop retrying and the collection timer is armed. TanStack: `type: 'observerRemoved'`. |
| `QueryObserverOptionsUpdated` | `query`, `observer` | An observer's options changed. A key change emits `QueryObserverRemoved` on the old query, `QueryObserverAdded` on the new one, then this on the new one. TanStack: `type: 'observerOptionsUpdated'`. |
| `QueryObserverResultsUpdated` | `query` | An observer delivered a new result, after its listeners ran. TanStack: `type: 'observerResultsUpdated'`. |

The [debugging guide](../guides/debugging.md) shows a listener that logs
them.

### Query actions

`QueryUpdated.action` is a
[`QueryAction`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryAction-class.html),
also sealed. Actions are read-only from outside: only a `Query` dispatches
one.

| Action | Fields | Meaning |
|---|---|---|
| `QueryFetchAction` | `meta` (`Object?`) | A fetch started. Resets the failure count, records `meta` as `state.fetchMeta`, and moves `fetchStatus` to `fetching` — or `paused` when the network mode forbids starting. TanStack: `type: 'fetch'`. |
| `QueryFailedAction` | `failureCount`, `error`, `stackTrace` | One attempt failed and will be retried. `status` and data are untouched. TanStack: `type: 'failed'`. |
| `QuerySuccessAction<T>` | `data`, `dataUpdatedAt` (`DateTime?`), `manual` (`bool`) | Data arrived, fetched or written with `setQueryData` (`manual: true`). A manual write leaves a fetch in flight alone. TanStack: `type: 'success'`. |
| `QueryErrorAction` | `error`, `stackTrace` | A fetch failed for good, or was cancelled with neither `silent` nor `revert`. Existing data is flagged as invalidated. TanStack: `type: 'error'`. |
| `QueryPauseAction` | — | The fetch was suspended: offline, or a retry waiting for the foreground. TanStack: `type: 'pause'`. |
| `QueryContinueAction` | — | A paused fetch resumed. TanStack: `type: 'continue'`. |
| `QueryInvalidateAction` | — | `invalidateQueries` marked the query stale. Only `isInvalidated` changes. TanStack: `type: 'invalidate'`. |
| `QuerySetStateAction<T>` | `state` | The whole state was replaced: a reset, a revert after a cancel, or `Query.setState`. TanStack: `type: 'setState'`. |

## `MutationCache`

[`MutationCache`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationCache-class.html)
holds every mutation the client has run, in submission order. Mutations are
never shared by key: every `mutate` call adds a new `Mutation`, which stays
while it runs and for its `gcTime` after the last observer leaves. It is
reachable as `client.mutationCache`.

### Constructor

`MutationCache({onMutate, onSuccess, onError, onSettled})`, all optional and
final. Each hook runs **before** the mutation's own option callback of the
same name, and a returned future is awaited before the next callback
starts. The mutation stays `pending` until all of them are done; the per-call
`MutateCallbacks` passed to `mutate` run after that.

| Callback | Signature | Default | Meaning |
|---|---|---|---|
| `onMutate` | `FutureOr<void> Function(Object? variables, Mutation<Object?, Object?, Object?> mutation)` | unset | Runs when any mutation is submitted. What it returns is ignored. A throw fails the mutation without running its function. |
| `onSuccess` | `FutureOr<void> Function(Object? data, Object? variables, Object? onMutateResult, Mutation<Object?, Object?, Object?> mutation)` | unset | Runs after any mutation succeeds. A throw turns the success into an error. |
| `onError` | `FutureOr<void> Function(Object error, StackTrace stackTrace, Object? variables, Object? onMutateResult, Mutation<Object?, Object?, Object?> mutation)` | unset | Runs after any mutation fails for good. A throw is reported to the zone and the remaining callbacks still run. |
| `onSettled` | `FutureOr<void> Function(Object? data, Object? error, StackTrace? stackTrace, Object? variables, Object? onMutateResult, Mutation<Object?, Object?, Object?> mutation)` | unset | Runs after any mutation settles, success or failure. |

TanStack Query passes a trailing function context to each hook; here the
mutation is the last argument, and the error comes with its stack trace.

### Members

| Member | Signature | Meaning |
|---|---|---|
| [`subscribe`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationCache/subscribe.html) | `void Function() subscribe(void Function(MutationCacheEvent event) listener)` | Calls `listener` with every [event](#mutation-cache-events); returns the unsubscribe function. Listeners are isolated, as on the query cache. |
| `hasListeners` | `bool` | Whether any listener is subscribed. |
| `mutations` | `List<Mutation<Object?, Object?, Object?>>` | Every mutation in submission order, as a copy. TanStack: `getAll()`. |
| `findAll` | `List<Mutation<…>> findAll({MutationFilters filters = const MutationFilters()})` | Every match, in submission order. The key matches as a prefix unless `exact: true`. |
| `find` | `Mutation<…>? find({required MutationFilters filters})` | The first match, or `null`. An unset `exact` means an exact match here. |
| `build` | `Mutation<D, V, R> build<D, V, R>(QueryClient client, DefaultedMutationOptions<D, V, R> options, {MutationState<D, V, R>? state})` | Creates a mutation with the next id and adds it. `state` restores an offline mutation; a restored `pending` state is set to paused, and one without variables (unless `null` is a valid variables value) throws `ArgumentError`. |
| `add` | `void add(Mutation<…> mutation)` | Appends a hand-built mutation and emits `MutationAdded`. Adding the same instance twice does nothing; a removed one throws `StateError`. |
| `remove` | `void remove(Mutation<…> mutation)` | Takes the mutation out and emits `MutationRemoved`. A running one is told to stop retrying: the attempt in flight still settles, a backoff is cut short, and a paused one fails with `CancelledError`. In TanStack Query a removed mutation keeps retrying. |
| `clear` | `void clear()` | Removes every mutation, stopping retries as `remove` does. Never starts a mutation queued in a scope. |
| `resumePaused` | `Future<void> resumePaused()` | Continues every paused mutation that can run now; completes when they have settled. Errors stay with each mutation. `QueryClient.resumePausedMutations` calls it. TanStack: `resumePausedMutations`, which resumes nothing while offline; here each mutation's network mode decides. |
| `notify` | `void notify(MutationCacheEvent event)` | Delivers an event to every listener. |
| `onMutate`, `onSuccess`, `onError`, `onSettled` | see above | The constructor's hooks, readable. TanStack: read from `config`. |

### Mutation cache events

[`MutationCacheEvent`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationCacheEvent-class.html)
is sealed. Every event carries `mutation`, typed
`Mutation<Object?, Object?, Object?>`.

| Event | Carries | Emitted when |
|---|---|---|
| `MutationAdded` | `mutation` | A mutation was created and appended — the moment `mutate` is called, or a restored one is built. TanStack: `type: 'added'`. |
| `MutationRemoved` | `mutation` | A mutation left the cache: collected, or removed by `remove` or `clear`. TanStack: `type: 'removed'`. |
| `MutationUpdated` | `mutation`, `action` | The mutation's state changed. Emitted for every [action](#mutation-actions). TanStack: `type: 'updated'`. |
| `MutationObserverAdded` | `mutation`, `observer` | An observer attached; also cancels the pending collection. TanStack: `type: 'observerAdded'`. |
| `MutationObserverRemoved` | `mutation`, `observer` | An observer detached; when it was the last one, the collection timer is armed. TanStack: `type: 'observerRemoved'`. |
| `MutationObserverOptionsUpdated` | `mutation`, `observer` | An observer's options changed while it stayed on the same mutation. TanStack: `type: 'observerOptionsUpdated'`. |

### Mutation actions

`MutationUpdated.action` is a sealed
[`MutationAction`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationAction-class.html).

| Action | Fields | Meaning |
|---|---|---|
| `MutationPendingAction` | `variables`, `onMutateResult`, `isPaused` | A run started: status `pending`, fresh `submittedAt`. Dispatched a second time once `onMutate` has run, when it produced a result or the pause changed. TanStack: `type: 'pending'`. |
| `MutationFailedAction` | `failureCount`, `error`, `stackTrace` | One attempt failed and will be retried. TanStack: `type: 'failed'`. |
| `MutationSuccessAction` | `data` | The function resolved and every success callback ran. TanStack: `type: 'success'`. |
| `MutationErrorAction` | `error`, `stackTrace` | The run failed for good — the last attempt's error, a callback's, or a `CancelledError` after `cancel`. TanStack: `type: 'error'`. |
| `MutationPauseAction` | — | The run was suspended: offline, in the background, or queued behind its scope. TanStack: `type: 'pause'`. |
| `MutationContinueAction` | — | A paused run resumed, or a restored one was run. TanStack: `type: 'continue'`. |

## `Query`

[`Query<TQueryData>`](https://pub.dev/documentation/query_kit/latest/query_kit/Query-class.html)
is one cache entry. You never construct one; you meet it in `find`/`findAll`,
in every cache event and cache callback, in a `QueryFilters.predicate`, and in
callbacks such as `StaleTime.dynamic`. It has one type parameter, the data
type the cache stores.

| Member | Signature | Meaning |
|---|---|---|
| `queryKey` | `QueryKey` | The key it is stored under. |
| `dataType` | `Type` | The exact data type it holds. A cache listener sees `Query<Object?>`; this recovers the real type. No TanStack counterpart. |
| `state` | `QueryState<TQueryData>` | The current [state](#querystate). Replaced on every action. |
| `options` | `DefaultedQueryOptions<TQueryData>` | The options in force, fully resolved. |
| `meta` | `Object?` | The options' `meta`, for cache callbacks and listeners. |
| `client` | `QueryClient` | The client it belongs to. No TanStack counterpart. |
| `observers` | `List<QueryObserverRef>` | The attached observers, read-only. |
| `observersCount` | `int` | How many observers are attached. Zero makes it collectable after `gcTime`. TanStack: `getObserversCount()`. |
| `future` | `Future<TQueryData>?` | The fetch in flight, shared by every caller, or `null`. TanStack: `promise`. |
| `resetState` | `QueryState<TQueryData>` | The state `reset` returns to: pending, or the `initialData` seed. |
| `gcTime` | `GcTime?` | How long the query may sit without observers before it is collected: the longest `gcTime` of any options applied to it, five minutes when none set one. Only applying options moves it. |
| `isStale()` | `bool isStale()` | With observers: whether any observer's current result is stale. Without: no data, or invalidated. |
| `isStaleByTime(staleTime)` | `bool isStaleByTime(StaleTime staleTime)` | Whether the data is older than `staleTime`. `StaleTime.static` outranks an invalidation; `StaleTime.infinite` does not. |
| `isActive()` | `bool isActive()` | Whether any observer's `enabled` resolves to true. What `QueryTypeFilter.active` selects. |
| `isDisabled()` | `bool isDisabled()` | With observers: none is enabled. Without: nothing has ever been fetched. |
| `isStatic()` | `bool isStatic()` | Whether an attached observer uses `StaleTime.static`. |
| `isFetched()` | `bool isFetched()` | Whether a fetch or a manual write has ever settled. |
| `fetch` | `Future<TQueryData> fetch({DefaultedQueryOptions<TQueryData>? options, FetchOptions? fetchOptions})` | Fetches now, joining a fetch in flight unless `fetchOptions.cancelRefetch` is set on a query with data. Completes with the data, or throws the fetch's error. Usually reached through `client.query` or an observer; see [`FetchOptions`](#fetchoptions) below. |
| `invalidate` | `void invalidate()` | Marks the data stale; refetches nothing. |
| `cancel` | `Future<void> cancel({bool revert = false, bool silent = false})` | Cancels the fetch in flight. Both `false`: the fetch fails with `CancelledError`, recorded and reported to `onError`. `revert`: back to the state before the fetch, no error. `silent`: no error, state left alone, and `fetchStatus` returns to `idle` when no new fetch follows. See [errors](errors.md#cancellederror). In TanStack Query a silent cancel with no successor stays `fetching`. |
| `reset` | `void reset()` | Back to `resetState`, cancelling any fetch; refetches nothing. |
| `setState` | `void setState(QueryState<TQueryData> state)` | Replaces the **whole** state, for a persistence layer or a devtools panel. `fetchStatus` is installed as given. A `success` state without data throws `ArgumentError`. TanStack's `setState` merges a partial state instead. |

### `QueryState`

[`QueryState<TQueryData>`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState-class.html)
is what `query.state` and `client.getQueryState` return. Observers turn it
into a `QueryResult`; see [results](results.md).

| Field | Type | Default | Meaning |
|---|---|---|---|
| `status` | `QueryStatus` | `pending` | `pending`, `success` or `error`. |
| `fetchStatus` | `FetchStatus` | `idle` | `fetching`, `paused` or `idle`. |
| `hasData` | `bool` | `false` | Whether `data` is meaningful — true even when the data is `null`. No TanStack counterpart; there `data !== undefined` says the same. |
| `data` | `TQueryData?` | `null` | The cached data. |
| `dataUpdatedAt` | `DateTime?` | `null` | When data was last written; `staleTime` counts from here. |
| `dataUpdateCount` | `int` | `0` | Writes so far, fetched and manual. |
| `error` | `Object?` | `null` | Why the last fetch failed; cleared by the next success. |
| `errorStackTrace` | `StackTrace?` | `null` | The stack trace of `error`. No TanStack counterpart. |
| `errorUpdatedAt` | `DateTime?` | `null` | When the query last ended in an error. |
| `errorUpdateCount` | `int` | `0` | Errors over the query's whole life; never goes down. |
| `consecutiveErrorCount` | `int` | `0` | Fetches in a row that ended in an error. Reset only by fetched data; a manual write or a cancel leaves it. No TanStack counterpart. |
| `fetchFailureCount` | `int` | `0` | Failed attempts inside the current fetch. |
| `fetchFailureReason` | `Object?` | `null` | What the latest failed attempt threw. |
| `fetchFailureStackTrace` | `StackTrace?` | `null` | Its stack trace. No TanStack counterpart. |
| `fetchMeta` | `Object?` | `null` | What the fetch carried; an infinite query's page direction. |
| `isInvalidated` | `bool` | `false` | Stale regardless of `staleTime`: set by an invalidation or a failed fetch. |
| `isFetched` | `bool` (getter) | — | Whether anything has ever been fetched or written. No TanStack counterpart. |

### `FetchOptions`

[`FetchOptions`](https://pub.dev/documentation/query_kit/latest/query_kit/FetchOptions-class.html)
are the per-call overrides `Query.fetch` takes. All three are unset by
default, which leaves the fetch as the query's options describe it.

| Field | Type | Default | Meaning |
|---|---|---|---|
| `cancelRefetch` | `bool?` | `null` — join | Cancel a running fetch and start over, on a query that holds data. Without data the call joins the running fetch, so a first load is never restarted. |
| `meta` | `Object?` | `null` | Carried into `state.fetchMeta` for the length of the fetch; infinite queries put the page direction here. |
| `retry` | `RetryPolicy?` | `null` — the options' `retry` | A retry policy for this fetch only; the query's options are not changed. `client.query` uses it for its no-retries rule. No TanStack counterpart. |

## `Mutation`

[`Mutation<TData, TVariables, TOnMutateResult>`](https://pub.dev/documentation/query_kit/latest/query_kit/Mutation-class.html)
is one run of a mutation function. `MutationObserver.mutate` builds it; you
meet it in cache events, in `findAll`, in a `MutationFilters.predicate` and in
a `MutationStateObserver`'s `select`.

| Member | Signature | Meaning |
|---|---|---|
| `mutationId` | `int` | Unique within the cache, in submission order. |
| `state` | `MutationState<TData, TVariables, TOnMutateResult>` | The current state. |
| `options` | `DefaultedMutationOptions<TData, TVariables, TOnMutateResult>` | The options in force. Retry, delay, network mode and scope are fixed for each run. |
| `meta` | `Object?` | The options' `meta`. |
| `client` | `QueryClient` | The client it belongs to. No TanStack counterpart. |
| `observers` | `List<MutationObserverRef>` | The attached observers, read-only. |
| `gcTime` | `GcTime?` | How long the mutation stays after its last observer leaves and it has settled: the longest `gcTime` of any options applied to it, five minutes when none set one. |
| [`cancel`](https://pub.dev/documentation/query_kit/latest/query_kit/Mutation/cancel.html) | `void cancel()` | Fails the run in flight with a `CancelledError`: the signal is cancelled, no further attempt is made, `onError` and `onSettled` run. A paused, queued or restored run fails without its function running. Once the function has returned, it does nothing. See [cancelling mutations](../guides/cancelling-mutations.md). No TanStack counterpart. |
| `continueMutation` | `Future<void> continueMutation()` | Releases a paused mutation, or runs a restored one with its saved variables; completes when it settles, callbacks included, or throws the error it settled on. A settled mutation is not run again. `resumePaused` is the usual caller. TanStack: `continue()`. |
| `execute` | `Future<TData> execute(TVariables variables)` | Runs the mutation once, callbacks included. The observer calls it; you call `mutate`. |

`MutationStatus` is `idle`, `pending`, `success` or `error`. A mutation stays
`pending` until its callbacks have run, `onSettled`'s future included.

| `MutationState` field | Type | Default | Meaning |
|---|---|---|---|
| `status` | `MutationStatus` | `idle` | Where the mutation is in its life. |
| `variables` | `TVariables?` | `null` | The variables of the run in flight or last finished. |
| `hasVariables` | `bool` | `false` | Whether `variables` was set by a run — `null` is then a real value. No TanStack counterpart. |
| `data` | `TData?` | `null` | What the last successful run returned. |
| `hasData` | `bool` | `false` | Whether `data` is meaningful. No TanStack counterpart. |
| `error` | `Object?` | `null` | Why the last run failed. |
| `errorStackTrace` | `StackTrace?` | `null` | Its stack trace. No TanStack counterpart. |
| `onMutateResult` | `TOnMutateResult?` | `null` | What `onMutate` returned. TanStack: `context`. |
| `failureCount` | `int` | `0` | Failed attempts of the current run. |
| `failureReason` | `Object?` | `null` | What the last failed attempt threw. |
| `isPaused` | `bool` | `false` | Parked: offline, in the background, or queued behind its scope. |
| `submittedAt` | `DateTime?` | `null` | When the run was submitted. |

## Observers

An observer follows one entry — or a list of them, or a selection over the
mutation cache — and reports it to listeners. Every observer has the same
lifecycle: construct it (nothing is fetched), `subscribe` a listener (the
first one attaches it and fetches what is due), read `currentResult` at any
time, and `destroy` it when done. A listener is **not** called with the
result that was current when it subscribed; read that from `currentResult`.
Each `subscribe` returns its own unsubscribe function, which works once.

The Flutter binding wraps each observer in a controller, so widget code
rarely holds one; see [widgets and controllers](widgets-and-controllers.md).
In a [pure-Dart](../guides/pure-dart.md) program you own them directly.

### Creating one from the client

| Member | Signature | Same as |
|---|---|---|
| [`observe`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/observe.html) | `QueryObserver<TQueryData, TData> observe<TQueryData, TData>(QueryObserverOptionsBase<TQueryData, TData> options)` | `QueryObserver(client, options)` TanStack: `new QueryObserver(client, options)`. |
| [`observeInfinite`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/observeInfinite.html) | `InfiniteQueryObserver<TPageData, TPageParam, TData> observeInfinite<…>(InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options)` | `InfiniteQueryObserver(client, options)` TanStack: `new InfiniteQueryObserver(client, options)`. |

The caller owns the observer's lifetime: unsubscribe, or `destroy`, when
done.

### `QueryObserver`

[`QueryObserver<TQueryData, TData>`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserver-class.html)
follows one query. `TQueryData` is what the cache holds, `TData` what the
observer reports — the same type unless the options have a `select`.

| Member | Signature | Meaning |
|---|---|---|
| constructor | `QueryObserver(QueryClient client, QueryObserverOptionsBase<TQueryData, TData> options)` | Resolves the options against the client's defaults and builds or joins the query. Fetches nothing. Throws `ArgumentError` when there is no `select` and a `TQueryData` is not a `TData`. |
| [`subscribe`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserver/subscribe.html) | `void Function() subscribe(void Function(QueryResult<TData> result) listener)` | The first listener attaches the observer, fetches if due (no data, or stale data and `refetchOnMount`) and arms the stale and polling timers. The last one leaving detaches it. A throw from an option callback during the first subscribe propagates and leaves nothing registered. In TanStack Query the listener stays registered after such a throw. |
| `hasListeners` | `bool` | Whether anyone is subscribed ("mounted"). |
| `currentResult` | `QueryResult<TData>` | The latest result; readable right after construction. TanStack: `getCurrentResult()`. |
| `currentQuery` | `Query<TQueryData>` | The entry followed now. TanStack: `getCurrentQuery()`. |
| `options` | `DefaultedQueryObserverOptions<TQueryData, TData>` | The options in force, resolved. |
| [`setOptions`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserver/setOptions.html) | `void setOptions(QueryObserverOptionsBase<TQueryData, TData> options)` | Replaces the options, moving to another query if the key changed. Equal options are cheap and notify nobody. While subscribed, it fetches when it lands on stale or missing data, or `enabled` turned true over stale data. `enabled` is compared with what it resolved to the last time options were applied, so an `Enabled.when` over outside state takes effect on the next `setOptions`. In TanStack Query both sides are evaluated at the same instant. |
| `getOptimisticResult` | `QueryResult<TData> getOptimisticResult(QueryObserverOptionsBase<TQueryData, TData> options)` | The result these options would give now, the fetch about to start included — the right read for a first build. Fetches nothing and does not apply the options, but the result becomes `currentResult` until the next update. Throws as the constructor does for mismatched types. |
| [`refetch`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserver/refetch.html) | `Future<QueryResult<TData>> refetch({bool cancelRefetch = true})` | Fetches whether or not the data is stale, `enabled` ignored. Completes with the result; never with an error. TanStack's `refetch` also takes `throwOnError`; this one never throws. |
| `updateResult` | `void updateResult()` | Recomputes the result and notifies if it changed. The observer calls it itself. |
| `destroy` | `void destroy()` | Clears listeners and timers and leaves the query, which starts its `gcTime` clock. |

### `InfiniteQueryObserver`

[`InfiniteQueryObserver<TPageData, TPageParam, TData>`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryObserver-class.html)
is a `QueryObserver` over `InfiniteData<TPageData, TPageParam>` with paging
on top. Everything in the table above applies. The paging flags live on the
observer, not on the result, so the sealed result keeps one shape; a change
in any of them notifies listeners even when the result itself did not
change. See [infinite queries](../guides/infinite-queries.md).

| Member | Signature | Meaning |
|---|---|---|
| constructor | `InfiniteQueryObserver(QueryClient client, InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options)` | The paging half of the options becomes the query's fetch behaviour. |
| `infiniteOptions` | `InfiniteQueryOptions<TPageData, TPageParam>` | The paging functions in force. No TanStack counterpart. |
| `setInfiniteOptions` | `void setInfiniteOptions(InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options)` | The typed form of `setOptions`. TanStack: `setOptions`. |
| `setOptions` | inherited | Takes only options that carry the paging behaviour (`client.infiniteObserverOptions(…)`); plain observer options throw `UnsupportedError`. |
| `getOptimisticInfiniteResult` | `QueryResult<TData> getOptimisticInfiniteResult(InfiniteQueryObserverOptionsBase<…> options)` | The typed form of `getOptimisticResult`. TanStack: `getOptimisticResult`. |
| [`fetchNextPage`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryObserver/fetchNextPage.html) | `Future<QueryResult<TData>> fetchNextPage({bool cancelRefetch = true})` | Fetches the page after the last one and appends it. Does nothing when `getNextPageParam` returns `null`; loads the first page when there is none. With `cancelRefetch`, a fetch already running on a query with pages is cancelled — check `isFetchingNextPage` first. Never completes with an error. |
| `fetchPreviousPage` | `Future<QueryResult<TData>> fetchPreviousPage({bool cancelRefetch = true})` | The mirror: prepends the page before the first one. |
| `hasNextPage` | `bool` | Whether `fetchNextPage` would fetch anything. False before the first page. TanStack: on the infinite result. |
| `hasPreviousPage` | `bool` | Whether `fetchPreviousPage` would. TanStack: on the infinite result. |
| `isFetchingNextPage` | `bool` | A `fetchNextPage` is in flight. TanStack: on the infinite result. |
| `isFetchingPreviousPage` | `bool` | A `fetchPreviousPage` is in flight. TanStack: on the infinite result. |
| `isFetchNextPageError` | `bool` | The query's error came from `fetchNextPage`; the held pages are still there. TanStack: on the infinite result. |
| `isFetchPreviousPageError` | `bool` | The error came from `fetchPreviousPage`. TanStack: on the infinite result. |
| `isRefetching` | `bool` | The held pages are being refetched — a page being added does not count. TanStack: on the infinite result. |
| `isRefetchError` | `bool` | A refetch failed, not a page fetch. TanStack: on the infinite result. |

### `QueriesObserver`

[`QueriesObserver<TQueryData, TData>`](https://pub.dev/documentation/query_kit/latest/query_kit/QueriesObserver-class.html)
follows a list of queries of one type, one `QueryObserver` per entry, and
reports the list of results in input order. For a fixed handful of
different types, observe them separately and combine the results; see
[combining queries](../guides/combining-queries.md).

| Member | Signature | Meaning |
|---|---|---|
| constructor | `QueriesObserver(QueryClient client, List<QueryObserverOptionsBase<TQueryData, TData>> queries)` | Builds or joins each query; fetches nothing. Throws `ArgumentError` when an entry has no `select` and the two types differ. TanStack's constructor also takes a `combine` option; here the results are combined afterwards. |
| `subscribe` | `void Function() subscribe(void Function(List<QueryResult<TData>>) listener)` | The first listener subscribes every member, which fetches each one due; the last one leaving unsubscribes them. |
| `hasListeners` | `bool` | Whether anyone is subscribed. |
| `currentResult` | `List<QueryResult<TData>>` | The latest results, read-only, in input order. TanStack: `getCurrentResult()`. |
| `observers` | `List<QueryObserver<TQueryData, TData>>` | The members, read-only; their lifetime belongs to this observer. TanStack: `getObservers()`. |
| `getOptimisticResult` | `List<QueryResult<TData>> getOptimisticResult()` | Each member's optimistic result for its current options. |
| `setQueries` | `void setQueries(List<QueryObserverOptionsBase<TQueryData, TData>> queries)` | Replaces the list. Members are matched by key and occurrence and handed their new options; new keys get new members; members left over are destroyed. If an entry throws, the list stays as it was — new members are destroyed, none is removed — though members before the failing entry keep the options they were just given. |
| `destroy` | `void destroy()` | Removes every listener and destroys every member. |

### `MutationObserver`

[`MutationObserver<TData, TVariables, TOnMutateResult>`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationObserver-class.html)
runs mutations and reports the latest one's state as a `MutationResult`.
Each `mutate` builds a new `Mutation`; the observer follows the newest.

| Member | Signature | Meaning |
|---|---|---|
| constructor | `MutationObserver(QueryClient client, MutationOptions<TData, TVariables, TOnMutateResult> options)` | An idle observer. Both `mutationFn` and `mutationFnWithContext` set fails an assertion in the `MutationOptions` constructor in a debug build, and throws `ArgumentError` here when the options are resolved. |
| `subscribe` | `void Function() subscribe(void Function(MutationResult<TData, TVariables> result) listener)` | The first listener re-attaches to the mutation being watched; the last one leaving detaches, starting its `gcTime` clock. |
| `hasListeners` | `bool` | Whether anyone is subscribed. Per-call callbacks only run while this is true. |
| `currentResult` | `MutationResult<TData, TVariables>` | Idle until the first `mutate`, then the observed mutation's state. TanStack: `getCurrentResult()`. |
| `options` | `DefaultedMutationOptions<TData, TVariables, TOnMutateResult>` | The options in force, resolved. |
| `setOptions` | `void setOptions(MutationOptions<TData, TVariables, TOnMutateResult> options)` | Replaces the options. A changed `mutationKey` resets the observer; otherwise a mutation still in flight takes the new callbacks, `meta` and `gcTime`, and a retry calls the new mutation function, but it keeps the `retry`, `retryDelay`, `networkMode` and `scope` it started with. |
| [`mutate`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationObserver/mutate.html) | `void mutate(TVariables variables, {MutateCallbacks<TData, TVariables, TOnMutateResult>? callbacks})` | Starts a run and returns at once. Errors reach the callbacks and the result, never the zone. |
| `mutateAsync` | `Future<TData> mutateAsync(TVariables variables, {MutateCallbacks<…>? callbacks})` | Starts a run; completes with the data or throws the error, after the callbacks ran. TanStack: `mutate`, which returns a promise. |
| `cancel` | `void cancel()` | Cancels the run this observer shows — see `Mutation.cancel`. No TanStack counterpart. |
| `reset` | `void reset()` | Back to idle. The mutation keeps running and firing its own callbacks. |
| `destroy` | `void destroy()` | Drops every listener and leaves the mutation, so it can be collected. No TanStack counterpart. |

### `MutationStateObserver`

[`MutationStateObserver<TSelected>`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationStateObserver-class.html)
selects a value from every matching mutation in the cache — not only the
ones one observer started. See [mutation state](../guides/mutation-state.md).

| Member | Signature | Meaning |
|---|---|---|
| constructor | `MutationStateObserver(QueryClient client, {MutationFilters filters = const MutationFilters(), required TSelected Function(Mutation<Object?, Object?, Object?> mutation) select})` | A selection, readable at once. TanStack: `useMutationState({ filters, select })`. |
| [`typed`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationStateObserver/typed.html) | `static MutationStateObserver<TSelected> typed<TData, TVariables, TOnMutateResult, TSelected>(QueryClient client, {MutationFilters filters, required TSelected Function(Mutation<TData, TVariables, TOnMutateResult>) select})` | Only mutations **declared** with these types, handed to `select` typed. The type test runs before `filters.predicate`, which may therefore cast. A mutation whose types were never written or inferred is `Mutation<Object?, Object?, Object?>` and drops out. No TanStack counterpart. |
| `currentResult` | `List<TSelected>` | The selected values in submission order. Read without listeners, it refreshes from the cache. TanStack: the return value of `useMutationState`. |
| `hasListeners` | `bool` | Whether it follows cache events. No TanStack counterpart. |
| `subscribe` | `void Function() subscribe(void Function(List<TSelected>) listener)` | Follows the mutation cache while anyone listens. No initial snapshot. Equal selections (compared deeply) do not notify. No TanStack counterpart. |
| `setOptions` | `void setOptions({MutationFilters? filters, MutationStateSelect<TSelected>? select})` | Replaces either and recomputes. A `typed` observer keeps its type test. No TanStack counterpart. |
| `destroy` | `void destroy()` | Removes listeners and the cache subscription. No TanStack counterpart. |

## Filters

Filters select entries for the client's bulk operations and the caches'
`find`/`findAll`. Every field is optional, `null` means "do not filter on
this", and an entry must match every field that is set — so empty filters
match everything. See [filters](../guides/filters.md).

### `QueryFilters`

[`QueryFilters`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryFilters-class.html)
is taken as `filters:` by `invalidateQueries`, `refetchQueries`,
`cancelQueries`, `resetQueries`, `removeQueries`, `isFetching`,
`getQueriesData`, `updateQueriesData`, `QueryCache.find` and `findAll`, and
the binding's `IsFetchingController`.

| Field | Type | Default | Meaning |
|---|---|---|---|
| `queryKey` | `QueryKey?` | `null` — every key | The key to match, as a prefix: `QueryKey(['todos'])` matches `['todos']` and `['todos', 3]`. |
| `exact` | `bool?` | `null` — prefix for `findAll` and the bulk operations, exact for `find` | Whether `queryKey` must be the whole key. |
| `type` | `QueryTypeFilter?` | `null` — same as `all` | Observed queries, unobserved ones, or both. |
| `stale` | `bool?` | `null` | `true` matches queries whose `isStale()` is true, `false` fresh ones. |
| `fetchStatus` | `FetchStatus?` | `null` | `fetching`, `paused` or `idle`. `isFetching` ignores it and always counts `fetching`. |
| `status` | `QueryStatus?` | `null` | `pending`, `success` or `error`. No TanStack counterpart. |
| `predicate` | `bool Function(Query<Object?> query)?` | `null` | Your own test, run last, on queries that passed the other fields. |
| [`matches`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryFilters/matches.html) | `bool matches(Query<Object?> query, {bool exactByDefault = false})` | — | Whether `query` passes every set field. `exactByDefault` is what an unset `exact` means: the caches pass `true` for `find`. For a filter of your own over `queries`. |

[`QueryTypeFilter`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryTypeFilter.html)
is `all` (every query), `active` (at least one enabled observer) or
`inactive` (no enabled observer: none at all, or every one disabled).

[`RefetchType`](https://pub.dev/documentation/query_kit/latest/query_kit/RefetchType.html)
is what `invalidateQueries(refetchType: …)` refetches after marking:

| Value | Refetches |
|---|---|
| `active` | invalidated queries with an enabled observer |
| `inactive` | invalidated queries nobody observes |
| `all` | every invalidated query |
| `none` | nothing; observers pick it up on their next trigger |
| unset | the filters' `type`, else `active` (TanStack: `refetchType` left unset) |

`refetchType` is a parameter of `invalidateQueries`, not a field of the
filters as in TanStack Query. The matched set is fixed before invalidating,
so a filter over state (`stale: false`, say) still refetches what it marked.

### `MutationFilters`

[`MutationFilters`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationFilters-class.html)
is taken by `MutationCache.find` and `findAll`, `QueryClient.isMutating`,
`MutationStateObserver` and the binding's `MutationStateController`.

| Field | Type | Default | Meaning |
|---|---|---|---|
| `mutationKey` | `QueryKey?` | `null` — every mutation | The key to match, as a prefix. A mutation without a key never matches a key filter. |
| `exact` | `bool?` | `null` — prefix for `findAll` and `isMutating`, exact for `find` | Whether `mutationKey` must be the whole key. |
| `status` | `MutationStatus?` | `null` | `idle`, `pending`, `success` or `error`. `isMutating` ignores it and always counts `pending`. |
| `predicate` | `bool Function(Mutation<Object?, Object?, Object?> mutation)?` | `null` | Your own test, run last. |
| [`matches`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationFilters/matches.html) | `bool matches(Mutation<Object?, Object?, Object?> mutation, {bool exactByDefault = false})` | — | Whether `mutation` passes every set field, as `QueryFilters.matches` does. |

## Managers

Each client owns one of each manager, as `client.focusManager`,
`client.onlineManager` and `client.notifyManager`; pass your own to the
`QueryClient` constructor to share or configure one. In TanStack Query they
are module-level singletons. A client reacts to the first two only while it
is **mounted**: `client.mount()` subscribes to both, and on focus or
reconnect it first resumes paused mutations, then lets the queries refetch.
The Flutter binding's `QueryClientProvider` mounts its client and drives
both managers; see [connectivity](../guides/connectivity.md) and
[app focus refetching](../guides/window-focus-refetching.md).

### `AppFocusManager`

[`AppFocusManager`](https://pub.dev/documentation/query_kit/latest/query_kit/AppFocusManager-class.html)
tracks whether the app is in the foreground. Pure Dart has no notion of
focus, so the default is "focused".

| Member | Signature | Meaning |
|---|---|---|
| constructor | `AppFocusManager({Duration refetchMinBackgroundDuration = Duration.zero})` | Throws `ArgumentError` for a negative duration. No TanStack counterpart. |
| `refetchMinBackgroundDuration` | `Duration` | An absence shorter than this does not start refetches on return; paused work still resumes. No TanStack counterpart. |
| `isFocused()` | `bool isFocused()` | The value last set, or `true` when nothing is set. |
| [`setFocused`](https://pub.dev/documentation/query_kit/latest/query_kit/AppFocusManager/setFocused.html) | `void setFocused(bool? focused)` | Sets the state by hand; a change notifies the listeners. `null` forgets the value, and `isFocused()` answers `true`. |
| [`setEventListener`](https://pub.dev/documentation/query_kit/latest/query_kit/AppFocusManager/setEventListener.html) | `void setEventListener(FocusSetup setup)` | Replaces the source of focus events; see the contract below. |
| `onFocus` | `void onFocus({bool refetchQueries = true})` | Notifies every listener with the current state. |
| `shouldRefetchOnFocus` | `bool` | Whether the current notification allows new refetches. No TanStack counterpart. |
| `subscribe` | `void Function() subscribe(void Function(bool focused) listener)` | Listens to changes; a mounted client is such a listener. |
| `hasListeners` | `bool` | Whether anyone listens. |

`FocusSetup` is `void Function() Function(void Function(bool? focused) setFocused)`.

### `OnlineManager`

[`OnlineManager`](https://pub.dev/documentation/query_kit/latest/query_kit/OnlineManager-class.html)
tracks whether the device believes it is online. The default is "online".
Under `NetworkMode.online`, the default, fetches and mutations pause while
offline.

| Member | Signature | Meaning |
|---|---|---|
| constructor | `OnlineManager()` | Reports online until told otherwise. No TanStack counterpart. |
| `isOnline()` | `bool isOnline()` | The value last set, or `true`. |
| [`setOnline`](https://pub.dev/documentation/query_kit/latest/query_kit/OnlineManager/setOnline.html) | `void setOnline(bool online)` | Sets the state by hand. A change notifies; setting the same value does nothing. |
| [`setEventListener`](https://pub.dev/documentation/query_kit/latest/query_kit/OnlineManager/setEventListener.html) | `void setEventListener(OnlineSetup setup)` | Replaces the source of connectivity events; see below. |
| `subscribe` | `void Function() subscribe(void Function(bool online) listener)` | Listens to changes. |
| `hasListeners` | `bool` | Whether anyone listens. |

`OnlineSetup` is `void Function() Function(void Function(bool online) setOnline)`.

### The `setEventListener` contract

Both managers follow the same rules:

- `setup` is called **at once** with a callback, and returns a cleanup
  function.
- The previous source's cleanup, if any, runs first.
- When the manager's last listener unsubscribes — the client unmounts — the
  cleanup runs. When a listener subscribes again, `setup` is called again.
- A `setup` that throws throws out of `setEventListener`. When it throws on
  a later re-subscribe, the throw is reported to the zone instead, and the
  next subscribe tries again.
- The focus callback takes `bool?`: `true` or `false` sets the state through
  `setFocused`, `null` re-announces the current state without changing it.
- An adapter writes through the same `setFocused`/`setOnline` as a manual
  call, so the last writer wins. In Flutter, installing your own focus
  adapter goes with `QueryClientProvider(observeAppLifecycle: false)`, and a
  connectivity source is better given as the provider's `onlineStatus`.

### `NotifyManager`

[`NotifyManager`](https://pub.dev/documentation/query_kit/latest/query_kit/NotifyManager-class.html)
batches notifications so a cascade of cache writes produces one round of
listener calls. Most apps never touch it; the Flutter binding installs a
build-phase-aware scheduler on the client's.

| Member | Signature | Meaning |
|---|---|---|
| constructor | `NotifyManager()` | An independent queue with the microtask scheduler. No TanStack counterpart. |
| `shared` | `static final NotifyManager shared` | One process-wide instance, for batching across clients. Not the default. TanStack: the module-level `notifyManager`. |
| [`batch`](https://pub.dev/documentation/query_kit/latest/query_kit/NotifyManager/batch.html) | `T batch<T>(T Function() callback)` | Runs `callback`, holding what is scheduled inside it until the outermost batch ends. |
| `batchCalls` | `void Function(A) batchCalls<A>(void Function(A) callback)` | Wraps `callback` so each call is scheduled instead of run — the way to defer and batch a cache subscription. |
| `schedule` | `void schedule(void Function() callback)` | Queues `callback` for the next flush, or hands it to the scheduler at once when no batch is open. |
| `flush` | `void flush()` | Delivers what is queued. `batch` calls it; rarely needed by hand. No TanStack counterpart. |
| `setScheduler` | `void setScheduler(ScheduleFunction fn)` | Replaces when a batch runs. Default: `scheduleMicrotask`. TanStack's default is `setTimeout(0)`. |
| `scheduler` | `ScheduleFunction` | The scheduler in force, to put back later. No TanStack counterpart. |
| `setNotifyFunction` | `void setNotifyFunction(NotifyFunction fn)` | Wraps the delivery of each notification; must call its callback exactly once. |
| `setBatchNotifyFunction` | `void setBatchNotifyFunction(BatchNotifyFunction fn)` | Wraps the delivery of a whole batch; must call its callback exactly once. |

Only callbacks submitted through `schedule` or `batchCalls` are deferred.
Direct observer subscriptions and cache listeners still run synchronously
for each change. A callback that throws inside a flushed batch is reported
to the zone and does not discard the rest of the batch.
