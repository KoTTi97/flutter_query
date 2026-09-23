---
title: Parallel queries
description: Several queries at once — separate reads that run side by side, and QueriesBuilder for a list of queries that changes length or order.
---

{/* depth: todo */}
{/* demo: parallel-queries, query-collections */}

# Parallel queries

Queries that do not depend on each other run in parallel. There is nothing to
set up.

## A fixed number of queries

Read each one. Two `context.query` calls in one `build`, two `watchQuery`
calls in a `QueryMixin` `State`, two nested builders — each read starts its
fetch when it subscribes, and they run side by side. `context.query(taskQuery(id))`
next to `context.query(commentsQuery(id))` is two requests in flight at once.

To turn the two results into one value to render — loading while either
loads, an error if either failed — [combine them](combining-queries.md).

## A list of queries

`QueriesBuilder` observes a list that may change length or order — the
counterpart of `useQueries`, minus the heterogeneous tuple (for that, see
[combining queries](combining-queries.md)).

```dart snippet="guides/parallel-queries.md#queries-builder"
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
one element type. `QueriesController` is the same thing as a
`ValueListenable`, and `QueriesObserver` the same thing without Flutter. For
queries of **different** types, [combine](combining-queries.md) their results
instead.

## See it running

The `parallel-queries` screen runs independent reads side by side, and
`query-collections` has a list that grows, shrinks and reorders, with
duplicate keys and a partial failure; see [examples](../examples/index.md).
