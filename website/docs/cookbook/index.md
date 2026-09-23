---
title: Cookbook
description: Recipes for tasks that combine several features — each one a complete, compiled answer to "how do I…".
---

# Cookbook

The guides explain one concept each. A recipe starts from a task instead —
"refresh a token once for every request that hit it", "load the next page
before the user reaches the end" — and puts together the pieces it needs, as
complete code in the shape of an app: which file each part lives in, what
each step does, the traps, and the variations.

The recipes below build one small app between them — a product catalogue with
a list, a search, a detail screen, an edit form and an endless feed — so the
code on one page is the code the next page uses.

## Data and networking

| Recipe | What it answers |
|---|---|
| [Wiring dio or package:http](wiring-dio-and-http.md) | One API client: cancellation handed to the transport, timeouts, readable errors |
| [Auth and token refresh](auth-and-token-refresh.md) | Refresh a token once, retry only what can succeed, a cache per signed-in user |
| [List to detail, seeded](list-detail-seeding.md) | Open a detail screen with the data the list already has |
| [Lifecycle and connectivity wiring](lifecycle-and-connectivity-wiring.md) | `connectivity_plus`, a reachability probe, calmer focus refetches, an offline switch |

## UI patterns

| Recipe | What it answers |
|---|---|
| [Pull to refresh](pull-to-refresh.md) | A `RefreshIndicator` that lasts as long as the refetch and keeps the list on failure |
| [Search as you type](search-as-you-type.md) | Debounced, cancelled when superseded, the last results kept while the next load |
| [Forms and server validation](forms-and-server-validation.md) | A mutation-driven form with the server's field errors next to the fields |
| [A global error snackbar](global-error-snackbar.md) | One toast for failed refreshes and saves, and a per-query way out |
| [An infinite list view](infinite-list-view.md) | Load the next page near the end, once per page, with a footer for the rest |

## Testing

| Recipe | What it answers |
|---|---|
| [Testing a screen](testing-a-screen.md) | A fake API with latency, a harness with the teardown, and tests that step fake time |

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
| [Disconnecting a device](device-and-iot-disconnect.md) | No request to a device the user disconnected, and no old reading left in the cache |
| [Sign out and multiple accounts](sign-out-and-multi-account.md) | A fresh cache per user, cleared after the screens, and accounts kept apart by prefix |
| [Normalised data or one key per entity](normalised-vs-per-entity-keys.md) | A list plus per-item keys, or a map by id, with unchanged items kept |
| [Models with freezed and JSON](freezed-and-json-models.md) | Value equality, and `StructurallyShareable` for a class that wraps a list |

Every sample on this site is compiled and checked against its source, so a
recipe you copy here compiles against the current release. The few that need
`dio`, `package:http` or `connectivity_plus` — packages this library does not
depend on — say so above the code.
