/// Ported from `query-core/src/__tests__/focusManager.test.tsx`
/// at upstream `50680b98c`. 6 of 9 cases; the three that spy on `window` /
/// `document` are browser-environment omissions (see PORTING_NOTES.md).
library;

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('focusManager', () {
    late AppFocusManager focusManager;

    setUp(() {
      focusManager = AppFocusManager();
    });

    test(
      'should call previous remove handler when replacing an event listener',
      () {
        var remove1Calls = 0;
        var remove2Calls = 0;

        focusManager.setEventListener((_) => () => remove1Calls++);
        focusManager.setEventListener((_) => () => remove2Calls++);

        expect(remove1Calls, 1);
        expect(remove2Calls, 0);
      },
    );

    testFakeAsync('should use focused boolean arg', (time) async {
      var count = 0;

      void Function() setup(void Function(bool? focused) setFocused) {
        Future<void>.delayed(ms(20), () {
          count++;
          setFocused(true);
        }).ignore();
        return () {};
      }

      focusManager.setEventListener(setup);

      await time.advance(ms(20));
      expect(count, 1);
      expect(focusManager.isFocused(), isTrue);
    });

    test(
      // Upstream deletes `globalThis.document` to prove the manager defaults to
      // focused where there is nothing to ask. Pure Dart has nothing to ask in
      // the first place, so the same assertion is made against the default.
      'should return true for isFocused if document is undefined',
      () {
        focusManager.setFocused(null);
        expect(focusManager.isFocused(), isTrue);
      },
    );

    test(
      'should replace default window listener when a new event listener is set',
      () {
        var unsubscribeCalls = 0;
        var handlerCalls = 0;

        focusManager.setEventListener((_) {
          handlerCalls++;
          return () => unsubscribeCalls++;
        });

        final unsubscribe = focusManager.subscribe((_) {});

        // Should call the custom event once
        expect(handlerCalls, 1);

        unsubscribe();

        // Should unsubscribe our event listener once
        expect(unsubscribeCalls, 1);
      },
    );

    test('should call removeEventListener when last listener unsubscribes', () {
      var cleanupCalls = 0;
      focusManager.setEventListener((_) => () => cleanupCalls++);

      final unsubscribe1 = focusManager.subscribe((_) {});
      final unsubscribe2 = focusManager.subscribe((_) {});

      unsubscribe1();
      expect(cleanupCalls, 0);
      unsubscribe2();
      expect(cleanupCalls, 1);
    });

    test('should keep setup function even if last listener unsubscribes', () {
      var setupCalls = 0;
      void Function() setup(void Function(bool? focused) _) {
        setupCalls++;
        return () {};
      }

      focusManager.setEventListener(setup);

      final unsubscribe1 = focusManager.subscribe((_) {});

      expect(setupCalls, 1);

      unsubscribe1();

      final unsubscribe2 = focusManager.subscribe((_) {});

      expect(setupCalls, 2);

      unsubscribe2();
    });

    test('should call listeners when setFocused is called', () {
      final calls = <bool>[];

      focusManager.subscribe(calls.add);

      focusManager.setFocused(true);
      focusManager.setFocused(true);

      expect(calls, equals(<bool>[true]));

      focusManager.setFocused(false);
      focusManager.setFocused(false);

      expect(calls, equals(<bool>[true, false]));

      focusManager.setFocused(null);
      focusManager.setFocused(null);

      expect(calls, equals(<bool>[true, false, true]));
    });
  });
}
