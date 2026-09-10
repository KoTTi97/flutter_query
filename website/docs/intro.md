---
id: intro
title: What this is
sidebar_position: 1
slug: /
description: A Dart port of TanStack Query's query-core, with a Flutter binding, proven by running upstream's own test suite.
---

# What this is

A Dart port of [TanStack Query](https://tanstack.com/query)'s `query-core`,
with a Flutter binding on top.

- **`query_kit`** — the cache: staleness, background refetching, retries,
  cancellation, mutations, infinite queries. Pure Dart, no Flutter.
- **`query_kit_flutter`** — the binding: a provider, listenable controllers,
  builder widgets, a `State` mixin and `context.query(...)`. No dependency
  beyond Flutter itself.

:::danger Read this first
This is a **port** of TanStack Query, published with gratitude under upstream's
MIT licence — and it is **not affiliated with, endorsed by, or connected in any
way to** Tanner Linsley, the TanStack team, or the TanStack organisation.
Problems with this package belong in
[this repository's issues](https://github.com/KoTTi97/flutter_query/issues),
never theirs.

It is also an **AI-written project**: effectively all of the code, tests and
documentation here were written by AI agents, with a human in the loop only
rarely.

Both of those deserve more than a line — [credits, and what this is
not](project/credits.md).
:::

## The bet

Several Dart packages cover the *idea* of TanStack Query. This one ports the
behaviour and then ports upstream's test suite against it, case for case,
keeping upstream's test names so the two files diff against each other.

That is the whole differentiator, and it is checkable:

|  |  |
|---|---|
| **549** tests in the core | run on the Dart VM *and* compiled to JavaScript |
| **84** widget tests in the binding | four call styles, each proven to interoperate |
| **215** tests across the two examples | plus **155** Playwright tests in a real browser |
| **22** bugs found by porting | none of which a test written from the Dart side would have caught |
| **every omission listed by name** | in [`PORTING_NOTES.md`](https://github.com/KoTTi97/flutter_query/blob/main/packages/query_kit/test/PORTING_NOTES.md) |

Upstream is pinned at `50680b98c`. When a ported test fails, the assumption is
that the port is wrong, not the test — see [how fidelity is
proven](project/fidelity.md).

## What it looks like

```dart
class TaskScreen extends StatelessWidget {
  const TaskScreen(this.id, {super.key});

  final String id;

  @override
  Widget build(BuildContext context) {
    final task = context.query(taskQuery(id));
    return switch (task) {
      QueryPending() => const CircularProgressIndicator(),
      QuerySuccess(:final data) => TaskCard(data),
      QueryError(:final error, :final staleData) => ErrorBanner(error, staleData),
    };
  }
}
```

The result is a **sealed** type, so the `switch` is exhaustive and the data is
simply there — no `data!`. A `QueryError` still carries the last good data,
which is what makes stale-while-revalidate readable.

That is one of [four equal ways](guides/reading-a-query.md) to read a query.
The documentation names no default.

## Where to go next

- [Installation](getting-started/installation.md), then [your first
  query](getting-started/first-query.md).
- Coming from JavaScript? [The name map](reference/coming-from-react-query.md)
  is the fastest route in.
- Wondering whether something is here at all? [The feature
  matrix](reference/feature-matrix.md) says what is out and why.
