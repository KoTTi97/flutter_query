/// Port of `query-core/src/subscribable.ts` at upstream `50680b98c`.
library;

import 'package:meta/meta.dart';

/// A minimal listener registry with hooks for the first and last listener.
///
/// Upstream returns an unsubscribe closure from [subscribe]; so do we, because
/// the alternative — handing back the listener and asking callers to pass it to
/// `unsubscribe` — makes anonymous closures unremovable.
abstract class Subscribable<TListener extends Function> {
  final Set<TListener> _listeners = <TListener>{};

  /// The listeners currently registered, in subscription order. Subclasses
  /// iterate a copy when notifying, since a listener may unsubscribe mid-loop.
  @protected
  Set<TListener> get listeners => _listeners;

  /// Whether at least one listener is registered — what tells a manager to keep
  /// its platform event source installed.
  bool get hasListeners => _listeners.isNotEmpty;

  /// Registers [listener] and returns the function that removes it again.
  void Function() subscribe(TListener listener) {
    _listeners.add(listener);
    onSubscribe();
    return () {
      _listeners.remove(listener);
      onUnsubscribe();
    };
  }

  /// Called after every [subscribe]. Subclasses use it to install their event
  /// source when the first listener arrives.
  @protected
  void onSubscribe() {}

  /// Called after every unsubscribe. Subclasses use it to tear their event
  /// source down once [hasListeners] turns false.
  @protected
  void onUnsubscribe() {}
}
