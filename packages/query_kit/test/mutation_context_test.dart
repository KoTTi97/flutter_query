/// Port-only: `mutationFnWithContext` and `Mutation.cancel` (#83). Upstream
/// has neither the `onMutate` result nor a signal in its function context,
/// and cannot cancel a mutation.
library;

import 'dart:async';

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

import 'test_utils.dart';

void main() {
  testFakeAsync(
      'the function is told the client, meta, key and what onMutate returned',
      (time) async {
    final client = testClient();
    final key = queryKey();
    final mutationKey = queryKey();
    client.setQueryData<String>(key, 'old');
    MutationFunctionContext<String>? seen;
    final observer = MutationObserver<String, String, String>(
        client,
        MutationOptions(
          mutationKey: mutationKey,
          meta: 'm',
          onMutate: (name) {
            final before = client.getQueryData<String>(key)!;
            client.setQueryData<String>(key, name);
            return before;
          },
          mutationFnWithContext: (name, context) async {
            seen = context;
            // The cache is already patched; the context still knows.
            return '${context.onMutateResult} -> ${client.getQueryData<String>(key)}';
          },
        ));
    expect(await observer.mutateAsync('new'), 'old -> new');
    expect(seen!.client, same(client));
    expect(seen!.meta, 'm');
    expect(seen!.mutationKey, mutationKey);
    expect(seen!.signal.isCancelled, isFalse);
    observer.destroy();
    client.clear();
  });

  testFakeAsync('a retry gets the same signal and the same onMutate result',
      (time) async {
    final client = testClient();
    final contexts = <MutationFunctionContext<int>>[];
    final observer = MutationObserver<int, void, int>(
        client,
        MutationOptions(
          retry: const RetryPolicy.times(1),
          retryDelay: const RetryDelay.fixed(Duration(milliseconds: 10)),
          onMutate: (_) => 7,
          mutationFnWithContext: (_, context) async {
            contexts.add(context);
            return contexts.length == 1 ? throw StateError('once') : 1;
          },
        ));
    final done = observer.mutateAsync(null);
    await time.advance(const Duration(milliseconds: 10));
    expect(await done, 1);
    expect(contexts, hasLength(2));
    expect(contexts[1].signal, same(contexts[0].signal));
    expect(contexts.map((c) => c.onMutateResult), [7, 7]);
    observer.destroy();
    client.clear();
  });

  testFakeAsync(
      'cancel fails the run with a CancelledError, cancels the signal, runs '
      'the rollback and discards what the function returns later',
      (time) async {
    final client = testClient();
    final key = queryKey();
    client.setQueryData<String>(key, 'old');
    final calls = <String>[];
    var aborted = false;
    final observer = MutationObserver<String, String, String>(
        client,
        MutationOptions(
          retry: const RetryPolicy.times(3),
          onMutate: (name) {
            final before = client.getQueryData<String>(key)!;
            client.setQueryData<String>(key, name);
            return before;
          },
          mutationFnWithContext: (name, context) {
            calls.add('fn');
            context.signal.onCancel(() => aborted = true);
            return Future.delayed(const Duration(seconds: 10), () => name);
          },
          onSuccess: (_, __, ___) => calls.add('success'),
          onError: (error, _, __, before) {
            calls.add('error ${error is CancelledError}');
            client.setQueryData<String>(key, before!);
          },
          onSettled: (_, __, ___, ____, _____) => calls.add('settled'),
        ));
    final unsubscribe = observer.subscribe((_) {});
    Object? thrown;
    unawaited(observer.mutateAsync('new').then((_) {}, onError: (Object e) {
      thrown = e;
    }));
    await time.advance(const Duration(seconds: 1));
    expect(client.getQueryData<String>(key), 'new');

    observer.cancel();
    expect(aborted, isTrue, reason: 'the signal fires synchronously');
    await time.flushMicrotasks();
    expect(thrown, isA<CancelledError>());
    expect(observer.currentResult.isError, isTrue);
    expect(client.getQueryData<String>(key), 'old');

    await time.advance(const Duration(seconds: 10));
    expect(calls, ['fn', 'error true', 'settled'],
        reason: 'no retry, and the late result changes nothing');
    expect(observer.currentResult.isError, isTrue);

    observer.cancel(); // nothing running: nothing happens
    unsubscribe();
    observer.destroy();
    client.clear();
  });

  testFakeAsync(
      'cancelling a mutation queued behind its scope fails it without running '
      'it, and the scope moves on', (time) async {
    final client = testClient();
    const scope = MutationScope('device');
    final ran = <String>[];
    MutationObserver<String, String, void> writer() => MutationObserver(
        client,
        MutationOptions.simple(
          scope: scope,
          mutationFn: (String name) {
            ran.add(name);
            return Future.delayed(const Duration(seconds: 1), () => name);
          },
        ));
    final first = writer();
    final second = writer();
    final third = writer();
    first.mutate('a');
    Object? secondError;
    unawaited(second.mutateAsync('b').then((_) {}, onError: (Object e) {
      secondError = e;
    }));
    third.mutate('c');
    await time.flushMicrotasks();

    second.cancel();
    await time.flushMicrotasks();
    expect(secondError, isA<CancelledError>());

    await time.advance(const Duration(seconds: 2));
    expect(ran, ['a', 'c']);
    for (final observer in [first, second, third]) {
      observer.destroy();
    }
    client.clear();
  });

  testFakeAsync('cancel during an async onMutate: the function never runs',
      (time) async {
    final client = testClient();
    var ran = false;
    final observer = MutationObserver<int, void, int>(
        client,
        MutationOptions(
          onMutate: (_) =>
              Future.delayed(const Duration(milliseconds: 10), () => 1),
          mutationFnWithContext: (_, __) {
            ran = true;
            return 1;
          },
        ));
    Object? thrown;
    unawaited(observer.mutateAsync(null).then((_) {}, onError: (Object e) {
      thrown = e;
    }));
    await time.flushMicrotasks();
    observer.cancel();
    await time.advance(const Duration(milliseconds: 10));
    expect(thrown, isA<CancelledError>());
    expect(ran, isFalse);
    observer.destroy();
    client.clear();
  });

  test('one function, not two', () {
    expect(
        () => MutationOptions<int, int, void>(
              mutationFn: (v) => v,
              mutationFnWithContext: (v, _) => v,
            ),
        throwsA(isA<AssertionError>()));
  });

  testFakeAsync(
      'a function with context wins over one registered with '
      'setMutationDefaults', (time) async {
    final client = testClient();
    final key = queryKey();
    client.setMutationDefaults(
        key, MutationDefaults(mutationFn: (_) async => 'default'));
    final observer = MutationObserver<String, void, void>(
        client,
        MutationOptions(
          mutationKey: key,
          mutationFnWithContext: (_, __) => 'own',
        ));
    expect(await observer.mutateAsync(null), 'own');
    observer.destroy();
    client.clear();
  });
}
