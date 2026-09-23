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

## Optimistic updates

Two shapes, and the showcase has a screen for each.

**From `variables`.** While a mutation is pending, `MutationPending` carries
the variables it was started with, so the UI can render the pending row without
touching the cache. Nothing to roll back — if it fails, the pending row simply
goes away.

**From the cache, with rollback.** `onMutate` snapshots and patches; whatever it
returns is handed to `onError` and `onSettled` as their last argument:

```dart snippet="guides/mutations.md#optimistic"
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

:::tip Returning the invalidation future
A mutation whose `onSuccess` **returns** the `invalidateQueries` future stays
`pending` until that refetch lands — upstream's "return the promise" idiom. It
is often what you want (the button stays busy until the screen is actually
consistent), but say so on screen, because otherwise it looks like the write is
slow.
:::

## What the function may know, and cancelling a write

`mutationFn` takes the variables and nothing else. When the function needs to
know about its run, give `mutationFnWithContext` instead — the same function
with a second argument:

```dart snippet="guides/mutations.md#function-context"
MutationOptions<Task, String, Task> renameWithContext(
        QueryClient client, String id) =>
    MutationOptions(
      onMutate: (name) {
        final before = client.getQueryData<Task>(taskKey(id))!;
        client.setQueryData<Task>(taskKey(id), before.copyWith(name: name));
        return before;
      },
      // The cache already says `name`. What it said before is in the context,
      // and so is the signal `cancel()` cancels.
      mutationFnWithContext: (name, context) => api.rename(
        id,
        name,
        from: context.onMutateResult?.name,
        signal: context.signal,
      ),
      onError: (_, __, ___, before) {
        if (before != null) client.setQueryData<Task>(taskKey(id), before);
      },
      onSettled: (_, __, ___, ____, _____) => client.invalidateQueries(
        filters: QueryFilters(queryKey: taskKey(id)),
      ),
    );
```

The context holds upstream's three — `client`, `meta`, `mutationKey` — and two
of this port's own:

- **`onMutateResult`**, typed. `onMutate` runs *before* the function, so after
  an optimistic patch the cache no longer says what was there. A function that
  compares "before" with "wanted" and reads the cache will find no difference
  and send nothing. What `onMutate` kept is the answer.
- **`signal`**, cancelled by `cancel()` — on the controller, the observer or
  the `Mutation`.

**Cancelling is failing.** `cancel()` fails the run with a `CancelledError`:
no further retry, `onError` and `onSettled` run, and the scope moves on. So the
rollback you already wrote rolls it back, and the invalidation you already
wrote finds out what the server really did — which nobody can know otherwise,
because the request may have arrived. That is why it is not the quiet return
to the previous state that cancelling a *query* is: a write has no previous
state to return to. A function that honours the signal aborts its transport;
one that does not runs on unobserved and its result is discarded. `mutateAsync` throws that `CancelledError` at its call site like any other
failure, so a `mutateAsync` nobody awaits needs a handler (or use `mutate`,
which has the controller hold the error instead). Only
`cancel()` cancels the signal: removing a mutation from the cache or disposing
its controller leaves an attempt in flight to settle, so there is nothing to
abort. A mutation
that is paused, queued behind its scope or still in `onMutate` fails the same
way without its function ever running. So does one restored `pending` from
persistence that has not been resumed yet. Once the function has returned,
`cancel()` does nothing: the write went through.

One function per mutation — both at once fails an assertion at the options
literal in a debug build, and is an `ArgumentError` when the client resolves
them in a release build — and a
function registered with `setMutationDefaults` has no context form.

## A mutation outlives its widget

Disposing a controller does not cancel the mutation — a write the user started
should normally finish; call `cancel()` first when it should not. That has one
practical consequence, and it bites everyone once:

```dart snippet="excerpt: getting-started/first-query.md#mutation"
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

## Narrowing rebuilds

All four styles take [`buildWhen`](rebuilds.md#buildwhen) — the builder and,
since [#67](https://github.com/KoTTi97/flutter_query/issues/67), the two
keyless reads. It is the only narrowing a mutation reader has: there is no
`select` on a mutation.

```dart snippet="guides/rebuilds.md#build-when-mutation"
final rename = context.mutation(
  renameTask(id),
  // A retrying run moves `failureCount` while it stays pending; a spinner
  // does not care which attempt it is on.
  buildWhen: (previous, current) => previous.status != current.status,
);
```

A `MutationObserver` never reports a result equal to the one before it, so —
unlike a query's — this predicate is asked about every notification the reader
gets. A `MutationController` takes none, for the reason every controller takes
none: it *is* the notifier.

## Identity

In the context and mixin styles a mutation is identified by `id:` if you give
one, else by its `mutationKey`, each together with its three type arguments;
without either, by the types alone. A `mutationKey` is a category, as
upstream's is, not a name: two mutations of the same shape under one key in
one build without an `id:` are caught by an assertion in debug builds — they
would otherwise share one controller. Give each an `id:`.

Like a query, a mutation is released after the frame once a build stops reading
it.

## Serialising writes: `MutationScope`

Mutations in the same scope run **one at a time**, in the order they were
started:

```dart snippet="guides/mutations.md#scope"
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

## Offline

A mutation started while the client believes it is offline is **paused**, not
failed. `client.resumePausedMutations()` releases them, and the client does it
itself when the online manager flips back — as long as the client is
[mounted](lifecycle-and-connectivity.md). See
[network mode](lifecycle-and-connectivity.md#network-mode). A mutation that
could run offline (`NetworkMode.always`) but is queued behind a scope-mate
that cannot stays paused until the scope moves; `resumePausedMutations()`
does not wait for it.

## Cache-wide mutation state

`MutationStateController` (and the core's `MutationStateObserver`) reads *every*
mutation matching a filter through a `select` — upstream's `useMutationState`.
It is how a "saving…" badge in an app bar works without any widget owning the
mutation. Concurrent runs under one key are kept apart.

A filter spans mutations of every type, so `select` receives them erased. When
you want the mutations of *one* type, `typed` filters by it and hands them over
typed — the pending variables as an optimistic display, without a cast:

```dart snippet="guides/mutations.md#typed-mutation-state"
MutationStateController<String> pendingRenames(QueryClient client) =>
    MutationStateController.typed(
      client,
      filters: const MutationFilters(status: MutationStatus.pending),
      // The parameter's type is the filter: every mutation whose variables
      // are a String, and `variables` needs no cast.
      select: (Mutation<Object?, String, Object?> mutation) =>
          mutation.state.variables!,
    );
```

Two things to know, because an empty list after a filter looks harmless:

- The filter is the mutation's **declared** type arguments, not the runtime
  type of its variables. A mutation built from options whose types were never
  written or inferred is a `Mutation<Object?, Object?, Object?>` and is not a
  `Mutation<Object?, String, Object?>`, whatever it was called with — it drops
  out silently. Options with a typed `mutationFn` infer correctly; check the
  ones assembled from pieces.
- The type is the controller's for its life: a later `setOptions` may
  replace the filters or the select, and the selection still sees only
  mutations of that type (a new select receives them erased, as the untyped
  one does).
- A typed selection does not replace an untyped one where the mutations are
  mixed on purpose: "is *any* write in flight?" over a scope that holds two
  variable types is still one untyped controller, next to the typed one.

## Defaults

`client.setMutationDefaults(key, MutationDefaults(...))` registers
`mutationFn`, `retry`, `retryDelay`, `networkMode`, `gcTime`, `scope` and
`meta` per key. **Not callbacks** — that is a deliberate divergence, recorded
in the porting notes.

A mutation with no `mutationFn` anywhere fails with
`MissingMutationFunctionError`, and is never retried.
