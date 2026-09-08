/// Base for the observable pieces of the cache.
///
/// Listeners are held in insertion order and compared by identity, so the
/// closure returned by [subscribe] is the only way to remove one.
abstract class Subscribable<TListener extends Function> {
  final Set<TListener> listeners = <TListener>{};

  /// Registers [listener] and returns the function that removes it.
  void Function() subscribe(TListener listener) {
    listeners.add(listener);
    onSubscribe();
    return () {
      listeners.remove(listener);
      onUnsubscribe();
    };
  }

  bool get hasListeners => listeners.isNotEmpty;

  /// Called after every [subscribe]. Implementations typically start their
  /// event source once the first listener arrives.
  void onSubscribe() {}

  /// Called after every unsubscribe. Implementations typically tear down their
  /// event source once the last listener leaves.
  void onUnsubscribe() {}
}
