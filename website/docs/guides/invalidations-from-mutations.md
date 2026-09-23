---
title: Invalidations from mutations
description: Invalidate the queries a write affected in its onSuccess or onSettled, and what returning the future does to the mutation's state.
---

{/* depth: todo */}
{/* demo: mutations */}

# Invalidations from mutations

A write makes some cached reads wrong. The simplest way to make them right is
to invalidate them when the write has landed, and let the active ones refetch:

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

Invalidate by the most general key the write could affect: adding a task
changes every list, so `['tasks']`; renaming one changes its detail and every
list it appears in, so `['tasks']` again. See [query keys](query-keys.md) for
building keys so that a prefix is a real parent.

## `onSuccess` or `onSettled`

- In **`onSuccess`**, only a write that went through refetches.
- In **`onSettled`**, a failed write refetches too. Use it after an
  [optimistic update](optimistic-updates.md), or whenever a failure may have
  half-happened on the server.

## Returning the future

A mutation whose `onSuccess` **returns** the `invalidateQueries` future stays
`pending` until that refetch lands — the Dart form of TanStack Query's "return
the promise". It is often what you want (the button stays busy until the
screen is actually consistent), but say so on screen, because otherwise it
looks like the write is slow.

Returning nothing — a block body, or `.ignore()` on the future — settles the
mutation at once and lets the refetch run behind it.

## Take the client in `build`

The callback may run after the widget that started the mutation is gone.
Close over the `QueryClient` — `QueryClientProvider.of(context)` in `build` —
not over the `BuildContext`; see [mutations](mutations.md#a-mutation-outlives-its-widget).

When the server answers with the new data, you can write it into the cache
instead of refetching; see [updates from mutation
responses](updates-from-mutation-responses.md).
