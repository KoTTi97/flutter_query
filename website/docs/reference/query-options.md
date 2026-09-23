---
title: Options reference
sidebar_label: Options
description: Every field of the query, infinite-query and mutation options, with its type, its built-in default and what it does.
---

# Options reference

Every option a query, an infinite query or a mutation takes, with its type,
its default and what it does. The guides explain *when* to reach for each
one; this page is the table to look things up in. The concept page is
[describing a query once](../guides/query-options.md). A row names the
TanStack Query spelling only where it differs from the Dart one.

## How a field gets its value

**`null` means "not configured"** on every field below. A field that
`QueryDefaults` or `MutationDefaults` also has takes, when left `null`, in
this order:

1. the defaults registered for a matching key with
   `client.setQueryDefaults` / `client.setMutationDefaults` (several matching
   prefixes merge in the order their keys were first registered, the later
   one winning per field),
2. the client-wide `DefaultOptions` passed to `QueryClient(defaultOptions:)`
   or `setDefaultOptions`,
3. the built-in default in the **Default** column.

So `queryFn`, `mutationFn`, `structuralSharing`, `scope` and `meta`, which
the defaults layer can also supply, show only the built-in fallback below.
The other fields — `initialData` and its two timestamps, `select`,
`placeholderData`, the paging fields, `mutationKey`, `mutationFnWithContext`
and the mutation callbacks — have no defaults layer: unset is unset.

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
`copyWith`, which leaves a field it is not handed as it was (handing one of
`initialDataUpdatedAt` and `initialDataUpdatedAtCompute` clears the other) —
except `MutationOptions`, which has none. The infinite shapes' `copyWith` throws
`ArgumentError` for a `queryFn`, and the observer shapes' for `pages`.

None of these classes has value equality, on purpose: options built inline in
`build` are handed to the observer on every build, and the observer compares
the values they *resolve* to. An inline `queryFn` closure is a new function
on every build, so the resolved options differ and the query cache reports a
`QueryObserverOptionsUpdated` event; it does not refetch and does not restart
the stale or polling timers, which follow the query, `enabled` and the
resolved `staleTime` and `refetchInterval`.

## Cache fields

On `QueryOptions` and so on every query shape. They describe the cache entry,
which every reader of the key shares.

| Field | Type | Default | What it does |
|---|---|---|---|
| [`queryKey`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/queryKey.html) | `QueryKey` | required | The key the entry is cached under. A key holds one exact type; reading it as another throws `QueryDataTypeError`. |
| [`queryFn`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/queryFn.html) | `QueryFn<TQueryData>?` — `FutureOr<TQueryData> Function(QueryFunctionContext)` | none | Fetches the data. With none here or in the defaults, a fetch fails with `MissingQueryFunctionError`, which is never retried. Not on the infinite shapes, which take `pageFn`. |
| [`enabled`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/enabled.html) | `Enabled?` | `Enabled.yes` | Whether the query fetches on its own. A disabled query still serves cached data and can be refetched by hand. |
| [`staleTime`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/staleTime.html) | `StaleTime?` | `StaleTime.zero` | How long fetched data counts as fresh. |
| [`gcTime`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/gcTime.html) | `GcTime?` | five minutes (`GcTime.defaultValue`) | How long the entry stays cached after its last reader leaves. |
| [`retry`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/retry.html) | `RetryPolicy?` | `RetryPolicy.times(3)`; for `client.query` with no retry configured anywhere, no retries | Whether and how often a failed fetch is retried. |
| [`retryDelay`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/retryDelay.html) | `RetryDelay?` | 1 s doubling, at most 30 s (`RetryDelay.defaultValue`) | The wait between attempts. |
| [`networkMode`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/networkMode.html) | `NetworkMode?` | `NetworkMode.online` | How connectivity gates the fetch. See [network mode](../guides/network-mode.md). |
| [`initialData`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/initialData.html) | `InitialData<TQueryData>?` | none | Seed data written into the cache as if fetched. See [initial data](../guides/initial-query-data.md). |
| [`initialDataUpdatedAt`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/initialDataUpdatedAt.html) | `DateTime?` | none: the seed counts as fetched when written | When the seed was fetched, for the staleness clock. TanStack: `initialDataUpdatedAt` as a number. |
| [`initialDataUpdatedAtCompute`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/initialDataUpdatedAtCompute.html) | `DateTime? Function()?` | none | The same, computed only when data is actually seeded; `null` from it means now. Setting both forms throws `ArgumentError` when the options are resolved. TanStack: `initialDataUpdatedAt` as a function. |
| [`structuralSharing`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/structuralSharing.html) | `StructuralSharing<TQueryData>?` — `TQueryData Function(TQueryData? previous, TQueryData next)` | `replaceEqualDeep` | How new data is reconciled with what is cached. `noStructuralSharing()` turns it off. See [structural sharing](../guides/structural-sharing.md). TanStack spells the opt-out `structuralSharing: false`. |
| [`meta`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryOptions/meta.html) | `Object?` | none | Free-form data, handed to the query function as `context.meta` and readable off the query. |

The query function receives a [`QueryFunctionContext`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryFunctionContext-class.html):
`client`, `queryKey`, `meta` and `signal`, a `QueryCancelToken`. Reading
`signal` is what makes the fetch cancellable; see [query
cancellation](../guides/query-cancellation.md).

## Observer fields

On `QueryObserverOptions`, `QuerySelectOptions` and the infinite observer
shapes. They describe one reader, so two widgets watching one key may poll,
refetch and select differently.

| Field | Type | Default | What it does |
|---|---|---|---|
| [`select`](https://pub.dev/documentation/query_kit/latest/query_kit/QuerySelectOptions/select.html) | `SelectFn<TQueryData, TData>` — `TData Function(TQueryData)` | required on the select shapes, absent on the plain ones | Projects the cached data into what this reader sees. While the projection stays equal, `data` keeps its instance (unless `structuralSharing` is switched off); the rest of the result (`fetchStatus`, `dataUpdatedAt`, …) still changes and still notifies — `buildWhen` narrows rebuilds. A throwing `select` makes the result a `QueryError`. See [render optimizations](../guides/render-optimizations.md). |
| [`placeholderData`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserverOptionsBase/placeholderData.html) | `PlaceholderData<TQueryData>?` | none | Data shown while the query is pending with no data of its own — not while it is in an error state, though a refetch after the error shows it again. Never cached; the result reports `isPlaceholderData`. See [placeholder data](../guides/placeholder-query-data.md). |
| [`refetchOnMount`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserverOptionsBase/refetchOnMount.html) | `RefetchOn?` | `RefetchOn.ifStale` | Whether this reader subscribing triggers a refetch. |
| [`refetchOnWindowFocus`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserverOptionsBase/refetchOnWindowFocus.html) | `RefetchOn?` | `RefetchOn.ifStale` | Whether the app returning to the foreground triggers a refetch. See [app focus refetching](../guides/window-focus-refetching.md). |
| [`refetchOnReconnect`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserverOptionsBase/refetchOnReconnect.html) | `RefetchOn?` | `RefetchOn.ifStale`; `RefetchOn.never` under `NetworkMode.always` | Whether the network coming back triggers a refetch. |
| [`refetchInterval`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserverOptionsBase/refetchInterval.html) | `RefetchInterval?` | `RefetchInterval.off` | Polls while this reader is subscribed and the query is enabled, stale or not, a `StaleTime.static` query included. See [polling](../guides/polling.md). |
| [`refetchIntervalInBackground`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserverOptionsBase/refetchIntervalInBackground.html) | `bool?` | `false` | Whether polling continues while the app is not focused. |
| [`retryOnMount`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserverOptionsBase/retryOnMount.html) | `bool?` | `true` | Whether a query in an error state with no data is fetched again when a reader subscribes (one holding data follows `refetchOnMount`). TanStack also takes a function of the query here. |

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

| Field | Type | Default | What it does |
|---|---|---|---|
| [`pageFn`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryOptions/pageFn.html) | `InfinitePageFn<TPageData, TPageParam>` — `FutureOr<TPageData> Function(InfinitePageContext<TPageParam>)` | required | Fetches one page. Its context carries a typed `pageParam`, the `direction`, `queryKey`, `client`, `meta` and `signal`. TanStack: `queryFn`. |
| [`initialPageParam`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryOptions/initialPageParam.html) | `TPageParam` | required | The param the first page is fetched with. |
| [`getNextPageParam`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryOptions/getNextPageParam.html) | `PageParamFn<TPageData, TPageParam>` — `TPageParam? Function(page, pages, pageParam, pageParams)` | required | The param of the page after the last one; `null` means there is none, so `hasNextPage` is false. |
| [`getPreviousPageParam`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryOptions/getPreviousPageParam.html) | `PageParamFn<TPageData, TPageParam>?` | none: `hasPreviousPage` is always false | The same, backwards from the first page. |
| [`maxPages`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryOptions/maxPages.html) | `int?` | none: every page is kept (`0` too) | How many pages to keep. A page fetch past the limit drops one page from the far end. |
| [`pages`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryOptions/pages.html) | `int?` | none: one page into an empty query, every held page on a refetch | How many pages to fetch up front. Only on `InfiniteQueryOptions`, for `client.infiniteQuery` (or `client.query`); the observer shapes refuse it. A count handed to the client stays on the shared query and shapes later refetches that bring no options of their own (`invalidateQueries`, `refetchQueries`) until an observer on the key installs its own options — creating or subscribing one, or any `setOptions`, does that without a fetch. |

A refetch of an infinite query — invalidation, focus, polling — requests
the held pages again, first to last, each with the param computed from the
page before it, and stops early if `getNextPageParam` returns `null`. `hasNextPage`, `fetchNextPage` and their backward twins live
on the infinite observer and controller, not on the result; see
[results](results.md).

## Mutation fields

On [`MutationOptions`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions-class.html).
The three type arguments are what the function returns, what it is called
with, and what `onMutate` returns. `MutationOptions.simple(...)` takes the
same fields minus `onMutate` and fixes the third type to `void`, so the other
two infer from `mutationFn`. See [mutations](../guides/mutations.md).

| Field | Type | Default | What it does |
|---|---|---|---|
| [`mutationKey`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/mutationKey.html) | `QueryKey?` | none | Addresses the mutation for filters, `isMutating`, mutation state and `setMutationDefaults`. |
| [`mutationFn`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/mutationFn.html) | `MutationFn<TData, TVariables>?` — `FutureOr<TData> Function(TVariables)` | none | Performs the write. With none here or in the defaults, a run fails with `MissingMutationFunctionError`, not retried. |
| [`mutationFnWithContext`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/mutationFnWithContext.html) | `MutationFnWithContext<TData, TVariables, TOnMutateResult>?` — `FutureOr<TData> Function(TVariables, MutationFunctionContext)` | none | The same with a context: `client`, `meta`, `mutationKey`, `onMutateResult` and a `signal` that `cancel()` cancels. Set one of the two functions, never both (an assertion in debug builds, `ArgumentError` when resolved); when set it wins over a default `mutationFn`. TanStack: `mutationFn`'s second argument. |
| [`onMutate`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/onMutate.html) | `OnMutate<TVariables, TOnMutateResult>?` — `FutureOr<TOnMutateResult?> Function(TVariables)` | none | Runs when the mutation is submitted, before the function; its result is handed to the other callbacks, typically a rollback snapshot. A throw fails the mutation without running the function. |
| [`onSuccess`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/onSuccess.html) | `OnMutationSuccess?` — `(data, variables, onMutateResult)` | none | Runs after `MutationCache.onSuccess`. Awaited; a throw turns the success into an error. |
| [`onError`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/onError.html) | `OnMutationError?` — `(error, stackTrace, variables, onMutateResult)` | none | Runs after `MutationCache.onError`, retries spent. Awaited; a throw is reported to the zone and does not replace the error. |
| [`onSettled`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/onSettled.html) | `OnMutationSettled?` — `(data, error, stackTrace, variables, onMutateResult)` | none | Runs last, on success and error alike. The mutation stays pending until a returned future completes. |
| [`retry`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/retry.html) | `RetryPolicy?` | `RetryPolicy.never` | Whether a failed attempt is retried. TanStack's default is `retry: 0`. |
| [`retryDelay`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/retryDelay.html) | `RetryDelay?` | 1 s doubling, at most 30 s | The wait between attempts. |
| [`networkMode`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/networkMode.html) | `NetworkMode?` | `NetworkMode.online` | Offline, an `online` mutation pauses and a mounted client resumes it on reconnect. |
| [`gcTime`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/gcTime.html) | `GcTime?` | five minutes | How long a settled mutation stays in the cache once nothing observes it. |
| [`scope`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/scope.html) | `MutationScope?` | none: unscoped mutations run in parallel | Mutations with equal scopes run one at a time, in submission order. Fixed for a run once it starts. See [mutation scopes](../guides/mutation-scopes.md). TanStack: `scope: { id }`. |
| [`meta`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions/meta.html) | `Object?` | none | Free-form data, readable as `mutation.meta` and `context.meta`. |

The callbacks run in this order, each returned future awaited before the
next: `MutationCache.onMutate`, `onMutate`; after the function,
`MutationCache.onSuccess` (or `onError`), `onSuccess` (or `onError`),
`MutationCache.onSettled`, `onSettled`. Callbacks have no default layer:
`setMutationDefaults` carries none.

### Per-call callbacks

`mutate(variables, callbacks: MutateCallbacks(...))` adds callbacks for one
call — closing a dialog, showing a snack bar.
[`MutateCallbacks`](https://pub.dev/documentation/query_kit/latest/query_kit/MutateCallbacks-class.html)
has `onSuccess`, `onError` and `onSettled` with the signatures above, each
optional. They run after the options' callbacks, only while the observer
still has a listener, are not awaited, and a throw in one is reported to the
zone. TanStack Query: the second argument of `mutate`.

## Option values

Each option with modes is a small sealed family of `const` values. A value
built inline compares equal to an equal one, so a rebuild with the same value
is not a change; the computed forms compare equal when their function is the
same (a tear-off, not an inline closure). Each type also has the method the
library resolves it with (`resolve`, `shouldRetry`, …); application code
rarely calls them. Each case is a public class (`StaleTimeDuration`,
`EnabledWhen`, `RetryTimes`, …), so a `switch` can name them.

| Type | Spellings |
|---|---|
| [`StaleTime`](https://pub.dev/documentation/query_kit/latest/query_kit/StaleTime-class.html) | `StaleTime.zero` (default), `StaleTime.duration(d)`, `StaleTime.infinite` (never stale by time, invalidation still works), `StaleTime.static` (never stale; skipped by the mount, focus and reconnect refetches and by `refetchQueries` and invalidation while observed; `refetchInterval` still polls it), `StaleTime.dynamic((query) => StaleTime)`. TanStack: `0`, a number of ms, `Infinity`, `'static'`, a function. |
| [`GcTime`](https://pub.dev/documentation/query_kit/latest/query_kit/GcTime-class.html) | `GcTime.duration(d)`, `GcTime.defaultValue` (five minutes), `GcTime.never`; `GcTime.longest(a, b)` picks the longer of two. TanStack: a number of ms, `Infinity`. |
| [`Enabled`](https://pub.dev/documentation/query_kit/latest/query_kit/Enabled-class.html) | `Enabled.yes` (default), `Enabled.no`, `Enabled.when((query) => bool)`. TanStack: `true`, `false` (also standing in for `queryFn: skipToken`), a function. |
| [`RetryPolicy`](https://pub.dev/documentation/query_kit/latest/query_kit/RetryPolicy-class.html) | `RetryPolicy.never`, `RetryPolicy.always`, `RetryPolicy.times(n)` (n retries, n + 1 attempts), `RetryPolicy.when((failureCount, error, stackTrace) => bool)` — `failureCount` is `0` on the first decision. TanStack: `false`, `true`, a number, a function. |
| [`RetryDelay`](https://pub.dev/documentation/query_kit/latest/query_kit/RetryDelay-class.html) | `RetryDelay.defaultValue`, `RetryDelay.exponential({base = 1 s, maximum = 30 s})` — with no arguments the default, `RetryDelay.fixed(d)`, `RetryDelay.dynamic((failureCount, error) => Duration)`. TanStack: the default function, a number of ms, a function. |
| [`RefetchOn`](https://pub.dev/documentation/query_kit/latest/query_kit/RefetchOn-class.html) | `RefetchOn.ifStale` (default), `RefetchOn.always`, `RefetchOn.never`, `RefetchOn.when((query) => RefetchOn)`. TanStack: `true`, `'always'`, `false`, a function. |
| [`RefetchInterval`](https://pub.dev/documentation/query_kit/latest/query_kit/RefetchInterval-class.html) | `RefetchInterval.off` (default), `RefetchInterval.every(d)`, `RefetchInterval.dynamic((query) => Duration?)` — `null`, zero or a negative duration stops polling. TanStack: `false`, a number of ms, a function. |
| [`NetworkMode`](https://pub.dev/documentation/query_kit/latest/query_kit/NetworkMode.html) (an enum) | `online` (default), `always`, `offlineFirst`. |
| [`InitialData`](https://pub.dev/documentation/query_kit/latest/query_kit/InitialData-class.html) | `InitialData.value(data)`, `InitialData.compute(() => data?)` — `null` from the callback means no seed. TanStack: a value, a function. |
| [`PlaceholderData`](https://pub.dev/documentation/query_kit/latest/query_kit/PlaceholderData-class.html) | `PlaceholderData.keepPrevious()`, `PlaceholderData.value(data)`, `PlaceholderData.compute((previousData, previousQuery) => data?)`. TanStack: `keepPreviousData`, a value, a function. |
| [`MutationScope`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationScope-class.html) | `MutationScope(id)` — equal ids are one scope. TanStack: `{ id }`. |

`.value(null)` is a seed (or placeholder) of `null` for a nullable type; only
a `.compute` returning `null` means "none". That is the one place where Dart's
single `null` carries two meanings.
