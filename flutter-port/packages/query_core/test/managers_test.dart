import 'package:query_core/query_core.dart';
import 'package:test/test.dart';

/// Ports upstream `focusManager.test.tsx` / `onlineManager.test.tsx`, minus the
/// DOM-listener cases (visibilitychange, window online/offline events), which
/// have no core equivalent: the Flutter binding drives these instead (D10).
void main() {
  group('FocusManager', () {
    late FocusManager manager;

    setUp(() => manager = FocusManager());

    test('is focused by default', () {
      expect(manager.isFocused, isTrue);
    });

    test('notifies listeners on change', () {
      final events = <bool>[];
      manager.subscribe(events.add);

      manager.setFocused(false);
      expect(events, [false]);
      expect(manager.isFocused, isFalse);

      manager.setFocused(true);
      expect(events, [false, true]);
    });

    test('does not notify when the state is unchanged', () {
      final events = <bool>[];
      manager.setFocused(false);
      manager.subscribe(events.add);

      manager.setFocused(false);
      expect(events, isEmpty);
    });

    test('restores the default when set to null', () {
      final events = <bool>[];
      manager.setFocused(false);
      manager.subscribe(events.add);

      manager.setFocused(null);
      expect(events, [true]);
      expect(manager.isFocused, isTrue);
    });

    test('unsubscribing stops notifications', () {
      final events = <bool>[];
      final unsubscribe = manager.subscribe(events.add);

      unsubscribe();
      manager.setFocused(false);
      expect(events, isEmpty);
    });

    test('a listener unsubscribing during notification is safe', () {
      final events = <bool>[];
      late void Function() unsubscribe;
      unsubscribe = manager.subscribe((focused) {
        events.add(focused);
        unsubscribe();
      });
      manager.subscribe(events.add);

      manager.setFocused(false);
      expect(events, [
        false,
        false,
      ], reason: 'both listeners see the event the removal happened during');

      manager.setFocused(true);
      expect(events, [false, false, true], reason: 'only the survivor remains');
    });
  });

  group('OnlineManager', () {
    late OnlineManager manager;

    setUp(() => manager = OnlineManager());

    test('is online by default', () {
      expect(manager.isOnline, isTrue);
    });

    test('notifies listeners on change', () {
      final events = <bool>[];
      manager.subscribe(events.add);

      manager.setOnline(false);
      expect(events, [false]);
      expect(manager.isOnline, isFalse);

      manager.setOnline(true);
      expect(events, [false, true]);
    });

    test('does not notify when the state is unchanged', () {
      final events = <bool>[];
      manager.subscribe(events.add);

      manager.setOnline(true);
      expect(events, isEmpty);
    });
  });

  group('Subscribable', () {
    test('tracks whether it has listeners', () {
      final manager = FocusManager();
      expect(manager.hasListeners, isFalse);

      final unsubscribe = manager.subscribe((_) {});
      expect(manager.hasListeners, isTrue);

      unsubscribe();
      expect(manager.hasListeners, isFalse);
    });

    test('unsubscribing twice is harmless', () {
      final manager = FocusManager();
      final unsubscribe = manager.subscribe((_) {});

      unsubscribe();
      expect(unsubscribe, returnsNormally);
      expect(manager.hasListeners, isFalse);
    });
  });
}
