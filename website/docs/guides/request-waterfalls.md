---
title: Request waterfalls
description: When one request cannot start before another has answered — where waterfalls come from in a widget tree, and how prefetching and flatter reads avoid them.
---

{/* depth: todo */}
{/* demo: prefetching */}

# Request waterfalls

A waterfall is a request that could have started earlier but waited for
another one to finish. Each step adds a full round trip, and on a phone
network a round trip is what the user waits for.

## Where they come from

- **Dependent queries.** The second query needs the first one's result — the
  comments of a post you have not loaded. That one is in the data; see
  [dependent queries](dependent-queries.md).
- **Nested widgets.** A parent reads its query and shows a spinner; only when
  its data arrives does it build the child, and only then does the child's
  query start. Neither request needed the other, but the tree made them
  wait.
- **Code the user has to navigate to.** The detail screen's query starts
  when the route is built, after the tap.

## Avoiding them

- **Read where you can.** Queries that do not depend on each other and are
  read in the same `build` run in parallel; see [parallel
  queries](parallel-queries.md).
- **Prefetch in the parent.** A parent that knows its child will read a query
  can start it with `client.query(options).ignore()` while it loads its own —
  the child then joins the fetch in flight or finds the data cached. See
  [prefetching](prefetching.md).
- **Prefetch on intent.** Start the detail screen's query when the row is
  tapped — before the route builds — or as it scrolls into view.
- **Ask the server once.** When two queries always go together and the server
  can answer both in one response, one query is better than two.
