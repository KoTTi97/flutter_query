/// Ported from `query-core/src/__tests__/subscribable.test.tsx`
/// at upstream `50680b98c`. 9 of 9 cases, one of them with a changed
/// assertion (see PORTING_NOTES, "a Set of listeners does not port"), plus
/// two port-specific cases beside it.
library;

// The unit under test is internal plumbing the package does not export.
import 'package:query_kit/src/subscribable.dart';
import 'package:test/test.dart';

typedef Listener = void Function();

class SubscribableTest extends Subscribable<Listener> {
  int onSubscribeCalls = 0;
  int onUnsubscribeCalls = 0;

  /// Calls every listener, so a test can see which ones are still there.
  void notify() {
    for (final listener in listeners.toList()) {
      listener();
    }
  }

  @override
  void onSubscribe() => onSubscribeCalls++;

  @override
  void onUnsubscribe() => onUnsubscribeCalls++;
}

/// Two subscriptions passing a tear-off of one method on one object.
class _Watcher {
  int calls = 0;

  void onEvent() => calls += 1;
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

    // Upstream's name is "should deduplicate the same listener reference",
    // and there it does: a `Set` of function objects, and one `delete`
    // removes the single entry three `add`s produced. The port keeps a list
    // instead, so each `subscribe` is its own registration and its own handle
    // — see PORTING_NOTES, "a Set of listeners does not port". In JavaScript
    // the difference is invisible (two functions are never equal); in Dart a
    // tear-off of one method on one object is equal to itself, so deduping
    // let one subscriber's unsubscribe silence another's.
    test('registers the same listener reference once per subscribe', () {
      final subscribable = SubscribableTest();
      void listener() {}

      subscribable.subscribe(listener);
      subscribable.subscribe(listener);

      expect(subscribable.hasListeners, isTrue);

      final unsubscribe = subscribable.subscribe(listener);
      unsubscribe();

      // Two registrations left, not zero: the handle removed its own.
      expect(subscribable.hasListeners, isTrue);
    });

    test('one subscriber cannot unsubscribe another', () {
      final subscribable = SubscribableTest();
      // Two independent subscribers that happen to pass a tear-off of the
      // same method on the same object — `==`-equal in Dart.
      final watcher = _Watcher();
      final first = subscribable.subscribe(watcher.onEvent);
      subscribable.subscribe(watcher.onEvent);

      first();
      expect(subscribable.hasListeners, isTrue);
      subscribable.notify();
      expect(watcher.calls, 1);
    });

    test('an unsubscribe handle called twice removes nothing more', () {
      final subscribable = SubscribableTest();
      void listener() {}

      final unsubscribe = subscribable.subscribe(listener);
      subscribable.subscribe(listener);

      unsubscribe();
      unsubscribe();

      expect(subscribable.hasListeners, isTrue);
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
