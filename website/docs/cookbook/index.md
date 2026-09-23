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

## Architecture and integration

How query_kit fits into the rest of an app: state management, injection,
routing, persistence, realtime data, devices, accounts and models.

| Recipe | What it answers |
|---|---|
| [Next to Riverpod, Bloc or Provider](riverpod-bloc-provider.md) | Server state in the cache, app state in your store, connected through `QueryController` |
| [Offline first, and surviving a restart](offline-first-and-persistence.md) | Save chosen queries and unsent writes to disk, and restore them before the first frame |
| [Where the client lives](dependency-injection.md) | One client, provided at the root, reached with `of`, `maybeOf` and `read`, and shared with get_it |
| [Routing with go_router](routing-go-router.md) | Keys from path parameters, a prefetch on tap, a refetch on return, reads in dialogs |
| [Realtime updates over a WebSocket](realtime-websockets.md) | Server events write to the cache or invalidate it, with a resync after a reconnect |
| [Poll until a device confirms](poll-until-confirmed.md) | An accepted write, a poll that starts and stops itself, and a state for giving up |
| [Disconnecting a device](device-and-iot-disconnect.md) | No request to a device the user disconnected, and no entry that comes back |
| [Sign out and multiple accounts](sign-out-and-multi-account.md) | A fresh cache per user, cleared after the screens, and accounts kept apart by prefix |
| [Normalised data or one key per entity](normalised-vs-per-entity-keys.md) | A list plus per-item keys, or a map by id, with unchanged items kept |
| [Models with freezed and JSON](freezed-and-json-models.md) | Value equality, and `StructurallyShareable` for a class that wraps a list |

Every sample on this site is compiled and checked against its source, so a
recipe you copy here compiles against the current release.
