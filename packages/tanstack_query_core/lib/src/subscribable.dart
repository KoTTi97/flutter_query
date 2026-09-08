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

  @protected
  Set<TListener> get listeners => _listeners;

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

  @protected
  void onSubscribe() {}

  @protected
  void onUnsubscribe() {}
}
