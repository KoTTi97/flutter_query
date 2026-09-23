---
title: Infinite queries
description: A list of pages behind one key — pageFn, getNextPageParam and maxPages, why paging lives on the controller, and a scrolling list with load-on-scroll and pull-to-refresh.
---

# Infinite queries

A query whose data is a *list of pages*. Same four call styles; the difference
is that the function is `pageFn` rather than `queryFn`, and it receives a typed
page context.

```dart snippet="guides/infinite-queries.md#options"
InfiniteQueryObserverOptions<List<Post>, int> feedQuery() =>
    InfiniteQueryObserverOptions<List<Post>, int>(
      queryKey: QueryKey(<Object?>['feed']),
      pageFn: (context) => api.feed(cursor: context.pageParam),
      initialPageParam: 0,
      getNextPageParam: (page, pages, pageParam, pageParams) =>
          page.isEmpty ? null : pageParam + page.length,
    );
```

:::note[Two shapes, as with plain queries]
A *reader* takes one of two observer shapes, mirroring
[`QueryObserverOptions` and `QuerySelectOptions`](query-options.md#two-shapes):
`InfiniteQueryObserverOptions<TPageData, TPageParam>`, above, has no
`select` and its data is the whole `InfiniteData<TPageData, TPageParam>`;
`InfiniteQuerySelectOptions<TPageData, TPageParam, TData>` has a required
`select` over it, the place to flatten pages into one list. The infinite entry
points — `InfiniteQueryBuilder`, `context.infiniteQuery`,
`watchInfiniteQuery`, `InfiniteQueryController` — take either and read every
type argument off the options, so `InfiniteQueryBuilder(options: feedQuery(),
…)` names none. `InfiniteQueryOptions<TPageData, TPageParam>` is what
`QueryClient.query` takes, where there is no observer and so no `select`.
:::

- **`initialPageParam`** is where the first page starts.
- **`getNextPageParam`** returns where the next page starts, or `null` when
  there is none — that `null` is what `hasNextPage` is derived from.
- **`getPreviousPageParam`** is the same for the other direction; give it only
  if you page backwards.
- **`maxPages`** caps how many pages are kept. Pages are dropped from the far
  end, and a refetch then touches exactly `maxPages` pages rather than every
  page ever loaded.
- **`context.direction`** on the page context says which way this call is
  going, for a backend whose two directions differ.

## Paging lives on the controller

Every style hands back a controller for an infinite query, because the paging
surface is not part of the sealed result — the result keeps one shape whether
a query pages or not.

```dart snippet="guides/infinite-queries.md#read"
final feed = context.infiniteQuery(feedQuery());
// or watchInfiniteQuery(...), InfiniteQueryBuilder(...), InfiniteQueryController

final posts = feed.value.dataOrNull?.flatten<Post>() ?? const <Post>[];
if (feed.hasNextPage && !feed.isFetchingNextPage) {
  feed.fetchNextPage().ignore();
}
```

On the controller: `hasNextPage`, `hasPreviousPage`, `fetchNextPage()`,
`fetchPreviousPage()`, `isFetchingNextPage`, `isFetchingPreviousPage`,
`isFetchNextPageError`, `isFetchPreviousPageError`, `isRefetching`,
`isRefetchError`.

Those flags **notify**: a direction starting or finishing is a change a
widget can see, and it rebuilds.

## The data

`InfiniteData<TPageData, TPageParam>` holds `pages` and `pageParams`, the same
length and in the same order: `pages[i]` was fetched with `pageParams[i]`.

For the common case where a page is itself a list:

```dart snippet="guides/infinite-queries.md#pages"
final pages = feed.value.dataOrNull?.pages ?? const <List<Post>>[];
```

Pages are structurally shared **page by page**, so a refetch that returns an
unchanged page keeps the same instances and the rows built from it do not
rebuild.

From the client, the typed read is `getInfiniteQueryData<TPageData,
TPageParam>(key)` rather than `getQueryData` with an `InfiniteData` type
argument.

## Scroll-triggered loading

A scroll listener is **level-triggered**. A view resting near the bottom keeps
receiving notifications — a page landing changes the content dimensions and
sends one — so "am I near the end?" alone asks for the next page again and
again, and how many pages you get depends on how fast the machine is.

Remember how long the list was when the last page was asked for, and ask
again only once it has grown. The scroll position is the wrong thing to
remember: one gesture keeps moving, so its next notification looks like a
new arrival at the end. The data is wrong too: a page can land and a
notification arrive before its rows are laid out, still reading as the end.
`maxScrollExtent` changes only when the new rows are laid out — the moment
the list really became longer:

```dart snippet="guides/infinite-queries.md#asked-at guides/infinite-queries.md#on-scroll"
double? _askedAtExtent;

void onScroll() {
  final position = scrollController.position;
  if (position.extentAfter < 400 &&
      position.maxScrollExtent != _askedAtExtent &&
      feed.hasNextPage &&
      !feed.isFetchingNextPage) {
    _askedAtExtent = position.maxScrollExtent;
    feed.fetchNextPage().ignore();
  }
}
```

## A device's activity log, start to end

A device's detail screen ends with its activity log: switched on, switched
off, firmware updated — thousands of entries over its life, fetched twenty
at a time, newest first. The server answers each page with the offset of the
next one, or none at the end:

```dart snippet="guides/infinite-queries.md#activity-query"
InfiniteQueryObserverOptions<ActivityPage, int> activityQuery(String id) =>
    InfiniteQueryObserverOptions<ActivityPage, int>(
      queryKey: DeviceKeys.activity(id),
      pageFn: (context) => deviceRepository.activity(
        id,
        offset: context.pageParam,
        signal: context.signal,
      ),
      initialPageParam: 0,
      getNextPageParam: (page, pages, offset, offsets) => page.nextOffset,
    );
```

The screen puts the pieces together — the scroll trigger from above, a
footer that says what the end of the list is doing, and pull-to-refresh.
Here it is with a controller; `context.infiniteQuery`, `watchInfiniteQuery`
and `InfiniteQueryBuilder` hand back the same controller surface, so the
list, the footer and the scroll trigger read the same with any of them:

```dart snippet="guides/infinite-queries.md#activity-log"
class _ActivityLogState extends State<ActivityLog> {
  late final InfiniteQueryController<ActivityPage, int,
      InfiniteData<ActivityPage, int>> _log = InfiniteQueryController(
    QueryClientProvider.read(context),
    activityQuery(widget.deviceId),
  );
  final ScrollController _scroll = ScrollController();
  double? _askedAtExtent;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    final position = _scroll.position;
    if (position.extentAfter < 400 &&
        position.maxScrollExtent != _askedAtExtent &&
        _log.hasNextPage &&
        !_log.isFetchingNextPage) {
      _askedAtExtent = position.maxScrollExtent;
      _log.fetchNextPage().ignore();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _log.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _log,
        builder: (context, _) {
          final result = _log.value;
          if (result is QueryPending) {
            return const Center(child: CircularProgressIndicator());
          }
          if (result case QueryError(hasStaleData: false, :final error)) {
            return Center(child: Text('No activity: $error'));
          }
          final entries = <ActivityEntry>[
            for (final page in result.dataOrNull?.pages ?? <ActivityPage>[])
              ...page.entries,
          ];
          return RefreshIndicator(
            // Refetches every page held, first to last.
            onRefresh: _log.refetch,
            child: ListView.builder(
              controller: _scroll,
              // Pull-to-refresh needs a list that scrolls when it is short.
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: entries.length + 1,
              // A widget per row: the row reads nothing through this context.
              itemBuilder: (context, index) => index < entries.length
                  ? ActivityTile(entries[index])
                  : _footer(),
            ),
          );
        },
      );

  Widget _footer() {
    if (_log.isFetchingNextPage) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_log.isFetchNextPageError) {
      return TextButton(
        onPressed: _log.fetchNextPage,
        child: const Text('Could not load older entries. Try again'),
      );
    }
    return _log.hasNextPage
        ? const SizedBox(height: 64)
        : const ListTile(title: Text('No older activity'));
  }
}
```

What each part is for:

- **The footer row** is one more item than there are entries. It shows a
  spinner while the next page loads, a retry button when that load failed
  (`isFetchNextPageError` — the entries already shown stay), and the end of
  the log when `hasNextPage` is `false`.
- **`RefreshIndicator`** calls `refetch`, which refetches every page held,
  first to last, each from the page parameter the previous one returns — so a
  new entry at the top shifts the pages correctly instead of leaving a gap or
  a duplicate. The indicator spins until the returned future completes.
- **`AlwaysScrollableScrollPhysics`** lets a log shorter than the screen be
  pulled down at all.
- **A widget per row.** `ActivityTile` receives its entry; it reads nothing.
  A row that needs a query of its own — the user who triggered the entry,
  say — is its own widget that reads it in its own `build`. A read through
  the `itemBuilder`'s `context` is refused in debug builds, because that
  context belongs to the list, and every row ever built would pile onto it.

Pulling to refresh a log of fifty pages makes fifty requests. To start over
with one page instead, reset the query:
`client.resetQueries(filters: QueryFilters(queryKey: DeviceKeys.activity(id)))`
drops the pages it held and fetches the first one again. `maxPages` bounds
the same cost ahead of time.

Try it: scroll to the bottom of the list below, or press *Load more*, and
`pages=` grows by one each time until *Nothing more to load* shows. Press
*Go to about* and then *Back to list*: the rows are back at once, from the
cache.

<LiveDemo feature="load-more" />

And with `maxPages: 3`, starting in the middle of the data: press *Load
next* twice and `pageParams=` reads `30,40,50`; a third time slides the
window to `40,50,60` — still three pages, the first one dropped. *Load
previous* slides it back, fetching `30` again, and *Refetch* requests exactly
the three pages held.

<LiveDemo feature="max-pages" />

## Related

- [Scroll restoration](scroll-restoration.md) — why a list comes back where
  it was.
- [Paginated queries](paginated-queries.md) — the page-numbered shape, one
  page at a time.

:::note[In React Query]
`useInfiniteQuery` returns `fetchNextPage`, `hasNextPage` and the
direction flags on its result; here they live on the controller every call
style hands back, and the result stays the same sealed type a plain query
has. `queryFn` for pages is `pageFn`, with a typed page context. See
[differences from TanStack Query](../reference/differences-from-tanstack.md).
:::
