---
title: Widgets and controllers
description: Every public widget, controller, extension and mixin of query_kit_flutter, with its parameters, defaults and TanStack Query counterpart.
---

# Widgets and controllers

This page lists the Flutter binding's public surface: the provider, the four
call styles for reading queries and mutations, the side-effect listeners, the
collection helpers and the connectivity value. Everything here comes from one
import, `package:query_kit_flutter/query_kit_flutter.dart`, which also
re-exports the whole core.

For the options these widgets take, see [query options](query-options.md);
for what they hand back, see [results](results.md); for the client itself,
see [QueryClient](query-client.md). The guides explain when to reach for
what: [four ways to read a query](../guides/reading-queries-in-widgets.md),
[what rebuilds](../guides/render-optimizations.md) and
[mutations](../guides/mutations.md).

## The four call styles at a glance

The binding reads queries, infinite queries and mutations in four equal
styles. None is the default, the order of the columns means nothing, and the
styles mix freely inside one screen. Each takes the same options objects and
each takes a [`buildWhen`](#buildwhen-and-listenwhen) (a controller filters in
its listener instead, because it is the notifier).

| | Builder widgets | Controllers | `BuildContext` extension | `State` mixin |
|---|---|---|---|---|
| **Query** | `QueryBuilder`, `QuerySelectBuilder` | `QueryController`, `QueryController.create` | `context.query`, `context.selectQuery` | `watchQuery`, `watchSelectQuery` |
| **Infinite query** | `InfiniteQueryBuilder` | `InfiniteQueryController` | `context.infiniteQuery` | `watchInfiniteQuery` |
| **Mutation** | `MutationBuilder` | `MutationController` | `context.mutation` | `watchMutation` |

What they share:

- **One observer per reader, one query per key.** Every builder, controller
  and keyless read owns its own observer. The query in the cache is shared,
  so two readers of one key cost one request.
- **Options are re-applied on every build.** An `Enabled.when` over outside
  state is re-evaluated each time; the observer compares the defaulted
  options by value, and only a real difference reaches the query. A changed
  key switches the observed query in place.
- **No notification for nothing.** A reader is never rebuilt for a
  notification carrying what it is already showing. Under a
  `QueryClientProvider`, a result that changes during a build is delivered
  after the frame.
- **Infinite queries hand out the controller.** Paging lives on
  `InfiniteQueryController`, so the infinite-query form of each style gives
  you the controller rather than a bare result. A change of the paging flags
  alone rebuilds even when the result is equal.
- **Mutations hand out the controller.** `mutate` lives on
  `MutationController`, so the mutation form of each style gives you the
  controller; its `value` is the `MutationResult`.

## `QueryClientProvider`

[Dartdoc](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryClientProvider-class.html)
· TanStack Query: `QueryClientProvider`

A `StatefulWidget` that provides a `QueryClient` to the widgets below it and
wires the client to Flutter while it is mounted. Put one above everything
that reads a query.

### Constructors

| Constructor | Meaning |
|---|---|
| [`QueryClientProvider.create({key, required create, required child, onlineStatus, observeAppLifecycle, isAppShown})`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryClientProvider/create.html) | A static method returning a `Widget`. Calls `create` once and owns the client: it lives as long as the provider and is cleared (`client.clear()`) after the provider unmounts. Rebuilding with a different `create` callback keeps the client; change `key` to replace it. |
| [`QueryClientProvider({key, required client, required child, onlineStatus, observeAppLifecycle, isAppShown})`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryClientProvider/QueryClientProvider.html) | `const`. Takes a client you made yourself — one configured with `defaultOptions`, shared with code outside the tree, or created in a test — and never clears it. A different `client` on a later build unmounts the old one and mounts the new one. |

### Parameters

| Parameter | Type | Default | Meaning | TanStack equivalent |
|---|---|---|---|---|
| `create` (`.create` only) | `QueryClient Function()` | required | Makes the owned client, once, in `initState`. `QueryClient.new` is the shortest form. | `new QueryClient()` |
| [`client`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryClientProvider/client.html) (unnamed only) | `QueryClient` | required | The client every builder, controller and keyless read below runs on unless it names its own. Swapping it recreates every observer below, because each belonged to the old client. | `client` prop |
| [`child`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryClientProvider/child.html) | `Widget` | required | The subtree that can reach the client. | `children` |
| [`onlineStatus`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryClientProvider/onlineStatus.html) | `OnlineStatus?` | `null` | Connectivity, if you bring it: [`OnlineStatus.fixed`](#onlinestatus) or `OnlineStatus.stream`. `null` installs nothing and the client assumes it is online. | `onlineManager.setEventListener` |
| [`observeAppLifecycle`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryClientProvider/observeAppLifecycle.html) | `bool` | `true` | Whether to map the app's lifecycle onto the client's focus state. Turn it off when you install your own focus source with `client.focusManager.setEventListener(…)`: both write through `setFocused`, so with both the last writer wins. | `focusManager` (the default browser `visibilitychange` listener) |
| [`isAppShown`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryClientProvider/isAppShown.html) | `bool Function(AppLifecycleState state)?` | `null` (built-in mapping) | Which lifecycle states count as focused. The mapping given on the latest build is in force: it is applied to the current state when it changes, and decides every transition after. | — |
| `key` | `Key?` | `null` | For `.create`, a new key is the way to get a new client. | — |

The built-in focus mapping: `resumed` is focused; `hidden`, `paused` and
`detached` are not. `inactive` counts as focused on iOS, Android and Fuchsia,
where it is a transient interruption (the notification shade, an incoming
call), and as unfocused on macOS, Windows and Linux, where it means the
window lost focus. The state the app is already in at mount is mapped too,
not only later transitions. See [app focus
refetching](../guides/window-focus-refetching.md).

At mount the provider also installs a notify scheduler on the client:
notifications arriving while a build is in flight are deferred to a
post-frame callback, so a query resolving mid-build cannot call `setState`
during that build. Several providers may share one client; the scheduler
stays until the last of them goes.

### Static members

| Member | Type | Meaning | TanStack equivalent |
|---|---|---|---|
| [`of(context)`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryClientProvider/of.html) | `QueryClient` | The nearest client above `context`, subscribing the caller to a change of client. For `build`. Throws a `FlutterError` when there is no provider. | `useQueryClient()` |
| [`maybeOf(context)`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryClientProvider/maybeOf.html) | `QueryClient?` | The same, `null` without a provider. Subscribes like `of`. | — |
| [`read(context)`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryClientProvider/read.html) | `QueryClient` | Like `of`, without subscribing. For callbacks, `initState` and anywhere outside `build`. Throws a `FlutterError` when there is no provider. | — |

## Builder widgets

The `StreamBuilder` shape. Each widget creates its controller on its first
build (nothing is fetched before that), owns it until it is disposed, and
rebuilds its own subtree. Do not dispose a controller a builder hands you.

All four take `client`: `null` uses the nearest `QueryClientProvider`'s. What
counts is the client resolved, so naming the provider's own client changes
nothing; a different resolved client on a later build — this field's or the
provider's — recreates the controller. Changed options on the same client
are applied in place.

### `QueryBuilder`

[Dartdoc](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryBuilder-class.html)
· TanStack Query: `useQuery`

`QueryBuilder<TData>` — a query without `select`. The type argument comes
from `queryFn`'s return type or is written out; an options literal with
neither is refused by an assertion in debug builds.

| Parameter | Type | Default | Meaning | TanStack equivalent |
|---|---|---|---|---|
| [`options`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryBuilder/options.html) | [`QueryObserverOptions<TData>`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryObserverOptions-class.html) | required | The query. Re-applied whenever the parent rebuilds this widget. | the options object |
| [`builder`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryBuilder/builder.html) | `Widget Function(BuildContext context, QueryResult<TData> result)` | required | Builds the subtree from the sealed [`QueryResult`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryResult-class.html). Called on the first build, then for each changed result `buildWhen` lets through. | the hook's return value |
| [`buildWhen`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryBuilder/buildWhen.html) | `BuildWhen<QueryResult<TData>>?` | `null` (every change) | Whether a change from the result last built to the current one rebuilds. | `notifyOnChangeProps` (different mechanism) |
| [`client`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryBuilder/client.html) | `QueryClient?` | `null` (provider's) | The client to observe on. | the `queryClient` argument |
| `key` | `Key?` | `null` | | — |

### `QuerySelectBuilder`

[Dartdoc](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QuerySelectBuilder-class.html)
· TanStack Query: `useQuery` with `select`

`QuerySelectBuilder<TQueryData, TData>` — the cache holds `TQueryData`, the
builder sees `TData`. The parameters are those of `QueryBuilder`, with these
types:

| Parameter | Type | Default | Meaning |
|---|---|---|---|
| `options` | [`QuerySelectOptions<TQueryData, TData>`](https://pub.dev/documentation/query_kit/latest/query_kit/QuerySelectOptions-class.html) | required | The query and its required `select`, which lets Dart infer `TData`. |
| `builder` | `Widget Function(BuildContext context, QueryResult<TData> result)` | required | Built from the *selected* result. |
| `buildWhen` | `BuildWhen<QueryResult<TData>>?` | `null` | Compares selected results. |
| `client` | `QueryClient?` | `null` | As for `QueryBuilder`. |

A `select` that returns an equal value keeps the previous instance, but the
rest of the result (`fetchStatus`, `dataUpdatedAt`) still changes; that is
what `buildWhen` is for.

### `InfiniteQueryBuilder`

[Dartdoc](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/InfiniteQueryBuilder-class.html)
· TanStack Query: `useInfiniteQuery`

`InfiniteQueryBuilder<TPageData, TPageParam, TData>` — no type arguments at
the call site; inference reads all three off the options.

| Parameter | Type | Default | Meaning | TanStack equivalent |
|---|---|---|---|---|
| `options` | [`InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData>`](https://pub.dev/documentation/query_kit/latest/query_kit/InfiniteQueryObserverOptionsBase-class.html) (`InfiniteQueryObserverOptions` or `InfiniteQuerySelectOptions`) | required | Key, page function and paging functions. Re-applied whenever the parent rebuilds this widget. | the options object |
| `builder` | `Widget Function(BuildContext context, InfiniteQueryController<TPageData, TPageParam, TData> query)` | required | Given the controller, not a bare result: the pages are in `query.value`, paging is `query.fetchNextPage` and its siblings. | the hook's return value |
| `buildWhen` | `BuildWhen<QueryResult<TData>>?` | `null` | Compares the controller's results. A change of the paging flags alone rebuilds regardless. | — |
| `client` | `QueryClient?` | `null` | As for `QueryBuilder`. | the `queryClient` argument |

### `MutationBuilder`

[Dartdoc](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/MutationBuilder-class.html)
· TanStack Query: `useMutation`

`MutationBuilder<TData, TVariables, TOnMutateResult>` — the type arguments
come from the options; `MutationOptions.simple` infers them from
`mutationFn`.

| Parameter | Type | Default | Meaning | TanStack equivalent |
|---|---|---|---|---|
| `options` | [`MutationOptions<TData, TVariables, TOnMutateResult>`](https://pub.dev/documentation/query_kit/latest/query_kit/MutationOptions-class.html) | required | The mutation function and callbacks. Re-applied whenever the parent rebuilds this widget, so the next run uses the latest ones. | the options object |
| `builder` | `Widget Function(BuildContext context, MutationController<TData, TVariables, TOnMutateResult> mutation)` | required | Given the controller: the result is `mutation.value`, and `mutate` or `mutateAsync` starts a run. | the hook's return value |
| `buildWhen` | `BuildWhen<MutationResult<TData, TVariables>>?` | `null` | The only filter a mutation reader has; it has no `select`. | — |
| `client` | `QueryClient?` | `null` | The client to run on. | the `queryClient` argument |

Disposing the widget does not cancel a run in flight: the mutation finishes
and its options' callbacks run. Call `MutationController.cancel` first when
it should not.

## Controllers

Plain `ValueListenable`s, usable without widgets: in view models, with
`ValueListenableBuilder` or `ListenableBuilder`, or in any state-management
package that reads a listenable. You create one, listen to it and dispose it.
Do not create one in `build`: every rebuild would leak an observer and its
timers.

Every controller here is **subscribed only while listened to**: the first
listener subscribes it to its observer (which is when a query fetches, if it
needs to), the last one leaving unsubscribes it. It notifies only when
something a reader can see changed, and under a `QueryClientProvider` never
in the middle of a build.

### `QueryController`

[Dartdoc](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryController-class.html)
· TanStack Query: `useQuery` (over a `QueryObserver`)

`QueryController<TQueryData, TData>` extends `ChangeNotifier` and implements
`ValueListenable<QueryResult<TData>>`.

| Member | Type | Default | Meaning | TanStack equivalent |
|---|---|---|---|---|
| [`QueryController(client, options)`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryController/QueryController.html) | constructor; `options` is `QueryObserverOptionsBase<TQueryData, TData>` | — | Creates the observer. Takes either options shape, a `QuerySelectOptions` included. Nothing is fetched until the first listener. Asserts in debug builds that `TData` is not a top type. | `new QueryObserver(client, options)` |
| [`QueryController.create(client, options)`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryController/create.html) | static, returns `QueryController<TData, TData>`; `options` is `QueryObserverOptions<TData>` | — | The form without `select`, with one type argument. | — |
| [`QueryController.observing(client, observer)`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryController/QueryController.observing.html) | constructor; `observer` is `QueryObserver<TQueryData, TData>` | — | Wraps an observer built elsewhere and owns it from then on. Holds no options of its own, so `value` before the first listener is the observer's current result. | — |
| [`client`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryController/client.html) | `QueryClient` | — | The client the observer runs on. | — |
| [`value`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryController/value.html) | `QueryResult<TData>` | — | The current result. While nobody listens it is the *optimistic* result — `fetching` for a query that will fetch on subscribe — which is what every widget style shows on its first build. | the hook's return value |
| [`setOptions(options)`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryController/setOptions.html) | `void`; `QueryObserverOptionsBase<TQueryData, TData>` | — | Replaces the options in place; a new key switches the observed query. Does not notify. When the observer refuses the options, nothing is kept. | `observer.setOptions` |
| [`refetch({cancelRefetch})`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryController/refetch.html) | `Future<QueryResult<TData>>` | `cancelRefetch: true` | Refetches. `true` cancels a fetch in flight and starts again; `false` joins it. | `refetch` |
| [`observer`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryController/observer.html) | `QueryObserver<TQueryData, TData>` | — | The observer underneath, for what the controller does not mirror, such as `currentQuery`. | — |
| [`isDisposed`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryController/isDisposed.html) | `bool` | — | Whether `dispose` has run. | — |
| `addListener` / `removeListener` | `void` | — | The first listener subscribes, the last one leaving unsubscribes. | — |
| `dispose()` | `void` | — | Destroys the observer. Runs once. | component unmount |

### `InfiniteQueryController`

[Dartdoc](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/InfiniteQueryController-class.html)
· TanStack Query: `useInfiniteQuery` (over an `InfiniteQueryObserver`)

`InfiniteQueryController<TPageData, TPageParam, TData>` extends
`QueryController<InfiniteData<TPageData, TPageParam>, TData>`, so `client`,
`value`, `refetch`, `observer`, `isDisposed` and `dispose` are inherited. Its
notifications also cover the paging flags: two fetches in opposite
directions leave the result equal and still notify.

| Member | Type | Default | Meaning | TanStack equivalent |
|---|---|---|---|---|
| [`InfiniteQueryController(client, options)`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/InfiniteQueryController/InfiniteQueryController.html) | constructor; `options` is `InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData>` | — | Creates an `InfiniteQueryObserver`. Same contract as `QueryController`. | `new InfiniteQueryObserver(client, options)` |
| [`setInfiniteOptions(options)`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/InfiniteQueryController/setInfiniteOptions.html) | `void`; `InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData>` | — | Replaces the options, paging half included. Does not notify. | `observer.setOptions` |
| [`setOptions(options)`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/InfiniteQueryController/setOptions.html) | `void` | — | Accepts only options that carry the paging behaviour; plain observer options throw an `UnsupportedError` in every build mode. | `observer.setOptions` |
| [`hasNextPage`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/InfiniteQueryController/hasNextPage.html) | `bool` | — | `getNextPageParam` returns a param for the pages held. False before the first page. | `hasNextPage` |
| [`hasPreviousPage`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/InfiniteQueryController/hasPreviousPage.html) | `bool` | — | `getPreviousPageParam` returns a param. Always false without one. | `hasPreviousPage` |
| [`isFetchingNextPage`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/InfiniteQueryController/isFetchingNextPage.html) | `bool` | — | The fetch in flight is a `fetchNextPage`. | `isFetchingNextPage` |
| [`isFetchingPreviousPage`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/InfiniteQueryController/isFetchingPreviousPage.html) | `bool` | — | The fetch in flight is a `fetchPreviousPage`. | `isFetchingPreviousPage` |
| [`isFetchNextPageError`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/InfiniteQueryController/isFetchNextPageError.html) | `bool` | — | The result's error came from a `fetchNextPage`; the pages held are still there. | `isFetchNextPageError` |
| [`isFetchPreviousPageError`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/InfiniteQueryController/isFetchPreviousPageError.html) | `bool` | — | The error came from a `fetchPreviousPage`. | `isFetchPreviousPageError` |
| [`isRefetching`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/InfiniteQueryController/isRefetching.html) | `bool` | — | The pages held are being refetched, as opposed to a page being added. | `isRefetching` |
| [`isRefetchError`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/InfiniteQueryController/isRefetchError.html) | `bool` | — | A refetch of the held pages failed, as opposed to a page fetch. | `isRefetchError` |
| [`fetchNextPage({cancelRefetch})`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/InfiniteQueryController/fetchNextPage.html) | `Future<QueryResult<TData>>` | `cancelRefetch: true` | Fetches the page after the ones held. | `fetchNextPage` |
| [`fetchPreviousPage({cancelRefetch})`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/InfiniteQueryController/fetchPreviousPage.html) | `Future<QueryResult<TData>>` | `cancelRefetch: true` | Fetches the page before the ones held. | `fetchPreviousPage` |
| [`infiniteObserver`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/InfiniteQueryController/infiniteObserver.html) | `InfiniteQueryObserver<TPageData, TPageParam, TData>` | — | `observer`, typed with the paging half visible. | — |

### `MutationController`

[Dartdoc](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/MutationController-class.html)
· TanStack Query: `useMutation` (over a `MutationObserver`)

`MutationController<TData, TVariables, TOnMutateResult>` extends
`ChangeNotifier` and implements
`ValueListenable<MutationResult<TData, TVariables>>`.

| Member | Type | Default | Meaning | TanStack equivalent |
|---|---|---|---|---|
| [`MutationController(client, options)`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/MutationController/MutationController.html) | constructor; `options` is `MutationOptions<TData, TVariables, TOnMutateResult>` | — | Creates a `MutationObserver`. Idle until a run starts. | `new MutationObserver(client, options)` |
| [`client`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/MutationController/client.html) | `QueryClient` | — | The client the observer runs on. | — |
| [`value`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/MutationController/value.html) | `MutationResult<TData, TVariables>` | — | The current result. | the hook's return value |
| [`mutate(variables, {callbacks})`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/MutationController/mutate.html) | `void`; `callbacks` is `MutateCallbacks<TData, TVariables, TOnMutateResult>?` | `callbacks: null` | Fire and forget: the result lands in `value`, errors never reach the caller. | `mutate` |
| [`mutateAsync(variables, {callbacks})`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/MutationController/mutateAsync.html) | `Future<TData>` | `callbacks: null` | Completes with the data or throws. The per-call callbacks run after the options' own for as long as the controller is not disposed, listened to or not. Called after `dispose`, the mutation still runs with its options' callbacks, nothing lands in `value`, and the per-call callbacks are dropped. | `mutateAsync` |
| [`setOptions(options)`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/MutationController/setOptions.html) | `void` | — | Replaces the options the next run uses. Does not notify. | `observer.setOptions` |
| [`reset()`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/MutationController/reset.html) | `void` | — | Back to idle, detaching from the mutation being observed. | `reset` |
| [`cancel()`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/MutationController/cancel.html) | `void` | — | Fails the run this controller shows with a `CancelledError`; its error callbacks run. See [cancelling mutations](../guides/cancelling-mutations.md). | — |
| [`observer`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/MutationController/observer.html) | `MutationObserver<TData, TVariables, TOnMutateResult>` | — | The observer underneath, for its defaulted `options`, say. Run mutations through the controller: `observer.mutate` on a controller nobody listens to drops the per-call callbacks. | — |
| [`isDisposed`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/MutationController/isDisposed.html) | `bool` | — | Whether `dispose` has run. | — |
| `dispose()` | `void` | — | Detaches the observer from whatever mutation it ran, so that mutation can be collected. Does **not** cancel a run in flight. | component unmount |

## `context.query` and its siblings

[Dartdoc](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryContext.html)
· TanStack Query: `useQuery`, `useInfiniteQuery`, `useMutation`

`QueryContext` is an extension on `BuildContext`. It works in a
`StatelessWidget`, needs no wrapper widget, and rebuilds per reader: only the
widgets that read a query rebuild when it changes. There is no `client:`
parameter: it always reads the nearest `QueryClientProvider`'s client, and
without a provider every member throws a `FlutterError`.

| Member | Returns | Parameters | TanStack equivalent |
|---|---|---|---|
| [`query<TData>(options, {id, buildWhen})`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryContext/query.html) | `QueryResult<TData>` | `QueryObserverOptions<TData> options`, `Object? id`, `BuildWhen<QueryResult<TData>>? buildWhen` | `useQuery` |
| [`selectQuery<TQueryData, TData>(options, {id, buildWhen})`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryContext/selectQuery.html) | `QueryResult<TData>` | `QuerySelectOptions<TQueryData, TData> options`, `Object? id`, `BuildWhen<QueryResult<TData>>? buildWhen` | `useQuery` with `select` |
| [`infiniteQuery<TPageData, TPageParam, TData>(options, {id, buildWhen})`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryContext/infiniteQuery.html) | `InfiniteQueryController<TPageData, TPageParam, TData>` | `InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options`, `Object? id`, `BuildWhen<QueryResult<TData>>? buildWhen` | `useInfiniteQuery` |
| [`mutation<TData, TVariables, TOnMutateResult>(options, {id, buildWhen})`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryContext/mutation.html) | `MutationController<TData, TVariables, TOnMutateResult>` | `MutationOptions<TData, TVariables, TOnMutateResult> options`, `Object? id`, `BuildWhen<MutationResult<TData, TVariables>>? buildWhen` | `useMutation` |

The controllers `infiniteQuery` and `mutation` return belong to the reading
widget and are disposed for you; do not dispose them. `id` and `buildWhen`
default to `null`.

### Identity

- **A query read** is identified by its key and its types, not by call
  order, so a read inside an `if` is fine. Two readers of one key share the
  query in the cache but not an observer.
- **`id`** takes the key's place in the read's identity (the types stay part
  of it). A read with an `id` keeps its observer when its key changes, which
  is what keeping the previous key's data on screen with a placeholder
  needs. `id` also tells apart two reads of one key with different selectors
  of the same output type; two such reads without one are caught in debug
  builds.
- **A mutation read** is identified by `id`, else by its `mutationKey`, each
  with its three types, else by the types alone. Two reads of one identity
  in one build share one controller, so without an `id` a debug assertion
  fires when they differ in the mutation function, in `onMutate`,
  `onSuccess`, `onError` or `onSettled`, or in `scope`, `retry`,
  `retryDelay`, `networkMode` or `gcTime`. Those five compare by value,
  except `RetryPolicy.when` and `RetryDelay.dynamic`, which compare by
  variant only. `meta` is not compared. A function literal is a new function
  on every build, so keep it in a field or read the mutation once.

### Which element a read belongs to, and when it is released

A read belongs to the element whose `context` it went through, rebuilds that
element, and lives as long as that element's own builds keep reading it.

| Situation | What happens |
|---|---|
| A key read in the last build but not in this one | Released after the frame. A mutation too. |
| The widget unmounts | Everything it read is released. Releasing a mutation's controller does not cancel a run in flight. |
| A widget stops reading altogether | No signal Flutter can see: its last observers stay until it unmounts. Put a conditional read in a small widget of its own. |
| A read outside `build` (a tap handler) | Creates an observer that is only matched up at the next build. Read in `build`, act in the handler. |
| A read through the outer `context` inside a `ValueListenableBuilder`, `AnimatedBuilder` or `LayoutBuilder` callback | Additive: it releases nothing the widget's own build read. A key the callback stops reading stays until the widget's next own build that reads, or its unmount. A `build` that reads nothing itself never starts over; those keys stay until the parent rebuilds the widget or it unmounts. |
| A read through the `context` a `LayoutBuilder`, `SliverLayoutBuilder` or `OrientationBuilder` hands its builder | Starts over whenever that builder provably runs: its constraints changed, its parent rebuilt it, or one of its own reads notified. A rebuild caused only by an `InheritedWidget` it depends on carries no signal, so a key picked from an inherited value stays until the next of those. |
| A read from a `showDialog` or bottom-sheet builder through the page's `context` | Rebuilds the page, not the dialog, and the page's next build releases it while the dialog may still show it. Read through the builder's own `context`, or in a widget inside the dialog. |
| A read through the `context` a `ListView.builder`, `GridView.builder`, `PageView.builder` or another lazily built list hands its item builder | **Debug builds throw a `FlutterError`** naming the fix. That context belongs to the whole list, not the row. In release builds the reads are additive: no row on screen loses its subscription, and rows scrolled away stay subscribed until the list is rebuilt or unmounts. Give each row a widget of its own and read in its `build`. |
| The provider's client changes | Every observer read through it is released, and the readers rebuild and recreate what they read on the new client. |

## `QueryMixin`

[Dartdoc](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryMixin-mixin.html)
· TanStack Query: `useQuery`, `useInfiniteQuery`, `useMutation`

`mixin QueryMixin<T extends StatefulWidget> on State<T>`. Reads like a hook,
flat in a `State`'s `build`, and everything it creates belongs to the
`State`: disposed with it, and recreated when its client changes.

| Member | Returns | Parameters | Meaning | TanStack equivalent |
|---|---|---|---|---|
| [`queryClient`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryMixin/queryClient.html) | `QueryClient` (getter) | — | The client every read runs on; `QueryClientProvider.of(context)` by default. Override it to read from another client, `widget.client` say. Looked up again at every read: a different client releases everything held and recreates it on the new one. A `build` that reads nothing needs no provider. | `useQueryClient()` |
| [`watchQuery<TData>(options, {id, buildWhen})`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryMixin/watchQuery.html) | `QueryResult<TData>` | `QueryObserverOptions<TData> options`, `Object? id`, `BuildWhen<QueryResult<TData>>? buildWhen` | Subscribes this `State` to the query and returns its current result. | `useQuery` |
| [`watchSelectQuery<TQueryData, TData>(options, {id, buildWhen})`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryMixin/watchSelectQuery.html) | `QueryResult<TData>` | `QuerySelectOptions<TQueryData, TData> options`, `Object? id`, `BuildWhen<QueryResult<TData>>? buildWhen` | `watchQuery` with a `select`. | `useQuery` with `select` |
| [`watchInfiniteQuery<TPageData, TPageParam, TData>(options, {id, buildWhen})`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryMixin/watchInfiniteQuery.html) | `InfiniteQueryController<TPageData, TPageParam, TData>` | `InfiniteQueryObserverOptionsBase<TPageData, TPageParam, TData> options`, `Object? id`, `BuildWhen<QueryResult<TData>>? buildWhen` | The controller belongs to the `State`; do not dispose it. | `useInfiniteQuery` |
| [`watchMutation<TData, TVariables, TOnMutateResult>(options, {id, buildWhen})`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryMixin/watchMutation.html) | `MutationController<TData, TVariables, TOnMutateResult>` | `MutationOptions<TData, TVariables, TOnMutateResult> options`, `Object? id`, `BuildWhen<MutationResult<TData, TVariables>>? buildWhen` | A mutation owned by this `State`, not shared. | `useMutation` |

The mixin also overrides `dispose`, releasing everything the `State` read.

Identity is the same as for [`context.query`](#identity): key and types, or
`id`; for a mutation `id`, else `mutationKey`, with the same debug assertion.
Release differs in one way, because a `State` is one reader:

- A key read in the previous build but not in this one is released after
  the frame; everything goes when the `State` is disposed. A `State` that
  stops reading altogether keeps its last observers until it is disposed.
- A `watchQuery` inside a nested builder callback — a
  `ValueListenableBuilder`, `LayoutBuilder`, `AnimatedBuilder`, or a
  `ListView.builder`'s `itemBuilder` — reads for this `State` and is
  additive. It is **not** refused in debug builds. A key the callback stops
  reading stays until an own `build` of this `State` that reads, or its
  disposal. For a long list, give each row a widget of its own.
- A read always rebuilds this `State`. A dialog builder calling
  `watchQuery` is not rebuilt by a change; give a dialog a reader of its
  own.

## `BuildWhen` and `ListenWhen`

### `BuildWhen`

[Dartdoc](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/BuildWhen.html)
· TanStack Query: `notifyOnChangeProps` (a different mechanism)

`typedef BuildWhen<T> = bool Function(T previous, T current)`

Whether a reader rebuilds for a change from `previous` to `current`. Every
builder widget, `context` read and mixin read takes one.

- It is asked only when the value really changed. A notification carrying
  what the reader already shows never rebuilds, with or without a predicate.
- `previous` is what is on screen: the result the reader last *built* from.
  When the predicate returns `false`, that stays `previous`, and the next
  change is compared against it.
- `select` narrows the data a reader sees; `buildWhen` narrows when it
  rebuilds. It is the tool for a change `select` cannot see: a background
  refetch moves `fetchStatus` and `dataUpdatedAt`, both part of a result's
  `==`.
- Each keyless read has its own predicate, and any one of them letting a
  change through rebuilds the whole widget or `State`.
- For infinite queries it compares results; a change of the paging flags
  alone rebuilds regardless.
- Controllers, `QueriesBuilder` and `QueriesController` take none. A
  controller is the notifier, and a predicate on it would impose one
  listener's filter on every listener. See [`buildWhen`](../guides/render-optimizations.md#buildwhen).

### `ListenWhen`

[Dartdoc](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/ListenWhen.html)

`typedef ListenWhen<T> = bool Function(T previous, T next)`

Whether a transition runs a listener widget's side effect. It sees every
transition, and a rejected one still becomes the `previous` of the next.

## Listeners

[`QueryListener`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueryListener-class.html),
[`InfiniteQueryListener`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/InfiniteQueryListener-class.html),
[`MutationListener`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/MutationListener-class.html)
· TanStack Query: — (a `useEffect` over the result)

Run a side effect — a snackbar, a navigation, a log line — when a
controller's result changes, without rebuilding `child`. Each listens to a
controller you own and never disposes it. See [side
effects](../guides/side-effects.md).

| Parameter | Type | Default | Meaning |
|---|---|---|---|
| `controller` | `QueryController<TQueryData, TData>` / `InfiniteQueryController<TPageData, TPageParam, TData>` / `MutationController<TData, TVariables, TOnMutateResult>` | required | The controller to listen to. Borrowed: whoever created it disposes it. A different controller on a later build is listened to from then on, and transitions of the old one still queued are dropped. |
| `listener` | `void Function(BuildContext context, T result)` | required | The side effect. `T` is `QueryResult<TData>` for the two query listeners and `MutationResult<TData, TVariables>` for `MutationListener`. |
| `listenWhen` | `ListenWhen<T>?` | `null` (every change) | Which transitions run `listener`. |
| `child` | `Widget` | required | Returned unchanged; a transition never rebuilds it. |
| `key` | `Key?` | `null` | |

When `listener` runs:

- **Not on mount.** Only a later change of the controller's value is a
  transition.
- **Outside the build phase**, in a microtask after the notification, so it
  may show a dialog, navigate or call `setState`. Each transition is
  delivered with the value it carried, even if a later one has arrived by
  then. `listenWhen` is asked in the same microtask.
- **Once per notification.** Two cache writes inside one
  `notifyManager.batch` are one transition, to the second value.
- **For `InfiniteQueryListener`, only on a change of the result.** A paging
  flag changing on its own is not a transition.
- An error thrown by `listener` is reported through `FlutterError`, not
  thrown into the tree.

For a side effect of one particular call, the per-call `callbacks` of
`MutationController.mutate` are the alternative; `MutationListener` hears
every run of the controller.

## Collections

### `QueriesBuilder`

[Dartdoc](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueriesBuilder-class.html)
· TanStack Query: `useQueries`

`QueriesBuilder<TQueryData, TData>` builds from a list of queries of one
type that may change length or order. It owns a `QueriesController`.

| Parameter | Type | Default | Meaning | TanStack equivalent |
|---|---|---|---|---|
| `queries` | `List<QueryObserverOptionsBase<TQueryData, TData>>` | required | The queries, in the order their results are handed to `builder`. Re-applied whenever the parent rebuilds this widget; an unchanged list moves nothing. | `queries` |
| `builder` | `Widget Function(BuildContext context, List<QueryResult<TData>> results)` | required | Built from one result per entry of `queries`, first and again whenever a result or the list changes. | the hook's return value |
| `client` | `QueryClient?` | `null` (provider's) | As for `QueryBuilder`. | the `queryClient` argument |
| `key` | `Key?` | `null` | | — |

- **Observers are reused by key and occurrence**, so reordering starts no
  requests. Duplicate keys share one cache entry and keep their own options.
- **Each query fails and settles on its own.**
- **No `buildWhen`.** A predicate over the whole list would say nothing about
  which query changed; read each query on its own to filter per query. The
  widget still never rebuilds for results it already shows, compared element
  by element.
- For queries of different types, read each one and combine them; see
  [combining queries](../guides/combining-queries.md).

### `QueriesController`

[Dartdoc](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/QueriesController-class.html)
· TanStack Query: `useQueries` (over a `QueriesObserver`)

`QueriesController<TQueryData, TData>` is a
`ValueListenable<List<QueryResult<TData>>>`, the same collection outside a
widget.

| Member | Type | Default | Meaning | TanStack equivalent |
|---|---|---|---|---|
| `QueriesController(client, queries)` | constructor; `List<QueryObserverOptionsBase<TQueryData, TData>> queries` | — | Creates the collection. Nothing fetches until the first listener; then every enabled query that needs to does. | `new QueriesObserver(client, queries)` |
| `client` | `QueryClient` | — | The client every query in the collection uses. | — |
| `value` | `List<QueryResult<TData>>` | — | The results, in order. Before the first listener, the optimistic list. | the hook's return value |
| `setQueries(queries)` | `void` | — | Replaces the list, reusing observers by key occurrence. A new key fetches like any new query. | `observer.setQueries` |
| `observer` | `QueriesObserver<TQueryData, TData>` | — | The core observer, including its underlying observers. | — |
| `dispose()` | `void` | — | Destroys every observer. | component unmount |

Listeners are told only when a result changed, compared element by element;
each result's `refetch` target is compared too, so replacing or reordering
equal results still notifies.

### `IsFetchingController`

[Dartdoc](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/IsFetchingController-class.html)
· TanStack Query: `useIsFetching`

A `ValueListenable<int>`: how many queries matching the filters are fetching
right now. A background refetch counts. Subscribed to the query cache only
while something listens, and notifies only when the count changes.

| Member | Type | Default | Meaning | TanStack equivalent |
|---|---|---|---|---|
| `IsFetchingController(client, {filters})` | constructor | `filters: const QueryFilters()` (all queries) | Creates the count over `client`'s query cache. | `useIsFetching(filters)` |
| `client` | `QueryClient` | — | The client whose queries are counted. | — |
| `filters` | [`QueryFilters`](https://pub.dev/documentation/query_kit/latest/query_kit/QueryFilters-class.html) | all queries | Which queries count. Fixed for the controller's life; other filters are another controller. | `filters` |
| `value` | `int` | — | `client.isFetching(filters: filters)`. | the hook's return value |
| `dispose()` | `void` | — | Unsubscribes. | — |

`QueryClient.isFetching` is the same count as a one-off snapshot. For
mutations in flight, use a `MutationStateController` filtered on
`MutationStatus.pending`; its list length is the count.

### `MutationStateController`

[Dartdoc](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/MutationStateController-class.html)
· TanStack Query: `useMutationState`

`MutationStateController<TSelected>` is a `ValueListenable<List<TSelected>>`:
a value selected from every mutation in the cache that matches the filters,
one entry per mutation, in the order they were added. For showing mutations
somewhere other than where they started — a "saving" badge, a pending row for
a write started on another screen. See [mutation
state](../guides/mutation-state.md).

| Member | Type | Default | Meaning | TanStack equivalent |
|---|---|---|---|---|
| `MutationStateController(client, {filters, required select})` | constructor; `select` is `MutationStateSelect<TSelected>`, a `TSelected Function(Mutation<Object?, Object?, Object?> mutation)` | `filters: const MutationFilters()` | A selection over the mutation cache. `select` runs over every matching mutation on every cache change, so keep it cheap. | `useMutationState({ filters, select })` |
| [`MutationStateController.typed(client, {filters, required select})`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/MutationStateController/typed.html) | static; `select` is `TypedMutationStateSelect<TData, TVariables, TOnMutateResult, TSelected>`, a `TSelected Function(Mutation<TData, TVariables, TOnMutateResult> mutation)` | `filters: const MutationFilters()` | Selects from mutations of one type only, typed. The types usually come from `select`'s parameter; a type left as `Object?` matches anything. The type test stays through a later `setOptions`. | — |
| `client` | `QueryClient` | — | The client whose mutations are selected. | — |
| `value` | `List<TSelected>` | — | The current selection. | the hook's return value |
| `setOptions({filters, select})` | `void`; `MutationFilters?`, `MutationStateSelect<TSelected>?` | both `null` (unchanged) | Replaces the filters and/or selector. The selection is recomputed at once, and listeners are told when it changed. | — |
| `dispose()` | `void` | — | Destroys the observer. | — |

Subscribed to the mutation cache only while something listens; listeners are
told only when the selection changed, element by element.

## `OnlineStatus`

[Dartdoc](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/OnlineStatus-class.html)
· TanStack Query: `onlineManager.setEventListener`

A sealed value passed as `QueryClientProvider.onlineStatus`: what the client
should believe about the network, and where later changes come from.
Connectivity is opt-in — nothing is installed by default, no connectivity
package is a dependency, and a client with no status assumes it is online.
See [connectivity](../guides/connectivity.md) for a `connectivity_plus`
example.

| Variant | Class | Fields | Meaning |
|---|---|---|---|
| `OnlineStatus.fixed(bool online)` | [`OnlineStatusFixed`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/OnlineStatusFixed-class.html) | `online` | This is the state, with no source of changes. For a test, a desktop build or a developer's offline switch. |
| `OnlineStatus.stream(Stream<bool> changes, {required bool initial})` | [`OnlineStatusStream`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/OnlineStatusStream-class.html) | `changes`, `initial` | Follow `changes`, assuming `initial` until the first event. `initial` is required because a `Stream` has no current value. |

Both are `const` and compare by value. The base class exposes
[`initial`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/OnlineStatus/initial.html)
(`bool`: the whole story for `fixed`, the starting assumption for `stream`)
and
[`changes`](https://pub.dev/documentation/query_kit_flutter/latest/query_kit_flutter/OnlineStatus/changes.html)
(`Stream<bool>?`, `null` for `fixed`). The classes are public so a `switch`
can name them.

How the provider feeds it to `client.onlineManager` (through `setOnline`):

- **`initial` is applied** whenever a client is given this status: at mount,
  to a client that arrives on a later build, and on any later build that
  changes the status. Not when a stream delivers while it is being listened
  to (a synchronous controller's `onListen`): that event is believed over
  `initial`.
- **Every stream event** is passed to the provider's current client.
- **A new client under the same stream** starts from that stream's last
  event, or from `initial` if it has said nothing yet.
- **One stream swapped for another** keeps the client's current verdict
  rather than rewinding it to `initial`, so a stream rebuilt in `build` does
  not flicker. A `fixed` status has no stream, so a changed one reaches the
  client on the rebuild that changes it and works as a live switch.
- **Taking the status away** (`null` on a later build) **or disposing the
  provider** puts the client back online, but only once no other provider
  has a status for that client; a replacement provider on the same client
  keeps its own verdict. A client the provider leaves for another client is
  left as it was.
- **A stream** is listened to once per stream object. A broadcast stream
  always works. A single-subscription stream works only while exactly one
  provider listens to it once; a second listen throws a `FlutterError`
  pointing to `asBroadcastStream()`. A stream error is reported through
  `FlutterError.reportError`, not thrown.

While the client believes it is offline, what a query or mutation does is
its [network mode](../guides/network-mode.md).

## Testing

Widget tests need a teardown step, because a `QueryClient` outlives the tree
and owns `gcTime` timers. It is a documented snippet rather than an export;
see [testing](../guides/testing.md).
