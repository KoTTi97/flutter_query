---
title: Overview
description: What query_kit is, the server-state problem it solves, and what reading a query looks like in Flutter.
---

{/* depth: todo */}
{/* demo: simple */}

# Overview

query_kit is a Dart port of [TanStack Query](https://tanstack.com/query)'s
`query-core`, with a Flutter binding on top. It fetches, caches and updates
the data your app gets from a server, and keeps it fresh without you writing
the plumbing.

- **`query_kit`** — the cache: staleness, background refetching, retries,
  cancellation, mutations, infinite queries. Pure Dart, no Flutter.
- **`query_kit_flutter`** — the binding: a provider, listenable controllers,
  builder widgets, a `State` mixin and `context.query(...)`. No third-party
  dependency.

:::danger[Read this first]
query_kit is an entirely AI-coded project: all code, tests and documentation
were written by AI coding agents (Anthropic's Claude). A human maintainer set
the goals and reviews releases, but did not write the code.

It is also a **port** of TanStack Query, published with gratitude under
TanStack Query's MIT licence, and it is **not affiliated with, endorsed by, or
connected in any way to** Tanner Linsley, the TanStack team, or the TanStack
organisation. Problems with this package belong in
[this repository's issues](https://github.com/KoTTi97/flutter_query/issues),
never theirs. [Credits, and what this is not](project/credits.md) says more.
:::

## The problem: server state

Most state management tools are good at *client* state — a selected tab, a
form's contents, a theme. Data that lives on a server is a different kind of
thing:

- it is stored somewhere you do not control, and fetched asynchronously;
- somebody else can change it without your app knowing;
- the copy on screen goes out of date the moment it arrives.

Treating it like client state means writing the same machinery on every
screen: a loading flag, an error flag, a cache so the second visit is not a
spinner, deduplication so five widgets do not send five requests, a refresh
when the app comes back to the foreground, retries, cancellation when nobody
is looking any more, and garbage collection of data nobody reads. That
machinery is hard to get right, and most of it is invisible until it is
wrong.

query_kit is that machinery, written once. You describe *what* a piece of
server data is — a key and a function that fetches it — and the cache decides
*when* to fetch it, how long to keep it and who gets told.

## What it looks like

```dart snippet="guides/reading-queries-in-widgets.md#context-query"
class TaskScreen extends StatelessWidget {
  const TaskScreen(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    final task = context.query(taskQuery(id));
    return switch (task) {
      QueryPending() => const CircularProgressIndicator(),
      QuerySuccess(:final data) => TaskCard(data),
      QueryError(:final error, :final staleData) =>
        ErrorBanner(error, staleData),
    };
  }
}
```

The result is a **sealed** type, so the `switch` is exhaustive and the data is
simply there — no `data!`. A `QueryError` still carries the last good data,
which is what makes stale-while-revalidate readable.

That is one of [four equal ways](guides/reading-queries-in-widgets.md) to read
a query. The documentation names no default.

## What you get without writing it

- **One request for many readers.** Read the same query in five widgets and
  the cache sends one request.
- **Stale-while-revalidate.** A second visit renders from the cache at once
  and refetches behind it when the data is older than its `staleTime`.
- **Refetch on focus and on reconnect**, retries with exponential backoff, and
  garbage collection of entries nobody is watching.
- **Mutations** with optimistic updates and rollback, and invalidation that
  refetches what a write made stale.
- **Infinite queries** that page in both directions.

## A port, checked against the original

The behaviour is TanStack Query's, and TanStack Query's own test suite —
ported to Dart case by case, with every case left out listed and explained —
is run against it. Where the port deliberately differs, the difference is
written down: see [differences from TanStack
Query](reference/differences-from-tanstack.md) and [how fidelity is
proven](project/fidelity.md).

## Where to go next

- [Installation](installation.md), then the [quick start](quick-start.md).
- [Important defaults](important-defaults.md) — read this before you are
  surprised by a refetch.
- Coming from JavaScript? [The name map](coming-from-react-query.md) is the
  fastest route in.
- Wondering whether something is here at all? [The feature
  matrix](reference/feature-matrix.md) says what is out and why.
- Something behaves in a way you did not expect?
  [Troubleshooting](reference/troubleshooting.md) is symptom first.
