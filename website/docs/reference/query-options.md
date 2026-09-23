---
title: Options reference
sidebar_label: Options
description: Every field of the query, infinite-query and mutation options, with its type, its default, what it does and its TanStack Query name.
---

# Options reference

Every option a query, an infinite query or a mutation takes, with its type,
its default and its TanStack Query name. The guides explain *when* to reach
for each one; this page is the table to look things up in. The concept page
is [describing a query once](../guides/query-options.md).

## How a field gets its value

**`null` means "not configured"** on every field below. A field left `null`
takes, in this order:

1. the defaults registered for a matching key with
   `client.setQueryDefaults` / `client.setMutationDefaults` (several matching
   prefixes merge, the later registration winning per field),
2. the client-wide `DefaultOptions` passed to `QueryClient(defaultOptions:)`
   or `setDefaultOptions`,
3. the built-in default in the **Default** column.

An option that can be switched off says so with a value — `Enabled.no`,
`RetryPolicy.never`, `RefetchInterval.off` — never with `null`. The value
types are listed [at the end of this page](#option-values). The defaults
layer is on the [client reference](query-client.md#defaults).

An example, from a shop app's `lib/data/product_queries.dart`:

```dart snippet="reference/query-options.md#product-query"
QueryObserverOptions<Product> productQuery(ProductRepository repo, String id) =>
    QueryObserverOptions(
      queryKey: QueryKey(<Object?>['products', 'detail', id]),
      queryFn: (context) => repo.product(id, signal: context.signal),
      // A price may change, but not every second.
      staleTime: const StaleTime.duration(Duration(minutes: 2)),
      // Kept for a while after the detail screen closes, for the back button.
      gcTime: const GcTime.duration(Duration(minutes: 10)),
      retry: const RetryPolicy.times(2),
      refetchOnWindowFocus: RefetchOn.never,
    );
```

## The option classes

| Class | Takes | Used by |
|---|---|---|
| [`QueryOptions<TQueryData>`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions-class.html) | the cache fields | `client.query` — fetch once and complete with the data |
| [`QueryObserverOptions<TData>`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserverOptions-class.html) | cache fields + observer fields, no `select` | every widget call style, `client.observe`, `QueryObserver` |
| [`QuerySelectOptions<TQueryData, TData>`](https://pub.dev/documentation/query_kit/latest/query_kit/QuerySelectOptions-class.html) | the same, `select` required | the same, when the reader sees a projection |
| [`InfiniteQueryOptions<TPageData, TPageParam>`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryOptions-class.html) | cache fields + paging fields | `client.infiniteQuery` (and `client.query`) |
| [`InfiniteQueryObserverOptions<TPageData, TPageParam>`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryObserverOptions-class.html) | cache + paging + observer fields, no `select` | the infinite call styles, `client.observeInfinite` |
| [`InfiniteQuerySelectOptions<TPageData, TPageParam, TData>`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQuerySelectOptions-class.html) | the same, `select` required | the same, with a projection of the pages |
| [`MutationOptions<TData, TVariables, TOnMutateResult>`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions-class.html) | the mutation fields | every mutation call style, `MutationObserver` |

The observer shapes extend the cache shape, so one options function serves
`client.query` and a widget alike. `QueryObserverOptions.withSelect(select)`
and `InfiniteQueryObserverOptions.withSelect(select)` turn a plain shape into
its select shape with every other field carried over. Every class has
`copyWith`, which leaves a field it is not handed as it was.

None of these classes has value equality, on purpose: options built inline in
`build` are handed to the observer on every build, and the observer compares
the values they *resolve* to. An inline `queryFn` closure is therefore not a
change by itself.

## Cache fields

On `QueryOptions` and so on every query shape. They describe the cache entry,
which every reader of the key shares.

| Field | Type | Default | What it does | TanStack Query |
|---|---|---|---|---|
| [`queryKey`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/queryKey.html) | `QueryKey` | required | The key the entry is cached under. A key holds one exact type; reading it as another throws `QueryDataTypeError`. | `queryKey` |
| [`queryFn`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/queryFn.html) | `QueryFn<TQueryData>?` — `FutureOr<TQueryData> Function(QueryFunctionContext)` | the key's registered `queryFn`, else none | Fetches the data. With none anywhere, a fetch fails with `MissingQueryFunctionError`, which is never retried. Not on the infinite shapes, which take `pageFn`. | `queryFn` |
| [`enabled`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/enabled.html) | `Enabled?` | `Enabled.yes` | Whether the query fetches on its own. A disabled query still serves cached data and can be refetched by hand. | `enabled` |
| [`staleTime`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/staleTime.html) | `StaleTime?` | `StaleTime.zero` | How long fetched data counts as fresh. | `staleTime` |
| [`gcTime`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/gcTime.html) | `GcTime?` | five minutes (`GcTime.defaultValue`) | How long the entry stays cached after its last reader leaves. | `gcTime` |
| [`retry`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/retry.html) | `RetryPolicy?` | `RetryPolicy.times(3)`; for `client.query` with no retry configured anywhere, no retries | Whether and how often a failed fetch is retried. | `retry` |
| [`retryDelay`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/retryDelay.html) | `RetryDelay?` | 1 s doubling, at most 30 s (`RetryDelay.defaultValue`) | The wait between attempts. | `retryDelay` |
| [`networkMode`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/networkMode.html) | `NetworkMode?` | `NetworkMode.online` | How connectivity gates the fetch. See [network mode](../guides/network-mode.md). | `networkMode` |
| [`initialData`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/initialData.html) | `InitialData<TQueryData>?` | none | Seed data written into the cache as if fetched. See [initial data](../guides/initial-query-data.md). | `initialData` |
| [`initialDataUpdatedAt`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/initialDataUpdatedAt.html) | `DateTime?` | none: the seed counts as fetched when written | When the seed was fetched, for the staleness clock. | `initialDataUpdatedAt` (a number) |
| [`initialDataUpdatedAtCompute`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/initialDataUpdatedAtCompute.html) | `DateTime? Function()?` | none | The same, computed only when data is actually seeded; `null` from it means now. Setting both forms throws `ArgumentError`. | `initialDataUpdatedAt` (a function) |
| [`structuralSharing`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/structuralSharing.html) | `StructuralSharing<TQueryData>?` — `TQueryData Function(TQueryData? previous, TQueryData next)` | the key's registered hook, else `replaceEqualDeep` | How new data is reconciled with what is cached. `noStructuralSharing()` turns it off. See [structural sharing](../guides/structural-sharing.md). | `structuralSharing` |
| [`meta`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/meta.html) | `Object?` | the key's registered `meta`, else none | Free-form data, handed to the query function as `context.meta` and readable off the query. | `meta` |

The query function receives a [`QueryFunctionContext`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryFunctionContext-class.html):
`client`, `queryKey`, `meta` and `signal`, a `QueryCancelToken`. Reading
`signal` is what makes the fetch cancellable; see [query
cancellation](../guides/query-cancellation.md).

## Observer fields

On `QueryObserverOptions`, `QuerySelectOptions` and the infinite observer
shapes. They describe one reader, so two widgets watching one key may poll,
refetch and select differently.

| Field | Type | Default | What it does | TanStack Query |
|---|---|---|---|---|
| [`select`](https://pub.dev/documentation/query_kit/latest/query_kit/QuerySelectOptions/select.html) | `SelectFn<TQueryData, TData>` — `TData Function(TQueryData)` | required on the select shapes, absent on the plain ones | Projects the cached data into what this reader sees; the reader is told only when the projection changes. See [render optimizations](../guides/render-optimizations.md). | `select` |
| [`placeholderData`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserverOptionsBase/placeholderData.html) | `PlaceholderData<TQueryData>?` | none | Data shown while the query has none of its own. Never cached; the result reports `isPlaceholderData`. See [placeholder data](../guides/placeholder-query-data.md). | `placeholderData` |
| [`refetchOnMount`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserverOptionsBase/refetchOnMount.html) | `RefetchOn?` | `RefetchOn.ifStale` | Whether this reader subscribing triggers a refetch. | `refetchOnMount` |
| [`refetchOnWindowFocus`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserverOptionsBase/refetchOnWindowFocus.html) | `RefetchOn?` | `RefetchOn.ifStale` | Whether the app returning to the foreground triggers a refetch. See [app focus refetching](../guides/window-focus-refetching.md). | `refetchOnWindowFocus` |
| [`refetchOnReconnect`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserverOptionsBase/refetchOnReconnect.html) | `RefetchOn?` | `RefetchOn.ifStale`; `RefetchOn.never` under `NetworkMode.always` | Whether the network coming back triggers a refetch. | `refetchOnReconnect` |
| [`refetchInterval`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserverOptionsBase/refetchInterval.html) | `RefetchInterval?` | `RefetchInterval.off` | Polls while this reader is subscribed. See [polling](../guides/polling.md). | `refetchInterval` |
| [`refetchIntervalInBackground`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserverOptionsBase/refetchIntervalInBackground.html) | `bool?` | `false` | Whether polling continues while the app is not focused. | `refetchIntervalInBackground` |
| [`retryOnMount`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserverOptionsBase/retryOnMount.html) | `bool?` | `true` | Whether a query in an error state is fetched again when a reader subscribes. | `retryOnMount` |

Not here: `notifyOnChangeProps` (whole results are compared; `buildWhen` on
every read narrows rebuilds), `throwOnError` (errors are a case of the sealed
result), `queryKeyHashFn` (`QueryKey` is a value type), `subscribed` and
`experimental_prefetchInRender`. See [differences from TanStack
Query](differences-from-tanstack.md).

## Infinite query fields

On `InfiniteQueryOptions` and the two infinite observer shapes, in addition
to the cache fields (without `queryFn`) and, on the observer shapes, the
observer fields. The data type is `InfiniteData<TPageData, TPageParam>`:
`pages` and `pageParams`. See [infinite queries](../guides/infinite-queries.md).

| Field | Type | Default | What it does | TanStack Query |
|---|---|---|---|---|
| [`pageFn`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryOptions/pageFn.html) | `InfinitePageFn<TPageData, TPageParam>` — `FutureOr<TPageData> Function(InfinitePageContext<TPageParam>)` | required | Fetches one page. Its context carries a typed `pageParam`, the `direction`, `queryKey`, `client`, `meta` and `signal`. | `queryFn` |
| [`initialPageParam`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryOptions/initialPageParam.html) | `TPageParam` | required | The param the first page is fetched with. | `initialPageParam` |
| [`getNextPageParam`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryOptions/getNextPageParam.html) | `PageParamFn<TPageData, TPageParam>` — `TPageParam? Function(page, pages, pageParam, pageParams)` | required | The param of the page after the last one; `null` means there is none, so `hasNextPage` is false. | `getNextPageParam` |
| [`getPreviousPageParam`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryOptions/getPreviousPageParam.html) | `PageParamFn<TPageData, TPageParam>?` | none: `hasPreviousPage` is always false | The same, backwards from the first page. | `getPreviousPageParam` |
| [`maxPages`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryOptions/maxPages.html) | `int?` | none: every page is kept (`0` too) | How many pages to keep. A page fetch past the limit drops one page from the far end. | `maxPages` |
| [`pages`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryOptions/pages.html) | `int?` | none: one page into an empty query, every held page on a refetch | How many pages to fetch up front. Only on `InfiniteQueryOptions`, for `client.infiniteQuery`; the observer shapes refuse it. | `pages` |

A refetch of an infinite query — invalidation, focus, polling — requests
every held page again, first to last, each with the param computed from the
page before it. `hasNextPage`, `fetchNextPage` and their backward twins live
on the infinite observer and controller, not on the result; see
[results](results.md).

## Mutation fields

On [`MutationOptions`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions-class.html).
The three type arguments are what the function returns, what it is called
with, and what `onMutate` returns. `MutationOptions.simple(...)` takes the
same fields minus `onMutate` and fixes the third type to `void`, so the other
two infer from `mutationFn`. See [mutations](../guides/mutations.md).

| Field | Type | Default | What it does | TanStack Query |
|---|---|---|---|---|
| [`mutationKey`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/mutationKey.html) | `QueryKey?` | none | Addresses the mutation for filters, `isMutating`, mutation state and `setMutationDefaults`. | `mutationKey` |
| [`mutationFn`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/mutationFn.html) | `MutationFn<TData, TVariables>?` — `FutureOr<TData> Function(TVariables)` | the key's registered `mutationFn`, else none | Performs the write. With none anywhere, a run fails with `MissingMutationFunctionError`, not retried. | `mutationFn` |
| [`mutationFnWithContext`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/mutationFnWithContext.html) | `MutationFnWithContext<TData, TVariables, TOnMutateResult>?` — `FutureOr<TData> Function(TVariables, MutationFunctionContext)` | none | The same with a context: `client`, `meta`, `mutationKey`, `onMutateResult` and a `signal` that `cancel()` cancels. Set one of the two functions, never both (an assertion in debug builds, `ArgumentError` when resolved). | `mutationFn`'s second argument |
| [`onMutate`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/onMutate.html) | `OnMutate<TVariables, TOnMutateResult>?` — `FutureOr<TOnMutateResult?> Function(TVariables)` | none | Runs when the mutation is submitted, before the function; its result is handed to the other callbacks, typically a rollback snapshot. A throw fails the mutation without running the function. | `onMutate` |
| [`onSuccess`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/onSuccess.html) | `OnMutationSuccess` — `(data, variables, onMutateResult)` | none | Runs after `MutationCache.onSuccess`. Awaited; a throw turns the success into an error. | `onSuccess` |
| [`onError`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/onError.html) | `OnMutationError` — `(error, stackTrace, variables, onMutateResult)` | none | Runs after `MutationCache.onError`, retries spent. Awaited; a throw is reported to the zone and does not replace the error. | `onError` |
| [`onSettled`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/onSettled.html) | `OnMutationSettled` — `(data, error, stackTrace, variables, onMutateResult)` | none | Runs last, on success and error alike. The mutation stays pending until a returned future completes. | `onSettled` |
| [`retry`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/retry.html) | `RetryPolicy?` | `RetryPolicy.never` | Whether a failed attempt is retried. | `retry` (default `0`) |
| [`retryDelay`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/retryDelay.html) | `RetryDelay?` | 1 s doubling, at most 30 s | The wait between attempts. | `retryDelay` |
| [`networkMode`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/networkMode.html) | `NetworkMode?` | `NetworkMode.online` | Offline, an `online` mutation pauses and a mounted client resumes it on reconnect. | `networkMode` |
| [`gcTime`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/gcTime.html) | `GcTime?` | five minutes | How long a settled mutation stays in the cache once nothing observes it. | `gcTime` |
| [`scope`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/scope.html) | `MutationScope?` | none: unscoped mutations run in parallel | Mutations with equal scopes run one at a time, in submission order. Fixed for a run once it starts. See [mutation scopes](../guides/mutation-scopes.md). | `scope: { id }` |
| [`meta`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/meta.html) | `Object?` | the key's registered `meta`, else none | Free-form data, readable as `mutation.meta` and `context.meta`. | `meta` |

The callbacks run in this order, each returned future awaited before the
next: `MutationCache.onMutate`, `onMutate`; after the function,
`MutationCache.onSuccess` (or `onError`), `onSuccess` (or `onError`),
`MutationCache.onSettled`, `onSettled`. Callbacks have no default layer:
`setMutationDefaults` carries none.

### Per-call callbacks

`mutate(variables, callbacks: MutateCallbacks(...))` adds callbacks for one
call — closing a dialog, showing a snack bar.
[`MutateCallbacks`](https://pub.dev/documentation/query_kit/latest/query_kit/MutateCallbacks-class.html)
has `onSuccess`, `onError` and `onSettled` with the signatures above. They run
after the options' callbacks, only while the observer still has a listener,
are not awaited, and a throw in one is reported to the zone. TanStack Query:
the second argument of `mutate`.

## Option values

Each option with modes is a small sealed family of `const` values. A value
built inline compares equal to an equal one, so a rebuild with the same value
is not a change; the computed forms compare equal when their function is the
same (a tear-off, not an inline closure).

| Type | Spellings | TanStack Query |
|---|---|---|
| [`StaleTime`](https://pub.dev/documentation/query_kit/latest/query_kit/StaleTime-class.html) | `StaleTime.zero` (default), `StaleTime.duration(d)`, `StaleTime.infinite` (never stale by time, invalidation still works), `StaleTime.static` (never stale, skipped by every refetch trigger and by `refetchQueries` while observed), `StaleTime.dynamic((query) => …)` | `0`, `ms`, `Infinity`, `'static'`, a function |
| [`GcTime`](https://pub.dev/documentation/query_kit/latest/query_kit/GcTime-class.html) | `GcTime.duration(d)`, `GcTime.defaultValue` (five minutes), `GcTime.never` | `ms`, `Infinity` |
| [`Enabled`](https://pub.dev/documentation/query_kit/latest/query_kit/Enabled-class.html) | `Enabled.yes` (default), `Enabled.no`, `Enabled.when((query) => bool)` | `true`, `false` or `skipToken`, a function |
| [`RetryPolicy`](https://pub.dev/documentation/query_kit/latest/query_kit/RetryPolicy-class.html) | `RetryPolicy.never`, `RetryPolicy.always`, `RetryPolicy.times(n)` (n retries, n + 1 attempts), `RetryPolicy.when((failureCount, error, stackTrace) => bool)` | `false`, `true`, a number, a function |
| [`RetryDelay`](https://pub.dev/documentation/query_kit/latest/query_kit/RetryDelay-class.html) | `RetryDelay.defaultValue`, `RetryDelay.exponential(base:, maximum:)`, `RetryDelay.fixed(d)`, `RetryDelay.dynamic((failureCount, error) => Duration)` | the default function, `ms`, a function |
| [`RefetchOn`](https://pub.dev/documentation/query_kit/latest/query_kit/RefetchOn-class.html) | `RefetchOn.ifStale` (default), `RefetchOn.always`, `RefetchOn.never`, `RefetchOn.when((query) => RefetchOn)` | `true`, `'always'`, `false`, a function |
| [`RefetchInterval`](https://pub.dev/documentation/query_kit/latest/query_kit/RefetchInterval-class.html) | `RefetchInterval.off` (default), `RefetchInterval.every(d)`, `RefetchInterval.dynamic((query) => Duration?)` — `null` stops polling | `false`, `ms`, a function |
| [`NetworkMode`](https://pub.dev/documentation/query_kit/latest/query_kit/NetworkMode.html) (an enum) | `online` (default), `always`, `offlineFirst` | `'online'`, `'always'`, `'offlineFirst'` |
| [`InitialData`](https://pub.dev/documentation/query_kit/latest/query_kit/InitialData-class.html) | `InitialData.value(data)`, `InitialData.compute(() => data?)` — `null` from the callback means no seed | a value, a function |
| [`PlaceholderData`](https://pub.dev/documentation/query_kit/latest/query_kit/PlaceholderData-class.html) | `PlaceholderData.keepPrevious()`, `PlaceholderData.value(data)`, `PlaceholderData.compute((previousData, previousQuery) => data?)` | `keepPreviousData`, a value, a function |
| [`MutationScope`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationScope-class.html) | `MutationScope(id)` — equal ids are one scope | `{ id }` |

`.value(null)` is a seed (or placeholder) of `null` for a nullable type; only
a `.compute` returning `null` means "none". That is the one place where Dart's
single `null` carries two meanings.
