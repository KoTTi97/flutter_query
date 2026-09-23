---
title: Important defaults
description: What the cache does out of the box — stale at once, kept five minutes, retried three times, refetched on return to the app — and how to change each default.
---

# Important defaults

Out of the box, query_kit is configured with **aggressive but sane** defaults
— the same numbers TanStack Query uses. They keep data fresh without any
configuration, and every one of them can surprise you once: a refetch you did
not ask for, an error that took seven seconds to appear, an entry that is
gone when you come back after lunch. This page lists them, says why each one
is what it is, and shows how to change it.

## At a glance

| What | Default | Change it with |
|---|---|---|
| How long data counts as fresh | `StaleTime.zero` — stale at once | `staleTime` |
| Refetch when a reader mounts | if stale | `refetchOnMount` |
| Refetch when the app returns to the foreground | if stale | `refetchOnWindowFocus`, the provider's `isAppShown` |
| Refetch when the network comes back | if stale — but nothing reports the network by default | `refetchOnReconnect`, the provider's `onlineStatus` |
| Polling | off | `refetchInterval`, `refetchIntervalInBackground` |
| How long an unused entry stays cached | `GcTime.defaultValue` — five minutes | `gcTime` |
| Retries of a failed query | three, 1 s → 2 s → 4 s apart | `retry`, `retryDelay` |
| Retries of a failed mutation | none | `retry` on the mutation or the mutation defaults |
| Unchanged data after a refetch | keeps its old instances | `structuralSharing` |
| Fetching while offline | paused until online | `networkMode` |

## Queries

### Cached data is stale at once

`staleTime` defaults to `StaleTime.zero`: data counts as stale the moment it
arrives. Stale does not mean hidden — stale data is shown like any other; it
only means the next *trigger* below refetches it in the background.

A longer `staleTime` is the first thing most apps change, and the one with
the biggest effect: data that is fresh is read from the cache without asking
anybody, however many screens read it. Three values do more than a duration:

- **`StaleTime.infinite`** — never stale by time. Nothing refetches it on its
  own, but an [invalidation](guides/query-invalidation.md) still does. For
  data only your own writes change — the invalidation after the write is then
  the only refresh.
- **`StaleTime.static`** — never stale and, while a widget reads it, never
  refetched by any trigger, invalidation included; only an explicit
  `refetch()` or a `refetchInterval` fetches it. For data that cannot change
  while the app runs: a feature-flag set fetched at start-up, reference
  tables.
- **`StaleTime.dynamic((query) => …)`** — computed per query, from its state.

### Stale queries refetch on three triggers

A stale query that a widget is reading is refetched in the background when:

- **another reader mounts** — a second screen opens on the same key
  (`refetchOnMount`);
- **the app returns to the foreground** (`refetchOnWindowFocus`);
- **the network comes back** (`refetchOnReconnect`).

All three default to `RefetchOn.ifStale`. `RefetchOn.always` refetches even
fresh data, `RefetchOn.never` switches the trigger off, and
`RefetchOn.when((query) => …)` decides per query. A query with
`NetworkMode.always` defaults to `RefetchOn.never` on reconnect: it never
waited for the network in the first place.

If a refetch surprises you, it was one of these three. The usual fix is not
to switch a trigger off but to give the data a `staleTime` it deserves.

### No polling

`refetchInterval` defaults to `RefetchInterval.off`. An interval you switch on
refetches whether the data is stale or not, and pauses while the app is in the
background unless `refetchIntervalInBackground` is `true`. See
[polling](guides/polling.md).

### Unused data is kept for five minutes

A query nothing reads any more — every widget that showed it is gone — stays
in the cache for `gcTime`, `GcTime.defaultValue`, which is five minutes, and is
then garbage collected. A screen that comes back within that time renders at
once from the cache (and refetches behind it, if stale). `GcTime.never` keeps
an entry until you remove it or clear the client.

`staleTime` and `gcTime` answer different questions — *when do I ask again?*
and *when do I forget?* — and the showcase's *stale and gc* screen sets each
one live. Pick `5 s` under *Stale time* and watch `isStale` flip five seconds
after a fetch; press the *Detach reader* icon with GC time `5 s` and watch the
strip turn to `status=absent` five seconds later. `static` ignores the
*Invalidate* icon; `infinite` does not:

<LiveDemo feature="stale-and-gc" />

### A failed query is retried three times

Before an error reaches the screen, a failed query is retried **three times**
— `RetryPolicy.times(3)`, four attempts in all — with `RetryDelay.defaultValue`
between them: one second, then two, then four, doubling up to a cap of thirty
seconds. So the first error of a query against a server that is down appears
about seven seconds after the first attempt.

While it retries, the result stays what it was — pending, or the old data —
with `failureCount` and `failureReason` telling you it is struggling. A query
that failed is also retried when a new reader mounts (`retryOnMount`,
default `true`). See [query retries](guides/query-retries.md).

### Unchanged data keeps its instances

After a refetch, the new data is compared with the cached data and every part
that is deep-equal keeps the **cached instance** — `replaceEqualDeep`. A
refetch that brings back the same list hands every reader the identical
object, so nothing rebuilds for it. Lists, maps and sets are walked; your own
classes are compared with their `==`, so give model classes value equality
(by hand, `equatable` or `freezed`) or each refetch renews them. Switch it off
per query with `structuralSharing: noStructuralSharing()`. See [structural
sharing](guides/structural-sharing.md).

### Queries wait for the network

`networkMode` defaults to `NetworkMode.online`: while the client believes it
is offline, a fetch does not start — the query is *paused*, and resumes when
the network comes back. Since nothing reports the network by default (see
below), the client believes it is online until you [tell it
otherwise](guides/connectivity.md). See [network mode](guides/network-mode.md).

## Mutations

- **Mutations are not retried.** `retry` defaults to `RetryPolicy.never`: a
  write that half-happened is not safe to send again blindly. Opt in, per
  mutation or in the client's mutation defaults, for writes that are
  idempotent.
- **A mutation started offline is paused**, not failed, and resumes when the
  client learns it is back online — the same `NetworkMode.online` default.
- **A finished mutation is kept for five minutes**, so cache-wide
  [mutation state](guides/mutation-state.md) can still see it.

## The client and the app

- **Create the client once.** A `QueryClient` *is* the cache. Build it at
  start-up, outside any `build` method: a client built in `build` is a new,
  empty cache on every rebuild. The client, its focus manager and its online
  manager are objects, not globals, so two clients in one process — two
  widget tests — never see each other.
- **The provider wires the client to the app, and does not dispose it.**
  `QueryClientProvider` mounts the client it is given: it maps the app
  lifecycle onto focus and makes listener notifications safe during a build.
  `client.clear()` stays yours to call; `QueryClientProvider.create` builds a
  client and clears it when the provider goes.
- **Focus follows the app lifecycle.** `resumed` counts as focused; `hidden`,
  `paused` and `detached` do not. `inactive` counts as focused on iOS and
  Android, where it is a passing interruption — the notification shade, a
  call — and as unfocused on macOS, Windows and Linux, where it means the
  window lost focus. See [app focus and
  refetching](guides/window-focus-refetching.md).
- **No connectivity source is installed.** The core ships no network check and
  the binding depends on no connectivity package, so a client assumes it is
  online, and `refetchOnReconnect` never fires, until you pass the provider an
  `onlineStatus`. See [connectivity](guides/connectivity.md).
- **An imperative `client.query` makes one attempt.** The three retries above
  are for queries a widget reads. A one-off fetch or prefetch that configures
  no `retry` — in its options or in any defaults — does not retry. See
  [prefetching](guides/prefetching.md).

## Changing a default

Every default can be set at three levels, and a field set closer to the query
wins: **the query's own options**, then **defaults for a key prefix**, then
**defaults for the whole client**, then the built-in value. A field you leave
`null` is "not configured" and falls through to the next level.

For the whole app, pass `defaultOptions` to the client:

```dart snippet="important-defaults.md#client-defaults"
// lib/main.dart
final QueryClient queryClient = QueryClient(
  defaultOptions: const DefaultOptions(
    queries: QueryDefaults(
      // Fresh for 30 seconds: a second screen within that time reads the
      // cache and asks nobody.
      staleTime: StaleTime.duration(Duration(seconds: 30)),
      // One retry, not three, before the error reaches the screen.
      retry: RetryPolicy.times(1),
    ),
    mutations: MutationDefaults(
      // Our writes are idempotent PUTs, so sending one twice is safe.
      retry: RetryPolicy.times(2),
    ),
  ),
);
```

For a family of keys, register defaults under their common prefix — every
query whose key starts with `['energy']` picks them up:

```dart snippet="important-defaults.md#key-defaults"
// Live readings: refetched on every return to the app, and dropped soon
// after no screen shows them.
client.setQueryDefaults(
  QueryKey(<Object?>['energy']),
  const QueryDefaults(
    refetchOnWindowFocus: RefetchOn.always,
    gcTime: GcTime.duration(Duration(seconds: 30)),
  ),
);
```

For one query, set the field in its options:

```dart snippet="important-defaults.md#per-query"
QueryObserverOptions<Firmware> firmwareQuery(String deviceId) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.firmware(deviceId),
      queryFn: (context) =>
          repository.firmware(deviceId, signal: context.signal),
      // Only an update changes it, and the update invalidates this key.
      staleTime: StaleTime.infinite,
      // Coming back to the app is no reason to ask again.
      refetchOnWindowFocus: RefetchOn.never,
    );
```

`client.setDefaultOptions(...)` replaces the client-wide defaults later; the
next build of each reader picks them up. The showcase's *playground* screen
does exactly that — its *Stale time* and *GC time* knobs call
`setDefaultOptions`. Set *Error rate* to `100 %` and press the refresh icon
on *Todos* to watch `failureCount` climb through the retries, or pick *Stale
time* `30 s` and see `isStale=false` hold with no fetch:

<LiveDemo feature="playground" height={720} />

The app-lifecycle mapping is the provider's to change. To count only a fully
resumed app as focused, on every platform:

```dart snippet="important-defaults.md#app-shown"
QueryClientProvider(
  client: queryClient,
  // Only a fully resumed app counts as focused, on every platform.
  isAppShown: (state) => state == AppLifecycleState.resumed,
  child: app,
)
```

:::note[In React Query]
These are TanStack Query's [important
defaults](https://tanstack.com/query/latest/docs/framework/react/guides/important-defaults),
with the same numbers. What differs is the spelling — sealed values like
`StaleTime.infinite` and `RefetchOn.ifStale` for `Infinity` and `true` — and
the source of focus and connectivity: the app lifecycle instead of the
browser's `visibilitychange`, and no online listener until you install one.
See [differences from TanStack Query](reference/differences-from-tanstack.md).
:::

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

:::warning[In Flutter, the provider owns this]
`QueryClientProvider` mounts the client it is given and unmounts it again when
it goes. That count is what keeps focus and reconnect refetches wired, so **an
extra `unmount()` of your own unbalances it** and the client stops listening to
either. Call `unmount()` only to balance a `mount()` you made yourself.
:::

## Further reading

The [caching walkthrough](guides/caching.md) follows one query through these
defaults step by step, and [default query
function](guides/default-query-function.md) shows key defaults carrying a
shared `queryFn`.
