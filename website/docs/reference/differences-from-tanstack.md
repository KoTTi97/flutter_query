---
title: Differences from TanStack Query
description: Where query_kit behaves differently from TanStack Query on purpose — the shape of the API, the rules Dart's type system adds, and the failure cases it settles differently.
---

{/* depth: todo */}

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
| module-level `focusManager`, `onlineManager`, `notifyManager` | instances owned by each `QueryClient` |
| cache callbacks on a reassignable `config` | final constructor arguments of `QueryCache` and `MutationCache` |

## Rebuilds

| TanStack Query | query_kit |
|---|---|
| `notifyOnChangeProps` and tracked result properties | whole results are compared; `buildWhen` narrows rebuilds explicitly. See [what rebuilds](../guides/render-optimizations.md) |
| `throwOnError` | errors live in the sealed result |
| a `select` memo kept while the selector is `===` the last one | kept while it is `==` — two tear-offs of one method count as one selector |

## Behaviour

| TanStack Query | query_kit |
|---|---|
| a fetch with no query function is retried like any failure | `MissingQueryFunctionError` is never retried |
| an imperative fetch with no retry policy writes `retry: 0` into the shared query | the one-attempt rule applies to that fetch alone |
| a state-dependent filter on `invalidateQueries` refetches none of what it invalidated | the matched set is fixed before invalidating, so it refetches what it marked |
| a filter predicate that throws, throws synchronously out of the bulk operations | it fails the returned future |
| a throwing listener, `retry` or `retryDelay` callback can leave a fetch pending forever | the throw is reported to the zone, or becomes the fetch's error; the fetch settles |
| a silent cancel with no successor leaves `fetchStatus: 'fetching'` | it is put back to `idle` |
| every foreground event refetches stale queries | the same by default; `refetchMinBackgroundDuration` can skip a refetch after a short absence. See [app focus refetching](../guides/window-focus-refetching.md) |
| `resumePausedMutations` waits for the whole client to be online | decided per mutation by its own network mode |
| a mutation's `setOptions` while it runs can move it to another scope | the scope is fixed for the run |
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
- **Cancellation is `QueryCancelToken`**, with `onCancel` as the interop point,
  because Dart has no ecosystem-wide abort signal.
