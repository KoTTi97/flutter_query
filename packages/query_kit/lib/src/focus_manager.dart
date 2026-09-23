/// App focus: [AppFocusManager].
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

import 'subscribable.dart';

/// An adapter for [AppFocusManager.setEventListener]: installs a platform
/// listener that reports focus through `setFocused`, and returns a function
/// that removes the listener again.
///
/// `setFocused(true)` / `setFocused(false)` report the new state;
/// `setFocused(null)` re-announces the current state without changing it.
///
/// {@category Managers}
typedef FocusSetup = void Function() Function(
    void Function(bool? focused) setFocused);

/// Tracks whether the app is in the foreground, so a mounted [QueryClient]
/// can refetch stale queries when the user comes back (the
/// `refetchOnWindowFocus` option) and resume work paused in the background.
///
/// Each client owns one, as `QueryClient.focusManager`. Pure Dart has no
/// notion of focus, so the default is "focused". Nothing is installed for
/// you: changes arrive through [setFocused] — the Flutter binding's
/// `QueryClientProvider` maps every `AppLifecycleState` onto it — or through
/// a [setEventListener] adapter of your own, for a focus source that is not
/// the app lifecycle.
///
/// ```dart
/// // By hand, e.g. from a desktop window's focus events:
/// client.focusManager.setFocused(false);
/// client.focusManager.setFocused(true); // refetches stale observed queries
///
/// // Or with an adapter over some event source:
/// client.focusManager.setEventListener((setFocused) {
///   final subscription = windowFocus.listen(setFocused);
///   return subscription.cancel;
/// });
/// ```
///
/// **The two are alternatives, not layers.** A [setEventListener] adapter
/// writes through [setFocused] exactly as the binding's lifecycle listener
/// does, so with both installed the last writer wins and neither can see the
/// other's verdict. Installing your own adapter therefore goes with
/// `QueryClientProvider(observeAppLifecycle: false)`, which is what turns the
/// lifecycle source off. This mirrors TanStack Query, where the browser's
/// `visibilitychange` listener is the built-in default and
/// `setEventListener` is what a React Native app calls with `AppState`.
///
/// {@category Managers}
class AppFocusManager extends Subscribable<void Function(bool focused)> {
  /// Creates a manager. [refetchMinBackgroundDuration] (default zero)
  /// suppresses new focus refetches after shorter absences, without blocking
  /// paused work resuming. Throws [ArgumentError] if it is negative.
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

  /// Reinstalls the event source the last listener's departure tore down.
  ///
  /// A setup that throws here is reported to the zone rather than thrown out
  /// of `subscribe`: the listener is registered by then, and a throw would
  /// lose the handle that removes it — a client's mount listener that could
  /// never be unsubscribed, and one more after every remount. The next
  /// subscription tries the setup again.
  @override
  @protected
  void onSubscribe() {
    if (_cleanup == null) {
      final setup = _setup;
      if (setup != null) {
        try {
          setEventListener(setup);
        } catch (error, stackTrace) {
          Zone.current.handleUncaughtError(error, stackTrace);
        }
      }
    }
  }

  @override
  @protected
  void onUnsubscribe() {
    if (!hasListeners) {
      _cleanup?.call();
      _cleanup = null;
    }
  }

  /// Replaces the source of focus events.
  ///
  /// [setup] is called at once with a `setFocused` callback and returns a
  /// cleanup function. The previous source's cleanup, if any, runs first.
  /// When the last listener of this manager unsubscribes (the client
  /// unmounts), the cleanup runs; when a listener subscribes again, [setup]
  /// is called again. A throwing [setup] throws out of this call.
  void setEventListener(FocusSetup setup) {
    _setup = setup;
    final previous = _cleanup;
    // Cleared before the setup runs: a setup that throws must not leave the
    // spent cleanup behind to be called a second time.
    _cleanup = null;
    previous?.call();
    _cleanup = setup((focused) {
      if (focused is bool) {
        setFocused(focused);
      } else {
        onFocus();
      }
    });
  }

  /// Sets the focus state by hand. Passing `null` forgets the value set by
  /// hand, and [isFocused] then answers `true` — pure Dart has nothing to
  /// consult (TanStack Query reads `document.visibilityState` here). It does
  /// not hand control to the event listener, which only ever calls this.
  ///
  /// A change notifies the listeners; a mounted client then refetches its
  /// stale observed queries on the way back to focus, unless the absence
  /// was shorter than [refetchMinBackgroundDuration].
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
