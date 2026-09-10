/// Where the [QueryClient] lives, and where the Flutter-side adapters are
/// installed (https://github.com/KoTTi97/flutter_query/issues/22).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:query_kit/query_kit.dart';

import 'query_context.dart';

/// Provides a [QueryClient] to the widgets below it, and wires the client to
/// Flutter while it is mounted.
///
/// Three things happen at mount:
///
/// 1. **App lifecycle → focus.** Every [AppLifecycleState] the app reports —
///    the one it is already in, and each transition after — is mapped onto
///    the client's focus state by [isAppShown]. `resumed` is focused;
///    `hidden`, `paused` and `detached` are not. `inactive` depends on the
///    platform, because the state means two different things: on iOS and
///    Android it is a transient interruption (the notification shade, the app
///    switcher, an incoming call) and counts as focused, since treating those
///    as "unfocused" would refetch the world on the way back; on macOS,
///    Windows and Linux it is precisely the window losing focus — the event
///    `refetchOnWindowFocus` is named after — and counts as unfocused. Pass
///    [isAppShown] to decide it yourself.
/// 2. **The notify scheduler.** Notifications that arrive while a build is in
///    flight are deferred to a post-frame callback, so a query resolving
///    mid-build cannot call `setState` during that build. The scheduler is
///    installed on the client's own `NotifyManager` and the previous one is
///    put back when the last provider using that manager goes away — the
///    installation is counted per manager, so providers whose lifetimes
///    overlap without nesting (siblings, or an old and a new one for a frame)
///    cannot uninstall each other's.
/// 3. **Connectivity, only if you bring it.** Pass [onlineStatus] and the
///    client follows it. Nothing is installed by default and no connectivity
///    package is a dependency — see the README for the `connectivity_plus`
///    snippet.
class QueryClientProvider extends StatefulWidget {
  /// Creates and owns a client for this widget's lifetime. Rebuilding with a
  /// different [create] callback keeps the client; change [key] to replace it.
  /// The owned client is cleared after its provider unmounts.
  static Widget create({
    Key? key,
    required QueryClient Function() create,
    required Widget child,
    Stream<bool>? onlineStatus,
    bool? initialOnlineStatus,
    bool observeAppLifecycle = true,
    bool Function(AppLifecycleState state)? isAppShown,
  }) =>
      _OwnedQueryClientProvider(
        key: key,
        create: create,
        onlineStatus: onlineStatus,
        initialOnlineStatus: initialOnlineStatus,
        isAppShown: isAppShown,
        observeAppLifecycle: observeAppLifecycle,
        child: child,
      );

  /// Provides [client] to [child] and wires it to Flutter for as long as this
  /// widget is mounted — the three things the class doc lists. A different
  /// [client] on a later build unmounts the old one and mounts the new.
  const QueryClientProvider({
    super.key,
    required this.client,
    required this.child,
    this.onlineStatus,
    this.initialOnlineStatus,
    this.observeAppLifecycle = true,
    this.isAppShown,
  });

  /// The client every builder, controller and `context.query` below runs on
  /// unless it names one of its own. Mounted while this widget is; swapping it
  /// recreates every observer below, because each belonged to the old client.
  final QueryClient client;

  /// The subtree that can reach [client] — through [of], [maybeOf] and
  /// [read], and through the builders, mixin and `context.query` built on
  /// them.
  final Widget child;

  /// Optional connectivity signal. `true` means "assume the network is
  /// reachable".
  final Stream<bool>? onlineStatus;

  /// What to assume until [onlineStatus] says otherwise.
  ///
  /// A `Stream` has no current value, so a provider that only listens starts
  /// out believing the default — online — however long the first event takes.
  /// An app launched in airplane mode then fetches once against a network
  /// that is not there. Most connectivity packages answer that question
  /// directly (`connectivity_plus`'s `checkConnectivity()`); pass the answer
  /// here and the client starts from it. `null` keeps the client's own
  /// starting value (third review, 2026-09-10).
  final bool? initialOnlineStatus;

  /// Whether to map the app's lifecycle onto the client's focus state.
  final bool observeAppLifecycle;

  /// Which [AppLifecycleState]s count as "the user is looking at the app",
  /// and so as focused for `refetchOnWindowFocus`.
  ///
  /// `null` uses the built-in mapping the class doc describes, which reads
  /// `AppLifecycleState.inactive` differently per platform. Override it for a
  /// platform whose conventions differ, or to switch focus refetching to a
  /// signal of your own (sixth review, 2026-09-10).
  final bool Function(AppLifecycleState state)? isAppShown;

  /// The nearest client above [context].
  ///
  /// Throws when there is none: a missing provider is a wiring mistake, and a
  /// nullable return would only move the crash somewhere less helpful.
  static QueryClient of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_QueryClientScope>();
    if (scope == null) {
      throw _missingProvider();
    }
    return scope.client;
  }

  // Thrown in every build mode: as an `assert` it would surface in release as
  // a null check on the scope, which says nothing about what is missing.
  static FlutterError _missingProvider() => FlutterError(
        'No QueryClientProvider found above this widget. Wrap your app (or '
        'the subtree that uses queries) in QueryClientProvider(client: …).',
      );

  /// The nearest client above [context], or `null` when there is none — for
  /// a widget that can do without one. Subscribes like [of].
  static QueryClient? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_QueryClientScope>()?.client;

  /// Like [of], but without subscribing the calling element to changes.
  static QueryClient read(BuildContext context) {
    final element =
        context.getElementForInheritedWidgetOfExactType<_QueryClientScope>();
    if (element == null) {
      throw _missingProvider();
    }
    return (element.widget as _QueryClientScope).client;
  }

  @override
  State<QueryClientProvider> createState() => _QueryClientProviderState();
}

class _OwnedQueryClientProvider extends StatefulWidget {
  const _OwnedQueryClientProvider({
    super.key,
    required this.create,
    required this.child,
    required this.onlineStatus,
    required this.initialOnlineStatus,
    required this.observeAppLifecycle,
    required this.isAppShown,
  });

  final QueryClient Function() create;
  final Widget child;
  final Stream<bool>? onlineStatus;
  final bool? initialOnlineStatus;
  final bool observeAppLifecycle;
  final bool Function(AppLifecycleState state)? isAppShown;

  @override
  State<_OwnedQueryClientProvider> createState() =>
      _OwnedQueryClientProviderState();
}

class _OwnedQueryClientProviderState extends State<_OwnedQueryClientProvider> {
  late final QueryClient _client;

  @override
  void initState() {
    super.initState();
    _client = widget.create();
  }

  @override
  Widget build(BuildContext context) => QueryClientProvider(
        client: _client,
        onlineStatus: widget.onlineStatus,
        initialOnlineStatus: widget.initialOnlineStatus,
        observeAppLifecycle: widget.observeAppLifecycle,
        isAppShown: widget.isAppShown,
        child: widget.child,
      );

  @override
  void dispose() {
    _client.clear();
    super.dispose();
  }
}

class _QueryClientProviderState extends State<QueryClientProvider> {
  AppLifecycleListener? _lifecycle;
  StreamSubscription<bool>? _onlineSubscription;
  bool? _lastOnline;

  @override
  void initState() {
    super.initState();
    _mountClient(widget.client);
    if (widget.observeAppLifecycle) {
      _observeLifecycle(widget.client);
    }
    _applyInitialOnlineStatus(widget.client);
    _follow(widget.onlineStatus);
  }

  void _mountClient(QueryClient client) {
    _installScheduler(client.notifyManager);
    client.mount();
  }

  void _unmountClient(QueryClient client) {
    _restoreScheduler(client.notifyManager);
    client.unmount();
  }

  void _observeLifecycle(QueryClient client) {
    // The listener only reports transitions; the state the app is already in
    // has to be read. A provider mounted while the app is hidden would
    // otherwise keep the client "focused" until the next show.
    final isShown = widget.isAppShown ?? _isShown;
    final current = WidgetsBinding.instance.lifecycleState;
    if (current != null) {
      client.focusManager.setFocused(isShown(current));
    }
    // Every transition, through one mapping — not `onShow`/`onHide`, which
    // are two of the transitions: `detached → resumed` fires neither, and
    // left the client unfocused for good.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => client.focusManager.setFocused(isShown(state)),
    );
  }

  void _stopObservingLifecycle() {
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  /// Subscribes to [onlineStatus] — once per stream object, never again for
  /// a new client. The handler reads `widget.client` at delivery time, so a
  /// client switch re-points it for free; cancelling and listening again
  /// would throw on a single-subscription stream (`Stream has already been
  /// listened to`), and the parameter type promises nothing about broadcast
  /// (fourth review, 2026-09-09).
  void _follow(Stream<bool>? onlineStatus) {
    _onlineSubscription?.cancel();
    // What the old stream last said dies with it. Carrying it to a client
    // that arrives later would pin that client offline with nothing left to
    // put it back online (third review, 2026-09-10).
    _lastOnline = null;
    _onlineSubscription = onlineStatus?.listen(
      _onOnline,
      // A stream error is the stream's problem, not the app's: reported the
      // way Flutter reports a build error, not thrown into the zone.
      onError: (Object error, StackTrace stackTrace) =>
          FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'query_kit_flutter',
          context: ErrorDescription('while listening to onlineStatus'),
        ),
      ),
    );
  }

  /// The starting assumption, before [_follow]'s stream has said anything.
  void _applyInitialOnlineStatus(QueryClient client) {
    final initial = widget.initialOnlineStatus;
    if (initial != null) {
      client.onlineManager.setOnline(initial);
    }
  }

  void _onOnline(bool online) {
    _lastOnline = online;
    widget.client.onlineManager.setOnline(online);
  }

  /// `resumed` is shown, `hidden`/`paused`/`detached` are not, and
  /// `inactive` depends on the platform (see the class doc).
  static bool _isShown(AppLifecycleState state) => switch (state) {
        AppLifecycleState.resumed => true,
        AppLifecycleState.inactive => _inactiveIsShown,
        AppLifecycleState.hidden ||
        AppLifecycleState.paused ||
        AppLifecycleState.detached =>
          false,
      };

  /// On a phone `inactive` is an interruption the user did not choose and
  /// will be back from in a moment; on a desktop it is the window losing
  /// focus, which is the whole point of `refetchOnWindowFocus`.
  static bool get _inactiveIsShown => switch (defaultTargetPlatform) {
        TargetPlatform.iOS ||
        TargetPlatform.android ||
        TargetPlatform.fuchsia =>
          true,
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux =>
          false,
      };

  /// How many providers have installed the Flutter scheduler on one
  /// [NotifyManager], and what was there before the first of them.
  ///
  /// One client can be under two providers at once — siblings, or an old and
  /// a new one overlapping for a frame — and their lifetimes need not nest.
  /// A per-provider save/restore then puts the original back while a provider
  /// is still running (notifications stop reaching the frame) and leaves the
  /// adapter installed after the last one is gone (notifications are deferred
  /// to a frame that is never coming). Counting per manager makes the
  /// installation what it actually is: shared (third review, 2026-09-10).
  static final Map<NotifyManager, ({ScheduleFunction original, int count})>
      _schedulerInstallations =
      <NotifyManager, ({ScheduleFunction original, int count})>{};

  static void _installScheduler(NotifyManager manager) {
    final installed = _schedulerInstallations[manager];
    if (installed == null) {
      _schedulerInstallations[manager] =
          (original: manager.scheduler, count: 1);
      manager.setScheduler(_scheduleNotification);
      return;
    }
    _schedulerInstallations[manager] =
        (original: installed.original, count: installed.count + 1);
  }

  static void _restoreScheduler(NotifyManager manager) {
    final installed = _schedulerInstallations[manager];
    if (installed == null) {
      return;
    }
    if (installed.count > 1) {
      _schedulerInstallations[manager] =
          (original: installed.original, count: installed.count - 1);
      return;
    }
    _schedulerInstallations.remove(manager);
    manager.setScheduler(installed.original);
  }

  /// Runs [callback] now when that is safe, and after this frame when it is
  /// not. Called for every batch of cache notifications.
  ///
  /// Synchronous on purpose, where upstream's default is a zero-delay timer:
  /// a `setState` outside a build is exactly what Flutter expects from a tap
  /// handler or a resolved future, and delivering right away means one `pump`
  /// in a test — or one frame in an app — shows the new result.
  ///
  /// "During a build" is two things. The frame's build phase, which the
  /// scheduler phase names; a notification there waits for the frame to end.
  /// And the very first build of the app: `runApp` attaches the root widget
  /// from a `Timer.run`, in `SchedulerPhase.idle`, and builds the whole tree
  /// synchronously right there — the one build no phase accounts for. That
  /// one is told apart by `BuildOwner.debugBuilding`, and its notifications
  /// go into a microtask, which runs the moment the attach returns and so
  /// lands before the first frame. `debugBuilding` is a debug-only fact, and
  /// that is enough: the "setState during build" assertion it guards against
  /// is debug-only too, and in release a widget marked dirty mid-scope is
  /// simply rebuilt before the scope ends.
  static void _scheduleNotification(void Function() callback) {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => callback());
      return;
    }
    if (WidgetsBinding.instance.buildOwner?.debugBuilding ?? false) {
      scheduleMicrotask(callback);
      return;
    }
    callback();
  }

  @override
  void didUpdateWidget(QueryClientProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Each wiring follows its own field. Tearing everything down for a new
    // `onlineStatus` object — which a stream built in a parent's `build` is
    // on every rebuild — would unmount and remount the client each time.
    final clientChanged = oldWidget.client != widget.client;
    if (clientChanged) {
      _stopObservingLifecycle();
      _unmountClient(oldWidget.client);
      _mountClient(widget.client);
      _applyInitialOnlineStatus(widget.client);
      // The stream will not repeat itself for the newcomer, so it starts from
      // what the stream last said — but only while it is *the same* stream
      // still running. A connectivity source that has been taken away speaks
      // for nobody, and a value it left behind would pin a later client
      // offline with nothing able to put it back (third review, 2026-09-10).
      final lastOnline = _lastOnline;
      if (lastOnline != null && oldWidget.onlineStatus == widget.onlineStatus) {
        widget.client.onlineManager.setOnline(lastOnline);
      }
    }
    if (clientChanged ||
        oldWidget.observeAppLifecycle != widget.observeAppLifecycle) {
      _stopObservingLifecycle();
      if (widget.observeAppLifecycle) {
        _observeLifecycle(widget.client);
      }
    }
    if (oldWidget.onlineStatus != widget.onlineStatus) {
      _follow(widget.onlineStatus);
    }
  }

  @override
  void dispose() {
    _stopObservingLifecycle();
    _onlineSubscription?.cancel();
    _onlineSubscription = null;
    _unmountClient(widget.client);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _QueryClientScope(
        client: widget.client,
        child: QueryScope(client: widget.client, child: widget.child),
      );
}

class _QueryClientScope extends InheritedWidget {
  const _QueryClientScope({required this.client, required super.child});

  final QueryClient client;

  @override
  bool updateShouldNotify(_QueryClientScope oldWidget) =>
      oldWidget.client != client;
}
