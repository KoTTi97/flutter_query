---
title: Optimistic updates
description: Show a write before the server confirms it — from the pending variables, or by patching the cache in onMutate and rolling back on error.
---

{/* depth: todo */}
{/* demo: optimistic-updates, playground */}

# Optimistic updates

An optimistic update shows the result of a write before the server has
confirmed it. There are two shapes.

**From `variables`.** While a mutation is pending, `MutationPending` carries
the variables it was started with, so the UI can render the pending row without
touching the cache. Nothing to roll back — if it fails, the pending row simply
goes away.

**From the cache, with rollback.** `onMutate` snapshots and patches; whatever it
returns is handed to `onError` and `onSettled` as their last argument:

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

The `cancelQueries` first is not optional: an in-flight refetch that lands after
the patch would overwrite it with pre-write data.

## Settling

Whichever shape you use, invalidate in `onSettled`: success or failure, the
server has the final word, and the refetch replaces the guess with it. See
[invalidations from mutations](invalidations-from-mutations.md).

Mutations in a [scope](mutation-scopes.md) run their `onMutate` when they are
submitted, not when their turn comes — roll back the row a mutation changed
rather than restoring a whole-list snapshot.
