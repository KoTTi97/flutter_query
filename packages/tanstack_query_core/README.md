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
| `query` | 43 / 51 | `mutation` | 28 / 28 |
| `queryCache` | 14 / 16 | `mutationCache` | 16 / 16 |
| `queryObserver` | 60 / 75 | `mutationObserver` | 16 / 16 |
| `queryClient` | 104 / 156 | `infiniteQueryBehavior` | 7 / 9 |
| `retryer` | 13 / 13 | `infiniteQueryObserver` | 6 / 7 |

Every case that is *not* ported is listed by name and category in
[`test/PORTING_NOTES.md`](test/PORTING_NOTES.md), together with every place this
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

## What is Dart rather than JavaScript

The port follows upstream's behaviour, not its type tricks. The differences that
matter at the call site:

- **Two type parameters, not five.** `Query<TQueryData>` at the cache layer,
  `QueryObserver<TQueryData, TData>` where `select` needs a second. There is no
  `TError` (errors are `Object` plus a `StackTrace`) and no `TQueryKey`.
- **`QueryKey` is a value type**, deep-frozen with structural equality — not a
  hashed string. `queryKeyHashFn` is gone; the hash string survives as
  `debugString`.
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

## Running the suite

```bash
dart test
```

```bash
dart analyze --fatal-infos . && dart format --set-exit-if-changed .
```

## Licence

MIT. Upstream's MIT notice is kept in `LICENSE-TANSTACK`.
