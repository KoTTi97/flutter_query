/// Connectivity: [OnlineManager].
library;

import 'dart:async';

import 'package:meta/meta.dart';

import 'subscribable.dart';

/// An adapter for [OnlineManager.setEventListener]: installs a platform
/// listener that reports connectivity through `setOnline`, and returns a
/// function that removes the listener again.
///
/// {@category Managers}
typedef OnlineSetup = void Function() Function(
    void Function(bool online) setOnline);

/// Tracks whether the device believes it has a network connection.
///
/// Fetches and mutations under [NetworkMode.online] (the default) do not
/// start while offline: they pause. When this manager reports online again,
/// a mounted [QueryClient] (see `QueryClient.mount`) continues them, resumes
/// paused mutations and refetches stale observed queries (the
/// `refetchOnReconnect` option). A client that is not mounted does not
/// listen, and what is paused stays paused.
///
/// Each client owns one, as `QueryClient.onlineManager`. The default is
/// "online". Nothing is installed for you: report connectivity with
/// [setOnline], or install an adapter with [setEventListener]. The Flutter
/// binding takes an optional `Stream<bool>` and depends on no connectivity
/// package; a `connectivity_plus` stream, which reports a *link* rather
/// than reachability, is the usual source.
///
/// ```dart
/// client.onlineManager.setEventListener((setOnline) {
///   final subscription = connectivityStream.listen(setOnline);
///   return subscription.cancel;
/// });
///
/// // Or by hand, e.g. in a test:
/// client.onlineManager.setOnline(false);
/// ```
///
/// {@category Managers}
class OnlineManager extends Subscribable<void Function(bool online)> {
  /// Creates a manager that reports online until [setOnline] or an adapter
  /// installed with [setEventListener] says otherwise.
  OnlineManager();

  bool _online = true;
  void Function()? _cleanup;
  OnlineSetup? _setup;

  /// Whether the device is currently believed to be online. Reads the value
  /// last passed to [setOnline], or `true` when nothing has been set; the
  /// retryer consults it before starting and before resuming a paused fetch.
  bool isOnline() => _online;

  /// Reinstalls the event source the last listener's departure tore down.
  ///
  /// A setup that throws here is reported to the zone rather than thrown out
  /// of `subscribe`: the listener is registered by then, and a throw would
  /// lose the handle that removes it — a client's mount listener that could
  /// never be unsubscribed, and one more after every remount. The next
  /// subscription tries the setup again.
  @override
  @protected
  void onSubscribe() {
    if (_cleanup == null) {
      final setup = _setup;
      if (setup != null) {
        try {
          setEventListener(setup);
        } catch (error, stackTrace) {
          Zone.current.handleUncaughtError(error, stackTrace);
        }
      }
    }
  }

  @override
  @protected
  void onUnsubscribe() {
    if (!hasListeners) {
      _cleanup?.call();
      _cleanup = null;
    }
  }

  /// Replaces the source of connectivity events.
  ///
  /// [setup] is called at once with the [setOnline] callback and returns a
  /// cleanup function. The previous source's cleanup, if any, runs first.
  /// When the last listener of this manager unsubscribes (the client
  /// unmounts), the cleanup runs; when a listener subscribes again, [setup]
  /// is called again. A throwing [setup] throws out of this call.
  void setEventListener(OnlineSetup setup) {
    _setup = setup;
    final previous = _cleanup;
    // Cleared before the setup runs: a setup that throws must not leave the
    // spent cleanup behind to be called a second time.
    _cleanup = null;
    previous?.call();
    _cleanup = setup(setOnline);
  }

  /// Sets the online state by hand. A change notifies the listeners — going
  /// online is what resumes paused work in a mounted client; setting the
  /// value it already has does nothing.
  void setOnline(bool online) {
    final changed = _online != online;
    if (changed) {
      _online = online;
      notifyListeners((listener) => listener(online));
    }
  }
}
