---
title: Infinite queries
sidebar_position: 5
description: pageFn, getNextPageParam, maxPages — and why paging lives on the controller rather than in the result.
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

:::note Two shapes, as with plain queries
A *reader* takes one of two observer shapes, mirroring
[`QueryObserverOptions` and `QuerySelectOptions`](options.md#two-shapes):
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

Those flags **notify** — a direction changing is a change a widget can see,
which was not true of an earlier version and is now a regression test.

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

Worth stating because the showcase got it wrong once and CI caught it: a
scroll listener is **level-triggered**. A view resting near the bottom keeps
receiving notifications — a page landing changes the content dimensions and
sends one — so "am I near the end?" alone asks for the next page again and
again, and how many pages you get depends on how fast the machine is.

Remember where the last request was made and require the view to have moved:

```dart snippet="guides/infinite-queries.md#asked-at guides/infinite-queries.md#on-scroll"
double? _askedAt;

void onScroll() {
  final position = scrollController.position;
  if (position.extentAfter < 400 &&
      position.pixels != _askedAt &&
      feed.hasNextPage &&
      !feed.isFetchingNextPage) {
    _askedAt = position.pixels;
    feed.fetchNextPage().ignore();
  }
}
```

## On screen

`load-more` (append on scroll, and cache survival across navigation),
`max-pages` (both directions with `maxPages: 3`) and `pagination` (the
page-numbered shape, with `PlaceholderData.keepPrevious()`) in the
[showcase](../project/examples.md).
