---
title: Placeholder query data
description: PlaceholderData is shown while the real fetch runs and never written to the cache — a fixed stand-in, a row borrowed from the list, or the previous key's data — flagged isPlaceholderData so the screen can render it as provisional.
---

# Placeholder query data

A device's detail screen opens. The full device — settings, firmware,
schedules — takes a moment to load, but the list the user tapped already
knows its name and room. Showing those straight away, dimmed, reads as
"loading" without a blank screen; showing them as if they were the whole
device would be a lie.

That is placeholder data: what a reader sees while the real fetch runs.
Unlike [initial data](initial-query-data.md), **it is never written to the
cache**. Other readers of the key do not see it, it does not count as
fetched, and the first real result replaces it.

| | |
|---|---|
| `PlaceholderData.value(v)` | this value |
| `PlaceholderData.compute((previousData, previousQuery) => …)` | computed; given the data (before `select`) of the query this reader last showed, and that query. Returning `null` means "none" |
| `const PlaceholderData.keepPrevious()` | the data this reader showed for the previous key |

While it shows, the result is a `QuerySuccess` with `isPlaceholderData:
true`, and the fetch runs as it would with no placeholder. A placeholder
goes through `select` like real data, so a selecting reader receives the
selected placeholder.

It shows only while the query has **no data and no error** — `pending`. Once
real data has landed, or the fetch has failed, there is nothing to stand in
for.

## A fixed stand-in

The simplest placeholder is a value of the right type that the screen can
lay out — a skeleton device:

```dart snippet="guides/placeholder-query-data.md#value"
QueryObserverOptions<Device> deviceQuery(String id) => QueryObserverOptions(
      queryKey: DeviceKeys.detail(id),
      queryFn: (context) => deviceRepository.byId(id, signal: context.signal),
      placeholderData: const PlaceholderData.value(Device.loading),
    );
```

The screen then renders one layout for both, so nothing jumps when the real
device lands, and distinguishes the two by the flag:

```dart snippet="guides/placeholder-query-data.md#render"
Widget deviceTitle(QueryResult<Device> device) => switch (device) {
      QuerySuccess(:final data, isPlaceholderData: true) =>
        Opacity(opacity: 0.5, child: Text(data.name)),
      QuerySuccess(:final data) => Text(data.name),
      QueryPending() => const Text('…'),
      QueryError(:final error) => Text('Could not load: $error'),
    };
```

## A row from the list

`PlaceholderData.compute` can borrow from another cache entry. The row the
user tapped is shown while the detail loads — and, because it is a
placeholder, it is not cached as the detail, so no other screen takes the
summary for the whole device:

```dart snippet="guides/placeholder-query-data.md#from-list"
QueryObserverOptions<Device> devicePreviewedFromList(
  QueryClient client,
  String id,
) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.detail(id),
      queryFn: (context) => deviceRepository.byId(id, signal: context.signal),
      // The list row, shown while the detail loads — and not cached as it.
      placeholderData: PlaceholderData.compute(
        (_, __) => client
            .getQueryData<List<Device>>(DeviceKeys.list)
            ?.where((device) => device.id == id)
            .firstOrNull,
      ),
    );
```

When the list row holds everything the detail shows, seed it as initial data
instead; see [seeding a detail from a list](initial-query-data.md#seeding-a-detail-from-a-list).

### How often it is computed

A reader keeps its placeholder while the `placeholderData` it is handed is
the **identical** instance, and the `select` is the same. A `const`
placeholder — `const PlaceholderData.value(…)`, `const
PlaceholderData.keepPrevious()` — is one instance forever, so it is
provided once. A `PlaceholderData.compute(…)` built in a function, as above,
is a new instance each time the options are built, so the callback runs again
on every rebuild while the detail loads. Keep it cheap — a lookup, as here.
A callback that needs nothing from outside can be a top-level function in a
`const PlaceholderData.compute(…)`, which is computed once like the others.

## Keeping the previous key's data

`keepPrevious` is for a key that changes — a page number, a search term, a
device picked in a side panel. The screen keeps showing the old key's data
until the new key's lands, instead of dropping back to a spinner.

It shows what *this reader* showed before, so the reader must survive the key
change: a builder and a controller keep their observer across a key change;
in the `context.query` and `QueryMixin` styles, give the read an `id:`. The
[paginated queries](paginated-queries.md) guide shows all four.

`keepPrevious` is `PlaceholderData.compute((previousData, _) =>
previousData)` with a name — and `const`.

Try it: in the screen below, card **B** shows the stand-in title with
`isPlaceholderData=true` and `cache=empty` while post 4 loads, then the real
title with `false` — the cache never held the placeholder. In card **C**,
switch between the posts: the previous post stays on screen, flagged, until
the next one arrives.

<LiveDemo feature="initial-and-placeholder" height={640} />

## Placeholder or initial?

| | Initial data | Placeholder data |
|---|---|---|
| Written to the cache | yes | no |
| Seen by other readers | yes | no |
| Subject to `staleTime` | yes — fresh initial data is not refetched | no — the fetch runs as if there were no data |
| `isPlaceholderData` | `false` | `true` |
| Shown after a failed fetch | yes, as `staleData` on the error | no |

Use initial data when it is the real data — a copy from another cache entry
that holds everything. Use placeholder data when it is only something to
show — a skeleton, a summary, the previous page.

:::note[In React Query]
`placeholderData` takes a value or a function `(previousData,
previousQuery) => …`, and `keepPreviousData` is the helper for the previous
key; here `PlaceholderData.value`, `PlaceholderData.compute` and `const
PlaceholderData.keepPrevious()`. A hook keeps its observer across renders by
position; a `context.query` or `watchQuery` read needs an `id:` for
`keepPrevious` to have a previous. See
[differences from TanStack Query](../reference/differences-from-tanstack.md).
:::
