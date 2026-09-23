---
title: Connectivity
description: Telling the client whether it is online — nothing is installed by default; OnlineStatus.fixed and OnlineStatus.stream, a connectivity_plus adapter, and a reachability probe, because a link is not the internet.
---

# Connectivity

The [network mode](network-mode.md) guide says what a query does while the
client believes it is offline. This one is about the belief: where it comes
from, and why the obvious source is not quite enough.

**Nothing is installed by default.** Neither package depends on a
connectivity plugin, so a client nobody tells otherwise believes it is online
— the same as TanStack Query with no listener. A request that cannot reach
the network then simply fails and is retried like any other failure. For
many apps that is fine. An app used on the move, where "no signal" is
normal, gets a better experience from pausing instead: queries that wait,
writes that queue, and everything continuing when the signal returns.

## `OnlineStatus`

`QueryClientProvider` takes an `onlineStatus`, one value with two modes:

| | |
|---|---|
| `OnlineStatus.fixed(online)` | this is the state, with no source of changes — a test, a desktop build, a developer's offline switch |
| `OnlineStatus.stream(changes, initial: …)` | follow `changes`, and assume `initial` until the first event |
| `null` (the default) | bring nothing: the client keeps believing it is online |

`initial` is **required** on the stream form because a `Stream` has no
current value. A provider that only listened would start out believing the
default — online — however long the first event took, and an app launched in
airplane mode would fetch once against a network that is not there.

### With `connectivity_plus`

The plugin stays **your** dependency. Ask it once for the current state,
then follow its changes:

```dart snippet="prose-only: needs connectivity_plus, which neither published package may depend on"
// lib/main.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final connectivity = Connectivity();
  bool isOnline(List<ConnectivityResult> results) =>
      !results.contains(ConnectivityResult.none);

  // Built once, outside `build`: a new stream on every rebuild would be
  // listened to again each time.
  final changes = connectivity.onConnectivityChanged.map(isOnline);
  final online = isOnline(await connectivity.checkConnectivity());

  runApp(
    QueryClientProvider.create(
      create: QueryClient.new,
      onlineStatus: OnlineStatus.stream(changes, initial: online),
      child: const MyApp(),
    ),
  );
}
```

A broadcast stream always works. A single-subscription one works only while
exactly one provider listens to it, once — no remount, no second provider,
no switching away and back — and a second listen fails with a `FlutterError`
that points to `asBroadcastStream()`. Wrap it when in doubt.

### Fixed

With no stream at all, a fixed status is the whole verdict. A changed value
reaches the client on the rebuild that changes it — a developer setting that
simulates offline, for instance:

```dart snippet="guides/connectivity.md#fixed-online-status"
QueryClientProvider(
  client: client,
  onlineStatus: OnlineStatus.fixed(online),
  child: const MyApp(),
),
```

### When the status changes hands

- A **swapped client** under the same provider inherits the last value the
  stream reported.
- **Taking the status away** (setting it to `null`) or disposing the provider
  puts the client back online — once no other provider has a status for that
  client.
- A **replacement provider** on the same client, under a new key or moved to
  another parent, mounts before the old one goes and keeps its own verdict.

## A link is not reachability

`connectivity_plus` reports a *link*: Wi-Fi joined, a cellular bearer up. It
does not say that a request will get through. A phone on hotel Wi-Fi behind
a captive portal reports "connected"; so does one whose router has lost its
uplink, and so does every phone when your backend is down. In each case the
client believes it is online, requests fail, and the retries run.

That is not a disaster — it is what happens with no connectivity source at
all — but an app that wants "offline" to mean "cannot reach *us*" can ask.
`OnlineStatus.stream` takes any `Stream<bool>`, so a reachability check is
one more stream: online when the link is up **and** a probe of the backend
answers.

```dart snippet="guides/connectivity.md#reachability"
/// `true` while the link is up *and* [probe] reaches the backend. Probes again
/// every [recheck] while the link is up: a captive portal or a server outage
/// ends without the link changing.
Stream<bool> reachability(
  Stream<bool> link,
  Future<bool> Function() probe, {
  Duration recheck = const Duration(seconds: 20),
}) {
  StreamSubscription<bool>? linkChanges;
  Timer? timer;
  var linkUp = false;
  var checks = 0;
  late final StreamController<bool> out;

  Future<void> check() async {
    final asked = ++checks;
    final reachable = linkUp && await probe();
    // A later check — the link dropping, say — overtakes this one's answer.
    if (asked == checks && !out.isClosed) out.add(reachable);
  }

  out = StreamController<bool>.broadcast(
    onListen: () {
      linkChanges = link.listen((up) {
        linkUp = up;
        check().ignore();
      });
      timer = Timer.periodic(recheck, (_) {
        if (linkUp) check().ignore();
      });
    },
    onCancel: () {
      timer?.cancel();
      linkChanges?.cancel().ignore();
    },
  );
  return out.stream.distinct();
}
```

The re-probe is the part that is easy to forget. Without it, a probe that
failed behind a captive portal leaves the app offline until the link
changes — and logging in to the portal does not change the link.

The probe itself is one cheap request with a short timeout. With
`package:http`:

```dart snippet="prose-only: needs package:http, which neither published package may depend on"
// lib/data/reachability.dart
Future<bool> probeBackend() async {
  try {
    final response = await http
        .head(Uri.parse('https://api.example.com/health'))
        .timeout(const Duration(seconds: 3));
    // Over HTTPS a captive portal cannot answer for our host, so a 2xx
    // is our server.
    return response.statusCode >= 200 && response.statusCode < 300;
  } on Exception {
    return false;
  }
}
```

and the two joined in `main`, the link from `connectivity_plus` as above:

```dart snippet="prose-only: needs connectivity_plus and package:http"
final initial = online && await probeBackend();
runApp(
  QueryClientProvider.create(
    create: QueryClient.new,
    onlineStatus: OnlineStatus.stream(
      reachability(changes, probeBackend),
      initial: initial,
    ),
    child: const MyApp(),
  ),
);
```

`reachability` listens to the link stream again whenever its own listener
comes back, so give it a broadcast link stream.

Keep the probe's traffic in proportion: one `HEAD` every twenty seconds while
the link is up is small, but it is not nothing on a metered connection, and
it runs for as long as the provider listens, whether or not a screen needs
the network.

## Without Flutter

A pure-Dart client has no provider to hand a status to. Its
`onlineManager` takes the same thing directly — an adapter over any source,
or a value set by hand:

```dart snippet="guides/connectivity.md#online-manager"
client.onlineManager.setEventListener((setOnline) {
  final subscription = reachable.listen(setOnline);
  return subscription.cancel;
});
// …or by hand:
client.onlineManager.setOnline(false);
```

Resuming paused work needs a mounted client (`client.mount()`); see
[pure Dart](pure-dart.md).

## Testing offline

`OnlineStatus.fixed(false)` in a widget test's provider puts the client
offline from the first frame, and pumping a new provider with
`OnlineStatus.fixed(true)` brings it back. In the live demo on the
[network mode](network-mode.md) page, the *Online* switch does the same
thing by hand: it calls `client.onlineManager.setOnline`.

:::note[In React Query]
TanStack Query listens to the browser's `online` and `offline` events by
default — which report a link, like `connectivity_plus` — and
`onlineManager.setEventListener` is how a React Native app installs
`NetInfo`. Here nothing is installed by default; the provider's
`onlineStatus` or `onlineManager.setEventListener` is where a source goes.
See [differences from TanStack Query](../reference/differences-from-tanstack.md).
:::
