---
title: Initial query data
description: InitialData seeds the cache with data the app already has — a bundled catalogue, a row from the list screen — and initialDataUpdatedAt says how old it is, so staleTime decides whether to fetch.
---

# Initial query data

The user taps a light in the device list. The detail screen is about to
fetch `/devices/42` — but the list screen fetched that device a second ago,
name, room and state included. Showing a spinner for data the app is already
holding is a waste of the user's time.

When the app already has the data a query will fetch, hand it over as
**initial data**. The query starts as a `QuerySuccess` with it, and no
spinner is shown.

**`InitialData` is written to the cache.** It is indistinguishable from a
fetch result: every reader of the key sees it, it is shared structurally
with what the fetch later returns, and it ages under `staleTime` like
fetched data. If it should not be believed — a skeleton, a partial object —
you want [placeholder data](placeholder-query-data.md) instead.

| | |
|---|---|
| `InitialData.value(v)` | this value |
| `InitialData.compute(() => …)` | computed; returning `null` means "none". `InitialData.value(null)` is a value *of* `null` |
| `initialDataUpdatedAt: DateTime?` | how old it is; `null` means now |
| `initialDataUpdatedAtCompute: () => DateTime?` | the lazy form, evaluated only when the data is actually seeded. Give one form or the other, never both |

Initial data is only a seed. It is used when the cache entry has no data —
an entry that already holds data, fetched or seeded, keeps it.

## Data that ships with the app

The "add a device" picker lists every device type the gateway supports. The
list changes a few times a year, so the app ships with a copy and asks the
server for the current one in the background:

```dart snippet="guides/initial-query-data.md#bundled"
// The catalogue ships with the app, so the "add a device" picker never
// shows a spinner. Dated when it was bundled, it is older than a day on
// most phones, and the server's copy replaces it in the background.
QueryObserverOptions<List<DeviceType>> deviceTypesQuery() =>
    QueryObserverOptions(
      queryKey: QueryKey(<Object?>['device-types']),
      queryFn: (context) => deviceRepository.types(signal: context.signal),
      staleTime: const StaleTime.duration(Duration(days: 1)),
      initialData: const InitialData.value(bundledDeviceTypes),
      initialDataUpdatedAt: bundledDeviceTypesDate,
    );
```

The date is what makes this right. Without it, the bundled copy would count
as fetched *now*, stay fresh for a day, and the picker would show last
release's catalogue until tomorrow. Dated when it was bundled, it is older
than the `staleTime` on any phone that installed the app more than a day
after the build — so the picker shows it at once and refetches behind it.

## Seeding a detail from a list

`InitialData.compute` can look in another cache entry. The task list's row
becomes the task detail's first state:

```dart snippet="guides/initial-query-data.md#seed-from-list"
QueryObserverOptions<Task> taskSeededFromList(QueryClient client, String id) =>
    QueryObserverOptions(
      queryKey: taskKey(id),
      queryFn: (context) => api.getTask(id, signal: context.signal),
      initialData: InitialData.compute(
        () => client
            .getQueryData<List<Task>>(tasksKey)
            ?.where((task) => task.id == id)
            .firstOrNull,
      ),
      // As old as the list it came from.
      initialDataUpdatedAtCompute: () => client.queryCache
          .find(filters: QueryFilters(queryKey: tasksKey))
          ?.state
          .dataUpdatedAt,
    );
```

Giving the list's `dataUpdatedAt` as the seed's age means the detail is as
stale as the list it came from, and refetches on the same schedule. The
lazy form is asked only when a seed is actually written — not on every
rebuild.

Only seed a detail from a list when the row holds everything the detail
screen shows. A list endpoint that returns a summary — a name and a room,
but not the device's settings — seeds a detail with gaps that the screen
then renders as real. That is a placeholder, not initial data.

### Only when the list is recent

A device's state changes on its own — a shutter moves, a light is switched
at the wall. A list fetched ten minutes ago is not the device's current
state, and showing it as such, even for the length of a refetch, flickers
between the wrong state and the right one. Seed only from a recent list:

```dart snippet="guides/initial-query-data.md#only-if-recent"
QueryObserverOptions<Device> deviceSeededIfRecent(
  QueryClient client,
  String id,
) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.detail(id),
      queryFn: (context) => deviceRepository.byId(id, signal: context.signal),
      initialData: InitialData.compute(() {
        final list = client.getQueryState<List<Device>>(DeviceKeys.list);
        final updatedAt = list?.dataUpdatedAt;
        // An old list is not worth showing as the device's current state.
        if (updatedAt == null ||
            DateTime.now().difference(updatedAt) >
                const Duration(seconds: 10)) {
          return null;
        }
        return list?.data?.where((device) => device.id == id).firstOrNull;
      }),
    );
```

Returning `null` means "no seed": the detail loads like any query.

`InitialData.compute` is asked again on every options update and every
fetch until the entry holds data, so a seed that appears later — the list
lands while the detail is still loading — still lands. Keep it cheap.

## With `staleTime`

With the default `staleTime` of zero, initial data is stale at once, so it is
shown *and* refetched behind. With a `staleTime`, initial data younger than
it is not refetched — which is why its age matters:

| Seed dated | `staleTime` | On mount |
|---|---|---|
| now (no date given) | zero | shown, refetched at once |
| now (no date given) | one minute | shown, no request for a minute |
| the list's `dataUpdatedAt`, 40 s ago | one minute | shown, refetched when the list would be |
| bundled, weeks ago | one day | shown, refetched at once |

Try it: in the screen below, open a post from card **A**. Its title shows at
once from the list, and the strip's `fetches=` stays `0` — the seed is
younger than the thirty-second `staleTime`. Turn on *Treat initial data as
old* and open another: the title still shows at once, and one fetch follows.
Card **D** does the same with the lazy date: `fresh` fetches nothing,
`backdated` refetches straight away, and `computeCalls=` stays at `1` through
every rebuild.

<LiveDemo feature="initial-and-placeholder" height={640} />

## Other ways to have data before the screen opens

Initial data lives in the options, so the query that needs it says where it
comes from. The alternatives write to the cache from outside:
[prefetching](prefetching.md) fetches ahead of a navigation, and
[updates from mutation responses](updates-from-mutation-responses.md) write
what a write returned. Both are better when the data is not at hand at the
moment the query is created.

:::note[In React Query]
`initialData` takes a value or a function, and `initialDataUpdatedAt` a
number of milliseconds or a function; here `InitialData.value` or
`InitialData.compute`, with `initialDataUpdatedAt` a `DateTime` and
`initialDataUpdatedAtCompute` its lazy form, as separate fields. See
[differences from TanStack Query](../reference/differences-from-tanstack.md).
:::
