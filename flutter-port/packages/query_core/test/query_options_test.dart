import 'package:query_core/query_core.dart';
import 'package:test/test.dart';

/// Upstream covers option defaulting inside `queryClient.test.tsx`
/// (`defaultQueryOptions`, `setQueryDefaults`). The merge is a standalone
/// function here, so it is tested standalone; the client-level cases
/// (prefix matching, registration order) land with the client in M5.
void main() {
  group('resolveQueryObserverOptions', () {
    final options = QueryObserverOptions<String, String>(
      queryKey: const QueryKey(['todos']),
      queryFn: (_) async => 'data',
    );

    test('applies library fallbacks when nothing is set', () {
      final resolved = resolveQueryObserverOptions(options);

      expect(resolved.gcTime, QueryOptionDefaults.gcTime);
      expect(resolved.retry, QueryOptionDefaults.retry);
      expect(resolved.retryDelay, QueryOptionDefaults.retryDelay);
      expect(resolved.networkMode, NetworkMode.online);
      expect(resolved.staleTime, StaleDuration.zero);
      expect(resolved.enabled, Enabled.on);
      expect(resolved.refetchOnMount, RefetchOn.ifStale);
      expect(resolved.refetchInterval, RefetchInterval.off);
      expect(resolved.refetchIntervalInBackground, isFalse);
      expect(resolved.retryOnMount, Enabled.on);
    });

    test('caller options beat defaults', () {
      final resolved = resolveQueryObserverOptions(
        QueryObserverOptions<String, String>(
          queryKey: const QueryKey(['todos']),
          staleTime: const StaleDuration.of(Duration(seconds: 45)),
          retry: const RetryOption.count(1),
        ),
        defaults: const QueryDefaults(
          staleTime: StaleDuration.of(Duration(seconds: 10)),
          retry: RetryOption.count(5),
          gcTime: GcDuration.of(Duration(minutes: 1)),
        ),
      );

      expect(resolved.staleTime, const StaleDuration.of(Duration(seconds: 45)));
      expect(resolved.retry, const RetryOption.count(1));
      expect(
        resolved.gcTime,
        const GcDuration.of(Duration(minutes: 1)),
        reason: 'a default the caller did not override still applies',
      );
    });

    test('defaults beat library fallbacks', () {
      final resolved = resolveQueryObserverOptions(
        options,
        defaults: const QueryDefaults(
          staleTime: StaleDuration.of(Duration(seconds: 30)),
          networkMode: NetworkMode.offlineFirst,
        ),
      );

      expect(resolved.staleTime, const StaleDuration.of(Duration(seconds: 30)));
      expect(resolved.networkMode, NetworkMode.offlineFirst);
    });

    // Upstream: `refetchOnReconnect ??= networkMode !== 'always'`.
    test('refetchOnReconnect follows the resolved network mode', () {
      final online = resolveQueryObserverOptions(options);
      expect(online.refetchOnReconnect, RefetchOn.ifStale);

      final always = resolveQueryObserverOptions(
        QueryObserverOptions<String, String>(
          queryKey: const QueryKey(['todos']),
          networkMode: NetworkMode.always,
        ),
      );
      expect(
        always.refetchOnReconnect,
        RefetchOn.never,
        reason: 'a query that ignores connectivity has nothing to react to',
      );

      final explicit = resolveQueryObserverOptions(
        QueryObserverOptions<String, String>(
          queryKey: const QueryKey(['todos']),
          networkMode: NetworkMode.always,
          refetchOnReconnect: RefetchOn.always,
        ),
      );
      expect(
        explicit.refetchOnReconnect,
        RefetchOn.always,
        reason: 'an explicit setting still wins',
      );
    });

    test('a network mode from defaults drives the dependent default', () {
      final resolved = resolveQueryObserverOptions(
        options,
        defaults: const QueryDefaults(networkMode: NetworkMode.always),
      );
      expect(resolved.refetchOnReconnect, RefetchOn.never);
    });

    test('carries typed-only options through untouched', () {
      String? seen;
      final resolved = resolveQueryObserverOptions(
        QueryObserverOptions<String, int>(
          queryKey: const QueryKey(['todos']),
          initialData: () => 'seed',
          initialDataUpdatedAt: () => DateTime.utc(2020),
          select: (data) {
            seen = data;
            return data.length;
          },
        ),
      );

      expect(resolved.initialData!(), 'seed');
      expect(resolved.initialDataUpdatedAt!(), DateTime.utc(2020));
      expect(resolved.select!('abc'), 3);
      expect(seen, 'abc');
    });

    test('falls back to a default query function', () async {
      final resolved = resolveQueryObserverOptions(
        QueryObserverOptions<String, String>(
          queryKey: const QueryKey(['todos']),
        ),
        defaults: QueryDefaults(queryFn: (_) async => 'from defaults'),
      );

      final context = QueryFunctionContext(
        queryKey: const QueryKey(['todos']),
        cancelToken: QueryCancelToken(),
        onTokenConsumed: () {},
      );
      expect(await resolved.queryFn!(context), 'from defaults');
    });

    test('a caller query function beats the default one', () async {
      final resolved = resolveQueryObserverOptions(
        QueryObserverOptions<String, String>(
          queryKey: const QueryKey(['todos']),
          queryFn: (_) async => 'from options',
        ),
        defaults: QueryDefaults(queryFn: (_) async => 'from defaults'),
      );

      final context = QueryFunctionContext(
        queryKey: const QueryKey(['todos']),
        cancelToken: QueryCancelToken(),
        onTokenConsumed: () {},
      );
      expect(await resolved.queryFn!(context), 'from options');
    });
  });

  group('QueryDefaults.mergedWith', () {
    test('later values win, unset ones keep the earlier value', () {
      const first = QueryDefaults(
        staleTime: StaleDuration.of(Duration(seconds: 10)),
        retry: RetryOption.count(1),
      );
      const second = QueryDefaults(retry: RetryOption.count(5));

      final merged = first.mergedWith(second);
      expect(merged.retry, const RetryOption.count(5));
      expect(
        merged.staleTime,
        const StaleDuration.of(Duration(seconds: 10)),
        reason: 'the second bag left staleTime unset',
      );
    });

    test('merging null is a no-op', () {
      const defaults = QueryDefaults(retry: RetryOption.count(2));
      expect(defaults.mergedWith(null).retry, const RetryOption.count(2));
    });
  });

  group('QueryFunctionContext', () {
    test('reading the token reports consumption', () {
      var consumed = 0;
      final context = QueryFunctionContext(
        queryKey: const QueryKey(['todos']),
        cancelToken: QueryCancelToken(),
        onTokenConsumed: () => consumed++,
      );

      expect(consumed, 0, reason: 'not consumed until read');
      context.cancelToken;
      expect(consumed, 1);
    });
  });

  group('QueryCancelToken', () {
    test('notifies listeners on cancel', () {
      final token = QueryCancelToken();
      final errors = <CancelledError>[];
      token.addListener(errors.add);

      token.cancel(const CancelledError(revert: true));

      expect(errors, hasLength(1));
      expect(errors.single.revert, isTrue);
      expect(token.isCancelled, isTrue);
    });

    test('a listener added after cancellation fires immediately', () {
      final token = QueryCancelToken()..cancel(const CancelledError());
      final errors = <CancelledError>[];

      token.addListener(errors.add);
      expect(errors, hasLength(1));
    });

    test('the first cancellation reason wins', () {
      final token = QueryCancelToken()
        ..cancel(const CancelledError(revert: true))
        ..cancel(const CancelledError(silent: true));

      expect(token.reason!.revert, isTrue);
      expect(token.reason!.silent, isFalse);
    });
  });
}
