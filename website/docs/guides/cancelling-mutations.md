---
title: Cancelling mutations
description: mutationFnWithContext, the signal cancel() cancels, and why cancelling a write fails it rather than reverting it.
---

{/* demo: mutation-cancel */}

# Cancelling mutations

`mutationFn` takes the variables and nothing else. When the function needs to
know about its run — to abort its request, or to read what `onMutate` kept —
give `mutationFnWithContext` instead: the same function with a second
argument.

```dart snippet="guides/cancelling-mutations.md#function-context"
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

The context holds `client`, `meta` and `mutationKey`, as in TanStack Query,
and two more:

- **`onMutateResult`**, typed. `onMutate` runs *before* the function, so after
  an optimistic patch the cache no longer says what was there. A function that
  compares "before" with "wanted" and reads the cache will find no difference
  and send nothing. What `onMutate` kept is the answer.
- **`signal`**, cancelled by `cancel()` — on the controller, the observer or
  the `Mutation`.

## Cancelling is failing

`cancel()` fails the run with a `CancelledError`:
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
