/// The gate every controller's notification passes: one carrying the state
/// its listeners have already seen is dropped.
///
/// The builders and the two keyless reads each skip a rebuild whose value has
/// not moved — that decision is `ReadEntry`, one implementation for all four
/// call styles (C48, https://github.com/KoTTi97/flutter_query/issues/57). A
/// *controller* had no such decision and passed every notification on, so a
/// `ValueListenableBuilder` over one — which is the fourth call style —
/// rebuilt for notifications carrying nothing. That asymmetry was C49's item
/// 3 (https://github.com/KoTTi97/flutter_query/issues/55), and closing it is
/// what makes "nothing rebuilds for nothing" true in all four styles rather
/// than in three.
///
/// Two notifications carrying nothing, both real:
///
/// * **The one the first subscribe provokes.** A controller's `value` before
///   anyone listens is the *optimistic* result — `fetching` for a query that
///   will fetch on subscribe — so the reader's first build already showed
///   what the observer then reports. [seed] is the answer: it records what a
///   listener arriving right now would read, before the subscription that
///   provokes it.
/// * **The second of two notifications delivered together.** Notifications
///   go through the client's `NotifyManager`, which schedules them; a
///   mutation that goes pending and then succeeds inside one scheduling
///   window queues two, and both read the same settled value when they run.
///
/// "Carries nothing" is exactly checkable, which is why this is a gate and
/// not a guess: a `QueryResult`'s `==` covers its data, its error and an
/// identity tuple down to `fetchStatus`, `isStale` and `failureCount`, and an
/// infinite query's `observedState` adds the paging flags that live beside
/// the result. Two equal states differ in nothing a listener could act on —
/// one that wants to know a fetch *happened* reads `fetchStatus`, which is
/// inside the equality.
library;

import 'package:flutter/foundation.dart';

/// What a controller's listeners have already seen, and whether what it is
/// about to tell them is any different.
///
/// Composition rather than a mixin: the four controllers do not share a
/// superclass beyond [ChangeNotifier], and a mixin would have to put its
/// members on their public surface to be reachable from them.
class NotifyGate<T> {
  NotifyGate._(this._equals);

  /// For a state with value equality — a `QueryResult`, a `MutationResult`,
  /// the record an infinite query observes.
  factory NotifyGate.byValue() =>
      NotifyGate<T>._((seen, current) => seen == current);

  /// For a state that is a list. A `List` compares by identity and a
  /// collection controller builds a fresh one on every optimistic read, so
  /// `==` would answer "moved" every time; its elements carry value
  /// equality, and element-wise is the comparison the core's own collection
  /// observers already make before they notify at all.
  static NotifyGate<List<E>> elementWise<E>() =>
      NotifyGate<List<E>>._(listEquals);

  final bool Function(T? seen, T current) _equals;

  T? _seen;
  bool _seeded = false;

  /// Records what a listener arriving right now would read. Called before
  /// subscribing, so the notification the subscription itself provokes is
  /// measured against the value the reader's build actually showed.
  void seed(T state) {
    _seen = state;
    _seeded = true;
  }

  /// Whether [state] is worth telling the listeners about — and if it is,
  /// remembers it as what they have now seen.
  bool moved(T state) {
    if (_seeded && _equals(_seen, state)) {
      return false;
    }
    _seen = state;
    _seeded = true;
    return true;
  }
}
