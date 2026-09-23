---
title: Mutation scopes
description: MutationScope runs the mutations that share it one at a time, in the order they were started.
---

{/* depth: todo */}
{/* demo: mutations */}

# Mutation scopes

Mutations in the same scope run **one at a time**, in the order they were
started:

```dart snippet="guides/mutation-scopes.md#scope"
MutationOptions<void, String, void> serialisedWrite(String id) =>
    MutationOptions.simple(
      mutationFn: (String name) => api.rename(id, name),
      scope: const MutationScope('task-writes'),
    );
```

That is the tool for "two edits of the same row must not race".

Only the **function** waits its turn. `onMutate` runs when the mutation is
submitted, so a snapshot it takes, a patch it applies or a `cancelQueries` it
calls happens at enqueue time, before the writes ahead of it have landed —
roll back the row this mutation changed rather than restoring a whole-list
snapshot. The scope is held until the running mutation's `onSettled` future
completes, and until then the mutation is still `pending` and
`client.isMutating()` counts it — inside its own `onSettled` too. The
per-call callbacks passed to `mutate` run after the state has moved on. A
queued run reports `isPaused`, as a run waiting for the network does.

A scope is a string id you choose: a constant for "every write of this kind",
or one per row — `MutationScope('task-$id')` — for "writes to the same row".
Mutations without a scope run in parallel.
