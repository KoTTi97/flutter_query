---
title: Connectivity
description: Nothing is installed by default — OnlineStatus.fixed and OnlineStatus.stream, a six-line connectivity_plus adapter, and what a link does not tell you.
---

{/* demo: offline */}

# Connectivity

Nothing is installed by default. The client assumes it is online — which is
what TanStack Query does with no listener — and a fetch that cannot reach the network
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
startup. A broadcast stream always works. A single-subscription one works
only while exactly one provider listens to it, once — no remount, no second
provider — and a second listen throws a `FlutterError` that points to
`asBroadcastStream()`; wrap it when in doubt. A swapped client inherits the
last value the stream reported, and taking `onlineStatus` away (setting it to
`null`) or disposing the provider puts the client back online — once no
other provider has a status for that client. A replacement provider on the
same client, under a new key or moved to another parent, mounts before the
old one goes and keeps its own verdict.

With no stream at all, a fixed status is the whole verdict, and a changed one
reaches the client on the rebuild that changes it:

```dart snippet="guides/connectivity.md#fixed-online-status"
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

## What offline does

What a query or a mutation does while the client believes it is offline is
its [network mode](network-mode.md). The `offline` screen in the
[examples](../examples/index.md) shows the online toggle, paused mutations and
resuming.
