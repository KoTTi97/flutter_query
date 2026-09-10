---
title: API reference
sidebar_position: 3
description: Where the generated dartdoc lives, and how to build it locally before the packages are published.
---

# API reference

The API reference is **generated from the source**, not written twice. Every
public member of both packages carries a dartdoc comment, and CI runs
`dart doc --validate-links` on every push, so a broken cross-reference fails
the build rather than shipping.

## Once published

pub.dev builds and hosts the reference for every version:

- `https://pub.dev/documentation/query_kit/latest/`
- `https://pub.dev/documentation/query_kit_flutter/latest/`

Nothing is published yet, so those links are [what they will
be](../project/releasing.md), not what they are.

## Locally, today

```bash
cd packages/query_kit && dart doc
```

```bash
cd packages/query_kit_flutter && dart doc
```

The output lands in `doc/api/` (gitignored). Open `doc/api/index.html`.

## Where to start reading

| If you want | Start at |
|---|---|
| the whole imperative surface | `QueryClient` |
| what a widget is handed | `QueryResult`, and its `QueryPending` / `QuerySuccess` / `QueryError` cases |
| every option and what unset means | `QueryObserverOptions`, then `option_values.dart` for the sealed types |
| paging | `InfiniteQueryOptions`, `InfiniteData`, `InfiniteQueryObserver` |
| writes | `MutationOptions`, `MutationResult`, `MutationObserver` |
| the Flutter side | `QueryClientProvider`, `QueryController`, `QueryBuilder`, `QueryMixin`, and the `context.query` extension |
| test helpers | `package:query_kit_flutter/testing.dart` |

## The other reference

For *behaviour* rather than signatures, the ported test suite is the more
honest document: `packages/query_kit/test/` names each upstream file it came
from, keeps upstream's test names, and
[`PORTING_NOTES.md`](https://github.com/KoTTi97/flutter_query/blob/main/packages/query_kit/test/PORTING_NOTES.md)
lists every case that was *not* ported and why. See [how fidelity is
proven](../project/fidelity.md).
