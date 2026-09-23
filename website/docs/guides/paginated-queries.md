---
title: Paginated queries
description: One page at a time with the page number in the key — PlaceholderData.keepPrevious keeps the last page on screen while the next loads, and a prefetch makes Next instant.
---

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

# Paginated queries

An installer's app lists the devices on a site, fifty to a page, with
*Previous* and *Next* underneath. That is an ordinary query with the page
number in its key — `['devices', 'page', 3]` — and every page is its own
cache entry, so going back to page 2 shows it at once from the cache.

What an ordinary query does badly is the moment between pages. The key
changes, the new key has no data, and the list drops back to a spinner, the
buttons jump, and the scroll position is gone. The fix is one option.

## Keeping the previous page

`PlaceholderData.keepPrevious()` shows the previous key's data while the new
key loads:

```dart snippet="guides/paginated-queries.md#page-query"
QueryObserverOptions<DevicePage> devicePageQuery(int page) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.page(page),
      queryFn: (context) => deviceRepository.page(page, signal: context.signal),
      // `const`: one value on every build, so the options compare unchanged.
      placeholderData: const PlaceholderData.keepPrevious(),
      staleTime: const StaleTime.duration(Duration(seconds: 30)),
    );
```

While the next page loads, the result is a `QuerySuccess` carrying the
**previous** page's data and `isPlaceholderData: true`. When the new page
lands it replaces the placeholder, and `isPlaceholderData` goes back to
`false`. Nothing is written to the cache: the placeholder is only what this
reader shows in the meantime; see [placeholder data](placeholder-query-data.md).

That gives the screen two things to do with the flag — dim the rows, so the
user sees they are about to change, and hold *Next* until the page it would
skip from has actually arrived:

```dart snippet="guides/paginated-queries.md#page-view"
/// The rows and the two buttons, from whichever read the screen uses.
Widget devicePageView(
  QueryResult<DevicePage> result, {
  required int page,
  required ValueChanged<int> goTo,
}) =>
    switch (result) {
      QueryPending() => const Center(child: CircularProgressIndicator()),
      QueryError(:final error) => Center(child: Text('No devices: $error')),
      QuerySuccess(:final data, :final isPlaceholderData) => Column(
          children: <Widget>[
            Expanded(
              // The previous page, dimmed, while this one loads.
              child: Opacity(
                opacity: isPlaceholderData ? 0.5 : 1,
                child: ListView(
                  children: <Widget>[
                    for (final device in data.devices) DeviceTile(device),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                TextButton(
                  onPressed: page == 0 ? null : () => goTo(page - 1),
                  child: const Text('Previous'),
                ),
                Text('Page ${page + 1}'),
                TextButton(
                  // Not while a placeholder shows: `hasMore` is the old page's.
                  onPressed: isPlaceholderData || !data.hasMore
                      ? null
                      : () => goTo(page + 1),
                  child: const Text('Next'),
                ),
              ],
            ),
          ],
        ),
    };
```

## The reader has to survive the key change

`keepPrevious` shows what *this reader* showed before. So the read must be
the same observer on page 3 as it was on page 2, with a new key. How that is
spelled depends on the call style; all four do it:

<Tabs groupId="call-style">
<TabItem value="context-query" label="context.query">

A read's `id:` names it, so a new key is the same read moved rather than a
new one:

```dart snippet="guides/paginated-queries.md#pager-context-query"
class _DevicePagerState extends State<DevicePager> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    // The id keeps one observer across pages, so keepPrevious has a previous.
    final result = context.query(devicePageQuery(_page), id: 'devices');
    return devicePageView(
      result,
      page: _page,
      goTo: (page) => setState(() => _page = page),
    );
  }
}
```

</TabItem>
<TabItem value="query-builder" label="QueryBuilder">

A builder keeps its observer when its options change:

```dart snippet="guides/paginated-queries.md#pager-builder"
class _DevicePagerBuilderState extends State<DevicePagerBuilder> {
  int _page = 0;

  @override
  Widget build(BuildContext context) => QueryBuilder(
        // The builder keeps its observer when the key changes.
        options: devicePageQuery(_page),
        builder: (context, result) => devicePageView(
          result,
          page: _page,
          goTo: (page) => setState(() => _page = page),
        ),
      );
}
```

</TabItem>
<TabItem value="query-mixin" label="QueryMixin">

As with `context.query`, the `id:` keeps one observer across pages:

```dart snippet="guides/paginated-queries.md#pager-mixin"
class _DevicePagerMixinState extends State<DevicePagerMixin> with QueryMixin {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    // The id keeps one observer across pages, so keepPrevious has a previous.
    final result = watchQuery(devicePageQuery(_page), id: 'devices');
    return devicePageView(
      result,
      page: _page,
      goTo: (page) => setState(() => _page = page),
    );
  }
}
```

</TabItem>
<TabItem value="query-controller" label="QueryController">

A controller is one observer for its lifetime; `setOptions` moves it to the
new page:

```dart snippet="guides/paginated-queries.md#pager-controller"
class _DevicePagerControllerState extends State<DevicePagerController> {
  int _page = 0;
  late final QueryController<DevicePage, DevicePage> _devices =
      QueryController.create(
    QueryClientProvider.read(context),
    devicePageQuery(_page),
  );

  void _goTo(int page) {
    setState(() => _page = page);
    // The same observer, a new key: keepPrevious has a previous.
    _devices.setOptions(devicePageQuery(page));
  }

  @override
  void dispose() {
    _devices.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: _devices,
        builder: (context, result, _) =>
            devicePageView(result, page: _page, goTo: _goTo),
      );
}
```

</TabItem>
</Tabs>

Without the `id:`, a new key is a new observer, and it has nothing previous
to show: the page falls back to `QueryPending` as if there were no
placeholder at all. See
[reading queries in widgets](reading-queries-in-widgets.md) for how reads
are identified.

## Knowing there is a next page

A query knows nothing about pages; the server does. Return what the screen
needs with the page — a `hasMore` flag, a total, a next cursor — and decide
from the data you have. While a placeholder shows, that data is the
**previous** page's, which is why *Next* above stays disabled until
`isPlaceholderData` is `false`: otherwise a fast double tap skips a page on
the strength of the page before it.

## Prefetching the next page

With a page on screen, the user will most likely want the next one. Fetch it
before they ask, and *Next* shows it instantly — no placeholder, no request:

```dart snippet="guides/paginated-queries.md#prefetch-next"
/// Call from `build` with the page on screen. Starts the next page's fetch
/// after the frame — a fetch fires cache events, and the widgets listening
/// to them are in the middle of building — and only once per page.
void prefetchNextPage(
  BuildContext context,
  QueryResult<DevicePage> result, {
  required int page,
  required Set<int> prefetched,
}) {
  if (result case QuerySuccess(:final data, isPlaceholderData: false)
      when data.hasMore && prefetched.add(page + 1)) {
    final client = QueryClientProvider.read(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      client.query(devicePageQuery(page + 1)).ignore();
    });
  }
}
```

Call it from the build that shows the page, with a `Set<int>` kept in the
widget's state. Three details make it work:

- **After the frame.** Starting a fetch fires cache events, and the widgets
  listening to them may be building right now; the post-frame callback waits
  for the frame to finish.
- **Once per page.** `prefetched.add` is `false` the second time, so a
  rebuild does not ask again.
- **A `staleTime`.** The prefetched page is fresh for thirty seconds, so the
  reader that moves to it finds it fresh and does not fetch again. With the
  default `staleTime` of zero it would be shown at once — and refetched
  straight away. See [prefetching](prefetching.md).

Try it: in the screen below, press *Next page* a few times. Each page is
there at once, because the one after the page on screen was prefetched as
soon as that page landed; press twice in quick succession, before the
prefetch answers, and the rows stay on screen with `isPlaceholderData=true`
until the new page replaces them. *Previous page* is instant too, from the
cache.

<LiveDemo feature="pagination" />

## Things to know

- **Every page is a cache entry.** Pages nobody reads are collected after
  `gcTime` — five minutes by default — like any query. A user who pages
  through two hundred pages holds at most five minutes' worth.
- **Invalidating the list invalidates every page.** With keys under one
  prefix, `invalidateQueries(filters: QueryFilters(queryKey: DeviceKeys.all))`
  marks every page stale; only the one on screen is refetched, the rest when
  they are next shown. See [query invalidation](query-invalidation.md).
- **Rows moving between pages.** Offset paging over data that changes can
  show a row twice or skip one when something is added or deleted between
  two page loads. That is the server's paging scheme, not the cache's; a
  cursor avoids it.
- **A list that grows as you scroll** rather than a page at a time is an
  [infinite query](infinite-queries.md).

:::note[In React Query]
`placeholderData: keepPreviousData` (the successor to v4's
`keepPreviousData: true`) is `PlaceholderData.keepPrevious()` here, with the
same `isPlaceholderData` flag. A hook keeps its observer across renders by
position; here a `context.query` or `watchQuery` read needs an `id:` to be
the same read on a new key. See
[differences from TanStack Query](../reference/differences-from-tanstack.md).
:::
