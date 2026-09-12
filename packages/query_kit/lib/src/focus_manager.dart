/// Port of `query-core/src/focusManager.ts` at upstream `50680b98c`.
library;

import 'package:clock/clock.dart';

import 'subscribable.dart';

/// Installs a platform listener; returns its cleanup, if it has one.
typedef FocusSetup = void Function() Function(
    void Function(bool? focused) setFocused);

/// Tracks whether the app is in the foreground.
///
/// Pure Dart has no notion of focus, so the default is "focused". Nothing is
/// installed for you: changes arrive through [setFocused] — the Flutter
/// binding's `QueryClientProvider` maps every `AppLifecycleState` onto it
/// directly (https://github.com/KoTTi97/flutter_query/issues/19) — or through
/// a [setEventListener] adapter of your own, for a focus source that is not
/// the app lifecycle.
class AppFocusManager extends Subscribable<void Function(bool focused)> {
  /// Creates a manager. [refetchMinBackgroundDuration] suppresses new focus
  /// refetches after shorter absences, without blocking paused work resuming.
  AppFocusManager({this.refetchMinBackgroundDuration = Duration.zero}) {
    if (refetchMinBackgroundDuration.isNegative) {
      throw ArgumentError.value(refetchMinBackgroundDuration,
          'refetchMinBackgroundDuration', 'Must not be negative');
    }
  }

  /// Minimum time unfocused before returning to focus starts new refetches.
  final Duration refetchMinBackgroundDuration;

  DateTime? _unfocusedAt;
  bool _shouldRefetchOnFocus = true;

  /// Whether the current focus notification permits new refetches. Paused
  /// requests may always continue when focused, regardless of this value.
  bool get shouldRefetchOnFocus => _shouldRefetchOnFocus;

  bool? _focused;
  void Function()? _cleanup;
  FocusSetup? _setup;

  /// Whether the app is currently in the foreground. Reads the value last set
  /// by [setFocused], or `true` when nothing has been set — pure Dart cannot
  /// tell, so it assumes the best case.
  bool isFocused() => _focused ?? true;

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

  /// Replaces the source of focus events.
  void setEventListener(FocusSetup setup) {
    _setup = setup;
    _cleanup?.call();
    _cleanup = setup((focused) {
      if (focused is bool) {
        setFocused(focused);
      } else {
        onFocus();
      }
    });
  }

  /// Sets the focus state by hand. Passing `null` returns control to the
  /// installed event listener.
  void setFocused(bool? focused) {
    final changed = _focused != focused;
    if (changed) {
      final wasFocused = isFocused();
      _focused = focused;
      final nowFocused = isFocused();
      if (wasFocused && !nowFocused) {
        _unfocusedAt = clock.now();
      }
      var refetchQueries = true;
      if (!wasFocused && nowFocused) {
        final since = _unfocusedAt;
        refetchQueries = since == null ||
            clock.now().difference(since) >= refetchMinBackgroundDuration;
        _unfocusedAt = null;
      }
      onFocus(refetchQueries: refetchQueries);
    }
  }

  /// Notifies every listener with the current state. [refetchQueries] controls
  /// new refetches only, never continuation of paused work.
  void onFocus({bool refetchQueries = true}) {
    _shouldRefetchOnFocus = refetchQueries;
    final focused = isFocused();
    notifyListeners((listener) => listener(focused));
  }
}
