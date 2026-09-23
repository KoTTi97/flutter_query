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

Every table names the TanStack Query equivalent, or "—" when the member is
Dart-only. Where a member behaves differently, the row says how; the full
list is in [differences from TanStack Query](/docs/reference/differences-from-tanstack).

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

| Callback | Signature | Default | Meaning | TanStack |
|---|---|---|---|---|
| `onSuccess` | `void Function(Object? data, Query<Object?> query)` | unset | Runs once per successful fetch, however many observers share it, after the data is in the cache. A manual write (`setQueryData`) does not run it. | `onSuccess(data, query)` |
| `onError` | `void Function(Object error, StackTrace stackTrace, Query<Object?> query)` | unset | Runs once per fetch that fails for good (retries exhausted), after the error is in the query's state. Data from an earlier success is still in `query.state.data`, which tells a failed background refresh from a failed first load. A cancel that is neither silent nor reverting runs it with a `CancelledError`. | `onError(error, query)` — no stack trace there |
| `onSettled` | `void Function(Object? data, Object? error, StackTrace? stackTrace, Query<Object?> query)` | unset | Runs right after `onSuccess` or `onError`, once per fetch. After a failure `data` is what the query still holds, or `null`. Skipped when the hook before it threw; a cancel that records no error runs neither. | `onSettled(data, error, query)` |

A throw from any of the three is reported to the current zone and does not
change the fetch's outcome.

### Members

| Member | Signature | Meaning | TanStack |
|---|---|---|---|
| [`subscribe`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryCache/subscribe.html) | `void Function() subscribe(void Function(QueryCacheEvent event) listener)` | Calls `listener` with every [event](#query-cache-events); returns the function that unsubscribes. Each listener is isolated: a throw is reported to the zone and the others still run. | `subscribe` |
| `queries` | `List<Query<Object?>>` | Every query, as a copy — safe to iterate while removing. | `getAll()` |
| [`findAll`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryCache/findAll.html) | `List<Query<Object?>> findAll({QueryFilters filters = const QueryFilters()})` | Every query matching `filters`, in insertion order. The key matches as a **prefix** unless `exact: true`. | `findAll` |
| [`find`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryCache/find.html) | `Query<Object?>? find({required QueryFilters filters})` | The first match, or `null`. An unset `exact` means an **exact** key match here. | `find` |
| `get` | `Query<T>? get<T>(QueryKey queryKey)` | The query stored under exactly this key, or `null`. Throws `QueryDataTypeError` when it holds a different type — a subtype or the nullable type included. | `get(queryHash)` |
| `build` | `Query<T> build<T>(QueryClient client, DefaultedQueryOptions<T> options, {QueryState<T>? state})` | The query for the key, created if missing. `state` restores a saved entry and is used only on creation; a restored `fetchStatus` is set back to `idle`, since no fetch survives the process it ran in. A `success` state without data throws `ArgumentError`. | `build` |
| `add` | `void add(Query<Object?> query)` | Puts a hand-built query in and emits `QueryAdded`; a key that already has a query keeps it. A query that was removed throws `StateError`. | `add` |
| `remove` | `void remove(Query<Object?> query)` | Takes the query out, cancels its fetch silently, stops its collection timer, emits `QueryRemoved`. | `remove` |
| `clear` | `void clear()` | Removes every query, one `QueryRemoved` each. Prefer `client.clear()`, which also clears the mutation cache inside one batch. | `clear` |
| `notify` | `void notify(QueryCacheEvent event)` | Delivers an event to every listener. The cache calls it; rarely useful from outside. | `notify` |
| `onFocus` | `void onFocus({bool refetchQueries = true})` | Every query reacts to the app returning to the foreground. A mounted client calls it. `refetchQueries: false` lets paused fetches continue without starting new ones. | `onFocus()` |
| `onOnline` | `void onOnline()` | Every query reacts to the device coming back online. A mounted client calls it. | `onOnline()` |
| `onSuccess`, `onError`, `onSettled` | see above | The constructor's hooks, readable. | `config` |

### Query cache events

[`QueryCacheEvent`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryCacheEvent-class.html)
is sealed, so a listener can `switch` over it exhaustively. Every event
carries `query`, typed `Query<Object?>` because a cache listener sees every
key. The observer an event names is a
[`QueryObserverRef`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserverRef-class.html):
an identity to hold and compare, not something to drive.

| Event | Carries | Emitted when | TanStack `type` |
|---|---|---|---|
| `QueryAdded` | `query` | A query was created — `build` or `add`, the first time anything used its key. | `added` |
| `QueryRemoved` | `query` | A query left the cache: collected after `gcTime` without observers, or removed by `removeQueries`, `remove` or `clear`. | `removed` |
| `QueryUpdated` | `query`, `action` | The query's state changed. Emitted for every [action](#query-actions). | `updated` |
| `QueryObserverAdded` | `query`, `observer` | An observer attached. This is also what cancels the query's pending garbage collection. | `observerAdded` |
| `QueryObserverRemoved` | `query`, `observer` | An observer detached. When it was the last one, the fetch in flight has already been told to stop retrying and the collection timer is armed. | `observerRemoved` |
| `QueryObserverOptionsUpdated` | `query`, `observer` | An observer's options changed. A key change emits `QueryObserverRemoved` on the old query, `QueryObserverAdded` on the new one, then this on the new one. | `observerOptionsUpdated` |
| `QueryObserverResultsUpdated` | `query` | An observer delivered a new result, after its listeners ran. | `observerResultsUpdated` |

The [debugging guide](../guides/debugging.md) shows a listener that logs
them.

### Query actions

`QueryUpdated.action` is a
[`QueryAction`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryAction-class.html),
also sealed. Actions are read-only from outside: only a `Query` dispatches
one.

| Action | Fields | Meaning | TanStack `type` |
|---|---|---|---|
| `QueryFetchAction` | `meta` (`Object?`) | A fetch started. Resets the failure count, records `meta` as `state.fetchMeta`, and moves `fetchStatus` to `fetching` — or `paused` when the network mode forbids starting. | `fetch` |
| `QueryFailedAction` | `failureCount`, `error`, `stackTrace` | One attempt failed and will be retried. `status` and data are untouched. | `failed` |
| `QuerySuccessAction<T>` | `data`, `dataUpdatedAt` (`DateTime?`), `manual` (`bool`) | Data arrived, fetched or written with `setQueryData` (`manual: true`). A manual write leaves a fetch in flight alone. | `success` |
| `QueryErrorAction` | `error`, `stackTrace` | A fetch failed for good, or was cancelled with neither `silent` nor `revert`. Existing data is flagged as invalidated. | `error` |
| `QueryPauseAction` | — | The fetch was suspended: offline, or a retry waiting for the foreground. | `pause` |
| `QueryContinueAction` | — | A paused fetch resumed. | `continue` |
| `QueryInvalidateAction` | — | `invalidateQueries` marked the query stale. Only `isInvalidated` changes. | `invalidate` |
| `QuerySetStateAction<T>` | `state` | The whole state was replaced: a reset, a revert after a cancel, or `Query.setState`. | `setState` |

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

| Callback | Signature | Default | Meaning | TanStack |
|---|---|---|---|---|
| `onMutate` | `FutureOr<void> Function(Object? variables, Mutation<Object?, Object?, Object?> mutation)` | unset | Runs when any mutation is submitted. What it returns is ignored. A throw fails the mutation without running its function. | `onMutate(variables, mutation, context)` |
| `onSuccess` | `FutureOr<void> Function(Object? data, Object? variables, Object? onMutateResult, Mutation<Object?, Object?, Object?> mutation)` | unset | Runs after any mutation succeeds. A throw turns the success into an error. | `onSuccess(…, mutation, context)` |
| `onError` | `FutureOr<void> Function(Object error, StackTrace stackTrace, Object? variables, Object? onMutateResult, Mutation<Object?, Object?, Object?> mutation)` | unset | Runs after any mutation fails for good. A throw is reported to the zone and the remaining callbacks still run. | `onError(…, mutation, context)` |
| `onSettled` | `FutureOr<void> Function(Object? data, Object? error, StackTrace? stackTrace, Object? variables, Object? onMutateResult, Mutation<Object?, Object?, Object?> mutation)` | unset | Runs after any mutation settles, success or failure. | `onSettled(…, mutation, context)` |

TanStack Query passes a trailing function context to each hook; here the
mutation is the last argument, and the error comes with its stack trace.

### Members

| Member | Signature | Meaning | TanStack |
|---|---|---|---|
| [`subscribe`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationCache/subscribe.html) | `void Function() subscribe(void Function(MutationCacheEvent event) listener)` | Calls `listener` with every [event](#mutation-cache-events); returns the unsubscribe function. Listeners are isolated, as on the query cache. | `subscribe` |
| `mutations` | `List<Mutation<Object?, Object?, Object?>>` | Every mutation in submission order, as a copy. | `getAll()` |
| `findAll` | `List<Mutation<…>> findAll({MutationFilters filters = const MutationFilters()})` | Every match, in submission order. The key matches as a prefix unless `exact: true`. | `findAll` |
| `find` | `Mutation<…>? find({required MutationFilters filters})` | The first match, or `null`. An unset `exact` means an exact match here. | `find` |
| `build` | `Mutation<D, V, R> build<D, V, R>(QueryClient client, DefaultedMutationOptions<D, V, R> options, {MutationState<D, V, R>? state})` | Creates a mutation with the next id and adds it. `state` restores an offline mutation; a restored `pending` state is set to paused, and one without variables (unless `null` is a valid variables value) throws `ArgumentError`. | `build` |
| `add` | `void add(Mutation<…> mutation)` | Appends a hand-built mutation and emits `MutationAdded`. Adding the same instance twice does nothing; a removed one throws `StateError`. | `add` |
| `remove` | `void remove(Mutation<…> mutation)` | Takes the mutation out and emits `MutationRemoved`. A running one is told to stop retrying: the attempt in flight still settles, a backoff is cut short, and a paused one fails with `CancelledError`. | `remove` — there a removed mutation keeps retrying |
| `clear` | `void clear()` | Removes every mutation, stopping retries as `remove` does. Never starts a mutation queued in a scope. | `clear` |
| `resumePaused` | `Future<void> resumePaused()` | Continues every paused mutation that can run now; completes when they have settled. Errors stay with each mutation. `QueryClient.resumePausedMutations` calls it. | `resumePausedMutations` — which there resumes nothing while offline; here each mutation's network mode decides |
| `notify` | `void notify(MutationCacheEvent event)` | Delivers an event to every listener. | `notify` |

### Mutation cache events

[`MutationCacheEvent`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationCacheEvent-class.html)
is sealed. Every event carries `mutation`, typed
`Mutation<Object?, Object?, Object?>`.

| Event | Carries | Emitted when | TanStack `type` |
|---|---|---|---|
| `MutationAdded` | `mutation` | A mutation was created and appended — the moment `mutate` is called, or a restored one is built. | `added` |
| `MutationRemoved` | `mutation` | A mutation left the cache: collected, or removed by `remove` or `clear`. | `removed` |
| `MutationUpdated` | `mutation`, `action` | The mutation's state changed. Emitted for every [action](#mutation-actions). | `updated` |
| `MutationObserverAdded` | `mutation`, `observer` | An observer attached; also cancels the pending collection. | `observerAdded` |
| `MutationObserverRemoved` | `mutation`, `observer` | An observer detached; when it was the last one, the collection timer is armed. | `observerRemoved` |
| `MutationObserverOptionsUpdated` | `mutation`, `observer` | An observer's options changed while it stayed on the same mutation. | `observerOptionsUpdated` |

### Mutation actions

`MutationUpdated.action` is a sealed
[`MutationAction`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationAction-class.html).

| Action | Fields | Meaning | TanStack `type` |
|---|---|---|---|
| `MutationPendingAction` | `variables`, `onMutateResult`, `isPaused` | A run started: status `pending`, fresh `submittedAt`. Dispatched a second time once `onMutate` has run, when it produced a result or the pause changed. | `pending` |
| `MutationFailedAction` | `failureCount`, `error`, `stackTrace` | One attempt failed and will be retried. | `failed` |
| `MutationSuccessAction` | `data` | The function resolved and every success callback ran. | `success` |
| `MutationErrorAction` | `error`, `stackTrace` | The run failed for good — the last attempt's error, a callback's, or a `CancelledError` after `cancel`. | `error` |
| `MutationPauseAction` | — | The run was suspended: offline, in the background, or queued behind its scope. | `pause` |
| `MutationContinueAction` | — | A paused run resumed, or a restored one was run. | `continue` |

## `Query`

[`Query<TQueryData>`](https://pub.dev/documentation/query_kit/latest/query_kit/Query-class.html)
is one cache entry. You never construct one; you meet it in `find`/`findAll`,
in every cache event and cache callback, in a `QueryFilters.predicate`, and in
callbacks such as `StaleTime.dynamic`. It has one type parameter, the data
type the cache stores.

| Member | Signature | Meaning | TanStack |
|---|---|---|---|
| `queryKey` | `QueryKey` | The key it is stored under. | `queryKey` |
| `dataType` | `Type` | The exact data type it holds. A cache listener sees `Query<Object?>`; this recovers the real type. | — |
| `state` | `QueryState<TQueryData>` | The current [state](#querystate). Replaced on every action. | `state` |
| `options` | `DefaultedQueryOptions<TQueryData>` | The options in force, fully resolved. | `options` |
| `meta` | `Object?` | The options' `meta`, for cache callbacks and listeners. | `meta` |
| `client` | `QueryClient` | The client it belongs to. | — |
| `observers` | `List<QueryObserverRef>` | The attached observers, read-only. | `observers` |
| `observersCount` | `int` | How many observers are attached. Zero makes it collectable after `gcTime`. | `getObserversCount()` |
| `future` | `Future<TQueryData>?` | The fetch in flight, shared by every caller, or `null`. | `promise` |
| `resetState` | `QueryState<TQueryData>` | The state `reset` returns to: pending, or the `initialData` seed. | `resetState` |
| `isStale()` | `bool isStale()` | With observers: whether any observer's current result is stale. Without: no data, or invalidated. | `isStale()` |
| `isStaleByTime(staleTime)` | `bool isStaleByTime(StaleTime staleTime)` | Whether the data is older than `staleTime`. `StaleTime.static` outranks an invalidation; `StaleTime.infinite` does not. | `isStaleByTime` |
| `isActive()` | `bool isActive()` | Whether any observer's `enabled` resolves to true. What `QueryTypeFilter.active` selects. | `isActive()` |
| `isDisabled()` | `bool isDisabled()` | With observers: none is enabled. Without: nothing has ever been fetched. | `isDisabled()` |
| `isStatic()` | `bool isStatic()` | Whether an attached observer uses `StaleTime.static`. | `isStatic()` |
| `isFetched()` | `bool isFetched()` | Whether a fetch or a manual write has ever settled. | `isFetched()` |
| `fetch` | `Future<TQueryData> fetch({DefaultedQueryOptions<TQueryData>? options, FetchOptions? fetchOptions})` | Fetches now, joining a fetch in flight unless `fetchOptions.cancelRefetch` is set on a query with data. Usually reached through `client.query` or an observer. | `fetch` |
| `invalidate` | `void invalidate()` | Marks the data stale; refetches nothing. | `invalidate` |
| `cancel` | `Future<void> cancel({bool revert = false, bool silent = false})` | Cancels the fetch in flight. Both `false`: the fetch fails with `CancelledError`, recorded and reported to `onError`. `revert`: back to the state before the fetch, no error. `silent`: no error, state left alone, and `fetchStatus` returns to `idle` when no new fetch follows. See [errors](errors.md#cancellederror). | `cancel` — there a silent cancel with no successor stays `fetching` |
| `reset` | `void reset()` | Back to `resetState`, cancelling any fetch; refetches nothing. | `reset` |
| `setState` | `void setState(QueryState<TQueryData> state)` | Replaces the **whole** state, for a persistence layer or a devtools panel. `fetchStatus` is installed as given. A `success` state without data throws `ArgumentError`. | `setState(partial)` — there it merges a partial state |

### `QueryState`

[`QueryState<TQueryData>`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryState-class.html)
is what `query.state` and `client.getQueryState` return. Observers turn it
into a `QueryResult`; see [results](results.md).

| Field | Type | Default | Meaning | TanStack |
|---|---|---|---|---|
| `status` | `QueryStatus` | `pending` | `pending`, `success` or `error`. | `status` |
| `fetchStatus` | `FetchStatus` | `idle` | `fetching`, `paused` or `idle`. | `fetchStatus` |
| `hasData` | `bool` | `false` | Whether `data` is meaningful — true even when the data is `null`. | — (`data !== undefined`) |
| `data` | `TQueryData?` | `null` | The cached data. | `data` |
| `dataUpdatedAt` | `DateTime?` | `null` | When data was last written; `staleTime` counts from here. | `dataUpdatedAt` (a number) |
| `dataUpdateCount` | `int` | `0` | Writes so far, fetched and manual. | `dataUpdateCount` |
| `error` | `Object?` | `null` | Why the last fetch failed; cleared by the next success. | `error` |
| `errorStackTrace` | `StackTrace?` | `null` | The stack trace of `error`. | — |
| `errorUpdatedAt` | `DateTime?` | `null` | When the query last ended in an error. | `errorUpdatedAt` |
| `errorUpdateCount` | `int` | `0` | Errors over the query's whole life; never goes down. | `errorUpdateCount` |
| `consecutiveErrorCount` | `int` | `0` | Fetches in a row that ended in an error. Reset only by fetched data; a manual write or a cancel leaves it. | — |
| `fetchFailureCount` | `int` | `0` | Failed attempts inside the current fetch. | `fetchFailureCount` |
| `fetchFailureReason` | `Object?` | `null` | What the latest failed attempt threw. | `fetchFailureReason` |
| `fetchFailureStackTrace` | `StackTrace?` | `null` | Its stack trace. | — |
| `fetchMeta` | `Object?` | `null` | What the fetch carried; an infinite query's page direction. | `fetchMeta` |
| `isInvalidated` | `bool` | `false` | Stale regardless of `staleTime`: set by an invalidation or a failed fetch. | `isInvalidated` |
| `isFetched` | `bool` (getter) | — | Whether anything has ever been fetched or written. | — |

## `Mutation`

[`Mutation<TData, TVariables, TOnMutateResult>`](https://pub.dev/documentation/query_kit/latest/query_kit/Mutation-class.html)
is one run of a mutation function. `MutationObserver.mutate` builds it; you
meet it in cache events, in `findAll`, in a `MutationFilters.predicate` and in
a `MutationStateObserver`'s `select`.

| Member | Signature | Meaning | TanStack |
|---|---|---|---|
| `mutationId` | `int` | Unique within the cache, in submission order. | `mutationId` |
| `state` | `MutationState<TData, TVariables, TOnMutateResult>` | The current state. | `state` |
| `options` | `DefaultedMutationOptions<TData, TVariables, TOnMutateResult>` | The options in force. Retry, delay, network mode and scope are fixed for each run. | `options` |
| `meta` | `Object?` | The options' `meta`. | `meta` |
| `client` | `QueryClient` | The client it belongs to. | — |
| `observers` | `List<MutationObserverRef>` | The attached observers, read-only. | `observers` |
| [`cancel`](https://pub.dev/documentation/query_kit/latest/query_kit/Mutation/cancel.html) | `void cancel()` | Fails the run in flight with a `CancelledError`: the signal is cancelled, no further attempt is made, `onError` and `onSettled` run. A paused, queued or restored run fails without its function running. Once the function has returned, it does nothing. See [cancelling mutations](../guides/cancelling-mutations.md). | — |
| `continueMutation` | `Future<void> continueMutation()` | Releases a paused mutation, or runs a restored one with its saved variables; completes when it settles. `resumePaused` is the usual caller. | `continue()` |
| `execute` | `Future<TData> execute(TVariables variables)` | Runs the mutation once, callbacks included. The observer calls it; you call `mutate`. | `execute` |

`MutationStatus` is `idle`, `pending`, `success` or `error`. A mutation stays
`pending` until its callbacks have run, `onSettled`'s future included.

| `MutationState` field | Type | Default | Meaning | TanStack |
|---|---|---|---|---|
| `status` | `MutationStatus` | `idle` | Where the mutation is in its life. | `status` |
| `variables` | `TVariables?` | `null` | The variables of the run in flight or last finished. | `variables` |
| `hasVariables` | `bool` | `false` | Whether `variables` was set by a run — `null` is then a real value. | — |
| `data` | `TData?` | `null` | What the last successful run returned. | `data` |
| `hasData` | `bool` | `false` | Whether `data` is meaningful. | — |
| `error` | `Object?` | `null` | Why the last run failed. | `error` |
| `errorStackTrace` | `StackTrace?` | `null` | Its stack trace. | — |
| `onMutateResult` | `TOnMutateResult?` | `null` | What `onMutate` returned. | `context` |
| `failureCount` | `int` | `0` | Failed attempts of the current run. | `failureCount` |
| `failureReason` | `Object?` | `null` | What the last failed attempt threw. | `failureReason` |
| `isPaused` | `bool` | `false` | Parked: offline, in the background, or queued behind its scope. | `isPaused` |
| `submittedAt` | `DateTime?` | `null` | When the run was submitted. | `submittedAt` (a number) |

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

| Member | Signature | Same as | TanStack |
|---|---|---|---|
| [`observe`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/observe.html) | `QueryObserver<TQueryData, TData> observe<TQueryData, TData>(QueryObserverOptionsBase<TQueryData, TData> options)` | `QueryObserver(client, options)` | `new QueryObserver(client, options)` |
| [`observeInfinite`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryClient/observeInfinite.html) | `InfiniteQueryObserver<TPageData, TPageParam, TData> observeInfinite<…>(InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options)` | `InfiniteQueryObserver(client, options)` | `new InfiniteQueryObserver(client, options)` |

The caller owns the observer's lifetime: unsubscribe, or `destroy`, when
done.

### `QueryObserver`

[`QueryObserver<TQueryData, TData>`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserver-class.html)
follows one query. `TQueryData` is what the cache holds, `TData` what the
observer reports — the same type unless the options have a `select`.

| Member | Signature | Meaning | TanStack |
|---|---|---|---|
| constructor | `QueryObserver(QueryClient client, QueryObserverOptionsBase<TQueryData, TData> options)` | Resolves the options against the client's defaults and builds or joins the query. Fetches nothing. Throws `ArgumentError` when there is no `select` and a `TQueryData` is not a `TData`. | `constructor` |
| [`subscribe`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserver/subscribe.html) | `void Function() subscribe(void Function(QueryResult<TData> result) listener)` | The first listener attaches the observer, fetches if due (no data, or stale data and `refetchOnMount`) and arms the stale and polling timers. The last one leaving detaches it. A throw from an option callback during the first subscribe propagates and leaves nothing registered. | `subscribe` — there the listener stays registered after such a throw |
| `hasListeners` | `bool` | Whether anyone is subscribed ("mounted"). | `hasListeners()` |
| `currentResult` | `QueryResult<TData>` | The latest result; readable right after construction. | `getCurrentResult()` |
| `currentQuery` | `Query<TQueryData>` | The entry followed now. | `getCurrentQuery()` |
| `options` | `DefaultedQueryObserverOptions<TQueryData, TData>` | The options in force, resolved. | `options` |
| [`setOptions`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserver/setOptions.html) | `void setOptions(QueryObserverOptionsBase<TQueryData, TData> options)` | Replaces the options, moving to another query if the key changed. Equal options are cheap and notify nobody. While subscribed, it fetches when it lands on stale or missing data, or `enabled` turned true over stale data. `enabled` is compared with what it resolved to the last time options were applied, so an `Enabled.when` over outside state takes effect on the next `setOptions`. | `setOptions` — there both sides are evaluated at the same instant |
| `getOptimisticResult` | `QueryResult<TData> getOptimisticResult(QueryObserverOptionsBase<TQueryData, TData> options)` | The result these options would give now, the fetch about to start included — the right read for a first build. Fetches nothing. | `getOptimisticResult` |
| [`refetch`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserver/refetch.html) | `Future<QueryResult<TData>> refetch({bool cancelRefetch = true})` | Fetches whether or not the data is stale, `enabled` ignored. Completes with the result; never with an error. | `refetch` — no `throwOnError` |
| `updateResult` | `void updateResult()` | Recomputes the result and notifies if it changed. The observer calls it itself. | `updateResult` |
| `destroy` | `void destroy()` | Clears listeners and timers and leaves the query, which starts its `gcTime` clock. | `destroy` |

### `InfiniteQueryObserver`

[`InfiniteQueryObserver<TPageData, TPageParam, TData>`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryObserver-class.html)
is a `QueryObserver` over `InfiniteData<TPageData, TPageParam>` with paging
on top. Everything in the table above applies. The paging flags live on the
observer, not on the result, so the sealed result keeps one shape; a change
in any of them notifies listeners even when the result itself did not
change. See [infinite queries](../guides/infinite-queries.md).

| Member | Signature | Meaning | TanStack |
|---|---|---|---|
| constructor | `InfiniteQueryObserver(QueryClient client, InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options)` | The paging half of the options becomes the query's fetch behaviour. | `constructor` |
| `infiniteOptions` | `InfiniteQueryOptions<TPageData, TPageParam>` | The paging functions in force. | — |
| `setInfiniteOptions` | `void setInfiniteOptions(InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options)` | The typed form of `setOptions`. | `setOptions` |
| `setOptions` | inherited | Takes only options that carry the paging behaviour (`client.infiniteObserverOptions(…)`); plain observer options throw `UnsupportedError`. | `setOptions` |
| `getOptimisticInfiniteResult` | `QueryResult<TData> getOptimisticInfiniteResult(InfiniteQueryObserverOptionsBase<…> options)` | The typed form of `getOptimisticResult`. | `getOptimisticResult` |
| [`fetchNextPage`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryObserver/fetchNextPage.html) | `Future<QueryResult<TData>> fetchNextPage({bool cancelRefetch = true})` | Fetches the page after the last one and appends it. Does nothing when `getNextPageParam` returns `null`; loads the first page when there is none. With `cancelRefetch`, a fetch already running on a query with pages is cancelled — check `isFetchingNextPage` first. Never completes with an error. | `fetchNextPage` |
| `fetchPreviousPage` | `Future<QueryResult<TData>> fetchPreviousPage({bool cancelRefetch = true})` | The mirror: prepends the page before the first one. | `fetchPreviousPage` |
| `hasNextPage` | `bool` | Whether `fetchNextPage` would fetch anything. False before the first page. | result's `hasNextPage` |
| `hasPreviousPage` | `bool` | Whether `fetchPreviousPage` would. | result's `hasPreviousPage` |
| `isFetchingNextPage` | `bool` | A `fetchNextPage` is in flight. | result's `isFetchingNextPage` |
| `isFetchingPreviousPage` | `bool` | A `fetchPreviousPage` is in flight. | result's `isFetchingPreviousPage` |
| `isFetchNextPageError` | `bool` | The query's error came from `fetchNextPage`; the held pages are still there. | result's `isFetchNextPageError` |
| `isFetchPreviousPageError` | `bool` | The error came from `fetchPreviousPage`. | result's `isFetchPreviousPageError` |
| `isRefetching` | `bool` | The held pages are being refetched — a page being added does not count. | result's `isRefetching` |
| `isRefetchError` | `bool` | A refetch failed, not a page fetch. | result's `isRefetchError` |

### `QueriesObserver`

[`QueriesObserver<TQueryData, TData>`](https://pub.dev/documentation/query_kit/latest/query_kit/QueriesObserver-class.html)
follows a list of queries of one type, one `QueryObserver` per entry, and
reports the list of results in input order. For a fixed handful of
different types, observe them separately and combine the results; see
[combining queries](../guides/combining-queries.md).

| Member | Signature | Meaning | TanStack |
|---|---|---|---|
| constructor | `QueriesObserver(QueryClient client, List<QueryObserverOptionsBase<TQueryData, TData>> queries)` | Builds or joins each query; fetches nothing. Throws `ArgumentError` when an entry has no `select` and the two types differ. | `constructor` — no `combine` option |
| `subscribe` | `void Function() subscribe(void Function(List<QueryResult<TData>>) listener)` | The first listener subscribes every member, which fetches each one due; the last one leaving unsubscribes them. | `subscribe` |
| `hasListeners` | `bool` | Whether anyone is subscribed. | `hasListeners()` |
| `currentResult` | `List<QueryResult<TData>>` | The latest results, read-only, in input order. | `getCurrentResult()` |
| `observers` | `List<QueryObserver<TQueryData, TData>>` | The members, read-only; their lifetime belongs to this observer. | `getObservers()` |
| `getOptimisticResult` | `List<QueryResult<TData>> getOptimisticResult()` | Each member's optimistic result for its current options. | `getOptimisticResult(queries, combine)` |
| `setQueries` | `void setQueries(List<QueryObserverOptionsBase<TQueryData, TData>> queries)` | Replaces the list. Members are matched by key and occurrence and handed their new options; new keys get new members; members left over are destroyed. If an entry throws, the list stays as it was. | `setQueries` |
| `destroy` | `void destroy()` | Removes every listener and destroys every member. | `destroy` |

### `MutationObserver`

[`MutationObserver<TData, TVariables, TOnMutateResult>`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationObserver-class.html)
runs mutations and reports the latest one's state as a `MutationResult`.
Each `mutate` builds a new `Mutation`; the observer follows the newest.

| Member | Signature | Meaning | TanStack |
|---|---|---|---|
| constructor | `MutationObserver(QueryClient client, MutationOptions<TData, TVariables, TOnMutateResult> options)` | An idle observer. Throws `ArgumentError` when both `mutationFn` and `mutationFnWithContext` are set. | `constructor` |
| `subscribe` | `void Function() subscribe(void Function(MutationResult<TData, TVariables> result) listener)` | The first listener re-attaches to the mutation being watched; the last one leaving detaches, starting its `gcTime` clock. | `subscribe` |
| `hasListeners` | `bool` | Whether anyone is subscribed. Per-call callbacks only run while this is true. | `hasListeners()` |
| `currentResult` | `MutationResult<TData, TVariables>` | Idle until the first `mutate`, then the observed mutation's state. | `getCurrentResult()` |
| `options` | `DefaultedMutationOptions<TData, TVariables, TOnMutateResult>` | The options in force, resolved. | `options` |
| `setOptions` | `void setOptions(MutationOptions<TData, TVariables, TOnMutateResult> options)` | Replaces the options. A changed `mutationKey` resets the observer; otherwise a mutation still in flight takes the new options. | `setOptions` |
| [`mutate`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationObserver/mutate.html) | `void mutate(TVariables variables, {MutateCallbacks<TData, TVariables, TOnMutateResult>? callbacks})` | Starts a run and returns at once. Errors reach the callbacks and the result, never the zone. | `mutate` without awaiting |
| `mutateAsync` | `Future<TData> mutateAsync(TVariables variables, {MutateCallbacks<…>? callbacks})` | Starts a run; completes with the data or throws the error, after the callbacks ran. | `mutate` (it returns a promise) |
| `cancel` | `void cancel()` | Cancels the run this observer shows — see `Mutation.cancel`. | — |
| `reset` | `void reset()` | Back to idle. The mutation keeps running and firing its own callbacks. | `reset` |
| `destroy` | `void destroy()` | Drops every listener and leaves the mutation, so it can be collected. | — |

### `MutationStateObserver`

[`MutationStateObserver<TSelected>`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationStateObserver-class.html)
selects a value from every matching mutation in the cache — not only the
ones one observer started. See [mutation state](../guides/mutation-state.md).

| Member | Signature | Meaning | TanStack |
|---|---|---|---|
| constructor | `MutationStateObserver(QueryClient client, {MutationFilters filters = const MutationFilters(), required TSelected Function(Mutation<Object?, Object?, Object?> mutation) select})` | A selection, readable at once. | `useMutationState({ filters, select })` |
| [`typed`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationStateObserver/typed.html) | `static MutationStateObserver<TSelected> typed<TData, TVariables, TOnMutateResult, TSelected>(QueryClient client, {MutationFilters filters, required TSelected Function(Mutation<TData, TVariables, TOnMutateResult>) select})` | Only mutations **declared** with these types, handed to `select` typed. The type test runs before `filters.predicate`, which may therefore cast. A mutation whose types were never written or inferred is `Mutation<Object?, Object?, Object?>` and drops out. | — |
| `currentResult` | `List<TSelected>` | The selected values in submission order. Read without listeners, it refreshes from the cache. | the hook's return value |
| `hasListeners` | `bool` | Whether it follows cache events. | — |
| `subscribe` | `void Function() subscribe(void Function(List<TSelected>) listener)` | Follows the mutation cache while anyone listens. No initial snapshot. Equal selections (compared deeply) do not notify. | — |
| `setOptions` | `void setOptions({MutationFilters? filters, MutationStateSelect<TSelected>? select})` | Replaces either and recomputes. A `typed` observer keeps its type test. | — |
| `destroy` | `void destroy()` | Removes listeners and the cache subscription. | — |

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

| Field | Type | Default | Meaning | TanStack |
|---|---|---|---|---|
| `queryKey` | `QueryKey?` | `null` — every key | The key to match, as a prefix: `QueryKey(['todos'])` matches `['todos']` and `['todos', 3]`. | `queryKey` |
| `exact` | `bool?` | `null` — prefix for `findAll` and the bulk operations, exact for `find` | Whether `queryKey` must be the whole key. | `exact` |
| `type` | `QueryTypeFilter?` | `null` — same as `all` | Observed queries, unobserved ones, or both. | `type` |
| `stale` | `bool?` | `null` | `true` matches queries whose `isStale()` is true, `false` fresh ones. | `stale` |
| `fetchStatus` | `FetchStatus?` | `null` | `fetching`, `paused` or `idle`. `isFetching` ignores it and always counts `fetching`. | `fetchStatus` |
| `status` | `QueryStatus?` | `null` | `pending`, `success` or `error`. | — |
| `predicate` | `bool Function(Query<Object?> query)?` | `null` | Your own test, run last, on queries that passed the other fields. | `predicate` |

[`QueryTypeFilter`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryTypeFilter.html)
is `all` (every query), `active` (at least one enabled observer) or
`inactive` (no enabled observer: none at all, or every one disabled) —
TanStack's `'all'`, `'active'`, `'inactive'`.

[`RefetchType`](https://pub.dev/documentation/query_kit/latest/query_kit/RefetchType.html)
is what `invalidateQueries(refetchType: …)` refetches after marking:

| Value | Refetches | TanStack |
|---|---|---|
| `active` | invalidated queries with an enabled observer | `'active'` |
| `inactive` | invalidated queries nobody observes | `'inactive'` |
| `all` | every invalidated query | `'all'` |
| `none` | nothing; observers pick it up on their next trigger | `'none'` |
| unset | the filters' `type`, else `active` | `refetchType` unset |

`refetchType` is a parameter of `invalidateQueries`, not a field of the
filters as in TanStack Query. The matched set is fixed before invalidating,
so a filter over state (`stale: false`, say) still refetches what it marked.

### `MutationFilters`

[`MutationFilters`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationFilters-class.html)
is taken by `MutationCache.find` and `findAll`, `QueryClient.isMutating`,
`MutationStateObserver` and the binding's `MutationStateController`.

| Field | Type | Default | Meaning | TanStack |
|---|---|---|---|---|
| `mutationKey` | `QueryKey?` | `null` — every mutation | The key to match, as a prefix. A mutation without a key never matches a key filter. | `mutationKey` |
| `exact` | `bool?` | `null` — prefix for `findAll` and `isMutating`, exact for `find` | Whether `mutationKey` must be the whole key. | `exact` |
| `status` | `MutationStatus?` | `null` | `idle`, `pending`, `success` or `error`. `isMutating` ignores it and always counts `pending`. | `status` |
| `predicate` | `bool Function(Mutation<Object?, Object?, Object?> mutation)?` | `null` | Your own test, run last. | `predicate` |

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

| Member | Signature | Meaning | TanStack |
|---|---|---|---|
| constructor | `AppFocusManager({Duration refetchMinBackgroundDuration = Duration.zero})` | Throws `ArgumentError` for a negative duration. | — |
| `refetchMinBackgroundDuration` | `Duration` | An absence shorter than this does not start refetches on return; paused work still resumes. | — |
| `isFocused()` | `bool isFocused()` | The value last set, or `true` when nothing is set. | `isFocused()` |
| [`setFocused`](https://pub.dev/documentation/query_kit/latest/query_kit/AppFocusManager/setFocused.html) | `void setFocused(bool? focused)` | Sets the state by hand; a change notifies the listeners. `null` forgets the value, and `isFocused()` answers `true`. | `setFocused` |
| [`setEventListener`](https://pub.dev/documentation/query_kit/latest/query_kit/AppFocusManager/setEventListener.html) | `void setEventListener(FocusSetup setup)` | Replaces the source of focus events; see the contract below. | `setEventListener` |
| `onFocus` | `void onFocus({bool refetchQueries = true})` | Notifies every listener with the current state. | `onFocus()` |
| `shouldRefetchOnFocus` | `bool` | Whether the current notification allows new refetches. | — |
| `subscribe` | `void Function() subscribe(void Function(bool focused) listener)` | Listens to changes; a mounted client is such a listener. | `subscribe` |
| `hasListeners` | `bool` | Whether anyone listens. | `hasListeners()` |

`FocusSetup` is `void Function() Function(void Function(bool? focused) setFocused)`.

### `OnlineManager`

[`OnlineManager`](https://pub.dev/documentation/query_kit/latest/query_kit/OnlineManager-class.html)
tracks whether the device believes it is online. The default is "online".
Under `NetworkMode.online`, the default, fetches and mutations pause while
offline.

| Member | Signature | Meaning | TanStack |
|---|---|---|---|
| constructor | `OnlineManager()` | Reports online until told otherwise. | — |
| `isOnline()` | `bool isOnline()` | The value last set, or `true`. | `isOnline()` |
| [`setOnline`](https://pub.dev/documentation/query_kit/latest/query_kit/OnlineManager/setOnline.html) | `void setOnline(bool online)` | Sets the state by hand. A change notifies; setting the same value does nothing. | `setOnline` |
| [`setEventListener`](https://pub.dev/documentation/query_kit/latest/query_kit/OnlineManager/setEventListener.html) | `void setEventListener(OnlineSetup setup)` | Replaces the source of connectivity events; see below. | `setEventListener` |
| `subscribe` | `void Function() subscribe(void Function(bool online) listener)` | Listens to changes. | `subscribe` |
| `hasListeners` | `bool` | Whether anyone listens. | `hasListeners()` |

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

| Member | Signature | Meaning | TanStack |
|---|---|---|---|
| constructor | `NotifyManager()` | An independent queue with the microtask scheduler. | — |
| `shared` | `static final NotifyManager shared` | One process-wide instance, for batching across clients. Not the default. | the module-level `notifyManager` |
| [`batch`](https://pub.dev/documentation/query_kit/latest/query_kit/NotifyManager/batch.html) | `T batch<T>(T Function() callback)` | Runs `callback`, holding what is scheduled inside it until the outermost batch ends. | `batch` |
| `batchCalls` | `void Function(A) batchCalls<A>(void Function(A) callback)` | Wraps `callback` so each call is scheduled instead of run — the way to defer and batch a cache subscription. | `batchCalls` |
| `schedule` | `void schedule(void Function() callback)` | Queues `callback` for the next flush, or hands it to the scheduler at once when no batch is open. | `schedule` |
| `flush` | `void flush()` | Delivers what is queued. `batch` calls it; rarely needed by hand. | — |
| `setScheduler` | `void setScheduler(ScheduleFunction fn)` | Replaces when a batch runs. Default: `scheduleMicrotask`. | `setScheduler` — default `setTimeout(0)` |
| `scheduler` | `ScheduleFunction` | The scheduler in force, to put back later. | — |
| `setNotifyFunction` | `void setNotifyFunction(NotifyFunction fn)` | Wraps the delivery of each notification; must call its callback exactly once. | `setNotifyFunction` |
| `setBatchNotifyFunction` | `void setBatchNotifyFunction(BatchNotifyFunction fn)` | Wraps the delivery of a whole batch; must call its callback exactly once. | `setBatchNotifyFunction` |

Only callbacks submitted through `schedule` or `batchCalls` are deferred.
Direct observer subscriptions and cache listeners still run synchronously
for each change. A callback that throws inside a flushed batch is reported
to the zone and does not discard the rest of the batch.
