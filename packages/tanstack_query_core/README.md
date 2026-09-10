# tanstack_query_core

A Dart port of [TanStack Query](https://github.com/TanStack/query)'s
`query-core`: a cache that knows about staleness, background refetching,
retries, cancellation, mutations and infinite queries — with **no Flutter
dependency**. The Flutter binding lives in a separate package.

> An independent community port. Not affiliated with, endorsed by, or a product
> of TanStack. Ported under upstream's MIT licence, kept in `LICENSE-TANSTACK`.

## What "port" means here

Not "inspired by". Upstream's own test suite is ported case for case, keeping
upstream's test names so the two files diff against each other:

| upstream suite | ported | upstream suite | ported |
|---|---|---|---|
| `query` | 44 / 51 | `mutation` | 28 / 28 |
| `queryCache` | 14 / 16 | `mutationCache` | 16 / 16 |
| `queryObserver` | 62 / 75 | `mutationObserver` | 16 / 16 |
| `queryClient` | 106 / 156 | `infiniteQueryBehavior` | 7 / 9 |
| `retryer` | 13 / 13 | `infiniteQueryObserver` | 6 / 7 |
| `queriesObserver` | 12 / 22 | | |

Every case that is *not* ported is listed by name and category in
[`test/PORTING_NOTES.md`](https://github.com/KoTTi97/flutter_query/blob/main/packages/tanstack_query_core/test/PORTING_NOTES.md), together with every place this
port deliberately diverges. No omission is silent.

Pinned upstream revision: `50680b98c`.

## A first query

```dart
final client = QueryClient();

// Imperative: fetch and cache, completing with the data.
final sensors = await client.query<List<Sensor>>(
  QueryOptions<List<Sensor>>(
    queryKey: QueryKey(<Object?>['sensors']),
    queryFn: (context) => api.listSensors(signal: context.signal),
    staleTime: StaleTime.duration(const Duration(seconds: 45)),
  ),
);

// Reactive: an observer that keeps a widget (or anything) up to date.
final observer = client.observe<Sensor, Sensor>(
  QueryObserverOptions<Sensor, Sensor>(
    queryKey: QueryKey(<Object?>['sensors', id]),
    queryFn: (context) => api.getSensor(id, signal: context.signal),
  ),
);

final unsubscribe = observer.subscribe((result) {
  switch (result) {
    case QueryPending():
      print('loading');
    case QuerySuccess(:final data):
      print(data.name);
    case QueryError(:final error, :final staleData):
      print('$error (still showing ${staleData?.name})');
  }
});
```

The result is a **sealed** type, so `switch` is exhaustive and the data is
simply there — no `result.data!`. A `QueryError` still carries the last good
data, which is what makes stale-while-revalidate readable.

Call `client.mount()` once at start-up and `client.unmount()` when done:
without it nothing reacts to the app returning to the foreground or the
device coming back online — no `refetchOnWindowFocus`, no
`refetchOnReconnect`, no resuming of paused mutations, and a `query` that
paused offline waits for a reconnect only while mounted. The Flutter binding
mounts the client it is given; in pure Dart it is your call. A client also
owns `gcTime` timers, so end with `client.clear()` to let the process exit.

## What is Dart rather than JavaScript

The port follows upstream's behaviour, not its type tricks. The differences that
matter at the call site:

- **Two type parameters, not five.** `Query<TQueryData>` at the cache layer,
  `QueryObserver<TQueryData, TData>` where `select` needs a second. There is no
  `TError` (errors are `Object` plus a `StackTrace`) and no `TQueryKey`.
- **`QueryKey` is a value type**, deep-frozen with structural equality — not a
  hashed string. `queryKeyHashFn` is gone; the hash string survives as
  `debugString`.
- **One key, one exact type.** A key is bound to the data type it was first
  used with, and reading it as any other type throws `QueryDataTypeError` —
  related types included: `int` and `int?` are two types, and so are
  `List<Sensor>` and `List<Object?>`. Upstream casts blindly and cannot tell;
  here `getQueryData<T>`, `getQueriesData<T>`, `setQueryData<T>` and an
  observer's `TQueryData` all have to agree with the key's first use.
- **Every option union is a sealed value type.** `StaleTime`, `GcTime`,
  `Enabled`, `RetryPolicy`, `RetryDelay`, `RefetchOn`, `RefetchInterval`. `null`
  means "not configured" on every field; "off" is a value, never a magic number.
- **Cancellation is `QueryCancelToken.onCancel`.** Dart has no ecosystem-wide
  cancellation primitive, so that callback is the interop point — hand it
  `dio`'s `CancelToken.cancel`, or ignore it entirely with a client that cannot
  cancel.
- **`QueryClient.query` replaces `fetchQuery`, `prefetchQuery` and
  `ensureQueryData`**, all three deprecated upstream. Prefetch is
  `.ignore()`; "only if nothing is cached" is `staleTime: StaleTime.static`.
- **An infinite query's function is `pageFn`**, taking a typed
  `InfinitePageContext` with `pageParam` and `direction`; the paging surface
  (`hasNextPage`, `fetchNextPage`) is on `InfiniteQueryObserver`.
- **Time goes through `package:clock`**, so `fake_async` controls it completely.
- **Stale-while-revalidate is `client.query(options, revalidateIfStale: true)`.**
  Cached data comes back at once while a stale entry refreshes behind it; with
  nothing cached the fetch is awaited as usual.
- **A list of queries is `QueriesObserver`**, upstream's `useQueries` without
  the heterogeneous tuple: one data type per collection, `select` when the
  selected type differs, and observers reused by key and occurrence.
- **Cache-wide mutation state is `MutationStateObserver`**, upstream's
  `useMutationState`: `MutationFilters` plus a `select`, with concurrent runs
  under one key kept apart.
- **`AppFocusManager(refetchMinBackgroundDuration:)`** suppresses focus
  refetches after an absence too short to matter — a divergence from upstream,
  which always refetches. It never blocks paused work from resuming, and the
  default of `Duration.zero` is upstream's behaviour.

The full JS-to-Dart name map is
[`docs/coming-from-react-query.md`](https://github.com/KoTTi97/flutter_query/blob/main/docs/coming-from-react-query.md)
in the repository.

## Deliberately not in v1

Each row is recorded, with its reason, in
[`test/PORTING_NOTES.md`](https://github.com/KoTTi97/flutter_query/blob/main/packages/tanstack_query_core/test/PORTING_NOTES.md).

| Upstream | Here |
|---|---|
| Persistence and hydration (`hydrate`, `dehydrate`, `persister`, `isRestoring`) | not in v1; `Query.setState` is the door a persister would use |
| `notifyOnChangeProps`, `trackResult` | `select`, plus `buildWhen` on the binding's builders |
| `throwOnError` | errors live in the sealed result (`QueryError`) |
| `queryKeyHashFn` | `QueryKey` is a value type |
| `structuralSharing` via `replaceEqualDeep` | deep value equality for lists, maps and sets, `==` for everything else (typed models need `==`/`hashCode`), plus an optional `structuralSharing` hook |
| `useQueries`' heterogeneous tuple and its `combine` step | `QueriesObserver` is homogeneous; mixed data types need a `select`, and the returned list is mapped by the caller |
| `streamedQuery` | not ported |
| `experimental_prefetchInRender`, Suspense, `fetchOptimistic` | React-only, not ported |
| `select` on `fetchQuery` | map the future |
| SSR: `isServer`, `environmentManager`, `timeoutManager` | not ported |
| `MutationFunctionContext` | not ported; a mutation function takes its variables only |
| Callbacks in `setMutationDefaults` | not ported |
| Devtools | none |

## Requirements

Dart SDK `^3.6.0`, no Flutter. The Flutter binding, `tanstack_query_flutter`,
needs Flutter 3.27 or later; its demo has been run on the iOS simulator and on
the web, other platforms untested.

## Running the suite

```bash
dart test
```

```bash
dart analyze --fatal-infos . && dart format --set-exit-if-changed .
```

## Licence

MIT. Upstream's MIT notice is kept in `LICENSE-TANSTACK`.
