---
title: Mutation state
description: MutationStateController and MutationStateObserver — every mutation matching a filter, for a "saving…" badge no widget owns, and its typed form.
---

# Mutation state

`MutationStateController` (and the core's `MutationStateObserver`) reads *every*
mutation matching a filter through a `select` — the counterpart of
`useMutationState`.
It is how a "saving…" badge in an app bar works without any widget owning the
mutation. Concurrent runs under one key are kept apart.

```dart snippet="guides/mutation-state.md#mutation-state"
final saving = MutationStateController<int>(
  client,
  filters: const MutationFilters(status: MutationStatus.pending),
  select: (mutation) => 1,
);
// saving.value.length is "how many writes are in flight"
```

`client.isMutating()` is the count alone, without a subscription.

## A "saving…" indicator in the app bar

A mutation belongs to the widget that asked for it, so the app bar cannot
read it. It can read the mutation *cache*, which holds every mutation
wherever it was started. The indicator below counts the writes in flight —
the power switches, the renames, a firmware upload — and knows none of them:

```dart snippet="guides/mutation-state.md#saving-indicator"
// lib/widgets/saving_indicator.dart — in the app bar, owning no mutation.
class _SavingIndicatorState extends State<SavingIndicator> {
  late final MutationStateController<int> _saving = MutationStateController(
    QueryClientProvider.read(context),
    filters: const MutationFilters(status: MutationStatus.pending),
    select: (mutation) => mutation.mutationId,
  );

  @override
  void dispose() {
    _saving.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<List<int>>(
        valueListenable: _saving,
        builder: (context, running, _) => running.isEmpty
            ? const SizedBox.shrink()
            : Text('Saving ${running.length}…'),
      );
}
```

Selecting the `mutationId` rather than a constant keeps each run apart in the
list, and the list is compared with the previous one before the controller
notifies: a cache event that leaves the same mutations pending does not
rebuild the indicator. A widget that wants to know *what* is being saved
selects the variables instead, as below.

Finished mutations stay in the mutation cache until their `gcTime` runs out
after their last observer is gone, so a filter without a `status` sees
recent successes and failures too — useful for a "2 changes could not be
saved" banner, which filters on `MutationStatus.error`.

The `mutation-state` screen puts such a badge above a todo list. Press *Add
todo* twice quickly: the badge counts `saving=2` while both run and drops to
zero when they settle. *Add, failing* ends in `failed=1` instead, and
`badge-builds` only moves when the selection actually changed.

<LiveDemo feature="mutation-state" />

## One type of mutation

A filter spans mutations of every type, so `select` receives them erased. When
you want the mutations of *one* type, `typed` filters by it and hands them over
typed — the pending variables as an optimistic display, without a cast:

```dart snippet="guides/mutation-state.md#typed-mutation-state"
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

Three things to know, because an empty list after a filter looks harmless:

- The filter is the mutation's **declared** type arguments, not the runtime
  type of its variables. A mutation built from options whose types were never
  written or inferred is a `Mutation<Object?, Object?, Object?>` and is not a
  `Mutation<Object?, String, Object?>`, whatever it was called with — it drops
  out silently. Options with a typed `mutationFn` infer correctly; check the
  ones assembled from pieces.
- The type is the controller's for its life: a later `setOptions` may
  replace the filters or the select, and the selection still sees only
  mutations of that type (a new select receives them erased, as the untyped
  one does). A filter's `predicate` runs after the type test, so it too
  sees only mutations of that type and may read the declared type.
- A typed selection does not replace an untyped one where the mutations are
  mixed on purpose: "is *any* write in flight?" over a scope that holds two
  variable types is still one untyped controller, next to the typed one.

:::note[In React Query]
`MutationStateController` is `useMutationState({ filters, select })`, and
`client.isMutating()` is `useIsMutating` without the subscription. The typed
form has no counterpart there: in TypeScript `select` receives the mutation
untyped and you cast.
:::
