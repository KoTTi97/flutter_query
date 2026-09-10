---
title: Mutations
sidebar_position: 4
description: mutate and mutateAsync, per-call callbacks, optimistic updates with rollback, and serialising writes with a scope.
---

# Mutations

A mutation is a write. It has the same four call styles as a query —
`context.mutation(...)`, `watchMutation(...)`, `MutationBuilder`,
`MutationController` — and every one of them hands back a **controller**,
because you need `mutate` as well as the state.

```dart
final add = context.mutation(
  MutationOptions.simple(
    mutationFn: (String name) => api.addSensor(name),
    onSuccess: (_, __, ___) => client.invalidateQueries(
      filters: QueryFilters(queryKey: sensorsKey),
    ),
  ),
);

// … add.value is the MutationResult; add.mutate(vars) starts it.
```

`MutationResult` is sealed: `MutationIdle`, `MutationPending`,
`MutationSuccess`, `MutationError`, with `isIdle` / `isPending` / `isSuccess` /
`isError` for the cases where a `switch` is more than you need.

## Three type arguments, and why `simple` exists

`MutationOptions<TData, TVariables, TOnMutateResult>`. The third is what
`onMutate` returns — the **rollback handle** of an optimistic update.

A mutation without an optimistic step has nothing to roll back, so
`MutationOptions.simple` fixes that third argument to `void` and lets the other
two infer from `mutationFn`. That is the only reason it exists: a typedef
cannot fix one type argument of a constructor and leave the rest to inference.

## `mutate` versus `mutateAsync`

- `mutate(vars)` starts it and returns nothing. Errors go to `onError` and to
  the result; nothing is thrown at the call site.
- `mutateAsync(vars)` returns a `Future<TData>` that **rejects** on failure.
  Use it when the caller genuinely wants to `await` the outcome — and then
  handle the rejection, or an unhandled async error will find you.

Per-call callbacks ride along, and run *after* the options' own:

```dart
add.mutate(
  'New sensor',
  callbacks: MutateCallbacks(
    onSuccess: (data, vars, _) => Navigator.of(context).pop(),
  ),
);
```

## Optimistic updates

Two shapes, and the showcase has a screen for each.

**From `variables`.** While a mutation is pending, `MutationPending` carries
the variables it was started with, so the UI can render the pending row without
touching the cache. Nothing to roll back — if it fails, the pending row simply
goes away.

**From the cache, with rollback.** `onMutate` snapshots and patches; whatever it
returns is handed to `onError` and `onSettled` as their last argument:

```dart
MutationOptions<Sensor, String, Sensor?>(
  mutationFn: (name) => api.rename(id, name),
  onMutate: (name) async {
    await client.cancelQueries(filters: QueryFilters(queryKey: sensorKey(id)));
    final previous = client.getQueryData<Sensor>(sensorKey(id));
    client.updateQueryData<Sensor>(sensorKey(id), (s) => s?.copyWith(name: name));
    return previous;                       // the rollback handle
  },
  onError: (error, stack, name, previous) {
    if (previous != null) client.setQueryData(sensorKey(id), previous);
  },
  onSettled: (_, __, ___, ____, _____) => client.invalidateQueries(
    filters: QueryFilters(queryKey: sensorKey(id)),
  ),
)
```

The `cancelQueries` first is not optional: an in-flight refetch that lands after
the patch would overwrite it with pre-write data.

:::tip Returning the invalidation future
A mutation whose `onSuccess` **returns** the `invalidateQueries` future stays
`pending` until that refetch lands — upstream's "return the promise" idiom. It
is often what you want (the button stays busy until the screen is actually
consistent), but say so on screen, because otherwise it looks like the write is
slow.
:::

## A mutation outlives its widget

Disposing a controller does not cancel the mutation. That has one practical
consequence, and it bites everyone once:

```dart
@override
Widget build(BuildContext context) {
  // Take the client HERE, not inside onSuccess. The callback can run after
  // this element is gone, and looking an ancestor up from a deactivated
  // element throws.
  final client = QueryClientProvider.of(context);
  final add = context.mutation(MutationOptions.simple(
    mutationFn: api.addSensor,
    onSuccess: (_, __, ___) => client.invalidateQueries(/* … */),
  ));
  // …
}
```

The cache work has to happen either way. The client is the right thing to close
over; the `BuildContext` is not.

## Identity

In the context and mixin styles a mutation is identified by `id:` if you give
one, else by its `mutationKey`, each together with its three type arguments;
without either, by the types alone. Two mutations of the same shape in one
build without an `id:` are caught by an assertion in debug builds.

Like a query, a mutation is released after the frame once a build stops reading
it.

## Serialising writes: `MutationScope`

Mutations in the same scope run **one at a time**, in the order they were
started:

```dart
MutationOptions.simple(
  mutationFn: api.rename,
  scope: const MutationScope('sensor-writes'),
)
```

That is the tool for "two edits of the same row must not race".

## Offline

A mutation started while the client believes it is offline is **paused**, not
failed. `client.resumePausedMutations()` releases them, and the client does it
itself when the online manager flips back — as long as the client is
[mounted](lifecycle-and-connectivity.md). See
[network mode](lifecycle-and-connectivity.md#network-mode).

## Cache-wide mutation state

`MutationStateController` (and the core's `MutationStateObserver`) reads *every*
mutation matching a filter through a `select` — upstream's `useMutationState`.
It is how a "saving…" badge in an app bar works without any widget owning the
mutation. Concurrent runs under one key are kept apart.

## Defaults

`client.setMutationDefaults(key, MutationDefaults(...))` registers
`mutationFn`, `retry`, `retryDelay`, `networkMode`, `gcTime`, `scope` and
`meta` per key. **Not callbacks** — that is a deliberate divergence, recorded
in the porting notes.

A mutation with no `mutationFn` anywhere fails with
`MissingMutationFunctionError`, and is never retried.
