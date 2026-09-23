---
title: Important defaults
description: What the cache does out of the box — stale at once, kept five minutes, retried three times, refetched on focus and reconnect — and how to change it.
---

{/* depth: todo */}
{/* demo: stale-and-gc, playground */}

# Important defaults

Out of the box, query_kit is configured with **aggressive but sane**
defaults, the same ones TanStack Query uses. They can surprise you if you do
not know them.

## Queries

- **Cached data is stale at once.** `staleTime` defaults to `StaleTime.zero`.
  Stale data is still shown — it is simply refetched behind it at the next
  opportunity. Set a `staleTime` per query, or client-wide, to change it.
- **Stale queries are refetched automatically** when:
  - a new reader of the query mounts (`refetchOnMount`),
  - the app returns to the foreground (`refetchOnWindowFocus`),
  - the device comes back online (`refetchOnReconnect`).

  All three default to `RefetchOn.ifStale`. A query with
  `NetworkMode.always` does not refetch on reconnect: it never waited for the
  network in the first place.
- **No polling.** `refetchInterval` defaults to `RefetchInterval.off`, and a
  poll you switch on stops while the app is in the background unless
  `refetchIntervalInBackground` is `true`.
- **Unused data is kept for five minutes.** When the last reader of a query
  goes, the entry stays in the cache for `gcTime` — `GcTime.defaultValue`,
  five minutes — and is then garbage collected. A reader that comes back
  within that time renders at once from the cache.
- **Failed queries are retried three times** with exponential backoff before
  the error reaches the screen: `RetryPolicy.times(3)` and
  `RetryDelay.exponential()`, which waits 1 s, 2 s, 4 s and so on, capped at
  30 s. While it retries, the result is still pending (or still shows its old
  data) and carries `failureCount` and `failureReason`.
- **Results are structurally shared.** A refetch that brings back data equal
  to what is cached keeps the cached instances, so nothing downstream sees a
  change. Your model classes need `==` and `hashCode` for that — see
  [structural sharing](guides/structural-sharing.md).

## Mutations

- **Mutations are not retried.** Their `retry` defaults to
  `RetryPolicy.never`, because a write that half-happened is not safe to send
  again blindly. Set a policy per mutation, or in the client's mutation
  defaults, when your writes are idempotent.
- **A mutation started offline is paused**, not failed, and resumes when the
  client learns it is back online.
- **A finished mutation is kept for five minutes** too, so cache-wide
  mutation state can still see it.

## The client

- **Create the client once.** A `QueryClient` holds the cache; build it at
  start-up, outside any `build` method. A client built in `build` is a new,
  empty cache on every rebuild.
- **The provider mounts the client, and does not dispose it.**
  `QueryClientProvider` wires the client to the app lifecycle while it is in
  the tree; `client.clear()` stays yours to call. `QueryClientProvider.create`
  owns a client it builds and clears it when it goes.
- **Nothing is installed for connectivity.** The client assumes it is online
  until you tell it otherwise, as TanStack Query does with no listener. See
  [connectivity](guides/connectivity.md).
- **Focus follows the app lifecycle.** `resumed` is focused; `inactive` is
  focused on phones and unfocused on desktops. See [app focus and
  refetching](guides/window-focus-refetching.md).
- **Focus, online and notification managers belong to the client.**
  `client.focusManager`, `client.onlineManager` and `client.notifyManager` are
  instances, not module-level singletons as in JavaScript, so two clients in
  one process are independent — which is what lets a widget test drive focus
  without touching its neighbours.
- **An imperative `client.query` without a retry policy makes one attempt.**
  The retry default above is for observed queries; a one-off fetch that
  configured none does not retry.

## The mount contract

Outside Flutter — or when you manage a client's life yourself — these three
calls are the whole lifecycle:

```dart snippet="important-defaults.md#mount-contract"
client.mount(); // once, at start-up
client.unmount(); // to balance your own mount()
client.clear(); // at the end: drop the caches and their timers
```

Without a mount, **nothing** reacts to the app returning to the foreground or
the device coming back online: no `refetchOnWindowFocus`, no
`refetchOnReconnect`, no resuming of paused mutations, and a `query` that
paused offline waits for a reconnect only while mounted.

:::warning In Flutter, the provider owns this
`QueryClientProvider` mounts the client it is given and unmounts it again when
it goes. That count is what keeps focus and reconnect refetches wired, so **an
extra `unmount()` of your own unbalances it** and the client stops listening to
either. Call `unmount()` only to balance a `mount()` you made yourself.
:::

## Changing a default

Every default can be changed per query, per key, or for the whole client —
see [default query function](guides/default-query-function.md) for the two
levels of defaults. What `null` means is the same everywhere: an option you
leave unset is "not configured", and the next level down decides.

## Further reading

The [caching walkthrough](guides/caching.md) follows one query through these
defaults step by step.
