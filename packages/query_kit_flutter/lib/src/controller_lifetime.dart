/// The subscribe-while-listened dance every controller does, in one place
/// (C50, https://github.com/KoTTi97/flutter_query/issues/59).
library;

import 'package:flutter/foundation.dart';

import 'notify_gate.dart';

/// A controller is subscribed to its observer exactly while something is
/// listening to *it*, and tells its listeners only what they have not seen.
///
/// The four controllers wrote that twice over — `QueryController` and
/// `MutationController` byte-for-byte apart from a type argument, the other
/// two shorter and, in `MutationStateController`'s case, missing two of the
/// guards. What is hidden here is everything a fourth copy would get wrong:
///
/// * **One subscription, even when a listener arrives inside the first
///   notification.** [listenerAdded] can notify synchronously, a listener
///   called there may add another, and that nested call would still see no
///   handle and subscribe a second time — one of the two handles then
///   overwritten and lost, leaving an observer attached for good (third
///   review, 2026-09-10).
/// * **The handle is only kept while someone still wants it.** A listener may
///   leave inside its first notification, or the controller may be disposed
///   from it; the subscription goes with them, or the observer stays attached
///   with nobody to tell (F09).
/// * **The gate is seeded before subscribing**, so the notification the
///   subscription itself provokes is measured against the value the reader's
///   build actually showed ([NotifyGate]).
/// * **Nothing is delivered after [dispose]**, and [dispose] runs once.
///
/// Composition rather than a mixin or a base class, for [NotifyGate]'s reason
/// and one more: the controllers already extend `ChangeNotifier`, and
/// `hasListeners` and `notifyListeners` are protected there — reachable from
/// a closure written inside the controller, not from a collaborator. Hence
/// [hasListeners] and [notify], which are those two tear-offs.
class ControllerLifetime<S> {
  /// Wires the lifetime to its controller.
  ///
  /// [read] is what a listener arriving right now would see — a controller's
  /// `value`, or its whole observable state where that is more than the value
  /// — and [gate] decides when two of those are the same. [subscribe] is
  /// handed the delivery callback and returns the observer's unsubscribe
  /// handle; it is the one line that stays typed at the call site, because
  /// only the controller knows its observer's listener type.
  ControllerLifetime({
    required NotifyGate<S> gate,
    required S Function() read,
    required void Function() Function(VoidCallback deliver) subscribe,
    required bool Function() hasListeners,
    required VoidCallback notify,
  })  : _gate = gate,
        _read = read,
        _subscribe = subscribe,
        _hasListeners = hasListeners,
        _notify = notify;

  final NotifyGate<S> _gate;
  final S Function() _read;
  final void Function() Function(VoidCallback deliver) _subscribe;
  final bool Function() _hasListeners;
  final VoidCallback _notify;

  void Function()? _unsubscribe;
  bool _subscribing = false;
  bool _disposed = false;

  /// Whether the observer subscription is held right now. A controller reads
  /// the optimistic value while this is false: nothing is keeping its
  /// observer up to date yet.
  bool get isSubscribed => _unsubscribe != null;

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;

  /// Called by the controller's `addListener`, after `super.addListener`.
  /// Subscribes when this is the first listener and nothing is subscribed.
  void listenerAdded() {
    if (_unsubscribe != null || _disposed || _subscribing) {
      return;
    }
    _subscribing = true;
    _gate.seed(_read());
    final void Function() unsubscribe;
    try {
      unsubscribe = _subscribe(_deliver);
    } finally {
      _subscribing = false;
    }
    if (!_hasListeners() || _disposed) {
      unsubscribe();
    } else {
      _unsubscribe = unsubscribe;
    }
  }

  /// Called by the controller's `removeListener`, after
  /// `super.removeListener`. Unsubscribes once the last listener has gone.
  void listenerRemoved() {
    if (_hasListeners()) {
      return;
    }
    _unsubscribe?.call();
    _unsubscribe = null;
  }

  /// Releases the subscription. Returns false when it had already been
  /// released, which is the controller's cue to leave the rest of its
  /// `dispose` alone.
  bool dispose() {
    if (_disposed) {
      return false;
    }
    _disposed = true;
    _unsubscribe?.call();
    _unsubscribe = null;
    return true;
  }

  /// What the observer's notification runs, through the notify manager: the
  /// listeners hear about it only if the state moved.
  void _deliver() {
    if (_disposed || !_hasListeners() || !_gate.moved(_read())) {
      return;
    }
    _notify();
  }
}
