---
title: API reference
description: Where the generated dartdoc lives, and how to build it locally.
---

{/* depth: todo */}

# API reference

The API reference is **generated from the source**, not written twice. Every
public member of both packages carries a dartdoc comment.

## On pub.dev

pub.dev builds and hosts the reference for every published version:

- [pub.dev/documentation/query_kit](https://pub.dev/documentation/query_kit/latest/)
- [pub.dev/documentation/query_kit_flutter](https://pub.dev/documentation/query_kit_flutter/latest/)

## Locally

`dart doc` in a package's directory writes the same reference to `doc/api/`;
open `doc/api/index.html`. For a package in your pub cache, run it there.

## Where to start reading

| If you want | Start at |
|---|---|
| the whole imperative surface | `QueryClient` |
| what a widget is handed | `QueryResult`, and its `QueryPending` / `QuerySuccess` / `QueryError` cases |
| every option and what unset means | `QueryObserverOptions` and `QuerySelectOptions`, then the sealed value types — `StaleTime`, `GcTime`, `Enabled`, `RetryPolicy`, `RetryDelay`, `RefetchOn`, `RefetchInterval` |
| paging | `InfiniteQueryOptions`, `InfiniteData`, `InfiniteQueryObserver` |
| writes | `MutationOptions`, `MutationResult`, `MutationObserver` |
| the caches | `QueryCache`, `MutationCache`, `QueryFilters`, `MutationFilters` |
| the Flutter side | `QueryClientProvider`, `QueryController`, `QueryBuilder`, `QueryMixin`, and the `context.query` extension |
| widget tests | nothing exported: the teardown is a documented snippet, see [Testing](../guides/testing.md) |

## Beyond signatures

- [Feature matrix](feature-matrix.md) — what exists, per TanStack Query
  feature.
- [Differences from TanStack Query](differences-from-tanstack.md) — where the
  behaviour differs, and why.
- [Troubleshooting](troubleshooting.md) — symptoms, causes and fixes.
- [Coming from React Query](../coming-from-react-query.md) — the name map.
