---
title: Cookbook
description: Recipes for tasks that combine several features — each one a complete, compiled answer to "how do I…".
---

{/* depth: todo */}

# Cookbook

The guides explain one concept each. A recipe starts from a task instead —
"show a toast when a background refresh fails", "stop polling a device that
has gone away" — and puts together the pieces it needs, as complete code.

These guide sections answer the most common tasks directly:

| Task | Where |
|---|---|
| One error toast for every failed refresh | [Global callbacks](../guides/global-callbacks.md) |
| A thin progress bar while anything is fetching | [Background fetching indicators](../guides/background-fetching-indicators.md) |
| Update a row before the server confirms | [Optimistic updates](../guides/optimistic-updates.md) |
| Stop polling after five failures in a row | [Polling](../guides/polling.md#giving-up-after-failures) |
| Pause polling while a write is in flight | [Polling](../guides/polling.md#pausing-a-poll) |
| Stop talking to a device that disconnected | [Query cancellation](../guides/query-cancellation.md#disconnecting-a-device) |
| A search box that fetches only once something is typed | [Disabling queries](../guides/disabling-queries.md#lazy-queries) |
| Seed a detail screen from the list it came from | [Initial query data](../guides/initial-query-data.md#seeding-a-detail-from-a-list) |
| Keep the old page on screen while the next loads | [Paginated queries](../guides/paginated-queries.md) |
| Load more as the user scrolls | [Infinite queries](../guides/infinite-queries.md#scroll-triggered-loading) |
| Follow the device's connectivity | [Connectivity](../guides/connectivity.md) |
| Widget tests that end cleanly | [Testing](../guides/testing.md) |

Every sample on this site is compiled and checked against its source, so a
recipe you copy here compiles against the current release.
