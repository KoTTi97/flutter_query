---
title: Pull to refresh
description: A RefreshIndicator whose spinner lasts exactly as long as the refetch, keeps the list on screen when the refresh fails, and works on an empty list too.
sidebar_position: 3
---

# Pull to refresh

The user pulls the list down; the spinner should stay until the new data is
there — not vanish at once, not hang when the refresh fails — and a refresh
that fails should leave the products they were looking at on screen, with a
note that they may be out of date. The pull has to work on every state of the
screen, including the spinner of a first load and the "no products yet" of an
empty catalogue, where there is nothing to scroll. The library does most of
this already: a query's `refetch` returns a future that completes when the
fetch has settled, and a failed refetch keeps the last data as `staleData`.

## The finished code

```dart snippet="cookbook/pull-to-refresh.md#screen" title="lib/features/products/product_list_screen.dart"
class ProductListScreen extends StatelessWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final products =
        context.query(productListQuery(ProductApiScope.of(context)));
    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      body: RefreshIndicator(
        // Completes when the refetch has settled, success or failure; it
        // never throws, so the spinner always goes away.
        onRefresh: products.refetch,
        child: switch (products) {
          QueryPending() => const _Scrollable(
              child: Center(child: CircularProgressIndicator()),
            ),
          QuerySuccess(:final data) => ProductListView(data),
          // A failed refresh keeps the list on screen, with a banner.
          QueryError(:final error, staleData: final data?) =>
            ProductListView(data, problem: '$error'),
          QueryError(:final error) => _Scrollable(
              child: Center(child: Text('Could not load products: $error')),
            ),
        },
      ),
    );
  }
}
```

The states with nothing to scroll are wrapped so the pull still works:

```dart snippet="cookbook/pull-to-refresh.md#scrollable" title="lib/features/products/product_list_screen.dart"
/// A `RefreshIndicator` only works over something that scrolls — also when
/// there is nothing to show yet.
class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(height: constraints.maxHeight, child: child),
        ),
      );
}
```

`productListQuery` is defined in
[List to detail, seeded](list-detail-seeding.md#the-finished-code), and
`ProductListView` is a `ListView.builder` of `ProductTile`s with
`AlwaysScrollableScrollPhysics`, plus a first row saying "Could not refresh"
when `problem` is set.

## How it works

1. **`onRefresh: products.refetch` is the whole wiring.** `RefreshIndicator`
   wants a `Future<void> Function()`, and `refetch` is one: it fetches again,
   stale or not, and completes with the new result once the fetch has settled.
   The spinner therefore lasts as long as the request.
2. **`refetch` never throws.** A failed fetch completes the future with a
   `QueryError` result rather than an error, so the indicator always gets its
   answer and the spinner always goes away. There is no `try` to write.
3. **A failed refresh keeps the data.** The result is a sealed type: a
   `QueryError` that follows a success carries the last good list as
   `staleData`. The screen matches that case before the plain error, and shows
   the list with a banner instead of replacing it with an error page.
4. **Every state is scrollable.** `RefreshIndicator` listens to a scrollable
   below it. The loading spinner and the empty state are put in a
   `SingleChildScrollView` with `AlwaysScrollableScrollPhysics`, sized to the
   viewport by a `LayoutBuilder`, so a first load that failed can be pulled
   again.
5. **A pull on a list already being fetched starts over.** `refetch` cancels a
   fetch that is running for a query with data and starts a new one
   (`cancelRefetch: true`, the default). Pass `cancelRefetch: false` in a
   lambda to join the running fetch instead:
   `onRefresh: () => products.refetch(cancelRefetch: false)`.

## Refreshing everything on the screen

When one pull should refresh several queries — a dashboard, or a list and the
counts in its header — refetch them through the client, by key prefix:

```dart snippet="cookbook/pull-to-refresh.md#refresh-everything" title="lib/features/products/refresh.dart"
/// Everything under `products` that is on screen, at once. Unlike an
/// observer's `refetch`, it does not wait for a fetch paused offline.
Future<void> refreshProducts(BuildContext context) =>
    QueryClientProvider.read(context).refetchQueries(
      filters: QueryFilters(
        queryKey: ProductKeys.all,
        type: QueryTypeFilter.active,
      ),
    );
```

`type: QueryTypeFilter.active` limits it to the queries something on screen
reads; the inactive ones are refetched when a screen reads them again, if they
are stale. Use it as `onRefresh: () => refreshProducts(context)`.

## Traps

- **The spinner can last longer than the request.** `refetch` waits for the
  fetch to *settle*, and a failing fetch retries first: with the default three
  retries and their growing delays, a pull on a dead server spins for about
  seven seconds before the banner appears. Give the query a shorter `retry`, or
  the [retry policy from the auth recipe](auth-and-token-refresh.md#retry-only-what-can-succeed),
  if that is too long.
- **Offline, `refetch` waits for the network.** A fetch that starts while the
  client believes it is offline is paused, not failed, and the future waits for
  it to resume — the spinner stays until the connection is back.
  `refreshProducts` above behaves differently: `refetchQueries` does not wait
  for paused fetches, so its spinner ends at once. Pick the one that fits the
  screen; [Network mode](../guides/network-mode.md) says when a fetch pauses.
- **Two error reports for one failure.** With the
  [global error snackbar](global-error-snackbar.md) installed, a failed refresh
  of data on screen shows a toast *and* this screen's banner. Keep one: mark
  the list query silent (`meta: ErrorReporting.silent`), or drop the banner.
- **`RefreshIndicator` needs a scrollable directly below it.** A `Column` with a
  `ListView` inside an `Expanded` works; a `Center` with a spinner does not,
  which is what `_Scrollable` is for.

## Variations

- **Another call style.** The same screen reads as well through a
  `QueryBuilder`, the `QueryMixin` methods or a `QueryController` held by a
  view model — `refetch` is on each of them. A view model that owns a
  `QueryController` passes `controller.refetch` to the indicator the same way.
- **An infinite list** refreshes the same way; see
  [An infinite list view](infinite-list-view.md) for how many pages it
  reloads.
- **Cupertino.** `CupertinoSliverRefreshControl` takes the same
  `onRefresh`.

:::note[In React Query]
React Native's `RefreshControl` is wired the same way: `refreshing` from
`isRefetching` and `onRefresh={refetch}`. Here `RefreshIndicator` keeps its own
spinner state from the future, so there is no flag to pass.
:::

## See also

- [Queries](../guides/queries.md) — the result types, `staleData` included.
- [Background fetching indicators](../guides/background-fetching-indicators.md)
  — showing a refetch that the user did not ask for.
- [Filters](../guides/filters.md) — what `QueryFilters` can match.
