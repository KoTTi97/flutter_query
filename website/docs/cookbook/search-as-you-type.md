---
title: Search as you type
description: A debounced search box that asks the server nothing while empty, cancels the request a newer keystroke replaced, and keeps the last results on screen while the next arrive.
---

# Search as you type

A search field over the product list. Typing "kettle" should not send six
requests, an empty field should send none, and a request for "ket" that is
still on its way when the user has typed "kett" should be stopped rather than
answered and thrown away. While the new results load, the old ones should stay
on screen — dimmed, not replaced by a spinner that flickers on every
keystroke. Four pieces do it: a debounce in the widget, a disabled query for
the empty field, the cancellation signal, and `keepPrevious` placeholder data.

## The finished code

The options: the list query, per search term, off while the term is empty.

```dart snippet="cookbook/search-as-you-type.md#options" title="lib/features/products/product_search.dart"
QueryObserverOptions<List<Product>> productSearchQuery(
  ProductApi api,
  String needle,
) =>
    productListQuery(api, search: needle).copyWith(
      // An empty box asks the server nothing.
      enabled: needle.isEmpty ? Enabled.no : Enabled.yes,
      // While the new needle loads, keep showing the last results.
      placeholderData: const PlaceholderData<List<Product>>.keepPrevious(),
    );
```

The screen, read through the `QueryMixin` methods:

```dart snippet="cookbook/search-as-you-type.md#screen" title="lib/features/products/product_search.dart"
class ProductSearchScreen extends StatefulWidget {
  const ProductSearchScreen({super.key});

  @override
  State<ProductSearchScreen> createState() => _ProductSearchScreenState();
}

class _ProductSearchScreenState extends State<ProductSearchScreen>
    with QueryMixin {
  static const Duration debounce = Duration(milliseconds: 300);

  Timer? _debounce;
  String _needle = '';

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(debounce, () {
      final needle = text.trim();
      if (mounted && needle != _needle) setState(() => _needle = needle);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // One `id`, so the read follows the needle from key to key and
    // `keepPrevious` has a previous to keep.
    final results = watchQuery(
      productSearchQuery(ProductApiScope.of(context), _needle),
      id: 'search',
    );
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(hintText: 'Search products'),
        ),
        bottom: results.isFetching
            ? const PreferredSize(
                preferredSize: Size.fromHeight(4),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: _needle.isEmpty
          ? const Center(child: Text('Type to search'))
          : switch (results) {
              QueryPending() => const SizedBox.shrink(),
              QueryError(:final error) => Center(child: Text('$error')),
              QuerySuccess(data: []) =>
                Center(child: Text('Nothing matches "$_needle"')),
              QuerySuccess(:final data) => Opacity(
                  // Last needle's results, while this one loads.
                  opacity: results.isPlaceholderData ? 0.5 : 1,
                  child: ListView(
                    children: <Widget>[
                      for (final product in data) ProductTile(product),
                    ],
                  ),
                ),
            },
    );
  }
}
```

`productListQuery` is the list query from
[List to detail, seeded](list-detail-seeding.md#the-finished-code); its key is
`ProductKeys.list(search: needle)`, so every term has an entry of its own.

## How it works

1. **The debounce lives in the widget.** The text field changes on every
   keystroke; `_needle` changes only after 300 ms without one. The query reads
   `_needle`, so the key — and with it the request — changes once per pause in
   the typing, not once per letter.
2. **A new term is a new key.** `ProductKeys.list(search: 'kett')` and
   `ProductKeys.list(search: 'ket')` are different entries. Going back to a term
   searched a moment ago shows its cached results at once, fresh for the
   list query's thirty-second `staleTime`.
3. **An empty field is a disabled query.** `Enabled.no` means the query never
   fetches on its own; the screen shows "Type to search" instead of reading the
   result. Clearing the box costs nothing.
4. **The superseded request is cancelled.** When the key changes, the reader
   moves on to the new entry and the old one has no reader left. Its query
   function consumed `context.signal` (the API client passes it to dio), so the
   library cancels the fetch and the bridge from
   [Wiring dio or package:http](wiring-dio-and-http.md) aborts the request on
   the wire.
5. **`keepPrevious` holds the last results.** While the new term's first fetch
   runs, the result is a `QuerySuccess` with the previous term's data and
   `isPlaceholderData` set. The list stays, at half opacity, and the progress
   bar in the app bar says something is on its way.
6. **One `id` for the read.** `watchQuery(..., id: 'search')` tells the mixin
   that the read for "ket" and the read for "kett" are the same read with a new
   key. Without it, a changed key would be a new read, and a new read has no
   previous data to keep.

Try it in the demo's "Search as you type" card: type a few letters, pause,
then type again before the answer arrives — `searchCancels` counts the
searches stopped in flight. The demo's backend is in memory, with a deliberate
delay.

<LiveDemo feature="cancellation" height={560} />

## Traps

- **Debouncing in the query function does not work.** A `Future.delayed`
  before the request makes every keystroke a fetch that waits, then runs; the
  entries still pile up, one per letter. Debounce the *key*.
- **A query function that ignores the signal is not cancelled.** When the
  key moves on, the library cancels the old fetch only if its function read
  `context.signal`. One that never read it is left to finish: the request runs
  to the end and its answer is cached under the old term. Pass
  `context.signal` to the transport.
- **Trim before comparing.** `'ket '` and `'ket'` are two keys and two requests
  for the same results; the screen trims the term once, where it sets
  `_needle`.
- **Placeholder data is not cached data.** While `isPlaceholderData` is true,
  the rows belong to the *previous* term. Do not act on them as if they
  answered the current one — a "3 results for kett" header would be wrong for
  a moment. This screen dims them instead.
- **The list query seeds the detail entries.** Every search response writes
  each product to its detail entry, which is what makes a tapped result open at
  once. That is useful here, but it means a search returning 200 products
  writes 200 entries; drop the seeding for a search that returns large pages.

## Variations

- **Search on submit.** Drop the debounce and set `_needle` in the field's
  `onSubmitted`. The rest stays.
- **A minimum length.** `enabled: needle.length < 2 ? Enabled.no : Enabled.yes`
  — and the matching message in the empty state.
- **Another call style.** The same options work with `context.query` — the id
  there is a named argument too — with a `QueryBuilder`, whose observer
  already follows a changing key, or with a `QueryController` in a view model
  that owns the debounce; call `setOptions` on it with the new term.

:::note[In React Query]
The same recipe, with `placeholderData: keepPreviousData` and a
`useDebounce` hook. A hook's identity comes from its position in the
component, so a changed key keeps the observer without asking; here the mixin
is told with `id:`.
:::

## See also

- [Disabling queries](../guides/disabling-queries.md#lazy-queries) — lazy
  queries and `Enabled`.
- [Query cancellation](../guides/query-cancellation.md) — what a cancel does
  to the entry, and what the signal adds.
- [Placeholder query data](../guides/placeholder-query-data.md#keeping-the-previous-page)
  — `keepPrevious` and `isPlaceholderData`.
- [Reading queries in widgets](../guides/reading-queries-in-widgets.md) — the
  four call styles and what `id:` does.
