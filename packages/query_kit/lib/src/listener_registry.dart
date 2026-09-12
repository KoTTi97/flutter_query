/// The listener list every subscribable thing in the core keeps, in one
/// place (C50, https://github.com/KoTTi97/flutter_query/issues/59).
library;

import 'dart:async';

/// A list of listeners, the handles that remove them, and the loop that calls
/// them.
///
/// Five things in the core keep one — [Subscribable], which the caches and the
/// managers extend, and the four observers, which cannot extend it because
/// Dart has no declaration-site variance and a listener type that mentions the
/// observer's own type parameters puts them in a contravariant position of a
/// superinterface. Composition is what crosses that line: the registry is a
/// *field*, so the listener type stays exact.
///
/// Four facts live here and nowhere else:
///
/// * **A `List`, where upstream keeps a `Set`.** In JavaScript two functions
///   are never equal, so a `Set` there is only an insertion-ordered list that
///   cannot hold the *same* closure twice. In Dart a tear-off of one method on
///   one object is `==` to itself, so two independent subscribers passing
///   `cache.onEvent` collapsed into a single entry — and the first of them to
///   unsubscribe silenced the other. A list keeps one entry per [add], which
///   is what the returned handle promises to remove (eighth review,
///   2026-09-10).
/// * **A handle removes its own registration, once.** Called twice it removes
///   nothing more. Unguarded, a second call took another registration of the
///   same listener with it and ran the last-listener teardown under a
///   subscriber still present (ninth review, 2026-09-10, C6) — a bug that had
///   to be fixed three times, in [Subscribable] and then in both observers,
///   which is the case for this module.
/// * **A listener removed while a notification is running is not called.**
///   Iterating the live list would throw in Dart, so [notify] iterates a copy
///   — and a copy alone would call a listener that an earlier one had just
///   unsubscribed. Upstream's `Set.forEach` skips it; so does this.
/// * **A listener's throw is the listener's.** It is reported to the zone and
///   the rest still run. Unisolated, a devtools or logging subscriber that
///   threw on a `failed` action blew up the retryer's loop and left the fetch
///   pending forever (fourth review, 2026-09-09).
///
/// What is *not* here is what the first and last listener mean: installing an
/// event source, attaching an observer, starting a fetch. Those differ in
/// every holder and stay at the call site, where [length] and [hasListeners]
/// answer for them.
class ListenerRegistry<TListener extends Function> {
  final List<_Registration<TListener>> _listeners = [];

  /// The listeners currently registered, in subscription order, read-only.
  List<TListener> get listeners =>
      List.unmodifiable(_listeners.map((entry) => entry.listener));

  /// How many registrations there are — one per [add], even when the same
  /// function was added twice. `== 1` is how a holder spots the first one.
  int get length => _listeners.length;

  /// Whether at least one listener is registered.
  bool get hasListeners => _listeners.isNotEmpty;

  /// Registers [listener] and returns the function that removes it again,
  /// running [onRemoved] after it has gone.
  ///
  /// The handle is once-only: a second call removes nothing and does not run
  /// [onRemoved] again.
  void Function() add(TListener listener, {void Function()? onRemoved}) {
    final entry = _Registration(listener);
    _listeners.add(entry);
    return () {
      if (!entry.active) {
        return;
      }
      entry.active = false;
      _listeners.remove(entry);
      onRemoved?.call();
    };
  }

  /// Calls every listener through [deliver], skipping any that an earlier one
  /// removed and reporting a throw to the zone.
  void notify(void Function(TListener listener) deliver) {
    for (final entry in List<_Registration<TListener>>.of(_listeners)) {
      if (!entry.active) {
        continue;
      }
      try {
        deliver(entry.listener);
      } catch (error, stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);
      }
    }
  }

  /// Drops every registration. Earlier handles become no-ops, including their
  /// removal hooks, and cannot affect a later registration of the same callback.
  void clear() {
    for (final entry in _listeners) {
      entry.active = false;
    }
    _listeners.clear();
  }
}

class _Registration<TListener extends Function> {
  _Registration(this.listener);
  final TListener listener;
  bool active = true;
}
