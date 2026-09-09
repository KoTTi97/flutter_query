/// Port of `query-core/src/focusManager.ts` at upstream `50680b98c`.
library;

import 'subscribable.dart';

/// Installs a platform listener; returns its cleanup, if it has one.
typedef FocusSetup = void Function() Function(
    void Function(bool? focused) setFocused);

/// Tracks whether the app is in the foreground.
///
/// Pure Dart has no notion of focus, so the default is "focused" and changes
/// arrive through [setFocused] or a [setEventListener] adapter — the Flutter
/// binding installs one backed by `AppLifecycleListener`
/// (https://github.com/KoTTi97/flutter_query/issues/19).
class AppFocusManager extends Subscribable<void Function(bool focused)> {
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
      _focused = focused;
      onFocus();
    }
  }

  /// Notifies every listener with the current state.
  void onFocus() {
    final focused = isFocused();
    for (final listener in List.of(listeners)) {
      listener(focused);
    }
  }
}
