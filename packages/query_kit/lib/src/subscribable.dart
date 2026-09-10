/// Port of `query-core/src/subscribable.ts` at upstream `50680b98c`.
library;

import 'package:meta/meta.dart';

/// A minimal listener registry with hooks for the first and last listener.
///
/// Upstream returns an unsubscribe closure from [subscribe]; so do we, because
/// the alternative — handing back the listener and asking callers to pass it to
/// `unsubscribe` — makes anonymous closures unremovable.
abstract class Subscribable<TListener extends Function> {
  /// A `List`, where upstream keeps a `Set`.
  ///
  /// In JavaScript two functions are never equal, so a `Set` there is only an
  /// insertion-ordered list that cannot hold the *same* closure twice. In
  /// Dart a tear-off of one method on one object is `==` to itself, so two
  /// independent subscribers passing `cache.onEvent` collapsed into a single
  /// entry — and the first of them to unsubscribe silenced the other. A list
  /// keeps one entry per `subscribe`, which is what the returned handle
  /// promises to remove (eighth review, 2026-09-10). The observers already
  /// kept a list for this reason.
  final List<TListener> _listeners = <TListener>[];

  /// The listeners currently registered, in subscription order. Subclasses
  /// iterate a copy when notifying, since a listener may unsubscribe mid-loop.
  @protected
  List<TListener> get listeners => _listeners;

  /// Whether at least one listener is registered — what tells a manager to keep
  /// its platform event source installed.
  bool get hasListeners => _listeners.isNotEmpty;

  /// Registers [listener] and returns the function that removes it again.
  ///
  /// Subscribing the same function twice registers it twice; each handle
  /// removes its own registration, and calling one twice removes nothing the
  /// second time.
  void Function() subscribe(TListener listener) {
    _listeners.add(listener);
    onSubscribe();
    var removed = false;
    return () {
      if (removed) {
        return;
      }
      removed = true;
      // By identity, so one handle never takes another's registration.
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
