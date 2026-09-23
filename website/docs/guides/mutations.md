---
title: Mutations
description: The four ways to read a mutation, MutationResult, mutate and mutateAsync, per-call callbacks, identity, and mutation defaults.
---

{/* demo: mutations */}

# Mutations

A mutation is a write. It has the same four call styles as a query —
`context.mutation(...)`, `watchMutation(...)`, `MutationBuilder`,
`MutationController` — and every one of them hands back a **controller**,
because you need `mutate` as well as the state.

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

```dart snippet="guides/mutations.md#per-call-callbacks"
add.mutate(
  'New task',
  callbacks: MutateCallbacks<void, String, void>(
    onSuccess: (data, vars, _) => Navigator.of(context).pop(),
  ),
);
```

## A mutation outlives its widget

Disposing a controller does not cancel the mutation — a write the user started
should normally finish; call `cancel()` first when it should not. That has one
practical consequence, and it bites everyone once:

```dart snippet="excerpt: quick-start.md#mutation"
@override
Widget build(BuildContext context) {
  // Take the client HERE, not inside onSuccess. The callback can run after
  // this element is gone, and looking an ancestor up from a deactivated
  // element throws.
  final client = QueryClientProvider.of(context);
  final add = context.mutation(MutationOptions.simple(
    mutationFn: api.addTask,
    onSuccess: (_, __, ___) => client.invalidateQueries(/* … */),
  ));
  // …
}
```

The cache work has to happen either way. The client is the right thing to close
over; the `BuildContext` is not.

Per-call callbacks — the `callbacks:` passed to `mutate` — are the exception:
once the reader has stopped listening, they are skipped, and only the
options' own callbacks run. Put what must happen in the options.

## Narrowing rebuilds

`context.mutation`, `watchMutation` and `MutationBuilder` take
[`buildWhen`](render-optimizations.md#buildwhen); a `MutationController`
has none, on purpose — it is the notifier. It is the only narrowing a
mutation reader has: there is no `select` on a mutation.

## Identity

In the context and mixin styles a mutation is identified by `id:` if you give
one, else by its `mutationKey`, each together with its three type arguments;
without either, by the types alone. A `mutationKey` is a category, as
TanStack Query's is, not a name: two mutations of the same shape under one key read
in one `build` without an `id:` would share one controller, and whichever was
read last would run for both — its function and its callbacks alike. When
their mutation functions or callbacks (`onMutate`, `onSuccess`, `onError`,
`onSettled`) differ, a debug build catches it with an assertion: "delete,
then pop" and "delete, then show a snackbar" are two mutations. So does a
different `scope`, `retry`, `retryDelay`, `networkMode` or `gcTime`: rows
reading `MutationScope('task-$id')` inline under one key would otherwise
share one queue. Give each an `id:`. Those five compare by value, except
the two that carry a closure — `RetryPolicy.when` and `RetryDelay.dynamic`
— which compare by variant only, so a helper building one inline and read
twice is still one mutation. `meta` is not compared — it is most often a map
literal, new on every build — and the last read's wins.

The same functions read twice are one mutation and do not assert: a getter
over one stored options object, options built around tear-offs or top-level
functions, or a nested builder re-reading what `build` read. A function
literal is a new function every time it is evaluated, so a getter that builds
one per read looks exactly like two mutations and still asserts — keep the
options (or the functions) in a field, or read the mutation once and share
the controller. Only a `StatelessWidget`'s or `State`'s own `build` is
checked; reads through a `LayoutBuilder`'s context never are.

Like a query, a mutation is released after the frame once a build stops reading
it.

## Defaults

`client.setMutationDefaults(key, MutationDefaults(...))` registers
`mutationFn`, `retry`, `retryDelay`, `networkMode`, `gcTime`, `scope` and
`meta` per key. **Not callbacks** — see [differences from TanStack
Query](../reference/differences-from-tanstack.md).

A mutation with neither a `mutationFn` nor a `mutationFnWithContext` anywhere
fails with
`MissingMutationFunctionError`, and is never retried.

## Where next

- [Invalidations from mutations](invalidations-from-mutations.md) and
  [updates from mutation responses](updates-from-mutation-responses.md) — making
  the cache agree with the write.
- [Optimistic updates](optimistic-updates.md) — showing the write before the
  server confirms it.
- [Mutation scopes](mutation-scopes.md), [cancelling
  mutations](cancelling-mutations.md) and [mutation state](mutation-state.md).
- Offline, a mutation is paused rather than failed; see [network
  mode](network-mode.md).
