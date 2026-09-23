---
title: Lifecycle and connectivity wiring
description: One main.dart that tells the client when the app is in front and when the network is there — connectivity_plus, a reachability probe, a calmer focus refetch and a debug offline switch.
---

# Lifecycle and connectivity wiring

Two facts decide when a query fetches on its own: whether the user is looking
at the app, and whether the network is there. The first comes for free —
`QueryClientProvider` follows the app lifecycle, so data that went stale while
the app was in the background refetches when it comes back. The second is not
installed at all: the client believes it is online until told otherwise, so a
phone in a tunnel fails every fetch and burns its retries. This recipe wires
both in `main`: connectivity from `connectivity_plus`, a lighter focus rule for
an app the user switches away from often, a probe for when a link is not
enough, and a switch to try the offline states from a debug build.

## The finished code

```dart snippet="prose-only: needs connectivity_plus, which neither published package may depend on" title="lib/main.dart"
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'app/query_client.dart';
import 'data/api_client.dart';
import 'data/dio_product_api.dart';
import 'data/product_api.dart';
import 'features/products/product_list_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final connectivity = Connectivity();
  bool isOnline(List<ConnectivityResult> results) =>
      !results.contains(ConnectivityResult.none);

  // Built once, here: a stream made in `build` would be a new one on every
  // rebuild, and the provider would listen again each time.
  final changes = connectivity.onConnectivityChanged.map(isOnline);
  // What is true right now, so an app started in flight mode does not
  // fetch once against a network that is not there.
  final online = isOnline(await connectivity.checkConnectivity());

  final api = DioProductApi(ApiClient(baseUrl: 'https://api.example.com/v1'));

  runApp(
    ProductApiScope(
      api: api,
      child: QueryClientProvider.create(
        create: createQueryClient,
        onlineStatus: OnlineStatus.stream(changes, initial: online),
        child: MaterialApp(
          scaffoldMessengerKey: scaffoldMessengerKey,
          home: const ProductListScreen(),
        ),
      ),
    ),
  );
}
```

`createQueryClient` is the client from
[A global error snackbar](global-error-snackbar.md#the-finished-code), and
`DioProductApi` the API from
[Wiring dio or package:http](wiring-dio-and-http.md). This is `connectivity_plus`
6, whose events are lists of `ConnectivityResult`s — one per interface — so
"online" means "any interface but none".

## How it works

1. **`OnlineStatus.stream` follows the link.** Every value the stream sends
   tells the client whether it is online. While it is not, a query in the
   default network mode does not fetch: one with nothing cached stays
   `pending` with `fetchStatus: paused`, one with data keeps showing it. A
   mutation started offline waits.
2. **`initial` is what is true at start.** A stream has no current value, and
   the first event can take a while. `checkConnectivity()` answers at once, so
   an app launched in flight mode starts offline instead of fetching once
   against no network.
3. **The stream is built once.** It is made in `main`, before `runApp`. A
   stream built in a `build` method would be a new stream on every rebuild,
   and the provider would listen again each time. `onConnectivityChanged` is a
   broadcast stream, so a remounted provider can listen again.
4. **Coming back online resumes.** When the stream says online again, paused
   fetches continue, paused mutations are sent, and active queries whose data
   is stale refetch (`refetchOnReconnect`, `RefetchOn.ifStale` by default).
5. **The lifecycle needs nothing.** The provider maps `AppLifecycleState` to
   the client's focus. Back in front, every active query whose data is stale
   refetches (`refetchOnWindowFocus`).

## A calmer focus refetch

On a phone the user leaves the app for a notification and is back in five
seconds. With short `staleTime`s that is a refetch of every screen, every time.
`AppFocusManager` can ignore short absences:

```dart snippet="cookbook/lifecycle-and-connectivity-wiring.md#focus" title="lib/app/query_client.dart"
QueryClient createClientWithFocusRules() => QueryClient(
      // Back after less than a minute away? Not a reason to refetch the
      // world. Paused work still resumes at once.
      focusManager: AppFocusManager(
        refetchMinBackgroundDuration: const Duration(minutes: 1),
      ),
    );
```

Back after less than a minute, focus-triggered refetches are skipped. Fetches
that were paused still resume at once — they are waiting for the app, not
refreshing it.

## When a link is not enough

`connectivity_plus` reports a *link*: a phone on hotel wifi behind a captive
portal is "connected", and so is one whose mobile data has run out. When that
matters, ask your own backend:

```dart snippet="cookbook/lifecycle-and-connectivity-wiring.md#probe" title="lib/app/reachability.dart"
/// Asks [probe] — "can I reach my own backend?" — every [every], and says
/// whenever the answer changes.
Stream<bool> reachability(
  Future<bool> Function() probe, {
  Duration every = const Duration(seconds: 30),
}) async* {
  bool? last;
  while (true) {
    final reachable = await probe();
    if (reachable != last) yield last = reachable;
    await Future<void>.delayed(every);
  }
}
```

`probe` is a cheap request — `HEAD /health` with a short timeout, returning
`false` on any error. The generator only sends a value when the answer
changes. It is a single-subscription stream, so make it broadcast before it
reaches a provider, and give it the link's verdict as its start:

```dart snippet="prose-only: a fragment of main, around a probe that needs dio"
// pingBackend: Future<bool> Function() — HEAD /health, false on any error.
final reachable = reachability(pingBackend).asBroadcastStream();

// … and in the provider, instead of the link's stream:
onlineStatus: OnlineStatus.stream(reachable, initial: online),
```

## A debug switch for offline

Trying the offline states on a device means flight mode and waiting. In a
debug build, a switch is quicker:

```dart snippet="cookbook/lifecycle-and-connectivity-wiring.md#debug-switch" title="lib/debug/debug_online_switch.dart"
/// A developer's "pretend to be offline" switch, for trying the offline
/// states without a flight-mode dance.
final ValueNotifier<bool> simulateOffline = ValueNotifier<bool>(false);

class DebugOnlineSwitch extends StatelessWidget {
  const DebugOnlineSwitch({
    super.key,
    required this.client,
    required this.child,
  });

  final QueryClient client;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: simulateOffline,
        builder: (context, offline, _) => QueryClientProvider(
          client: client,
          onlineStatus: OnlineStatus.fixed(!offline),
          child: child,
        ),
      );
}
```

In a debug build (`kDebugMode`), use `DebugOnlineSwitch` in place of the
provider in `main` — with the client created there, `createQueryClient()` —
rather than around it: two providers giving one client a verdict would
overrule each other. Toggle `simulateOffline` from a debug menu. `OnlineStatus.fixed` is a verdict with no
source of changes; a changed one reaches the client on the rebuild that
changes it.

Try it: turn "Online" off in the demo and press "Refetch" — the query pauses
instead of failing. Turn it back on and the paused work continues.

<LiveDemo feature="offline" height={560} />

## Traps

- **Nothing is installed by default.** Without an `onlineStatus`, the client
  is online for ever. That is a safe default — a fetch that cannot reach the
  network fails and retries — but none of the pausing on this page happens.
- **A link is not reachability.** A "connected" phone may reach nothing. Pair
  the link with a probe, or accept that a captive portal fails fetches instead
  of pausing them.
- **Offline is not an error.** A paused query is `pending` or shows its data,
  with `isPaused` true and no error. A screen that shows a spinner for every
  `pending` spins until the network is back; show "Offline" when `isPaused`.
- **A single-subscription stream fails on remount.** The provider listens
  again when it is rebuilt with a new stream or remounted. Pass a broadcast
  stream, or wrap it in `asBroadcastStream()`.
- **One focus source.** The provider's lifecycle listener and a
  `setEventListener` of your own both write the client's focus. Turn one off
  (`observeAppLifecycle: false`) if you install the other.

## Variations

- **Per-query network mode.** A query that talks to a local server or a
  device on the LAN can say `networkMode: NetworkMode.always` and ignore the
  online status altogether. See [Network mode](../guides/network-mode.md).
- **Pause polling in the background.** A `refetchInterval` stops while the app
  is not in front unless `refetchIntervalInBackground` says otherwise; see
  [Polling](../guides/polling.md).
- **Desktop.** On macOS, Windows and Linux, a window that loses focus counts as
  unfocused; pass `isAppShown` to the provider if your app reads the lifecycle
  differently.

:::note[In React Query]
React Native wires the same two managers by hand:
`onlineManager.setEventListener` with NetInfo, and `focusManager.setFocused`
from `AppState`. Here the focus side is built into the provider, and the
online side is one argument.
:::

## See also

- [Connectivity](../guides/connectivity.md) — `OnlineStatus` and its rules.
- [App focus refetching](../guides/window-focus-refetching.md#suppressing-pointless-refetches)
  — the lifecycle mapping and `refetchMinBackgroundDuration`.
- [Network mode](../guides/network-mode.md) — what a paused query and a paused
  mutation do, and how they resume.
