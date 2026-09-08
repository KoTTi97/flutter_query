import 'subscribable.dart';

/// Tracks network reachability.
///
/// Like [FocusManager], core stays unopinionated: it assumes online until an
/// adapter says otherwise, so `query_core` needs no connectivity dependency and
/// apps opt in (the demo installs a `connectivity_plus` adapter).
class OnlineManager extends Subscribable<void Function(bool online)> {
  bool _online = true;

  /// Sets connectivity. Only a real change notifies.
  void setOnline(bool online) {
    if (_online == online) {
      return;
    }
    _online = online;
    for (final listener in List.of(listeners)) {
      listener(online);
    }
  }

  bool get isOnline => _online;
}

/// The shared instance, as upstream.
final OnlineManager onlineManager = OnlineManager();
