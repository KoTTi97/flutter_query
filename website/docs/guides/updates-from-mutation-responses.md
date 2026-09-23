---
title: Updates from mutation responses
description: Write what a mutation returned straight into the cache — setQueryData, updateQueryData and updateQueriesData, immutable updates, and the one-key-one-type rule.
---

# Updates from mutation responses

Many endpoints answer a write with the object as it now is: a `PUT` returns
the saved settings, a `PATCH` the renamed device. That answer is already the
data the cache should hold — invalidating and fetching it again would be a
second request for something you have in your hand. Write it into the cache
in `onSuccess`, and every reader of that key shows it at once.

## A settings screen

The notification settings of a user, read by a query and saved by a
mutation. The server may clamp or fill in values, so what it answers is the
truth, not what the form sent:

```dart snippet="guides/updates-from-mutation-responses.md#settings"
// lib/data/settings_queries.dart
final QueryKey settingsKey = QueryKey(<Object?>['settings', 'notifications']);

QueryObserverOptions<NotificationSettings> settingsQuery() =>
    QueryObserverOptions(
      queryKey: settingsKey,
      queryFn: (context) => settingsRepository.load(signal: context.signal),
    );

MutationOptions<NotificationSettings, NotificationSettings, void>
    saveSettingsMutation(QueryClient client) => MutationOptions.simple(
          mutationFn: settingsRepository.save,
          // The server answers with what it stored — defaults applied,
          // values clamped. That is the new truth; there is nothing to
          // fetch.
          onSuccess: (saved, _, __) {
            client.setQueryData(settingsKey, saved);
          },
        );
```

The screen reads both and knows nothing about the cache:

```dart snippet="guides/updates-from-mutation-responses.md#settings-screen"
class NotificationSettingsTile extends StatelessWidget {
  const NotificationSettingsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    final settings = context.query(settingsQuery()).dataOrNull;
    final save = context.mutation(saveSettingsMutation(client));
    if (settings == null) return const LinearProgressIndicator();

    return SwitchListTile(
      title: const Text('Push notifications'),
      subtitle: save.value.isError ? const Text('Could not save') : null,
      value: settings.pushEnabled,
      onChanged: save.value.isPending
          ? null
          : (on) => save.mutate(settings.copyWith(pushEnabled: on)),
    );
  }
}
```

A cache write marks the data fresh as of now, so it triggers no refetch of
its own, and every other widget reading `settingsKey` — a badge in the app
bar, a banner on the home screen — rebuilds with the saved value.

## The calls

```dart snippet="guides/updates-from-mutation-responses.md#cache-writes"
client.getQueryData<List<Task>>(tasksKey);
client.setQueryData<Task>(taskKey(id), task);
client.updateQueryData<Task>(
  taskKey(id),
  (previous) => previous?.copyWith(name: 'Renamed'),
);
client.updateQueriesData<Task>(
  (previous) => previous?.copyWith(name: 'Renamed'),
  filters: QueryFilters(queryKey: tasksKey),
);
```

- `getQueryData` reads what is cached, or `null`.
- `setQueryData` takes a **value** and returns what the cache stored, after
  [structural sharing](structural-sharing.md).
- `updateQueryData` takes an updater from the previous value — `null` when
  nothing is cached — and returning `null` from it leaves the cache untouched.
- `updateQueriesData` runs one updater over every query the filters match. It
  runs every updater and checks every result before writing any.

For an infinite query, the typed read is
`getInfiniteQueryData<TPageData, TPageParam>(key)`.

A bare `setQueryData(key, null)` infers `Null` and writes nothing, as
`undefined` does in TanStack Query; write `setQueryData<Task?>(key, null)` to
store a null in a query whose type allows one.

## One answer, several places

A renamed device is in its detail entry and in its room's list. The answer
updates both, the list by building a new one:

```dart snippet="guides/updates-from-mutation-responses.md#rename-everywhere"
MutationOptions<Device, String, void> renameDeviceMutation(
  QueryClient client,
  String id,
) =>
    MutationOptions.simple(
      mutationFn: (String name) => devices.rename(id, name),
      onSuccess: (renamed, _, __) {
        client.setQueryData<Device>(DeviceKeys.detail(id), renamed);
        // Every room list that holds it gets a new list with the new device;
        // `null` leaves the others untouched.
        client.updateQueriesData<List<Device>>(
          (list) => list == null || !list.any((device) => device.id == id)
              ? null
              : <Device>[
                  for (final device in list) device.id == id ? renamed : device,
                ],
          filters: QueryFilters(queryKey: DeviceKeys.lists),
        );
      },
    );
```

`updateQueriesData` over `DeviceKeys.lists` reaches every room's list,
including rooms the device is not in. For those the updater returns `null`,
which leaves the entry alone: writing back an equal list would still date the
entry now and rebuild its readers. When the answer is only part of the
picture — the device moved rooms, a count on another screen changed —
[invalidate](invalidations-from-mutations.md) the rest rather than computing
it on the client.

## Immutability

The cache compares what you write with what it held, and tells readers only
when something changed. So a cache write must be a **new value**, never the
cached one edited in place:

```dart snippet="guides/updates-from-mutation-responses.md#immutability"
// Wrong: the cached list changes under every reader, and none is told.
client.getQueryData<List<Device>>(key)?.add(device);

// Right: a new list. The cache compares it, stores it and notifies.
client.updateQueryData<List<Device>>(
  key,
  (list) => <Device>[...?list, device],
);
```

The first line changes the list every reader holds without telling any of
them, so nothing rebuilds until some unrelated change comes along — and if
the repository handed back a `const` or unmodifiable list, it throws. Build
a new list, a `copyWith` of the model, a new map. The same goes for the value
a query function returns: hand the cache something nobody else will mutate
afterwards.

The `playground` screen does this for real. Open a todo in its editor and
rename it: the `PATCH`'s answer is written into the todo's own entry with
`setQueryData`, so its strip shows no new fetch, and only the list is
invalidated and refetched.

<LiveDemo feature="playground" />

:::danger[One key, one exact type]
A key is bound to the data type it was first used with, and reading it as any
other type throws `QueryDataTypeError` — **related types included**. `int` and
`int?` are two types. So are `List<Task>` and `List<Object?>`.
`getQueryData<T>`, `getQueriesData<T>` and an observer's `TQueryData` all have
to agree with the key's first use.

A **write** is the one place a related type is welcome. `setQueryData` infers
its type from the value (and so do `updateQueryData` and `updateQueriesData`
from the updater), so an entry that already exists takes any value its own
type can hold — a `String` into a `String?` query, a sealed type's variant
into a query of the sealed type — and keeps its type. Name the type when the
write *creates* the entry, as when seeding a key before its query exists:
`setQueryData<List<Task>>(key, [])`.
:::

:::note[In React Query]
`queryClient.setQueryData` in `onSuccess`, as there. The updater form is a
separate method here, `updateQueryData`, and TanStack Query's
`setQueriesData` is `updateQueriesData`. The immutability rule is the same.
:::
