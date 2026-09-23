---
title: App focus refetching
description: Stale queries refetch when the user comes back to the app — how Flutter's app lifecycle becomes focus on phones, desktop and the web, how to turn it off or narrow it, and how to bring your own focus source.
---

# App focus refetching

A user switches to another app, answers a message, comes back five minutes
later. The device list on screen is five minutes old, and the thermostat it
shows may have been turned down in the meantime. When the app returns to the
foreground, every query that has a reader and stale data refetches — the
data stays on screen while it does (see
[background fetching indicators](background-fetching-indicators.md)).

That is `refetchOnWindowFocus`, and it takes a `RefetchOn`:

| `RefetchOn` | When the app comes back |
|---|---|
| `RefetchOn.ifStale` | the default: refetch if the data is stale |
| `RefetchOn.always` | refetch even if the data is fresh |
| `RefetchOn.never` | do not refetch |
| `RefetchOn.when((query) => …)` | decide per query, at that moment; return one of the other three |

Only queries with at least one reader are refetched. An entry whose screen
is gone waits in the cache until something reads it again, and the
[`refetchOnMount`](caching.md) rule decides then. The same `RefetchOn` type
drives `refetchOnMount` and `refetchOnReconnect`.

With the default `staleTime` of zero, every return refetches every screen's
data. A `staleTime` is the usual way to make that rarer — data younger than it
is fresh and skipped. See [important defaults](../important-defaults.md).

Try it: in the screen below, set entry A's *On focus* to `ifStale`, turn
*App focused* off and on again, and watch `serial=` grow by one; set it to
`never` and the same round trip leaves it alone.

<LiveDemo feature="focus-refetch" height={640} />

## Turning it off

For every query, in the client's defaults:

```dart snippet="guides/window-focus-refetching.md#disable-globally"
QueryClient clientWithoutFocusRefetch() => QueryClient(
      defaultOptions: const DefaultOptions(
        queries: QueryDefaults(refetchOnWindowFocus: RefetchOn.never),
      ),
    );
```

For one query, in its options:

```dart snippet="guides/window-focus-refetching.md#per-query"
// The settings form copies the device into its fields once. A refetch on
// return would not change what the user typed, but it would make the
// "discard changes" button compare against a newer device than the form.
QueryObserverOptions<Device> deviceSettingsQuery(String id) =>
    QueryObserverOptions(
      queryKey: DeviceKeys.detail(id),
      queryFn: (context) => deviceRepository.byId(id, signal: context.signal),
      refetchOnWindowFocus: RefetchOn.never,
    );
```

An option set on the query wins over the client's default; see
[query options](query-options.md).

### A rule of your own

`RefetchOn.when` is asked per query each time the app comes back. Here, a
return refetches only data older than a minute, whatever `staleTime` says
for everything else:

```dart snippet="guides/window-focus-refetching.md#when"
const RefetchOn refetchIfOlderThanAMinute = RefetchOn.when(_olderThanAMinute);

RefetchOn _olderThanAMinute(Query<Object?> query) =>
    query.isStaleByTime(const StaleTime.duration(Duration(minutes: 1)))
        ? RefetchOn.always
        : RefetchOn.never;
```

A top-level function keeps the value `const`, so the options compare equal
on every rebuild; an inline closure is a new value each time. See
[describing a query once](query-options.md#options-built-in-build-are-fine).

## What "focused" means in Flutter

A browser tab has one focus event. A Flutter app has an
`AppLifecycleState`, and `QueryClientProvider` maps every state the app
reports onto the client's focus while it is mounted:

| `AppLifecycleState` | Focused? |
|---|---|
| `resumed` | yes |
| `inactive` | **depends on the platform** — see below |
| `hidden`, `paused`, `detached` | no |

`inactive` means two different things:

- On **iOS, Android and Fuchsia** it is a short interruption: the
  notification shade pulled down, a system dialog, the app switcher, an
  incoming call. The app counts as **focused** — treating each of those as a
  departure would refetch everything on the way back from a glance.
- On **macOS, Windows and Linux** it is the window losing focus to another
  window, which is exactly the event this option is named after. The app
  counts as **unfocused**.

**On the web**, Flutter reports `inactive` when the browser window loses
focus and `hidden` when the tab is hidden, and the platform is the one the
browser runs on. A desktop browser therefore refetches when its window comes
back to the front, and a phone's browser when the tab is shown again.

Without a provider — a pure-Dart client, or a widget test that builds none —
nothing sets focus and the client counts as focused forever; see
[the mount contract](../important-defaults.md#the-mount-contract).

### Your own mapping

`isAppShown` replaces the mapping, for an app whose idea of "looking at it"
differs from the platform's:

```dart snippet="guides/window-focus-refetching.md#is-app-shown"
QueryClientProvider(
  client: client,
  // Only a fully resumed app counts as focused, on every platform.
  isAppShown: (state) => state == AppLifecycleState.resumed,
  child: const MyApp(),
),
```

The mapping given on the latest build is the one in force; changing it needs
no new client.

### Your own focus source

Some apps know better than the lifecycle — a desktop app with several
windows, a kiosk that counts "someone is standing in front of it" as focus.
The client's focus manager takes an adapter over any source:

```dart snippet="guides/window-focus-refetching.md#event-listener"
void followWindowFocus(QueryClient client, Stream<bool> windowFocus) {
  client.focusManager.setEventListener((setFocused) {
    final subscription = windowFocus.listen(setFocused);
    return subscription.cancel;
  });
}
```

The adapter returns its cleanup. It is removed when the client unmounts and
installed again when it mounts. `client.focusManager.setFocused(bool)` is the
same report made by hand.

**An adapter replaces the provider's lifecycle listener; it does not sit on
top of it.** Both write through `setFocused`, so with both installed the last
one to report wins and neither sees the other. Turn the lifecycle off when
you install your own:

```dart snippet="guides/window-focus-refetching.md#own-focus-source"
QueryClientProvider(
  client: client,
  // The lifecycle listener and a setEventListener adapter are two sources
  // of focus for one manager. Pick one.
  observeAppLifecycle: false,
  child: const MyApp(),
),
```

## Skipping refetches after a short absence

A phone's user leaves the app for two seconds to copy a code from a message.
Refetching every screen on the way back is wasted traffic. The focus manager
takes a threshold: an absence shorter than it does not start focus
refetches.

```dart snippet="guides/window-focus-refetching.md#min-background"
QueryClient appClient() => QueryClient(
      focusManager: AppFocusManager(
        // A glance at another app is not a reason to reload every screen.
        refetchMinBackgroundDuration: const Duration(seconds: 30),
      ),
    );
```

The default is `Duration.zero`: every return refetches. The threshold holds
back only *new* refetches. A fetch that paused while the app was in the
background — a retry waiting for focus — continues on the way back
whatever the threshold, and reconnecting is never affected. The manager
belongs to the client from construction, so the threshold is set where the
client is built.

## Focus and other timers

Focus decides two more things, both covered on their own pages:

- **Polling** skips its turns while the app is unfocused, unless
  `refetchIntervalInBackground` is set. See [polling](polling.md#in-the-background).
- **Retries** pause while the app is unfocused and continue when it comes
  back. See [query retries](query-retries.md#in-the-background).

:::note[In React Query]
`refetchOnWindowFocus` takes `true`, `false`, `'always'` or a function; here
it is `RefetchOn.ifStale`, `never`, `always` and `when`. The browser's
`visibilitychange` listener is TanStack Query's built-in focus source; here it
is the app lifecycle, installed by `QueryClientProvider`, and
`focusManager.setEventListener` has the same role as it does for a React
Native app's `AppState`. `refetchMinBackgroundDuration` has no counterpart:
TanStack Query refetches on every return. See
[differences from TanStack Query](../reference/differences-from-tanstack.md).
:::
