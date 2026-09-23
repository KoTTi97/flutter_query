---
title: An infinite list view
description: A ListView that loads the next page as the user nears the end — once per page, with a footer that shows progress, a retry and the end of the list, and pull-to-refresh on top.
sidebar_position: 8
---

# An infinite list view

The catalogue's "All products" screen pages through the whole range, twenty
products at a time. The next page should load before the user reaches the end,
exactly once per page however many scroll events arrive, with a spinner at the
bottom while it does. A failed page should offer a retry without losing the
pages above it; the last page should say so; and a first page too short to
scroll should still have a way on. The library keeps the pages and knows
whether there is a next one. The screen owns the scroll listener and the
footer.

## The finished code

The options: pages of products, flattened into one list by a `select`.

```dart snippet="cookbook/infinite-list-view.md#options" title="lib/features/products/product_feed.dart"
InfiniteQuerySelectOptions<ProductPage, int, List<Product>> productFeedQuery(
  ProductApi api,
) =>
    InfiniteQuerySelectOptions<ProductPage, int, List<Product>>(
      queryKey: ProductKeys.feed,
      initialPageParam: 0,
      pageFn: (context) => api.page(context.pageParam, signal: context.signal),
      getNextPageParam: (page, _, __, ___) => page.nextOffset,
      select: _productsOf,
    );

/// A top-level function, not a closure: a new function on every build would
/// run the select again on every build.
List<Product> _productsOf(InfiniteData<ProductPage, int> data) =>
    <Product>[for (final page in data.pages) ...page.items];
```

The screen, with an `InfiniteQueryBuilder` and a scroll listener:

```dart snippet="cookbook/infinite-list-view.md#screen" title="lib/features/products/product_feed_screen.dart"
class ProductFeedScreen extends StatefulWidget {
  const ProductFeedScreen({super.key});

  @override
  State<ProductFeedScreen> createState() => _ProductFeedScreenState();
}

class _ProductFeedScreenState extends State<ProductFeedScreen> {
  static const double loadMoreThreshold = 400;

  final ScrollController _scroll = ScrollController();

  /// The builder's controller, for the scroll listener. The builder owns it.
  InfiniteQueryController<ProductPage, int, List<Product>>? _feed;

  /// How long the list was when the last page was asked for.
  double? _askedAtExtent;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final feed = _feed;
    if (feed == null || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.extentAfter < loadMoreThreshold &&
        // Once per length of the list: the listener hears every pixel.
        position.maxScrollExtent != _askedAtExtent &&
        feed.hasNextPage &&
        !feed.isFetchingNextPage) {
      _askedAtExtent = position.maxScrollExtent;
      feed.fetchNextPage().ignore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('All products')),
      body: InfiniteQueryBuilder(
        options: productFeedQuery(ProductApiScope.of(context)),
        builder: (context, feed) {
          _feed = feed;
          return switch (feed.value) {
            QueryPending() => const Center(child: CircularProgressIndicator()),
            QueryError(:final error, staleData: null) =>
              Center(child: Text('Could not load: $error')),
            QuerySuccess(:final data) ||
            QueryError(staleData: final data?) =>
              RefreshIndicator(
                onRefresh: feed.refetch,
                child: ListView.builder(
                  controller: _scroll,
                  physics: const AlwaysScrollableScrollPhysics(),
                  // One more row than there are products: the footer.
                  itemCount: data.length + 1,
                  itemBuilder: (context, index) => index < data.length
                      ? ProductTile(data[index])
                      : FeedFooter(feed),
                ),
              ),
          };
        },
      ),
    );
  }
}
```

The footer — the list's last row:

```dart snippet="cookbook/infinite-list-view.md#footer" title="lib/features/products/feed_footer.dart"
class FeedFooter extends StatelessWidget {
  const FeedFooter(this.feed, {super.key});

  final InfiniteQueryController<ProductPage, int, List<Product>> feed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: switch ((
            feed.isFetchingNextPage,
            feed.isFetchNextPageError,
            feed.hasNextPage,
          )) {
            (true, _, _) => const CircularProgressIndicator(),
            (_, true, _) => TextButton(
                onPressed: feed.fetchNextPage,
                child: const Text('Could not load more — try again'),
              ),
            // Also the way on when the first page does not fill the screen,
            // so there is nothing to scroll.
            (_, _, true) => TextButton(
                onPressed: feed.fetchNextPage,
                child: const Text('Load more'),
              ),
            _ => const Text("That's everything"),
          },
        ),
      );
}
```

`ProductPage` is the API's answer — a page of products and the offset the next
page starts at, `null` on the last one — and `ProductApi.page` is its call in
[Wiring dio or package:http](wiring-dio-and-http.md#the-finished-code).

## How it works

1. **The server says where the next page starts.** `getNextPageParam` returns
   the page's `nextOffset`; `null` means there is no next page, which sets
   `hasNextPage` to false. The library asks for the first page with
   `initialPageParam`, and for each next one with what the last page said.
2. **`select` flattens the pages.** The cache holds `InfiniteData`, a list of
   pages and the param each was fetched with. The widget wants one list of
   products; `_productsOf` makes it, and the builder receives
   `List<Product>`.
3. **The listener asks near the end.** `extentAfter` is how much list is left
   below the viewport. Under 400 pixels, the listener asks for the next page —
   early enough that the rows are usually there before the user reaches them.
4. **Once per page.** A scroll listener fires for every pixel. Before asking,
   it checks that the list has grown since the last ask (`maxScrollExtent`
   against `_askedAtExtent`), that there is a next page, and that one is not
   being fetched already. The first check is what stops a burst of scroll
   events from asking twice between the ask and the new rows.
5. **The controller comes from the builder.** `InfiniteQueryBuilder` owns its
   controller and hands it to `builder`; the screen keeps a reference for the
   listener, which runs outside `build`. `fetchNextPage` is on the controller,
   not on the result, because it is an action and the result is a value.
6. **The footer is a row like any other.** `itemCount` is one more than the
   products; the last index builds `FeedFooter`, which switches on three flags:
   fetching (a spinner), a failed next page (a retry button — the pages above
   stay), a next page to load (a button, for the list too short to scroll), or
   the end.
7. **Pull-to-refresh reloads what is held.** `feed.refetch` fetches every page
   the list holds again, first to last, each from the param the page before it
   now gives, so the list stays consistent if products were added.

Try it: scroll the demo's list to the bottom — the next page loads as you near
it, and "Load more" does the same by hand. Leave with "Go to about" and come
back: the pages are still cached.

<LiveDemo feature="load-more" height={560} />

## Traps

- **Guard on the list's length, not on a pixel offset.** A check like "within
  400 pixels of the end" is true for every scroll event until the new rows
  arrive, and `isFetchingNextPage` only turns true once the fetch has been
  started. Comparing `maxScrollExtent` with the extent at the last ask is
  what makes the ask happen once per page.
- **`select` must be a top-level function or a static method.** A closure
  written inside `build` is a new function on every build; the library cannot
  tell it is the same, and runs it again for every rebuild. A top-level
  function is the same object every time.
- **A first page that does not fill the screen never scrolls.** No scroll, no
  listener call. The footer's "Load more" is the way on; without it, a tall
  screen with twenty short rows shows a list that never grows.
- **Refetching many pages is many requests.** A list scrolled to page 30 and
  then invalidated refetches thirty pages, one after another. See `maxPages`
  below.
- **Keep the infinite key out of plain list prefixes.** `ProductKeys.feed` holds
  `InfiniteData`, not `List<Product>`. Under the `lists` prefix, a
  `getQueriesData<List<Product>>` over that prefix — as the
  [detail seeding](list-detail-seeding.md) does — would reach it and throw.

## Variations

- **Cap the pages.** `maxPages: 10` keeps at most ten pages: an eleventh drops
  the first, and a refetch reloads ten, not thirty. Pages dropped from the top
  come back only through `getPreviousPageParam` and `fetchPreviousPage`, and
  the rows above the viewport disappear — so this suits a list that is also
  loaded upward, not a plain endless scroll.
- **Only a button.** Drop the scroll listener; the footer's "Load more" alone
  is a complete, simpler screen.
- **Another call style.** `context.infiniteQuery`, the mixin's
  `watchInfiniteQuery` or an `InfiniteQueryController` held by the state read
  the same options. With the controller in hand from the start, `_feed`
  becomes a `late final` field.
- **Cursor pagination.** Make the page param a `String?` cursor instead of an
  offset; nothing else changes.

:::note[In React Query]
`useInfiniteQuery` with the same four options. On the web the trigger is
usually an `IntersectionObserver` on a sentinel element; in Flutter it is a
`ScrollController` listener, or a footer row that asks when it is built.
:::

## See also

- [Infinite queries](../guides/infinite-queries.md#scroll-triggered-loading) —
  the options, both directions, and `maxPages`.
- [Paginated queries](../guides/paginated-queries.md) — numbered pages instead
  of an endless list.
- [Scroll restoration](../guides/scroll-restoration.md) — coming back to the
  same place in the list.
- [Pull to refresh](pull-to-refresh.md) — the refresh gesture on an ordinary
  query.
