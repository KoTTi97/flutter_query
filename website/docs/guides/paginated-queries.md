---
title: Paginated queries
description: One page at a time with the page in the key — PlaceholderData.keepPrevious keeps the last page on screen while the next loads.
---

{/* depth: todo */}
{/* demo: pagination */}

# Paginated queries

A page-numbered list is an ordinary query with the page in its key:
`['tasks', 'page', 3]`. Every page is its own cache entry, so going back to
page 2 shows it at once from the cache.

What an ordinary query does badly is the moment between pages: the key
changes, the new key has no data, and the screen drops back to a spinner.

## Keeping the previous page

`PlaceholderData.keepPrevious()` shows the previous key's data while the new
key loads:

- the result is a `QuerySuccess` with the old page's data and
  `isPlaceholderData: true` — dim the list, or disable "next";
- when the new page lands, it replaces the placeholder, and
  `isPlaceholderData` goes back to `false`.

It shows what *this reader* showed before, so the reader must survive the key
change. A builder and a controller do. In the `context.query` and
`QueryMixin` styles, give the read an `id:`:

```dart snippet="guides/reading-queries-in-widgets.md#switched-key"
// With an id, the observer follows the key — so keepPrevious has a previous.
final page = watchQuery(pageQuery(widget.page), id: 'page');
```

Without an `id:`, a new key is a new observer, and it has nothing previous to
show.

## Knowing there is a next page

Return it from the server with the page — a `hasMore` flag, a total — and
disable "next" from the data you have. While a placeholder shows, that data
is the previous page's, so wait for `isPlaceholderData` to be `false` before
enabling "next" again.

## Prefetching the next page

With the current page on screen, `client.query(options).ignore()` for the next
page makes "next" instant; see [prefetching](prefetching.md).

For a list that grows as you scroll rather than a page at a time, see
[infinite queries](infinite-queries.md).
