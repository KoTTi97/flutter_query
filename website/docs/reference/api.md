---
title: API reference
description: One page per main surface of query_kit and query_kit_flutter — every option, field and member with its type, default and TanStack Query name — plus where the generated dartdoc lives.
---

# API reference

These pages list the public surface a user touches, one page per surface, in
tables: every option, field and member with its type, its default and what it
does, and the name it has in TanStack Query. Each row links to the generated
dartdoc, which has the full signature and the longer explanation.

| Page | What it covers |
|---|---|
| [QueryClient](query-client.md) | The client: fetching, reading and writing the cache, operating on many queries at once, defaults, mounting and clearing. |
| [Options](query-options.md) | `QueryOptions`, `QueryObserverOptions`, the infinite and mutation options — every field — and the sealed option values (`StaleTime`, `GcTime`, `RetryPolicy`, `RefetchOn`, …). |
| [Results](results.md) | What a reader is handed: `QueryResult` and its three cases, `QueryState`, `InfiniteData` and the paging flags, `MutationResult`, `MutationState`, `CombinedResult`. |
| [Widgets and controllers](widgets-and-controllers.md) | The Flutter binding: `QueryClientProvider`, the four call styles, listeners, collections, `OnlineStatus`. |
| [Caches and observers](caches-and-observers.md) | `QueryCache` and `MutationCache` with their events, `Query` and `Mutation`, the observers, the filters, and the focus, online and notify managers. |
| [Errors](errors.md) | Every error either package throws or records, and every check a debug build runs. |

A typical app touches them in that order: it builds a [client](query-client.md)
with some defaults, describes its queries with [options](query-options.md),
reads [results](results.md) through [a widget or a
controller](widgets-and-controllers.md), and looks at the
[caches](caches-and-observers.md) and [errors](errors.md) when something
needs explaining.

## The generated dartdoc

Every public member of both packages carries a dartdoc comment, and pub.dev
builds and hosts the reference for every published version:

- [pub.dev/documentation/query_kit](https://pub.dev/documentation/query_kit/latest/)
  — the core: client, caches, observers, options, results.
- [pub.dev/documentation/query_kit_flutter](https://pub.dev/documentation/query_kit_flutter/latest/)
  — the binding. It re-exports the core, so an app imports only this one.

`dart doc` in a package's directory writes the same reference to `doc/api/`;
open `doc/api/index.html`. For a package in your pub cache, run it there.

## Where to start reading

| If you want | Start at |
|---|---|
| the whole imperative surface | [`QueryClient`](query-client.md) |
| what a widget is handed | [`QueryResult`](results.md#queryresult), and its `QueryPending` / `QuerySuccess` / `QueryError` cases |
| every option and what unset means | [the options](query-options.md), then [the option values](query-options.md#option-values) |
| paging | [the infinite fields](query-options.md#infinite-query-fields), [`InfiniteData`](results.md#infinitedata), [`InfiniteQueryObserver`](caches-and-observers.md#infinitequeryobserver) |
| writes | [the mutation fields](query-options.md#mutation-fields), [`MutationResult`](results.md#mutationresult), [`MutationController`](widgets-and-controllers.md#mutationcontroller) |
| the caches | [`QueryCache`](caches-and-observers.md#querycache), [`MutationCache`](caches-and-observers.md#mutationcache), [filters](caches-and-observers.md#filters) |
| the Flutter side | [`QueryClientProvider`](widgets-and-controllers.md#queryclientprovider) and [the four call styles](widgets-and-controllers.md#the-four-call-styles-at-a-glance) |
| widget tests | nothing exported: the teardown is a documented snippet, see [Testing](../guides/testing.md) |

## Beyond signatures

- [Feature matrix](feature-matrix.md) — what exists, per TanStack Query
  feature.
- [Differences from TanStack Query](differences-from-tanstack.md) — where the
  behaviour differs, and why.
- [Troubleshooting](troubleshooting.md) — symptoms, causes and fixes.
- [Coming from React Query](../coming-from-react-query.md) — the name map.

:::note[In React Query]
TanStack Query's React reference is generated, one page per function, class
and interface: `useQuery`, `QueryClient`, `QueryCache`, `QueryObserverOptions`,
`QueryObserverSuccessResult` and so on. Here the pages group by surface
instead, and the options and the results have a page each, because the four
call styles share them.
:::
