---
title: Mutation scopes
description: MutationScope runs the mutations that share it one at a time, in the order they were started — for writes to the same thing that must not race.
---

# Mutation scopes

Mutations run in parallel by default. Two writes to *different* things racing
each other is harmless. Two writes to the *same* thing are not: a user taps a
light switch on, then off, and the two requests leave a few milliseconds
apart. Nothing guarantees they arrive in that order. If *off* lands first,
the light ends up on while the switch on screen says off.

A scope fixes that. Mutations in the same scope run **one at a time**, in the
order they were started:

```dart snippet="guides/mutation-scopes.md#scope"
MutationOptions<void, String, void> serialisedWrite(String id) =>
    MutationOptions.simple(
      mutationFn: (String name) => api.rename(id, name),
      scope: const MutationScope('task-writes'),
    );
```

## One scope per thing

A constant id serialises every write of that kind across the whole app. That
is sometimes what you want — one sync queue, one upload at a time — but it
also makes a write to one row wait for a write to another. For "writes to the
same row must not race", build the id from the row:

```dart snippet="guides/mutation-scopes.md#per-device"
MutationOptions<Device, bool, void> setPowerInOrder(
  QueryClient client,
  String id,
) =>
    MutationOptions.simple(
      mutationFn: (bool on) => devices.setPower(id, on: on),
      // Every write to this device waits for the one before it; writes to
      // other devices do not wait for it.
      scope: MutationScope('device-$id'),
      onSuccess: (device, _, __) {
        client.setQueryData<Device>(DeviceKeys.detail(id), device);
      },
    );
```

Now *on* then *off* on the hallway light always reach the hub in that order,
and switching the kitchen light meanwhile does not wait for either of them.

A scope's id is compared with `==`, so any value with value equality works;
a string is the usual choice. Mutations without a scope never wait for
anything.

## What waits, and what does not

Only the mutation **function** waits for its turn. Everything else happens
when the mutation is started:

- **`onMutate` runs at once**, before the writes ahead of it have landed. A
  snapshot it takes, a patch it applies or a `cancelQueries` it calls happens
  at that moment. For an [optimistic update](optimistic-updates.md) in a
  scope, roll back the row this mutation changed rather than restoring a
  whole-list snapshot — the snapshot may already contain the patch of a
  mutation queued ahead of it.
- **A queued mutation is `pending` and reports `isPaused`**, as one waiting
  for the network does. A spinner that shows for `isPending` shows for it
  too; show "queued" for `isPaused` if the difference matters to the user.
- **The scope is held until the running mutation has settled** — its
  `onSettled` future included. An invalidation returned from `onSettled`
  therefore finishes before the next write in the scope starts. Until then the
  mutation is still `pending`, and `client.isMutating()` counts it, inside its
  own `onSettled` too.
- **The per-call callbacks** passed to `mutate` run after the state has moved
  on, and do not hold the scope.

A failed mutation hands the scope on like a successful one; so does a
[cancelled one](cancelling-mutations.md). The writes behind it run anyway —
if they depended on it, check in their own function or cancel them.

The `mutations` screen has two buttons for this. *Run two unscoped* starts two
slow writes at once and both are pending together; *Run two scoped* starts
the same two in one scope, and the second shows paused until the first has
finished.

<LiveDemo feature="mutations" />

## When not to use a scope

A scope makes the user wait for the network one write at a time. When the
last write is the only one that matters — a text field saved as the user
types, a slider — sending every intermediate value in order is slow and
pointless. Debounce the input and send the latest value instead, or cancel
the write in flight before starting the next.

:::note[In React Query]
`scope: { id: 'device-42' }` on `useMutation`. The scope here is a value
class, `MutationScope('device-42')`, and the rules are the same: only the
function waits, a queued mutation is paused, and mutations without a scope
run in parallel.
:::
