---
title: Invalidations from mutations
description: Invalidate the queries a write affected from its onSuccess or onSettled — which keys, which callback, and what returning the future does to the mutation's state.
---

# Invalidations from mutations

A write makes some cached reads wrong. A device was removed, so every list
that showed it is out of date; a task was added, so the task list is short
by one. The simplest way to make them right is to invalidate them once the
write has landed, and let the ones on screen refetch:

```dart snippet="guides/mutations.md#read"
final add = context.mutation(
  MutationOptions.simple(
    mutationFn: api.addTask,
    onSuccess: (_, __, ___) => client.invalidateQueries(
      filters: QueryFilters(queryKey: tasksKey),
    ),
  ),
);

// … add.value is the MutationResult; add.mutate(vars) starts it.
```

That is the whole pattern. The rest of this page is about the three choices
inside it: which keys, which callback, and whether the mutation waits.

## Which keys

Invalidate the most general key the write could have affected. Adding a
task changes every task list, so `['tasks']`; renaming one changes its
detail and every list it appears in, so `['tasks']` again. A key factory —
see [query invalidation](query-invalidation.md#keys-decide-what-an-invalidation-reaches)
— turns this into a sentence about the domain.

Sometimes a write makes one entry *meaningless* rather than stale. After a
delete, refetching the device's detail would only fetch a 404; remove it
instead, and invalidate the lists:

```dart snippet="guides/invalidations-from-mutations.md#remove-device"
// lib/data/device_mutations.dart
MutationOptions<void, String, void> removeDeviceMutation(QueryClient client) =>
    MutationOptions.simple(
      mutationFn: devices.remove,
      onSuccess: (_, id, __) {
        // The device is gone: drop its detail rather than refetch a 404 …
        client.removeQueries(
          filters: QueryFilters(queryKey: DeviceKeys.detail(id)),
        );
        // … and refetch every room list that may have shown it.
        return client.invalidateQueries(
          filters: QueryFilters(queryKey: DeviceKeys.lists),
        );
      },
    );
```

`removeQueries` is for keys nobody is watching: a reader still attached keeps
showing what it had. Pop the detail screen before the delete starts, or, if
it has to stay up, invalidate its key instead and let it show the error.

When a write touches two unrelated keys, invalidate both — in parallel:

```dart snippet="guides/invalidations-from-mutations.md#move-device"
MutationOptions<Device, String, void> moveDeviceMutation(
  QueryClient client,
  Device device,
) =>
    MutationOptions.simple(
      mutationFn: (String toRoom) => devices.move(device.id, toRoom),
      // Two lists changed. Both refetches run at once, and the mutation
      // settles when both have landed.
      onSuccess: (moved, toRoom, _) => Future.wait(<Future<void>>[
        client.invalidateQueries(
          filters: QueryFilters(queryKey: DeviceKeys.list(room: device.room)),
        ),
        client.invalidateQueries(
          filters: QueryFilters(queryKey: DeviceKeys.list(room: toRoom)),
        ),
      ]),
    );
```

## `onSuccess` or `onSettled`

- In **`onSuccess`**, only a write that went through refetches. That is right
  when a failed write provably changed nothing.
- In **`onSettled`**, a failed write refetches too. Use it after an
  [optimistic update](optimistic-updates.md), which has to replace its guess
  with the server's answer either way, and whenever a failure may have
  half-happened on the server — a timeout after the request arrived, a
  cancelled upload.

## Returning the future, or not

A callback that **returns** the `invalidateQueries` future keeps the mutation
`pending` until the refetch has landed. The button that shows a spinner while
the mutation runs keeps it until the list on screen is actually up to date,
and the new row never flickers in a moment after the spinner has gone. Most
of the time that is what you want; when the refetch is slow, say so on
screen, or it looks as if the write were slow.

A callback that returns nothing — a block body, with `.ignore()` on the
future — lets the mutation succeed as soon as the server has answered, and
the refetch runs behind it:

```dart snippet="guides/invalidations-from-mutations.md#do-not-wait"
MutationOptions<Device, String, void> renameDeviceQuickly(
  QueryClient client,
  String id,
) =>
    MutationOptions.simple(
      mutationFn: (String name) => devices.rename(id, name),
      // A block body that returns nothing: the mutation succeeds as soon as
      // the server has answered, and the lists refresh behind it.
      onSuccess: (_, __, ___) {
        client
            .invalidateQueries(
              filters: QueryFilters(queryKey: DeviceKeys.all),
            )
            .ignore();
      },
    );
```

Either way the invalidation happens. What you choose is which moment the UI
calls "done".

Press *Increment (mutate)* on the `mutations` screen: the mutation goes
`pending`, then `success`, and the counter query its `onSuccess` invalidates
refetches to the new value.

<LiveDemo feature="mutations" />

## Take the client in `build`

The callbacks may run after the widget that started the mutation is gone —
the user saved and navigated back. Close over the `QueryClient`, taken with
`QueryClientProvider.of(context)` in `build` and passed into the options
function, never over the `BuildContext`; see
[mutations](mutations.md#a-mutation-outlives-its-widget).

## Every mutation, one rule

When every write in an app follows the same rule — "invalidate what the
mutation names" — it can live in one place, the mutation cache's `onSuccess`,
with each mutation naming its keys in `meta`. See [global
callbacks](global-callbacks.md#invalidating-after-every-mutation).

When the server answers the write with the new data, you can put that into
the cache instead of refetching; see [updates from mutation
responses](updates-from-mutation-responses.md).

:::note[In React Query]
The same pattern: `queryClient.invalidateQueries` in `useMutation`'s
`onSuccess` or `onSettled`, and returning the promise to keep the mutation
pending. A Dart callback returns the `Future` the same way.
:::
