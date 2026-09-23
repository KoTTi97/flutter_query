---
title: Combining queries
description: combine over a record or a list of results — the pending, error and data rules, optional sources, combineWith, CombineMemo and keys.
---

{/* demo: combine */}

# Combining queries

A record has a type per position, so `combine` is a function over a **record
of results** — from `context.query`, a builder, the mixin or a controller's
`value`, it does not matter which. Nothing new observes anything: the reads
you already have rebuild the widget, and `combine` says what they amount to
together.

```dart snippet="guides/combining-queries.md#combine"
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
six results; past six, put the sources in a list typed by what they have in
common — `<QueryResult<Object?>>[a, b, …]` — combine that, and cast in the
combiner. A `CombinedResult` is deliberately not a source, so two combinations
do not nest. Controllers combine the same way under a `ListenableBuilder` over
`Listenable.merge([a, b])`.

Two combinations that share a source each refetch it: `refetch()` and
`retry()` cancel a fetch in flight and start their own, as an observer's
`refetch()` does. To refresh several combinations at once without fetching a
shared source twice, pass `refetch(cancelRefetch: false)` — the second call
then joins the fetch the first one started.

The combiner runs on every call — every build. For a constructor call that is
nothing; for a join over long lists, keep a `CombineMemo<R>` next to the reads
(a `State` field) and pass it as `memo:`. The combiner is then skipped while
every source holds the identical data instance — which structural sharing
makes the normal case for a refetch that changed nothing — and an equal
result keeps its instance, as TanStack Query shares the output of
`combine`.

A source the screen can do without is `optional()`: it never blocks and never
fails the combination — its value is `null` until there is one — while
`isFetching` still sees it and `retry()` still refetches it when the query
behind it failed. And a **list** of results of one type, a
`QueriesController`'s value, combines by the same rules:

```dart snippet="guides/combining-queries.md#combine-optional-and-lists"
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

A list **and** a source of another type — typically the query the list of
queries was derived from — is `combineWith`. It is one combination, not two
nested ones: the rules read the same, and the deriving query's failure is an
error rather than an empty list. More than one extra source goes the same way
as more than six: one list typed by what the sources have in common, cast in
the combiner.

```dart snippet="guides/combining-queries.md#combine-with"
CombinedResult<List<Comment>> allComments(
  QueryResult<List<Post>> feed,
  List<QueryResult<List<Comment>>> perPost,
) =>
    // One combination, `feed` first: if the query the list was derived from
    // failed, this is an error — not an empty list.
    perPost.combineWith(
      feed,
      (perPost, feed) => [for (final comments in perPost) ...comments],
    );
```

**With a memo, the combiner must be a function of the sources and nothing
else.** A memo cannot see what a closure captures: a combiner that filters by a
search text it closes over keeps returning the list for the *old* text until a
source changes. Do that work on the combined data, after `combine` — or name
what the combiner reads with `keys: [search]`, which is compared with `==` and
re-runs the combiner when it differs.

## See it running

The `combine` screen shows the rules one source at a time; see
[examples](../examples/index.md).
