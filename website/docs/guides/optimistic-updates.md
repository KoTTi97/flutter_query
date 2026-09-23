---
title: Optimistic updates
description: Show a write before the server confirms it — drawn from the pending mutation's variables, or patched into the cache in onMutate and rolled back on error.
---

# Optimistic updates

A user adds a device and waits half a second for the list to show it; flips
a switch and watches it spring back until the server agrees. Most writes
succeed, so the app can show the result *before* the server has confirmed
it, and put things right in the rare case it fails. That is an optimistic
update, and there are two ways to do one:

- **Via the UI** — draw the pending write from the mutation's `variables`,
  next to the cached data. The cache is never touched, so there is nothing to
  roll back.
- **Via the cache** — patch the cached data in `onMutate`, before the request
  goes out, and restore it if the request fails. Every reader of the key sees
  the write.

## Via the UI

While a mutation is pending, its result carries the variables it was started
with. A widget that reads both the list and the mutation can draw the pending
row itself:

```dart snippet="guides/optimistic-updates.md#add-device"
// lib/data/device_mutations.dart
QueryKey addDeviceKey(String room) => QueryKey(<Object?>['add-device', room]);

MutationOptions<Device, String, void> addDeviceMutation(
  QueryClient client,
  String room,
) =>
    MutationOptions.simple(
      mutationKey: addDeviceKey(room),
      mutationFn: (String name) => devices.add(name: name, room: room),
      // Returned, so the mutation stays pending — and its greyed row on
      // screen — until the list has refetched with the real row in it.
      onSettled: (_, __, ___, ____, _____) => client.invalidateQueries(
        filters: QueryFilters(queryKey: DeviceKeys.list(room: room)),
      ),
    );
```

```dart snippet="guides/optimistic-updates.md#via-ui"
class RoomDeviceList extends StatelessWidget {
  const RoomDeviceList({super.key, required this.room});

  final String room;

  @override
  Widget build(BuildContext context) {
    final client = QueryClientProvider.of(context);
    final list = context.query(roomDevicesQuery(room));
    final add = context.mutation(addDeviceMutation(client, room));

    return ListView(
      children: <Widget>[
        for (final device in list.dataOrNull ?? const <Device>[])
          DeviceTile(device: device),
        // The write in flight, drawn from what it was called with.
        if (add.value case MutationPending(:final variables?))
          Opacity(opacity: 0.5, child: ListTile(title: Text(variables))),
        // A failed write keeps its variables: offer to send them again.
        if (add.value case MutationError(:final variables?))
          ListTile(
            title: Text(variables),
            subtitle: const Text('Not saved'),
            trailing: TextButton(
              onPressed: () => add.mutate(variables),
              child: const Text('Retry'),
            ),
          ),
        AddDeviceField(onSubmit: add.mutate),
      ],
    );
  }
}
```

The greyed row is the mutation, not the data. When the write fails, the
result turns into `MutationError` with the variables still on it, so the row
becomes an error with a *Retry* that sends the same name again — no retyping.
When it succeeds, `onSettled` invalidates the list, and because it
**returns** that future, the mutation stays pending until the refetched list
contains the real row: the greyed row and the real one never show together,
and there is no gap between them.

Every call style hands you the same `MutationResult`, so this works the same
with `MutationBuilder`, `watchMutation` or a `MutationController`'s `value`;
see the [four call styles for a mutation](mutations.md#in-an-app).

### When the list and the form are different widgets

The pending row has to be drawn where the list is, and the mutation is often
started somewhere else — a dialog, a bottom sheet. Give the mutation a
`mutationKey`, and read every pending mutation under it from the cache with
a [`MutationStateController`](mutation-state.md):

```dart snippet="guides/optimistic-updates.md#elsewhere"
class _PendingDevicesState extends State<PendingDevices> {
  // Every pending add for this room, wherever in the app it was started.
  late final MutationStateController<String> _adding =
      MutationStateController.typed(
    QueryClientProvider.read(context),
    filters: MutationFilters(
      mutationKey: addDeviceKey(widget.room),
      status: MutationStatus.pending,
    ),
    select: (Mutation<Object?, String, Object?> mutation) =>
        mutation.state.variables!,
  );

  @override
  void dispose() {
    _adding.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<String>>(
        valueListenable: _adding,
        builder: (context, names, _) => Column(
          children: <Widget>[
            for (final name in names)
              Opacity(opacity: 0.5, child: ListTile(title: Text(name))),
          ],
        ),
      );
}
```

`typed` hands the selection the mutation with its variables typed, so no
cast is needed; the filter's key picks this room's adds and nothing else.

## Via the cache

When several widgets show the data — a list, a count in the app bar, a room
overview — patching the cache shows the write everywhere at once. The work
moves into the mutation's callbacks:

1. **`onMutate`** runs before the request. It cancels any fetch of the key in
   flight, patches the cache, and returns what the rollback will need.
2. **`onError`** receives that value as its last argument and puts the cache
   back.
3. **`onSettled`** invalidates the key, so the server has the last word
   whether the write succeeded or not.

### Adding to a list

```dart snippet="guides/optimistic-updates.md#via-cache"
int _temporaryIds = 0;

MutationOptions<Device, String, String> addDeviceOptimistically(
  QueryClient client,
  String room,
) {
  final key = DeviceKeys.list(room: room);
  return MutationOptions<Device, String, String>(
    mutationFn: (name) => devices.add(name: name, room: room),
    onMutate: (name) async {
      // A refetch already in flight would land after the patch and undo it.
      await client.cancelQueries(filters: QueryFilters(queryKey: key));
      // Until the server names the device, a temporary id marks the row.
      final temporaryId = 'pending-${_temporaryIds++}';
      client.updateQueryData<List<Device>>(
        key,
        (list) => <Device>[
          ...?list,
          Device(id: temporaryId, name: name, room: room),
        ],
      );
      return temporaryId; // what onSuccess and onError need to find the row
    },
    onSuccess: (device, _, temporaryId) {
      // Swap in the server's device at once; the refetch below confirms it.
      client.updateQueryData<List<Device>>(
        key,
        (list) => list == null
            ? null
            : <Device>[
                for (final row in list) row.id == temporaryId ? device : row,
              ],
      );
    },
    onError: (error, stackTrace, name, temporaryId) {
      // Take out this row only: another add may be in flight beside it.
      client.updateQueryData<List<Device>>(
        key,
        (list) => list?.where((row) => row.id != temporaryId).toList(),
      );
    },
    onSettled: (_, __, ___, ____, _____) =>
        client.invalidateQueries(filters: QueryFilters(queryKey: key)),
  );
}
```

The **`cancelQueries` first is not optional.** A refetch already in flight
left before the write; if it lands after the patch, it writes the old list
over it and the new row vanishes until the next fetch. Cancelling it (with
its default `revert: true`) puts the query back as it was before that fetch,
so the patch is the last word until `onSettled`'s invalidation fetches again.

The rollback here removes the one row this mutation added rather than
restoring a snapshot of the whole list. That matters as soon as two adds can
be in flight: restoring the first one's snapshot when it fails would also
erase the second one's row.

### Updating one item

For a change to one entry, the classic shape — snapshot, patch, restore — is
exactly right, because nothing else writes that entry in the meantime:

```dart snippet="guides/optimistic-updates.md#optimistic"
MutationOptions<Task, String, Task?> renameOptimistically(
  QueryClient client,
  String id,
) =>
    MutationOptions<Task, String, Task?>(
      mutationFn: (name) => api.rename(id, name),
      onMutate: (name) async {
        await client.cancelQueries(
          filters: QueryFilters(queryKey: taskKey(id)),
        );
        final previous = client.getQueryData<Task>(taskKey(id));
        client.updateQueryData<Task>(
          taskKey(id),
          (task) => task?.copyWith(name: name),
        );
        return previous; // the rollback handle
      },
      onError: (error, stack, name, previous) {
        if (previous != null) client.setQueryData(taskKey(id), previous);
      },
      onSettled: (_, __, ___, ____, _____) => client.invalidateQueries(
        filters: QueryFilters(queryKey: taskKey(id)),
      ),
    );
```

Whatever `onMutate` returns reaches `onSuccess`, `onError` and `onSettled` as
their last argument, typed by the options' third type argument. If `onMutate`
itself throws, the mutation fails without running its function, and that
argument is `null`.

The `optimistic-updates` screen shows both shapes on one todo list. Pick *Via
variables* or *Via cache*, type a todo and press *Add*; then tick *Refuse
next write* and add another. Via variables, the refused row turns into an
error with a *Retry*; via cache, it appears, disappears again and the card
says *Rolled back*.

<LiveDemo feature="optimistic-updates" />

## When to use which

| | Via the UI | Via the cache |
|---|---|---|
| Where the write shows | where the mutation is read (or a `MutationStateController` looks) | in every reader of the key |
| On failure | the row turns into an error; nothing to undo | `onError` has to undo the patch |
| Code | a few lines in one widget | three callbacks, and a way to find what you wrote |
| Good for | one list, one form | data shown in several places, toggles that must not flicker |

Start with the UI shape; move to the cache when a second widget needs to see
the write before the server confirms it.

## Settling, retries and scopes

Whichever shape you use, invalidate in `onSettled`: success or failure, the
server has the final word, and the refetch replaces the guess with it. See
[invalidations from mutations](invalidations-from-mutations.md).

A mutation does not retry by default. If you turn retries on, the optimistic
state stays on screen through them — `onMutate` runs once per mutation, not
per attempt.

Mutations in a [scope](mutation-scopes.md) run their `onMutate` when they are
submitted, not when their turn comes — so, again, roll back the row a
mutation changed rather than restoring a whole-list snapshot.

The `playground` screen is the other half of the argument: its adds and
renames are not optimistic. Set *Latency* to *2 s* and add a todo — the wait
between pressing and seeing is what an optimistic update removes.

<LiveDemo feature="playground" />

:::note[In React Query]
The same two shapes: the UI one reads `variables` from `useMutation` (or
`useMutationState` from another component), the cache one uses `onMutate`,
`onError` and `onSettled`. What `onMutate` returns is called the *context* in
TanStack Query and `onMutateResult` here.
:::
