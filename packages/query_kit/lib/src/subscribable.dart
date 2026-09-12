/// Port of `query-core/src/subscribable.ts` at upstream `50680b98c`.
library;

import 'package:meta/meta.dart';

import 'listener_registry.dart';

/// A minimal listener registry with hooks for the first and last listener.
///
/// Upstream returns an unsubscribe closure from [subscribe]; so do we, because
/// the alternative — handing back the listener and asking callers to pass it to
/// `unsubscribe` — makes anonymous closures unremovable.
///
/// The list itself, the once-only handle and the notification loop are
/// [ListenerRegistry], which the four observers hold as well; this class is
/// upstream's name for it plus the two hooks (C50,
/// https://github.com/KoTTi97/flutter_query/issues/59).
abstract class Subscribable<TListener extends Function> {
  final ListenerRegistry<TListener> _registry = ListenerRegistry<TListener>();

  /// The listeners currently registered, in subscription order, read-only.
  /// Subclasses notifying by hand iterate this; [notifyListeners] is the loop
  /// that skips a listener an earlier one removed.
  @protected
  List<TListener> get listeners => _registry.listeners;

  /// Whether at least one listener is registered — what tells a manager to keep
  /// its platform event source installed.
  bool get hasListeners => _registry.hasListeners;

  /// Registers [listener] and returns the function that removes it again.
  ///
  /// Subscribing the same function twice registers it twice; each handle
  /// removes its own registration, and calling one twice removes nothing the
  /// second time. See [ListenerRegistry] for why.
  void Function() subscribe(TListener listener) {
    final remove = _registry.add(listener, onRemoved: onUnsubscribe);
    onSubscribe();
    return remove;
  }

  /// Calls every listener through [deliver]. See [ListenerRegistry.notify]:
  /// a listener an earlier one removed is skipped, and a throw is reported to
  /// the zone rather than escaping into whatever produced the event.
  @protected
  void notifyListeners(void Function(TListener listener) deliver) =>
      _registry.notify(deliver);

  /// Called after every [subscribe]. Subclasses use it to install their event
  /// source when the first listener arrives.
  @protected
  void onSubscribe() {}

  /// Called after every unsubscribe. Subclasses use it to tear their event
  /// source down once [hasListeners] turns false.
  @protected
  void onUnsubscribe() {}
}
