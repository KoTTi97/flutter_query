/// Ported from `query-core/src/__tests__/subscribable.test.tsx`
/// at upstream `50680b98c`. 9 of 9 cases.
library;

import 'package:tanstack_query_core/tanstack_query_core.dart';
import 'package:test/test.dart';

typedef Listener = void Function();

class SubscribableTest extends Subscribable<Listener> {
  int onSubscribeCalls = 0;
  int onUnsubscribeCalls = 0;

  @override
  void onSubscribe() => onSubscribeCalls++;

  @override
  void onUnsubscribe() => onUnsubscribeCalls++;
}

void main() {
  group('Subscribable', () {
    test('should call onSubscribe when a listener subscribes', () {
      final subscribable = SubscribableTest();

      subscribable.subscribe(() {});

      expect(subscribable.onSubscribeCalls, 1);
      expect(subscribable.onUnsubscribeCalls, 0);
    });

    test('should call onSubscribe once per subscribe call', () {
      final subscribable = SubscribableTest();

      subscribable.subscribe(() {});
      subscribable.subscribe(() {});

      expect(subscribable.onSubscribeCalls, 2);
    });

    test('should call onUnsubscribe when a listener unsubscribes', () {
      final subscribable = SubscribableTest();

      final unsubscribe = subscribable.subscribe(() {});
      unsubscribe();

      expect(subscribable.onUnsubscribeCalls, 1);
    });

    test(
      'should return `false` from hasListeners when there are no listeners',
      () {
        final subscribable = SubscribableTest();

        expect(subscribable.hasListeners, isFalse);
      },
    );

    test(
      'should return `true` from hasListeners while a listener is subscribed',
      () {
        final subscribable = SubscribableTest();

        subscribable.subscribe(() {});

        expect(subscribable.hasListeners, isTrue);
      },
    );

    test(
      'should return `false` from hasListeners after the last listener '
      'unsubscribes',
      () {
        final subscribable = SubscribableTest();

        final unsubscribe = subscribable.subscribe(() {});
        unsubscribe();

        expect(subscribable.hasListeners, isFalse);
      },
    );

    test('should still have listeners while at least one remains subscribed',
        () {
      final subscribable = SubscribableTest();

      final unsubscribe1 = subscribable.subscribe(() {});
      subscribable.subscribe(() {});

      unsubscribe1();

      expect(subscribable.hasListeners, isTrue);
    });

    test('should deduplicate the same listener reference', () {
      final subscribable = SubscribableTest();
      void listener() {}

      subscribable.subscribe(listener);
      subscribable.subscribe(listener);

      expect(subscribable.hasListeners, isTrue);

      final unsubscribe = subscribable.subscribe(listener);
      unsubscribe();

      expect(subscribable.hasListeners, isFalse);
    });

    test('should keep a stable subscribe reference when destructured', () {
      final subscribable = SubscribableTest();
      // Dart's equivalent of destructuring a method: a tear-off, which binds
      // the receiver.
      final subscribe = subscribable.subscribe;

      final unsubscribe = subscribe(() {});

      expect(subscribable.onSubscribeCalls, 1);
      expect(subscribable.hasListeners, isTrue);

      unsubscribe();

      expect(subscribable.hasListeners, isFalse);
    });
  });
}
