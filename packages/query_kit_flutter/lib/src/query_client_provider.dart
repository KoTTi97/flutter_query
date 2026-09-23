/// Where the [QueryClient] lives, and where the Flutter-side adapters are
/// installed. See [QueryClientProvider].
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:query_kit/query_kit.dart';

import 'online_status.dart';
import 'query_context.dart';

/// Provides a [QueryClient] to the widgets below it, and wires the client to
/// Flutter while it is mounted.
///
/// Put one above everything that reads a query — usually around the app:
///
/// ```dart
/// void main() {
///   runApp(
///     QueryClientProvider.create(
///       create: QueryClient.new,
///       child: const MyApp(),
///     ),
///   );
/// }
/// ```
///
/// [QueryClientProvider.create] makes the client and owns it: it lives as
/// long as the provider and is cleared after the provider unmounts. The
/// unnamed constructor takes a client you made yourself — one you configure
/// with `defaultOptions`, share with code outside the tree, or create in a
/// test — and never clears it:
///
/// ```dart
/// final client = QueryClient(
///   defaultOptions: DefaultOptions(
///     queries: QueryDefaults(
///       staleTime: const StaleTime.duration(Duration(seconds: 30)),
///     ),
///   ),
/// );
///
/// QueryClientProvider(client: client, child: const MyApp());
/// ```
///
/// Below it, every call style finds the client on its own. Code that needs
/// the client itself reads it with [of] (subscribes, for `build`),
/// [maybeOf] (the same, `null` without a provider) or [read] (no
/// subscription, for callbacks and `initState`):
///
/// ```dart
/// onPressed: () => QueryClientProvider.read(context)
///     .invalidateQueries(filters: QueryFilters(queryKey: tasksKey)),
/// ```
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
///    [isAppShown] to decide it yourself, or [observeAppLifecycle] `false` to
///    switch the mapping off.
/// 2. **The notify scheduler.** Notifications that arrive while a build is in
///    flight are deferred to a post-frame callback, so a query resolving
///    mid-build cannot call `setState` during that build. Several providers
///    may share one client — siblings, or an old and a new one for a frame —
///    and the scheduler stays installed until the last of them goes.
/// 3. **Connectivity, only if you bring it.** Pass [onlineStatus] — an
///    [OnlineStatus.fixed] value, or an [OnlineStatus.stream] with the
///    assumption to start from — and the client follows it. Nothing is
///    installed by default and no connectivity package is a dependency; see
///    [OnlineStatus] for a `connectivity_plus`-style example.
///
/// {@category Setup}
class QueryClientProvider extends StatefulWidget {
  /// Creates and owns a client for this widget's lifetime. Rebuilding with a
  /// different [create] callback keeps the client; change [key] to replace it.
  /// The owned client is cleared after its provider unmounts.
  static Widget create({
    Key? key,
    required QueryClient Function() create,
    required Widget child,
    OnlineStatus? onlineStatus,
    bool observeAppLifecycle = true,
    bool Function(AppLifecycleState state)? isAppShown,
  }) =>
      _OwnedQueryClientProvider(
        key: key,
        create: create,
        onlineStatus: onlineStatus,
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

  /// Optional connectivity, as one value: [OnlineStatus.fixed] for a client
  /// with no source of its own, [OnlineStatus.stream] for one that follows a
  /// stream from a stated starting assumption. `true` means "assume the
  /// network is reachable".
  ///
  /// ```dart
  /// QueryClientProvider.create(
  ///   create: QueryClient.new,
  ///   onlineStatus: OnlineStatus.stream(isOnlineChanges, initial: true),
  ///   child: const MyApp(),
  /// );
  /// ```
  ///
  /// `null` brings nothing and the client keeps its own default, which is
  /// online — and that is where it goes back to when a status is taken away
  /// on a later build, or when the provider leaves the tree: nothing is left
  /// to revise an offline verdict then. Only the *last* provider with a
  /// status for that client does this: a replacement mounted before the old
  /// one is disposed — a new key, a move to another parent — keeps its own
  /// verdict.
  ///
  /// [OnlineStatus.initial] is applied whenever a client is given this
  /// status: at mount, to a client that arrives on a later build, and on
  /// any later build that changes the status — except where a live stream
  /// already has a verdict. A stream that delivers while it is being
  /// listened to is believed over its `initial`; a client that arrives under
  /// the same stream starts from that stream's last event; and one stream
  /// swapped for another keeps the client's verdict, since rewinding it to
  /// `initial` would flicker for anyone building their stream in `build`.
  /// That is also why a [OnlineStatus.fixed] works as a live switch: having
  /// no stream, applying it is the only way it can reach the client.
  final OnlineStatus? onlineStatus;

  /// Whether to map the app's lifecycle onto the client's focus state.
  /// Defaults to `true`.
  ///
  /// Turn it **off** when you install a focus source of your own with
  /// `client.focusManager.setEventListener(...)`. The two are alternatives,
  /// not layers: both write through `setFocused`, so with both installed the
  /// last writer wins and neither can see the other's verdict.
  final bool observeAppLifecycle;

  /// Which [AppLifecycleState]s count as "the user is looking at the app",
  /// and so as focused for `refetchOnWindowFocus`.
  ///
  /// ```dart
  /// QueryClientProvider.create(
  ///   create: QueryClient.new,
  ///   // Only a fully resumed app counts, on every platform:
  ///   isAppShown: (state) => state == AppLifecycleState.resumed,
  ///   child: const MyApp(),
  /// );
  /// ```
  ///
  /// `null` uses the built-in mapping the class doc describes, which reads
  /// `AppLifecycleState.inactive` differently per platform. Override it for a
  /// platform whose conventions differ, or to switch focus refetching to a
  /// signal of your own. The mapping given on the latest build is the one in
  /// force: it is applied to the state the app is in when it changes, and
  /// decides every transition after.
  final bool Function(AppLifecycleState state)? isAppShown;

  /// The nearest client above [context].
  ///
  /// Throws when there is none: a missing provider is a wiring mistake, and a
  /// nullable return would only move the crash somewhere less helpful.
  static QueryClient of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<QueryScope>();
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
      context.dependOnInheritedWidgetOfExactType<QueryScope>()?.client;

  /// Like [of], but without subscribing the calling element to changes —
  /// the one to use in callbacks, `initState` and anywhere else outside
  /// `build`. Throws when there is no provider.
  static QueryClient read(BuildContext context) {
    final element =
        context.getElementForInheritedWidgetOfExactType<QueryScope>();
    if (element == null) {
      throw _missingProvider();
    }
    return (element.widget as QueryScope).client;
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
    required this.observeAppLifecycle,
    required this.isAppShown,
  });

  final QueryClient Function() create;
  final Widget child;
  final OnlineStatus? onlineStatus;
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

  /// Set when a failing `_follow` in [didUpdateWidget] gave back what this
  /// state held: Flutter abandons the element then, and should it dispose
  /// it after all, nothing is given back twice.
  bool _released = false;

  @override
  void initState() {
    super.initState();
    _mountClient(widget.client);
    // Listened to first: the one step here that can fail, so nothing below
    // has happened when it throws. A stream *can* deliver during `listen` —
    // a synchronous controller whose `onListen` adds the current value — and
    // then its value is already the client's.
    try {
      _follow(widget.onlineStatus);
    } catch (_) {
      // `_follow`'s error for a stream already listened to. A `State` whose
      // `initState` throws is never disposed, so what it took is given back
      // here, and it neither speaks for the client's connectivity nor tells
      // the client anything: counted first, its count would outlive it; its
      // `initial` applied first, an `initial: false` would stay with nobody
      // left to revise it, or override another provider's verdict.
      _unmountClient(widget.client);
      rethrow;
    }
    // Initial focus can resume restored mutations synchronously. It must
    // already see the connectivity snapshot supplied by the provider:
    // `initial`, unless the stream said something while it was listened to.
    if (_lastOnline == null) {
      _applyOnlineStatus(widget.client);
    }
    if (widget.observeAppLifecycle) {
      _observeLifecycle(widget.client);
    }
    if (widget.onlineStatus != null) {
      _speakForOnline(widget.client);
    }
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
    _applyCurrentLifecycleState(client);
    // Every transition, through one mapping — not `onShow`/`onHide`, which
    // are two of the transitions: `detached → resumed` fires neither, and
    // left the client unfocused for good. The mapping is read when the
    // transition arrives, not captured here: a `isAppShown` given on a later
    // build then decides the next transition without re-wiring anything.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => _setFocused(client, _currentIsShown(state)),
    );
  }

  /// Tells [client] whether the app is shown — unless the client already
  /// believes exactly that. The one case where the two differ is the first
  /// report after a mount that found no lifecycle state yet: the client's
  /// focus is then unset, which already reads as focused, and `setFocused`
  /// would count unset → `true` as a focus change and refetch every stale
  /// active query right after the mount fetched them.
  static void _setFocused(QueryClient client, bool shown) {
    if (client.focusManager.isFocused() != shown) {
      client.focusManager.setFocused(shown);
    }
  }

  /// The mapping the latest build gave, or the built-in one.
  bool _currentIsShown(AppLifecycleState state) =>
      (widget.isAppShown ?? _isShown)(state);

  /// Maps the state the app is in right now onto [client]'s focus — on mount,
  /// and again when the mapping changes, so the change is not held back until
  /// the next transition. `setFocused` with an unchanged value is a no-op, so
  /// an inline closure that is new on every build costs one call of it.
  void _applyCurrentLifecycleState(QueryClient client) {
    final current = WidgetsBinding.instance.lifecycleState;
    if (current != null) {
      _setFocused(client, _currentIsShown(current));
    }
  }

  void _stopObservingLifecycle() {
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  /// Subscribes to [onlineStatus]'s changes — once per stream object, never
  /// again for a new client. The handler reads `widget.client` at delivery
  /// time, so a client switch re-points it for free; cancelling and listening
  /// again would throw on a single-subscription stream (`Stream has already
  /// been listened to`), and [OnlineStatusStream.changes] promises nothing
  /// about broadcast.
  void _follow(OnlineStatus? onlineStatus) {
    _cancelOnline();
    // What the old stream last said dies with it. Carrying it to a client
    // that arrives later would pin that client offline with nothing left to
    // put it back online.
    _lastOnline = null;
    final changes = onlineStatus?.changes;
    if (changes == null) {
      return;
    }
    try {
      _onlineSubscription = changes.listen(
        _onOnline,
        // A stream error is the stream's problem, not the app's: reported
        // the way Flutter reports a build error, not thrown into the zone.
        onError: (Object error, StackTrace stackTrace) =>
            _report(error, stackTrace, 'while listening to onlineStatus'),
      );
    } on StateError catch (error, stackTrace) {
      // A single-subscription stream some provider already listened to —
      // this one before a remount, a sibling, or this one before a detour
      // through another status. Said in words a reader can act on.
      Error.throwWithStackTrace(
        FlutterError.fromParts([
          ErrorSummary(
            'QueryClientProvider could not listen to its onlineStatus.',
          ),
          ErrorDescription(
            'The stream has already been listened to ($error). A '
            'single-subscription stream can be followed by one provider, '
            'once: remounting a provider with the same OnlineStatus.stream, '
            'giving it to two providers, or switching away from it and back '
            'each listen again.',
          ),
          ErrorHint(
            'Pass a broadcast stream: call asBroadcastStream() once where '
            'the status is created, or use a source that already is one.',
          ),
        ]),
        stackTrace,
      );
    }
  }

  /// Cancels the subscription [_follow] made. `cancel()` returns a future
  /// that fails when the stream's `onCancel` does; nobody awaits it, so its
  /// error is reported like a stream error instead of reaching the zone
  /// unhandled.
  void _cancelOnline() {
    final cancelled = _onlineSubscription?.cancel();
    _onlineSubscription = null;
    cancelled
        ?.then<void>(
          (_) {},
          onError: (Object error, StackTrace stackTrace) => _report(
            error,
            stackTrace,
            'while cancelling the onlineStatus subscription',
          ),
        )
        .ignore();
  }

  static void _report(Object error, StackTrace stackTrace, String context) =>
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'query_kit_flutter',
          context: ErrorDescription(context),
        ),
      );

  /// Puts [client] back to the default a client with no status has —
  /// online — once this provider stops speaking for its connectivity: the
  /// status taken away on a later build, or the provider gone. Whatever the
  /// status last said would otherwise stay, and an offline verdict with no
  /// source left to revise it pins paused queries and mutations for good. A
  /// client that leaves this provider
  /// for another client is left as it was ([reset] false).
  ///
  /// Only when *no* provider speaks for it any more. One client can be under
  /// two providers at once, and a replacement's `initState` runs before the
  /// old one's `dispose` — a new key, a move to another parent without a
  /// `GlobalKey`. The old one putting the client back online would override
  /// the new one's verdict, for good with an [OnlineStatus.fixed]. So the
  /// speakers are counted per [OnlineManager], the way
  /// [_schedulerInstallations] counts the scheduler's installations, and the
  /// last one to stop is the one that resets.
  static void _releaseOnline(QueryClient client, {bool reset = true}) {
    final manager = client.onlineManager;
    final speakers = _onlineSpeakers[manager];
    if (speakers == null) {
      return;
    }
    if (speakers > 1) {
      _onlineSpeakers[manager] = speakers - 1;
      return;
    }
    _onlineSpeakers.remove(manager);
    if (reset && !manager.isOnline()) {
      manager.setOnline(true);
    }
  }

  /// Counts this provider as speaking for [client]'s connectivity until
  /// [_releaseOnline].
  static void _speakForOnline(QueryClient client) {
    final manager = client.onlineManager;
    _onlineSpeakers[manager] = (_onlineSpeakers[manager] ?? 0) + 1;
  }

  /// How many mounted providers currently have an `onlineStatus` for a client
  /// on one [OnlineManager] — see [_releaseOnline].
  static final Map<OnlineManager, int> _onlineSpeakers = <OnlineManager, int>{};

  /// Tells [client] what the current [QueryClientProvider.onlineStatus] says,
  /// before [_follow]'s stream has said anything. `null` tells it nothing —
  /// a client with no status keeps its own default.
  void _applyOnlineStatus(QueryClient client) {
    final status = widget.onlineStatus;
    if (status != null) {
      client.onlineManager.setOnline(status.initial);
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
  /// installation what it actually is: shared.
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
  /// Synchronous on purpose, where TanStack Query's default is a zero-delay
  /// timer: a `setState` outside a build is exactly what Flutter expects from a
  /// tap handler or a resolved future, and delivering right away means one
  /// `pump` in a test — or one frame in an app — shows the new result.
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
    final sameStream = widget.onlineStatus?.changes != null &&
        oldWidget.onlineStatus?.changes == widget.onlineStatus?.changes;
    final statusChanged = oldWidget.onlineStatus != widget.onlineStatus;
    // What the old stream last said, before a new one is followed.
    final lastOnline = _lastOnline;
    // Listened to first, as in `initState`: the one step that can fail, so
    // when it throws nothing has been told to any client. Flutter abandons
    // an element whose `didUpdateWidget` threw without disposing it, so
    // what this state held for the old widget is given back here, the way
    // `dispose` would (as in `initState`: an `initial: false` applied first
    // would stay, and so would the mount).
    if (statusChanged && !sameStream) {
      try {
        _follow(widget.onlineStatus);
      } catch (_) {
        _released = true;
        _stopObservingLifecycle();
        if (oldWidget.onlineStatus != null) {
          _releaseOnline(oldWidget.client);
        }
        _unmountClient(oldWidget.client);
        rethrow;
      }
    }
    if (clientChanged) {
      _stopObservingLifecycle();
      _unmountClient(oldWidget.client);
      _mountClient(widget.client);
      // The stream will not repeat itself for the newcomer, so it starts from
      // what the stream last said — but only while it is *the same* stream
      // still running. A connectivity source that has been taken away speaks
      // for nobody, and a value it left behind would pin a later client
      // offline with nothing able to put it back.
      if (lastOnline != null && sameStream) {
        widget.client.onlineManager.setOnline(lastOnline);
      } else if (_lastOnline == null) {
        // Unless a new stream already said something while it was listened
        // to.
        _applyOnlineStatus(widget.client);
      }
    }
    if (clientChanged ||
        oldWidget.observeAppLifecycle != widget.observeAppLifecycle) {
      _stopObservingLifecycle();
      if (widget.observeAppLifecycle) {
        _observeLifecycle(widget.client);
      }
    } else if (widget.observeAppLifecycle &&
        oldWidget.isAppShown != widget.isAppShown) {
      // The listener reads the new mapping by itself; what it cannot do is
      // re-map the state the app is already in, which the class doc promises
      // is mapped too.
      _applyCurrentLifecycleState(widget.client);
    }
    if (statusChanged) {
      // A changed status reaches the client as it stands — except when one
      // stream is swapped for another, where the client already has a verdict
      // from a live source and `initial` is the wrong thing to rewind it to.
      // Anyone building their stream in `build` hands the provider a new
      // stream object every rebuild (the class doc's own example does not,
      // but the provider survives it), and re-applying `initial`
      // there would yank the client back online between each rebuild and the
      // new stream's first event. A fixed status has no such source: applying
      // it here is the only way it can reach the client at all.
      // A new stream that delivered while it was listened to has already
      // said more than `initial` can. Changing only `initial` does
      // not replace the source or its latest event, and a single-subscription
      // stream cannot be listened to again: followed above, only when it is
      // a different stream.
      if (!clientChanged &&
          _lastOnline == null &&
          !(oldWidget.onlineStatus is OnlineStatusStream &&
              widget.onlineStatus is OnlineStatusStream)) {
        _applyOnlineStatus(widget.client);
      }
    }
    // Who speaks for which client's connectivity, counted: a client
    // left for another is left as it was; a status taken away from the same
    // client lets it go back online once nobody else speaks for it.
    final spoke = oldWidget.onlineStatus != null;
    final speaks = widget.onlineStatus != null;
    if (clientChanged) {
      if (spoke) _releaseOnline(oldWidget.client, reset: false);
      if (speaks) _speakForOnline(widget.client);
    } else if (spoke != speaks) {
      if (speaks) {
        _speakForOnline(widget.client);
      } else {
        _releaseOnline(widget.client);
      }
    }
  }

  @override
  void dispose() {
    if (_released) {
      super.dispose();
      return;
    }
    _stopObservingLifecycle();
    _cancelOnline();
    if (widget.onlineStatus != null) {
      _releaseOnline(widget.client);
    }
    _unmountClient(widget.client);
    super.dispose();
  }

  // One scope serves both `of` and `context.query`: the same field, the same
  // `updateShouldNotify` and the same lifetime, so one element and one
  // dependency set for one fact.
  @override
  Widget build(BuildContext context) =>
      QueryScope(client: widget.client, child: widget.child);
}
