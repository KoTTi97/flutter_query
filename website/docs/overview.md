---
title: Overview
description: What query_kit is, the server-state problem it solves, what reading a query looks like in Flutter, and who it is for.
---

# Overview

query_kit fetches, caches and updates the data your Dart or Flutter app gets
from a server, and keeps it fresh without you writing the plumbing. It is a
port of [TanStack Query](https://tanstack.com/query)'s `query-core` to Dart,
with a Flutter binding on top.

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

Most state management tools are good at *client* state — the selected tab, a
form's contents, the theme. Data that lives on a server is a different kind of
thing:

- it is stored somewhere you do not control, and fetched asynchronously;
- somebody else can change it without your app knowing — another phone, a
  colleague, a device reporting in;
- the copy on screen starts going out of date the moment it arrives.

Treat it like client state and every screen grows the same machinery: a
loading flag, an error flag, a cache so the second visit is not a spinner,
deduplication so five widgets do not send five requests, a refresh when the
app comes back to the foreground, retries for a flaky network, cancellation
when nobody is looking any more, garbage collection for data nobody reads,
and a way for a write to tell every screen that its copy is now wrong. That
machinery is hard to get right, and most of it is invisible until it is
wrong.

query_kit is that machinery, written once. You describe **what** a piece of
server data is — a key that names it and a function that fetches it — and the
cache decides **when** to fetch it, how long to keep it, and who is told.

## What it looks like

A smart-home app's device list, in full — the description of the data in one
file, the screen that shows it in another:

```dart snippet="overview.md#example"
// lib/data/device_queries.dart — what the data is, described once.
QueryObserverOptions<List<Device>> allDevicesQuery() => QueryObserverOptions(
      queryKey: QueryKey(<Object?>['devices']),
      queryFn: (context) => repository.devices(signal: context.signal),
    );

// lib/ui/device_list.dart — a widget that shows it.
class DeviceList extends StatelessWidget {
  const DeviceList({super.key});

  @override
  Widget build(BuildContext context) {
    return switch (context.query(allDevicesQuery())) {
      QueryPending() => const Center(child: CircularProgressIndicator()),
      QueryError(:final error) => Center(child: Text('Could not load: $error')),
      QuerySuccess(:final data) => ListView(
          children: <Widget>[
            for (final device in data) ListTile(title: Text(device.name)),
          ],
        ),
    };
  }
}
```

There is no loading flag, no `initState`, no `StreamSubscription` and no
`dispose`. The widget asks for the query in `build`; the cache fetches it,
shares it with every other widget that asks for the same key, and rebuilds
this one when the result changes.

The result is a **sealed** type, so the `switch` is exhaustive — forget the
error case and the analyzer says so — and the data is simply there, with no
`data!`. A `QueryError` also carries the last good data, which is what lets a
screen keep showing the list above a "could not refresh" banner.

`context.query` is one of [four equal ways](guides/reading-queries-in-widgets.md)
to read a query: a builder widget, a `State` mixin and a plain
`ValueListenable` are the other three, and this documentation names no
default.

:::note[In React Query]
This is `useQuery({ queryKey, queryFn })`. The options become a
`QueryObserverOptions` value you can name and reuse, and the result a sealed
class instead of `status` strings with optional fields. See [differences from
TanStack Query](reference/differences-from-tanstack.md).
:::

Here is one query running in your browser — the showcase's *simple* screen,
against an in-memory backend. Press the refresh icon and watch the data stay on
screen while the *refreshing* pill shows the background refetch:

<LiveDemo feature="simple" />

## What you get without writing it

- **One request for many readers.** Read the same query in five widgets and
  the cache sends one request.
- **Stale-while-revalidate.** A second visit renders from the cache at once
  and refetches behind it when the data is older than its `staleTime`.
- **Refetch on return and on reconnect.** When the app comes back to the
  foreground, stale queries on screen are refreshed; connectivity is yours to
  plug in, [with any package](guides/connectivity.md).
- **Retries** with exponential backoff, and **cancellation** of requests
  nobody is waiting for any more — once the query function hands its cancel
  token to the HTTP client.
- **Garbage collection** of entries that nothing has shown for five minutes.
- **Mutations** with optimistic updates and rollback, and invalidation that
  refetches what a write made stale.
- **Pagination and infinite lists** that page in both directions.
- **Testability.** A client is an object, not a global, and time goes through
  `package:clock`, so a test controls staleness and garbage collection
  completely.

[Important defaults](important-defaults.md) says which of these happen out of
the box and how to change each one.

## Who it is for

- **Flutter apps that talk to a backend** — REST, GraphQL, gRPC, Firebase
  callables, a local device API: anything that returns a `Future`. The query
  function is yours, so the transport is too.
- **Teams already using a state management package.** query_kit handles
  server state and nothing else; `provider`, `riverpod`, `bloc` or plain
  `setState` keep the client state. A controller is a plain `ValueListenable`,
  so it drops into any of them. See [does this replace state
  management?](guides/does-this-replace-state-management.md)
- **Pure Dart code.** A CLI, a server, a shared data package: the core has no
  Flutter in it. See [using the core without Flutter](guides/pure-dart.md).
- **Developers who know TanStack Query.** The concepts, option names and
  behaviour carry over; [the name map](coming-from-react-query.md) lists what
  is spelled differently.

It is not a networking library (bring dio, `package:http` or anything else),
not a database or an offline store, and not a replacement for the state that
lives only in your app.

## A port, checked against the original

The behaviour is TanStack Query's, and TanStack Query's own tests say so: the
bulk of its core test suite was ported to Dart and runs against this code, and
every upstream case that was not ported is listed with the reason. Where the port
deliberately behaves differently — mostly because Dart has sealed types,
value equality and no `undefined` — the difference is written down: see
[differences from TanStack Query](reference/differences-from-tanstack.md) and
[how fidelity is proven](project/fidelity.md).

## Where to go next

- [Installation](installation.md), then the [quick start](quick-start.md) —
  a provider, a first query and a first write, in four steps.
- [Important defaults](important-defaults.md) — read this before a refetch
  surprises you.
- [Queries](guides/queries.md), [query keys](guides/query-keys.md) and [query
  functions](guides/query-functions.md) — the three ideas everything else
  builds on.
- Coming from JavaScript? [The name map](coming-from-react-query.md) is the
  fastest route in.
- Wondering whether something is here at all? [The feature
  matrix](reference/feature-matrix.md) says what is out and why.
- Something behaves in a way you did not expect?
  [Troubleshooting](reference/troubleshooting.md) is symptom first.
