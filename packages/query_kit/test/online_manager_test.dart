/// Ported from `query-core/src/__tests__/onlineManager.test.tsx`
/// at upstream `50680b98c`. 6 of 11 cases; the five that spy on `window` /
/// `navigator` are browser-environment omissions (see PORTING_NOTES.md).
library;

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  group('onlineManager', () {
    late OnlineManager onlineManager;

    setUp(() {
      onlineManager = OnlineManager();
    });

    test(
      // Upstream forces `navigator` to be undefined; pure Dart has no
      // navigator, so this asserts the same default.
      'isOnline should return true if navigator is undefined',
      () {
        expect(onlineManager.isOnline(), isTrue);
      },
    );

    testFakeAsync('setEventListener should use online boolean arg', (
      time,
    ) async {
      var count = 0;

      void Function() setup(void Function(bool online) setOnline) {
        Future<void>.delayed(ms(20), () {
          count++;
          setOnline(false);
        }).ignore();
        return () {};
      }

      onlineManager.setEventListener(setup);

      await time.advance(ms(20));
      expect(count, 1);
      expect(onlineManager.isOnline(), isFalse);
    });

    test(
      'setEventListener should call previous remove handler when replacing an '
      'event listener',
      () {
        var remove1Calls = 0;
        var remove2Calls = 0;

        onlineManager.setEventListener((_) => () => remove1Calls++);
        onlineManager.setEventListener((_) => () => remove2Calls++);

        expect(remove1Calls, 1);
        expect(remove2Calls, 0);
      },
    );

    test('should call removeEventListener when last listener unsubscribes', () {
      var cleanupCalls = 0;
      onlineManager.setEventListener((_) => () => cleanupCalls++);

      final unsubscribe1 = onlineManager.subscribe((_) {});
      final unsubscribe2 = onlineManager.subscribe((_) {});

      unsubscribe1();
      expect(cleanupCalls, 0);
      unsubscribe2();
      expect(cleanupCalls, 1);
    });

    test('should keep setup function even if last listener unsubscribes', () {
      var setupCalls = 0;
      void Function() setup(void Function(bool online) _) {
        setupCalls++;
        return () {};
      }

      onlineManager.setEventListener(setup);

      final unsubscribe1 = onlineManager.subscribe((_) {});

      expect(setupCalls, 1);

      unsubscribe1();

      final unsubscribe2 = onlineManager.subscribe((_) {});

      expect(setupCalls, 2);

      unsubscribe2();
    });

    test('should call listeners when setOnline is called', () {
      final calls = <bool>[];

      onlineManager.subscribe(calls.add);

      onlineManager.setOnline(false);
      onlineManager.setOnline(false);

      expect(calls, equals(<bool>[false]));

      onlineManager.setOnline(true);
      onlineManager.setOnline(true);

      expect(calls, equals(<bool>[false, true]));
    });
  });
}
