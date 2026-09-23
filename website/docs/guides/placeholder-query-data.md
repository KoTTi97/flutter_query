---
title: Placeholder query data
description: PlaceholderData is shown while the real fetch runs and never written to the cache — a value, a computed placeholder, or the previous key's data.
---

{/* depth: todo */}
{/* demo: initial-and-placeholder */}

# Placeholder query data

Placeholder data is what a reader sees while the real fetch runs. Unlike
[initial data](initial-query-data.md), **it is never written to the cache**:
other readers of the key do not see it, and it is replaced by the first real
result.

| | |
|---|---|
| `PlaceholderData.value(v)` | this value |
| `PlaceholderData.compute((previous, previousQuery) => …)` | computed from what this reader showed before, and the query it came from |
| `const PlaceholderData.keepPrevious()` | the previous key's data — TanStack Query's `keepPreviousData` |

While it shows, the result is a `QuerySuccess` with `isPlaceholderData: true`,
so the screen can render the content dimmed or with a "loading" marker.

## Keeping the previous page

`keepPrevious` is for a key that changes — a page number, a search term. The
screen keeps showing the old key's data until the new key's lands, instead of
dropping back to a spinner. See [paginated queries](paginated-queries.md).

It needs the reader to survive the key change: `keepPrevious` shows what
*this observer* showed before. A builder and a controller keep their observer
across a key change; in the `context.query` and `QueryMixin` styles, give the
read an `id:` — see [four ways to read a
query](reading-queries-in-widgets.md#querymixin).

## Placeholder or initial?

| | Initial data | Placeholder data |
|---|---|---|
| Written to the cache | yes | no |
| Seen by other readers | yes | no |
| Subject to `staleTime` | yes | no — the fetch always runs |
| `isPlaceholderData` | `false` | `true` |

Use initial data when it is the real data — a copy from another cache entry.
Use placeholder data when it is only something to show — a skeleton, a
partial object, the previous page.
