/// Where the [QueryClient] lives, and where the Flutter-side adapters are
/// installed (https://github.com/KoTTi97/flutter_query/issues/22).
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:tanstack_query_core/tanstack_query_core.dart';

import 'query_context.dart';

/// Provides a [QueryClient] to the widgets below it, and wires the client to
/// Flutter while it is mounted.
///
/// Three things happen at mount:
///
/// 1. **App lifecycle → focus.** `onShow`/`onHide` from [AppLifecycleListener]
///    set the client's focus state. `onInactive` is deliberately ignored: on
///    iOS it fires for the notification shade and every system dialog, and
///    treating those as "unfocused" would refetch the world on the way back.
/// 2. **The notify scheduler.** Notifications that arrive while a build is in
///    flight are deferred to a post-frame callback, so a query resolving
///    mid-build cannot call `setState` during that build.
/// 3. **Connectivity, only if you bring it.** Pass [onlineStatus] and the
///    client follows it. Nothing is installed by default and no connectivity
///    package is a dependency — see the README for the `connectivity_plus`
///    snippet.
class QueryClientProvider extends StatefulWidget {
  const QueryClientProvider({
    super.key,
    required this.client,
    required this.child,
    this.onlineStatus,
    this.observeAppLifecycle = true,
  });

  final QueryClient client;
  final Widget child;

  /// Optional connectivity signal. `true` means "assume the network is
  /// reachable".
  final Stream<bool>? onlineStatus;

  /// Whether to map the app's lifecycle onto the client's focus state.
  final bool observeAppLifecycle;

  /// The nearest client above [context].
  ///
  /// Throws when there is none: a missing provider is a wiring mistake, and a
  /// nullable return would only move the crash somewhere less helpful.
  static QueryClient of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_QueryClientScope>();
    assert(
      scope != null,
      'No QueryClientProvider found above this widget. Wrap your app (or the '
      'subtree that uses queries) in QueryClientProvider(client: …).',
    );
    return scope!.client;
  }

  /// Like [of], but without subscribing the calling element to changes.
  static QueryClient read(BuildContext context) {
    final element =
        context.getElementForInheritedWidgetOfExactType<_QueryClientScope>();
    assert(
      element != null,
      'No QueryClientProvider found above this widget.',
    );
    return (element!.widget as _QueryClientScope).client;
  }

  @override
  State<QueryClientProvider> createState() => _QueryClientProviderState();
}

class _QueryClientProviderState extends State<QueryClientProvider> {
  AppLifecycleListener? _lifecycle;
  StreamSubscription<bool>? _onlineSubscription;
  ScheduleFunction? _previousScheduler;

  @override
  void initState() {
    super.initState();
    _install();
  }

  void _install() {
    // Kept so it can be put back: notify managers are shared by default, and a
    // scheduler that outlived the provider that set it would keep deferring
    // notifications to a frame that is never coming.
    _previousScheduler = widget.client.notifyManager.scheduler;
    widget.client.notifyManager.setScheduler(_scheduleNotification);
    widget.client.mount();

    if (widget.observeAppLifecycle) {
      _lifecycle = AppLifecycleListener(
        onShow: () => widget.client.focusManager.setFocused(true),
        onHide: () => widget.client.focusManager.setFocused(false),
      );
    }

    final onlineStatus = widget.onlineStatus;
    if (onlineStatus != null) {
      _onlineSubscription =
          onlineStatus.listen(widget.client.onlineManager.setOnline);
    }
  }

  void _uninstall() {
    _lifecycle?.dispose();
    _lifecycle = null;
    _onlineSubscription?.cancel();
    _onlineSubscription = null;
    _restoreScheduler(widget.client);
    widget.client.unmount();
  }

  void _restoreScheduler(QueryClient client) {
    final previous = _previousScheduler;
    if (previous != null) {
      client.notifyManager.setScheduler(previous);
      _previousScheduler = null;
    }
  }

  /// Runs [callback] now when that is safe, and after this frame when it is
  /// not. Called for every batch of cache notifications.
  static void _scheduleNotification(void Function() callback) {
    final phase = SchedulerBinding.instance.schedulerPhase;
    final duringBuild = phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (!duringBuild) {
      scheduleMicrotask(callback);
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) => callback());
  }

  @override
  void didUpdateWidget(QueryClientProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client ||
        oldWidget.onlineStatus != widget.onlineStatus ||
        oldWidget.observeAppLifecycle != widget.observeAppLifecycle) {
      _uninstallFor(oldWidget);
      _install();
    }
  }

  void _uninstallFor(QueryClientProvider previous) {
    _lifecycle?.dispose();
    _lifecycle = null;
    _onlineSubscription?.cancel();
    _onlineSubscription = null;
    _restoreScheduler(previous.client);
    previous.client.unmount();
  }

  @override
  void dispose() {
    _uninstall();
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
