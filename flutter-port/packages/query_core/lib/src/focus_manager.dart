import 'subscribable.dart';

/// Tracks whether the app is in the foreground.
///
/// Core has no opinion about how focus is detected — the Flutter binding drives
/// this from `AppLifecycleListener`, and tests drive it directly. Until someone
/// says otherwise the app counts as focused, which keeps pure-Dart use (CLIs,
/// servers, tests) working without setup.
class FocusManager extends Subscribable<void Function(bool focused)> {
  bool? _focused;

  /// Sets focus state. Passing null restores the default (focused).
  ///
  /// Only a real change notifies, so repeated lifecycle events are free.
  void setFocused(bool? focused) {
    if (_focused == focused) {
      return;
    }
    _focused = focused;
    onFocus();
  }

  /// Notifies listeners with the current state.
  void onFocus() {
    final focused = isFocused;
    for (final listener in List.of(listeners)) {
      listener(focused);
    }
  }

  bool get isFocused => _focused ?? true;
}

/// The shared instance, as upstream.
final FocusManager focusManager = FocusManager();
