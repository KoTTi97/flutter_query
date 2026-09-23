---
title: Differences from TanStack Query
description: Where query_kit behaves differently from TanStack Query on purpose — the shape of the API, the rules Dart's type system adds, and the failure cases it settles differently.
---

# Differences from TanStack Query

query_kit follows TanStack Query's behaviour: the same cache, the same
staleness and refetch rules, the same order of callbacks. Where it differs,
the difference is deliberate — usually because Dart or Flutter offers
something better, or because the JavaScript behaviour depends on something
Dart does not have. This page lists what you can notice. For a name-by-name
map, see [coming from React Query](../coming-from-react-query.md); for what
is not here at all, the [feature matrix](feature-matrix.md).

## Types

| TanStack Query | query_kit |
|---|---|
| `getQueryData` casts whatever is cached to the type you asked for | a key is bound to the exact type it was first used with; reading it as another type — a supertype or a nullable one included — throws `QueryDataTypeError`. A write may store any value the entry's type can hold. See [type safety in Dart](../dart-type-safety.md#one-key-one-exact-type) |
| union-typed options: `staleTime: number \| 'static' \| fn`, `retry: boolean \| number \| fn`, … | sealed value types: `StaleTime`, `RetryPolicy`, `Enabled`, `RefetchOn`, `RefetchInterval`, … `null` always means "not configured" |
| `staleTime: Infinity` | `StaleTime.infinite`, distinct from `StaleTime.static` |
| `initialData: null` and `placeholderData: null` mean "none" | `InitialData.value(null)` is a value of `null`; a `.compute` returning `null` means "none" |
| one observer options object with an optional `select` | two shapes: `QueryObserverOptions<TData>` without `select`, `QuerySelectOptions<TQueryData, TData>` with `select` required. `withSelect` turns the first into the second |
| `queryKeyHashFn`, keys hashed to strings | `QueryKey` is a value type compared part by part; `debugString` is for logs |
| `TError` type parameter | errors are `Object` plus a `StackTrace` |
| a `refetchInterval` or `enabled` callback gets a typed `Query` | the callbacks of `StaleTime.dynamic`, `Enabled.when`, `RefetchInterval.dynamic` and `RefetchOn`'s computed form get a `Query<Object?>`, because the same values sit in `QueryDefaults`, which match every key and type. Cast `query.state.data` to your type inside the callback |
| `setQueryData(key, undefined)` writes nothing | there is no `undefined`, and `null` is a value: `setQueryData<Product?>(key, null)` creates the entry and writes `null` into it. A bare `setQueryData(key, null)`, with no type, is treated as "write nothing". To leave the data alone from an updater, return `null` from `updateQueryData` |
| an observer without `select` whose data type differs from the query's is not checked | refused with `ArgumentError` when it is built or handed new options; the binding's controllers also refuse a top-typed result type (`Object?`, `dynamic`) in debug builds |

## API shape

| TanStack Query | query_kit |
|---|---|
| `fetchQuery`, `prefetchQuery`, `ensureQueryData` | one `client.query`: `await` it, `.ignore()` it, `staleTime: StaleTime.static`, or `revalidateIfStale: true`. See [prefetching](../guides/prefetching.md) |
| a positional filters object | a named `filters:` argument everywhere |
| `skipToken` | `Enabled.no` — which, unlike `skipToken`, lets `refetchQueries` refetch a cached query nobody observes |
| `hasNextPage`, `fetchNextPage` on the result | on the infinite query's controller or observer; the sealed result keeps one shape |
| an infinite query's `queryFn` | `pageFn`, with a typed page context |
| `useQueries` with a tuple of different types and `combine` | `QueriesBuilder` for a list of one type; different types combine as a record of results, `(a, b).combine(…)`. See [combining queries](../guides/combining-queries.md) |
| `keepPreviousData` | `const PlaceholderData.keepPrevious()` |
| `initialDataUpdatedAt` as a function | `initialDataUpdatedAtCompute` |
| a mutation function's second argument | `mutationFnWithContext: (variables, context)`; plain `mutationFn` takes the variables only |
| `mutate(variables, { onSuccess, … })` | `mutate(variables, callbacks: MutateCallbacks(…))` |
| the rollback handle on the mutation result (`context`) | passed to `onSuccess`, `onError` and `onSettled`, not on `MutationResult` |
| module-level `focusManager`, `onlineManager`, `notifyManager` | instances owned by each `QueryClient`; `NotifyManager.shared` opts back into one shared manager |
| `QueryClientProvider` always takes a client you made | `QueryClientProvider(client: …)` borrows one; `QueryClientProvider.create` builds its own and clears it when it goes. See [the reference](widgets-and-controllers.md#queryclientprovider) |
| cache callbacks on a reassignable `config` | final constructor arguments of `QueryCache` and `MutationCache` |

## Rebuilds

| TanStack Query | query_kit |
|---|---|
| `notifyOnChangeProps` and tracked result properties | whole results are compared; `buildWhen` narrows rebuilds explicitly. See [what rebuilds](../guides/render-optimizations.md) |
| `throwOnError` | errors live in the sealed result |
| a `select` memo kept while the selector is `===` the last one | kept while it is `==` — two tear-offs of one method count as one selector |
| an observer's listeners are told about every state change | a listener is told only when the new result is not `==` to the last one it was told. On a mutation that means fewer intermediate states: one `pending` across `onMutate`, not two |
| notifications are batched to the next macrotask (`setTimeout(0)`) | batched to a microtask, so a batch lands before the next frame rather than after it. `NotifyManager.setScheduler` puts the old timing back |
| a listener that subscribes during a notification hears that same notification | it hears the next one; a listener removed during a notification is skipped, as in TanStack Query |
| a side effect on a query result needs a component that also renders | `QueryListener`, `InfiniteQueryListener` and `MutationListener` run a callback per accepted change and never rebuild their child. See [the reference](widgets-and-controllers.md#listeners) |

## Behaviour

| TanStack Query | query_kit |
|---|---|
| a fetch with no query function is retried like any failure | `MissingQueryFunctionError` is never retried |
| an imperative fetch with no retry policy writes `retry: 0` into the shared query | the one-attempt rule applies to that fetch alone |
| a state-dependent filter on `invalidateQueries` refetches none of what it invalidated | the matched set is fixed before invalidating, so it refetches what it marked |
| a filter predicate that throws, throws synchronously out of the bulk operations | `invalidateQueries`, `refetchQueries`, `resetQueries` and `cancelQueries` fail their returned future instead; `removeQueries`, which returns nothing, still throws where it is called |
| a throwing listener, `retry` or `retryDelay` callback can leave a fetch pending forever | the throw is reported to the zone, or becomes the fetch's error; the fetch settles |
| a silent cancel with no successor leaves `fetchStatus: 'fetching'` | it is put back to `idle` |
| a cancelled fetch's late response can still write over the fetch that replaced it | only the fetch that currently owns the query writes; a cancelled one settles into nothing, and a third caller joins the running fetch instead of starting another |
| a cancelled fetch's retry delay still runs to its end | the delay is dropped with the fetch |
| a `retryDelay` callback runs once more than there are retries, after the final failure too | it runs only when a retry follows |
| two callers of one fetch can see its result before the cache has it | every caller's future completes after the cache is written and its callbacks ran, so callers and cache agree |
| an `enabled` callback over state outside the cache is never seen to change | it is re-read on the next `setOptions` — in Flutter, the reader's next rebuild — and a query that became enabled then fetches if stale. See [dependent queries](../guides/dependent-queries.md) |
| `refetchQueries` with `refetchType: 'all'` skips an unobserved query that was disabled with `skipToken` | `Enabled.no` spells both `skipToken` and `enabled: false`, and the second meaning is kept: an explicit `refetchQueries` refetches such a query. `enabled` governs automatic fetching only |
| a `select` that throws on a new key's first data shows the previous key's (or the placeholder's) selection as stale data | it is a loading error with no stale data: a selection belongs to the key it came from |
| every foreground event refetches stale queries | the same by default; `refetchMinBackgroundDuration` can skip a refetch after a short absence. See [app focus refetching](../guides/window-focus-refetching.md) |
| `resumePausedMutations` waits for the whole client to be online | decided per mutation by its own network mode |
| a mutation's `setOptions` while it runs can move it to another scope | the scope is fixed for the run |
| a scope's turn goes to the earliest-*built* pending mutation | it goes to the one that started first, and it holds the scope until its callbacks have run |
| two same-scope mutations with a synchronous `onMutate` run `optimistic 1, optimistic 2, request 1` | `optimistic 1, request 1, optimistic 2`: a synchronous `onMutate` goes straight to the request, so an optimistic update reaches the frame that asked for it |
| a mutation removed from the cache keeps retrying, or stays paused for good | it stops, and fails with its last error or a `CancelledError`; its `onError` runs a moment later, which is why a widget test's teardown clears the client twice. See [testing](../guides/testing.md) |
| `mutate` on a forgotten observer re-attaches it | `mutate` on a disposed `MutationController` still runs the mutation and its options' callbacks, attaches nothing, and drops the per-call callbacks |
| mutation defaults may carry callbacks | `setMutationDefaults` carries no callbacks |
| mutations cannot be cancelled | `cancel()` fails a run with `CancelledError`; see [cancelling mutations](../guides/cancelling-mutations.md) |

## Dart and Flutter only

- **Structural sharing into your own classes.** A class implementing
  `StructurallyShareable` is walked into; any other class is a leaf. See
  [structural sharing](../guides/structural-sharing.md).
- **`consecutiveErrorCount`** on the query's state and result, for giving up
  after failures in a row. See [polling](../guides/polling.md).
- **App lifecycle as focus.** `inactive` counts as focused on phones and as
  unfocused on desktops.
- **`refetchMinBackgroundDuration`** on the focus manager, so a glance at a
  notification does not refetch every stale query on return.
- **`combine` over a record of results**, of different types, with a
  `CombinedResult` that is pending, an error or data. See [combining
  queries](../guides/combining-queries.md).
- **Cancellation is `QueryCancelToken`**, with `onCancel` as the interop point,
  because Dart has no ecosystem-wide abort signal.

## Robustness

Some JavaScript behaviours leave a fetch hanging when user code throws in an
unexpected place. Here every such throw either becomes the fetch's error or is
reported to the zone (`FlutterError.onError` in an app), and the fetch
settles either way:

- a throwing `retry` or `retryDelay` callback is the fetch's error;
- a throwing cache listener, observer listener, focus or online listener, or
  a callback queued in a notification batch, is reported to the zone, and the
  listeners after it still run;
- a throwing cancel callback is reported, and the other cancel callbacks
  still run;
- a query or mutation removed from its cache cannot be added back, so one key
  never has two live entries.

Every one of these is covered by a test in the core package's suite. The
[errors reference](errors.md#errors-from-callbacks-and-listeners) says what
each throw becomes.
