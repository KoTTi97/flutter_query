---
title: Dependent queries
description: A query that needs another query's result waits with enabled — Enabled.yes, Enabled.no and Enabled.when.
---

{/* depth: todo */}
{/* demo: dependent-queries */}

# Dependent queries

A query that needs the result of another — the comments of a post you have not
loaded yet — must not run until that result is there. `enabled` holds it
back:

```dart snippet="guides/dependent-queries.md#enabled"
QueryObserverOptions<List<Comment>> commentsQuery(
  String? postId,
) =>
    QueryObserverOptions(
      queryKey: QueryKey(<Object?>['posts', postId, 'comments']),
      queryFn: (context) => api.comments(postId!),
      enabled: postId == null ? Enabled.no : Enabled.yes,
    );
```

Read the first query, and hand what it gave you — or `null` — to the second:
`commentsQuery(post.dataOrNull?.id)`. While the id is `null`, the second
query is `pending` and not fetching (`fetchStatus: idle`). When the first
result lands, the widget rebuilds with an id, the options change, and the
second query starts.

Put the value the query waits for in its key, as above. Otherwise the waiting
query and the running one would share a cache entry.

## `Enabled`

| | |
|---|---|
| `Enabled.yes` | the default: the query fetches on its own |
| `Enabled.no` | it never fetches on its own |
| `Enabled.when((query) => …)` | decided per query each time it matters |

`Enabled.yes` and `Enabled.no` are constants, not constructors. A predicate
given to `Enabled.when` is asked often; keep it cheap and free of side
effects.

A disabled query that already has data keeps it and stays `success`. See
[disabling queries](disabling-queries.md) for everything a disabled query
still does.

## Dependent queries are a waterfall

The second request cannot start before the first has answered. That is
inherent to the data, but it is still two round trips; if the server can
answer both at once, one endpoint beats two queries. See [request
waterfalls](request-waterfalls.md).
