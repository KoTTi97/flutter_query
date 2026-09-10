/// Port of `query-core/src/onlineManager.ts` at upstream `50680b98c`.
library;

import 'subscribable.dart';

/// Installs a platform listener; returns its cleanup, if it has one.
typedef OnlineSetup = void Function() Function(
    void Function(bool online) setOnline);

/// Tracks whether the device believes it has a network connection.
///
/// The default is "online". Nothing is installed for you: the Flutter binding
/// takes an optional `Stream<bool>` and depends on no connectivity package
/// (https://github.com/KoTTi97/flutter_query/issues/21); a
/// `connectivity_plus` stream, which reports a *link* rather than
/// reachability, is the usual source
/// (https://github.com/KoTTi97/flutter_query/issues/5).
class OnlineManager extends Subscribable<void Function(bool online)> {
  bool _online = true;
  void Function()? _cleanup;
  OnlineSetup? _setup;

  /// Whether the device is currently believed to be online. Reads the value
  /// last passed to [setOnline], or `true` when nothing has been set; the
  /// retryer consults it before starting and before resuming a paused fetch.
  bool isOnline() => _online;

  @override
  void onSubscribe() {
    if (_cleanup == null) {
      final setup = _setup;
      if (setup != null) {
        setEventListener(setup);
      }
    }
  }

  @override
  void onUnsubscribe() {
    if (!hasListeners) {
      _cleanup?.call();
      _cleanup = null;
    }
  }

  /// Replaces the source of connectivity events.
  void setEventListener(OnlineSetup setup) {
    _setup = setup;
    _cleanup?.call();
    _cleanup = setup(setOnline);
  }

  /// Sets the online state by hand.
  void setOnline(bool online) {
    final changed = _online != online;
    if (changed) {
      _online = online;
      for (final listener in List.of(listeners)) {
        listener(online);
      }
    }
  }
}
