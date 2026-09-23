---
title: Does this replace state management?
description: Server state and client state are different problems — what moves into the cache, what stays in your state-management package, and how the two meet.
---

# Does this replace state management?

For the part of your state that came from a server, mostly yes. For the rest,
no — and it does not try to.

## Two kinds of state

**Server state** lives somewhere else. You hold a copy that can go out of
date, that someone else can change, and that has to be fetched, cached,
refreshed and invalidated. That is this library's whole job.

**Client state** is yours alone: which tab is open, what is typed into a form,
whether a panel is expanded, a theme, a draft. It is never stale, because
nothing else owns it.

Most apps built with `provider`, `riverpod` or `bloc` hold both kinds in one
place, and most of the code is the first kind — loading flags, error fields,
refresh logic, "is this cached yet". Moving that into queries usually leaves
a much smaller client state behind, often small enough for `setState` and an
`InheritedWidget`.

## What moves

- A repository or bloc whose job is "fetch, keep, refresh" becomes a query
  options function and a key.
- Loading, error and "refreshing" flags become the [query
  result](queries.md).
- Manual refresh-after-write becomes an
  [invalidation](invalidations-from-mutations.md).
- A cache you wrote yourself — with its expiry — becomes
  [`staleTime` and `gcTime`](caching.md).

## What stays

Form input, navigation state, selections, feature flags, anything the server
never sees. Keep those in whatever you use today.

## How the two meet

- **Client state picks the query.** A selected filter or page number goes into
  the query's **key**, and the query follows it; see [query
  keys](query-keys.md).
- **A query is a listenable.** A `QueryController` is a
  `ValueListenable` of the query's result — a `ChangeNotifier`, to be exact —
  so anything that can wrap a listenable can hold one; see [four ways to read
  a query](reading-queries-in-widgets.md#querycontroller).
- **Nothing here needs another package**, and nothing here competes for the
  same job as one: the binding depends on Flutter alone.

The four ways the binding reads a query — `context.query`, the builder
widgets, `QueryMixin` and `QueryController` — are equal alternatives, and
they mix in one screen. In the *Four call styles* example, five readers
share one cache entry; press *Refetch*, then *Invalidate*, and watch one
request go out and every card update, with the strip still saying
`fetches=1` per request.

<LiveDemo feature="four-call-styles" />

## Next to Riverpod, Bloc, Provider and signals

The rule for all of them is the same: **the cache stays the owner of server
data**. Your state-management package may hold a controller, forward its
result, or react to it — but it does not copy the data into its own state and
keep it there, because then two places disagree after the next refetch.

Keep one `QueryClient` for the app, created once. If both your package and
the widgets read queries, hand the same client to `QueryClientProvider`.

### Riverpod

A notifier owns a `QueryController` and forwards its result as its state.
Riverpod's `autoDispose` and the controller's own lifetime line up: the
controller subscribes while the notifier is alive, and disposing it lets the
cache entry go after its `gcTime`.

```dart snippet="prose-only: needs package:flutter_riverpod, which this site's compiled samples do not depend on"
final queryClientProvider = Provider<QueryClient>((ref) => QueryClient());

class TasksNotifier extends Notifier<QueryResult<List<Task>>> {
  @override
  QueryResult<List<Task>> build() {
    final controller =
        QueryController(ref.watch(queryClientProvider), tasksQuery());
    void forward() => state = controller.value;
    controller.addListener(forward);
    ref.onDispose(() {
      controller
        ..removeListener(forward)
        ..dispose();
    });
    return controller.value;
  }
}

final tasksProvider =
    NotifierProvider.autoDispose<TasksNotifier, QueryResult<List<Task>>>(
  TasksNotifier.new,
);
```

A `ConsumerWidget` then switches over `ref.watch(tasksProvider)` exactly as
it would over any `QueryResult`. The sample is written for Riverpod 3; on
Riverpod 2 the class extends `AutoDisposeNotifier`. A notifier whose options
depend on another provider — a filter, a user id — watches that provider in
`build`, and Riverpod rebuilds it with a new controller for the new key.

### Bloc

A Cubit wraps a controller the same way and emits each result:

```dart snippet="prose-only: needs package:bloc, which this site's compiled samples do not depend on"
class TasksCubit extends Cubit<QueryResult<List<Task>>> {
  TasksCubit(QueryClient client)
      : this._(QueryController(client, tasksQuery()));

  TasksCubit._(this._controller) : super(_controller.value) {
    _controller.addListener(_forward);
  }

  final QueryController<List<Task>, List<Task>> _controller;

  void _forward() => emit(_controller.value);

  Future<void> refresh() => _controller.refetch();

  @override
  Future<void> close() {
    _controller
      ..removeListener(_forward)
      ..dispose();
    return super.close();
  }
}
```

The controller starts fetching when the listener is added, so the Cubit's
first state is the pending result and the next `emit` is the data. For a
Bloc that should *react* to a query — log out when a profile request fails
with a 401, say — listen to the controller in the Bloc and add an event,
rather than copying the result into the Bloc's state.

### Provider

`ChangeNotifierProvider` takes a `QueryController` as it is, since the
controller is a `ChangeNotifier`, and disposes it with the provider:
`ChangeNotifierProvider(create: (context) => QueryController(client,
tasksQuery()))`. Reading it with `context.watch` then rebuilds on every
result.

### Signals

A signals package that can wrap a `ValueListenable` wraps a
`QueryController` directly; one that cannot takes a listener that sets the
signal, as in the Cubit above. Either way, dispose the controller where the
signal is disposed.

:::note[In React Query]
The TanStack docs make the same split: "server state" in the query cache,
client state in whatever the app already uses — `useState`, Zustand, Redux.
The integrations here play the role of those libraries' hooks and selectors.
:::

## In practice

The *Task manager* example has no state-management package at all. Its
server state — the task list, each task, the search results — is queries and
mutations. Its client state — which task is open, the search text, the
project filter — is one small `ChangeNotifier`, `AppState` in
[`examples/task_manager/lib/src/app_state.dart`](https://github.com/dualmeta-gmbh/query_kit/blob/main/examples/task_manager/lib/src/app_state.dart),
with no copy of any task in it. The search text and the project go into the
list's query key, debounced, so the list follows them. A larger app keeps
its package for the client side and loses most of the server-side code.
