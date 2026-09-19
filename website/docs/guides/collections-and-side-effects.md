---
title: Collections and side effects
sidebar_position: 7
description: QueriesBuilder for a list of queries, the listener widgets for side effects, and MutationStateController for cache-wide write state.
---

# Collections and side effects

Three widgets sit beside the [four call styles](reading-a-query.md) rather than
among them, because none of them is a way of *reading* one query.

## A list of queries

`QueriesBuilder` observes a list that may change length or order — upstream's
`useQueries`, minus the heterogeneous tuple — for which see
[combining queries of different types](#combining-queries-of-different-types).

```dart snippet="guides/collections-and-side-effects.md#queries-builder"
Widget queriesBuilderSample(List<String> visibleIds) =>
    QueriesBuilder<Task, String>(
      queries: <QuerySelectOptions<Task, String>>[
        for (final id in visibleIds)
          QuerySelectOptions<Task, String>(
            queryKey: taskKey(id),
            queryFn: (context) => api.getTask(id, signal: context.signal),
            select: (task) => task.name,
          ),
      ],
      builder: (context, results) => Column(
        children: <Widget>[
          for (final result in results) Text(result.dataOrNull ?? '…'),
        ],
      ),
    );
```

- **Observers are reused by key and occurrence**, so reordering the list starts
  no requests.
- **Duplicate keys** share one cache entry while keeping their own options.
- **Each query fails and settles on its own**; one error does not disturb its
  neighbours.

It is homogeneous: one data type per collection, because a Dart `List` has
one element type. `QueriesObserver` is the same thing without Flutter. For
queries of **different** types, combine their results instead.

## Combining queries of different types

A record has a type per position, so `combine` is a function over a **record
of results** — from `context.query`, a builder, the mixin or a controller's
`value`, it does not matter which. Nothing new observes anything: the reads
you already have rebuild the widget, and `combine` says what they amount to
together.

```dart snippet="guides/collections-and-side-effects.md#combine"
class TaskWithComments extends StatelessWidget {
  const TaskWithComments(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    final combined = (
      context.query(taskQuery(id)),
      context.query(commentsQuery(id)),
    ).combine((task, comments) => '${task.name} (${comments.length})');

    return switch (combined) {
      CombinedPending() => const CircularProgressIndicator(),
      CombinedError(:final error) => TextButton(
          onPressed: combined.retry,
          child: Text('$error — retry'),
        ),
      CombinedData(:final data, :final refetchError) => Text(
          refetchError == null ? data : '$data (could not refresh)',
        ),
    };
  }
}
```

The rules, in order:

1. A source that **failed with nothing to show** makes the whole a
   `CombinedError` — it wins over a source that is still loading, because
   waiting does not cure it and `retry()` (which refetches only the failed
   sources) is something a user can press.
2. Otherwise a source with no data yet makes it `CombinedPending`.
3. Otherwise everything has data and the combiner runs. A background refetch
   that failed keeps its stale data in the combination and shows up as
   `refetchError`: content on screen is not blanked.

`isFetching` is "any source is", and `refetch()` refetches all of them. Two to
six results; past six, combine two combinations. Controllers combine the same
way under a `ListenableBuilder` over `Listenable.merge([a, b])`.

The combiner runs on every call — every build. For a constructor call that is
nothing; for a join over long lists, keep a `CombineMemo<R>` next to the reads
(a `State` field) and pass it as `memo:`. The combiner is then skipped while
every source holds the identical data instance — which structural sharing
makes the normal case for a refetch that changed nothing — and an equal
result keeps its instance, as upstream shares the output of `combine`.

A source the screen can do without is `optional()`: it never blocks and never
fails the combination — its value is `null` until there is one — while
`isFetching` still sees it and `retry()` still refetches it when the query
behind it failed. And a **list** of results of one type, a
`QueriesController`'s value, combines by the same rules:

```dart snippet="guides/collections-and-side-effects.md#combine-optional-and-lists"
CombinedResult<String> taskWithOptionalComments(
  QueryResult<Task> task,
  QueryResult<List<Comment>> comments,
) =>
    // Still loading, disabled or failed, `comments` is null here — and the
    // task is still the task.
    (task, comments.optional()).combine(
      (task, comments) => '${task.name} (${comments?.length ?? '–'})',
    );

CombinedResult<int> doneCount(List<QueryResult<Task>> tasks) =>
    // A QueriesController's value: one failure with nothing to show wins,
    // otherwise pending, otherwise every value in order.
    tasks.combine((tasks) => tasks.where((task) => task.done).length);
```

**With a memo, the combiner must be a function of the sources and nothing
else.** A memo cannot see what a closure captures: a combiner that filters by a
search text it closes over keeps returning the list for the *old* text until a
source changes. Do that work on the combined data, after `combine` — or name
what the combiner reads with `keys: [search]`, which is compared with `==` and
re-runs the combiner when it differs.

## Side effects

`QueryListener`, `InfiniteQueryListener` and `MutationListener` run a callback
on a controller they **borrow** — the owner still disposes it — and never
rebuild their `child`.

```dart snippet="guides/collections-and-side-effects.md#listener"
Widget queryListenerSample(QueryController<Task, Task> task) =>
    QueryListener<Task, Task>(
      controller: task,
      listenWhen: (previous, next) => previous.errorOrNull != next.errorOrNull,
      listener: (context, result) => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task unreachable')),
      ),
      child: const SizedBox.shrink(),
    );
```

Two properties make these safe for navigation and snackbars, which is the whole
point of having them:

- **Nothing fires on mount** — only later transitions.
- **Callbacks are delivered off the build phase**, so a result that arrives
  mid-build reaches the listener after the frame.

A rejected `listenWhen` still advances the comparison state, so the next
callback sees the transition it actually followed. (That is the opposite of
`buildWhen`, where `previous` is what was last *built* — the two fields have
genuinely different jobs.)

## Cache-wide mutation state

`MutationStateController` reads every mutation matching a filter through a
`select` — upstream's `useMutationState`:

```dart snippet="guides/collections-and-side-effects.md#mutation-state"
final saving = MutationStateController<int>(
  client,
  filters: const MutationFilters(status: MutationStatus.pending),
  select: (mutation) => 1,
);
// saving.value.length is "how many writes are in flight"
```

That is how a "saving…" badge in an app bar works without any widget owning the
mutation. Concurrent runs under one key are kept apart.

`MutationStateObserver` is the Flutter-free version.

## On screen

`query-collections` (a list that grows, shrinks and reorders, with duplicate
keys and a partial failure), `mutation-state` and `global-callbacks` in the
[showcase](../project/examples.md).
