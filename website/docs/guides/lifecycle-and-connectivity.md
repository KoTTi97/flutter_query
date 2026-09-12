---
title: Lifecycle and connectivity
sidebar_position: 8
description: What the provider does while it is mounted, how AppLifecycleState maps to focus per platform, and how to bring your own connectivity.
---

# Lifecycle and connectivity

`QueryClientProvider` does three things while it is mounted, and each of them
is a thing you would otherwise wire up by hand.

## App lifecycle → focus

Every lifecycle state the app reports is mapped onto the client's focus state,
which is what makes `refetchOnWindowFocus` mean anything on a phone.

| `AppLifecycleState` | Focused? |
|---|---|
| `resumed` | yes |
| `inactive` | **it depends** — see below |
| `hidden`, `paused`, `detached` | no |

:::note `inactive` means two different things
On **iOS, Android and Fuchsia**, `inactive` is a transient interruption: the
notification shade, a system dialog, the app switcher. Treating those as
"unfocused" would refetch the world on the way back, so `inactive` counts as
focused there.

On **macOS, Windows and Linux**, `inactive` is *the window lost focus* — a
different window is in front. That is exactly the case
`refetchOnWindowFocus` is named after, so `inactive` counts as **unfocused**
there.

The seam is `isAppShown`, if your app disagrees with either reading.
:::

`OnlineStatus`'s `initial` and `isAppShown` exist for the same reason: what a
`Stream` cannot tell you before its first event, and what the platform default
cannot know about your app.

### Bringing your own focus source

The client's focus manager has a seam of its own,
`client.focusManager.setEventListener(...)`, for a focus source that is not the
app lifecycle. **It is an alternative to the provider's listener, not a layer
on top of it.** Both write through `setFocused`, so with both installed the
last writer wins and neither can see the other's verdict. If you install one,
turn the other off:

```dart snippet="guides/lifecycle-and-connectivity.md#own-focus-source"
QueryClientProvider(
  client: client,
  // The lifecycle listener and a setEventListener adapter are two sources
  // of focus for one manager. Pick one.
  observeAppLifecycle: false,
  child: const MyApp(),
)
```

This is the same division upstream has: the browser's `visibilitychange`
listener is the built-in default, and `setEventListener` is what a React
Native app calls with `AppState`. Here the `AppLifecycleListener` is the
built-in default and `setEventListener` is yours.

### Suppressing pointless refetches

`AppFocusManager(refetchMinBackgroundDuration: …)` ignores a focus refetch
after an absence too short to matter — a glance at the notification shade is
not a reason to refetch the world.

This is a **divergence** from upstream, which always refetches. The default is
`Duration.zero`, which is upstream's behaviour, and it never blocks paused work
from resuming.

## A build-aware scheduler

Results are delivered right away outside a build — a tap handler or a resolved
future is where Flutter expects a `setState`, and one `pump` in a test shows
the new result — and **after** the build when they arrive inside one, so a
query resolving during a build can never call `setState` into it.

That covers the frame's build phase and the app's very first build, which
`runApp` runs outside any frame.

## Connectivity

Nothing is installed by default. The client assumes it is online — which is
what upstream does with no listener — and a fetch that cannot reach the network
simply fails and retries.

If you want link-state awareness, pass an `OnlineStatus` — one value with two
modes, the shape every option with modes has here:

| | |
|---|---|
| `OnlineStatus.fixed(online)` | this is the state, no source of changes — a test, a desktop build, a switch of your own |
| `OnlineStatus.stream(changes, initial: …)` | follow `changes`, and assume `initial` until the first event |

`initial` is **required** on the stream form, because a `Stream` has no current
value: a provider that only listens starts out believing the default — online —
however long the first event takes, and an app launched in airplane mode then
fetches once against a network that is not there. Most connectivity packages
answer the question directly.

Six lines with `connectivity_plus`, which stays **your** dependency:

```dart snippet="prose-only: needs connectivity_plus, which neither published package may depend on"
// Built once. A stream built in `build` would be a new one on every rebuild,
// and the provider would resubscribe each time.
final connectivity = Connectivity()
    .onConnectivityChanged
    .map((results) => !results.contains(ConnectivityResult.none));

QueryClientProvider(
  client: client,
  onlineStatus: OnlineStatus.stream(connectivity, initial: online),
  child: const MyApp(),
)
```

where `online` is what `Connectivity().checkConnectivity()` answered at
startup. Any `Stream<bool>` will do, single-subscription included: the provider
subscribes once per stream, and a swapped client inherits the last value the
stream reported.

With no stream at all, a fixed status is the whole verdict, and a changed one
reaches the client on the rebuild that changes it:

```dart snippet="guides/lifecycle-and-connectivity.md#fixed-online-status"
QueryClientProvider(
  client: client,
  onlineStatus: OnlineStatus.fixed(online),
  child: const MyApp(),
)
```

`null` — the default — brings nothing, and the client keeps believing it is
online.

:::warning A link is not reachability
`connectivity_plus` reports a *link*, not the internet. A phone on hotel wifi
behind a captive portal reports "connected".
:::

## Network mode

`NetworkMode` decides what a query does when the client believes it is offline:

| | |
|---|---|
| `NetworkMode.online` | the default: do not fetch; a query with nothing cached stays `pending` with `fetchStatus: paused` |
| `NetworkMode.always` | fetch regardless — for a query that does not need the network at all |
| `NetworkMode.offlineFirst` | try once, then pause instead of retrying — for a cache-backed transport that may answer offline |

A **mutation** started offline is paused rather than failed.
`client.resumePausedMutations()` releases them, and a mounted client does it
itself when the online manager flips back.

## On screen

`offline` (the online toggle, paused mutations, resuming, the mutation cache's
global callbacks) and `focus-refetch` (every `RefetchOn` value, and
`refetchMinBackgroundDuration`) in the [showcase](../project/examples.md).
