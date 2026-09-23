---
title: Cookbook
description: Recipes for tasks that combine several features — each one a complete, compiled answer to "how do I…".
sidebar_position: 0
sidebar_class_name: qk-sidebar-hidden
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

Every sample on this site is compiled and checked against its source, so a
recipe you copy here compiles against the current release. The few that need
`dio`, `package:http` or `connectivity_plus` — packages this library does not
depend on — say so above the code.
