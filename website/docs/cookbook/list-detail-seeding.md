---
title: List to detail, seeded
description: Open a detail screen with the data the list already has — no spinner, no second request — and still refetch it when it is old.
sidebar_position: 5
---

# List to detail, seeded

The list has just loaded twenty products, each with its name and price. The
user taps one, and the detail screen shows a spinner while it asks the server
for a product the app received a second ago. It should open with that product
instead, fetch nothing if the list is fresh, and fetch in the background if the
list is old — without the detail ever being treated as newer than the data it
came from. Two techniques do it, and this recipe uses both: the list *pushes*
each product into its detail entry when it loads, and the detail *pulls* from
the lists when it opens on an entry nobody pushed.

## The finished code

The list query, which writes every product it receives into that product's
detail entry:

```dart snippet="cookbook/list-detail-seeding.md#list-query" title="lib/features/products/product_queries.dart"
QueryObserverOptions<List<Product>> productListQuery(
  ProductApi api, {
  String search = '',
}) =>
    QueryObserverOptions<List<Product>>(
      queryKey: ProductKeys.list(search: search),
      queryFn: (context) async {
        final products = await api.list(search: search, signal: context.signal);
        // One entry per product, so the detail screen opens with data and
        // every later list response reaches the detail too.
        for (final product in products) {
          context.client
              .setQueryData<Product>(ProductKeys.detail(product.id), product);
        }
        return products;
      },
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );
```

The detail query, with a fallback that looks through the lists already in the
cache:

```dart snippet="cookbook/list-detail-seeding.md#detail-query" title="lib/features/products/product_queries.dart"
QueryObserverOptions<Product> productQuery(
  QueryClient client,
  ProductApi api,
  String id,
) =>
    QueryObserverOptions<Product>(
      queryKey: ProductKeys.detail(id),
      queryFn: (context) => api.get(id, signal: context.signal),
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
      // The fallback for an entry the list has not seeded yet — a deep
      // link, or a list still loading when the row was tapped.
      initialData: InitialData<Product>.compute(() => _findInLists(client, id)),
      // As old as the list it came from, so it is refetched when that is
      // stale rather than trusted as brand new.
      initialDataUpdatedAtCompute: () => _listUpdatedAt(client, id),
    );

Product? _findInLists(QueryClient client, String id) {
  for (final (_, products) in client.getQueriesData<List<Product>>(
    filters: QueryFilters(queryKey: ProductKeys.lists),
  )) {
    for (final product in products ?? const <Product>[]) {
      if (product.id == id) return product;
    }
  }
  return null;
}

DateTime? _listUpdatedAt(QueryClient client, String id) {
  for (final (key, products) in client.getQueriesData<List<Product>>(
    filters: QueryFilters(queryKey: ProductKeys.lists),
  )) {
    if (products?.any((product) => product.id == id) ?? false) {
      return client.getQueryState<List<Product>>(key)?.dataUpdatedAt;
    }
  }
  return null;
}
```

A row of the list, which opens the detail:

```dart snippet="cookbook/list-detail-seeding.md#tile" title="lib/features/products/product_tile.dart"
class ProductTile extends StatelessWidget {
  const ProductTile(this.product, {super.key});

  final Product product;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(product.name),
        subtitle: Text(formatPrice(product.price)),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ProductDetailScreen(id: product.id),
          ),
        ),
      );
}
```

And the detail screen, read through a `QueryBuilder`:

```dart snippet="cookbook/list-detail-seeding.md#detail-screen" title="lib/features/products/product_detail_screen.dart"
class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    final api = ProductApiScope.of(context);
    return QueryBuilder<Product>(
      options: productQuery(client, api, id),
      builder: (context, product) => Scaffold(
        appBar: AppBar(title: Text(product.dataOrNull?.name ?? 'Product')),
        body: switch (product) {
          QueryPending() => const Center(child: CircularProgressIndicator()),
          QueryError(:final error, staleData: null) =>
            Center(child: Text('Could not load: $error')),
          QueryError(staleData: final data?) ||
          QuerySuccess(:final data) =>
            ProductDetails(data, refreshing: product.isFetching),
        },
      ),
    );
  }
}
```

`ProductKeys` and `ProductApi` are from
[Wiring dio or package:http](wiring-dio-and-http.md#the-finished-code).

## How it works

1. **The list pushes.** `context.client` is the client running the fetch.
   After the list arrives, `setQueryData` writes each product under
   `ProductKeys.detail(id)`, stamped with the time of the write. A detail
   opened in the next thirty seconds is fresh: it shows at once and fetches
   nothing.
2. **Every later list response reaches the details too.** A refetch of the list
   writes the products again, so a detail entry never shows a price older than
   the list next to it.
3. **The detail pulls when nothing was pushed.** `InitialData.compute` runs
   only when the detail's entry does not exist yet — a deep link, a detail
   entry that was garbage-collected while the list was kept, or a list that is
   still loading from another screen. It looks through every cached list with
   `getQueriesData` and returns the product if one of them has it.
4. **Pulled data is as old as its list.** `initialDataUpdatedAtCompute` returns
   the list's `dataUpdatedAt`. Initial data without it would be stamped *now*,
   and a product from a list loaded ten minutes ago would count as fresh.
   With it, the detail is stale when its list is, and refetches in the
   background while showing the seeded product.
5. **`null` means "not found".** When no list has the product, `compute`
   returns `null` and the query starts `pending`, like any first load. The
   screen's spinner is still there for that case.
6. **The screen shows what it has.** `QueryError` with `staleData` shows the
   product it already had; `product.isFetching` puts a thin progress bar over
   a background refetch.

Try it in the demo's card A: open a post — it appears at once, seeded from the
cached list, and the debug strip under it shows no fetch. Switch on "Treat
initial data as old" and open another: the seed still shows at once, and a
background fetch follows, because the seed is dated as old as its list.

<LiveDemo feature="initial-and-placeholder" height={560} />

## Traps

- **Seed from the list's type, not the widget's.** `getQueriesData<List<Product>>`
  checks the type of every entry it matches and throws a `QueryDataTypeError`
  for one that holds something else. That is why the endless feed's key
  (`ProductKeys.feed`, which holds pages) sits beside `ProductKeys.lists`
  rather than under it: under the prefix, the lookup would reach it and throw.
- **`initialData` is only for an entry that does not exist.** When the detail
  entry is already in the cache — pushed by the list, or loaded before —
  `compute` never runs. It does not overwrite; it fills an empty slot.
- **Pushing costs entries.** A list of 500 products writes 500 detail entries.
  They are cheap, and garbage-collected after `gcTime` when nothing reads them,
  but a list with large pages is a reason to pull only.
- **A list row is not always a whole detail.** If the list endpoint sends a
  summary (name and price) and the detail has more (a description), seeding the
  detail with a summary shows a screen with holes. Use
  [placeholder data](../guides/placeholder-query-data.md) from the list
  instead: it shows while the full detail loads, and is never cached as the
  detail.
- **Keep the pushed product equal.** `Product` has value equality, so a refetch
  that returns the same product changes nothing and rebuilds nothing.

## Variations

- **Pull only.** Drop the loop from the list's query function. Every detail is
  seeded when it opens, from whichever list has it; nothing is written up front.
- **Push only.** Drop `initialData` from the detail. A deep link then loads with
  a spinner, which is often fine.
- **Another call style.** `context.query(productQuery(...))`, the mixin's
  `watchQuery` or a `QueryController` read the same options; nothing on this page
  depends on the `QueryBuilder`.

:::note[In React Query]
The same two approaches, often called push and pull: `queryClient.setQueryData`
in the list's `queryFn`, or `initialData` with `initialDataUpdatedAt` from
`getQueryState(...).dataUpdatedAt`. `InitialData.compute` is the function form
of `initialData`.
:::

## See also

- [Initial query data](../guides/initial-query-data.md#seeding-a-detail-from-a-list)
  — `initialData`, its timestamp, and the other seeding patterns.
- [Updates from mutation responses](../guides/updates-from-mutation-responses.md)
  — the same write, after a save.
- [Caching](../guides/caching.md) — `staleTime`, `gcTime`, and when an entry is
  fetched.
