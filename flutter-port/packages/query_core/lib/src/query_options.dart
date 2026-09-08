import 'package:meta/meta.dart';

import 'cancel_token.dart';
import 'option_values.dart';
import 'query_key.dart';

/// What a query function receives.
///
/// Reading [cancelToken] marks it consumed, which tells the cache the fetch can
/// really be aborted — see [QueryCancelToken].
class QueryFunctionContext {
  QueryFunctionContext({
    required this.queryKey,
    required QueryCancelToken cancelToken,
    required void Function() onTokenConsumed,
    this.meta,
  })  : _cancelToken = cancelToken,
        _onTokenConsumed = onTokenConsumed;

  final QueryKey queryKey;
  final Object? meta;

  final QueryCancelToken _cancelToken;
  final void Function() _onTokenConsumed;

  /// The token for this fetch. Taking it opts the query into real
  /// cancellation: the cache will then abort rather than let the request run
  /// to completion when nobody is observing any more.
  QueryCancelToken get cancelToken {
    _onTokenConsumed();
    return _cancelToken;
  }
}

typedef QueryFn<TQueryData> = Future<TQueryData> Function(
    QueryFunctionContext context);

/// Thrown when a query is fetched but no query function can be found for it —
/// the port of upstream's "Missing queryFn" error.
class MissingQueryFunctionError implements Exception {
  const MissingQueryFunctionError(this.queryKey);

  final QueryKey queryKey;

  @override
  String toString() =>
      'MissingQueryFunctionError: no queryFn for $queryKey. Pass one in the '
      'options, or set a default with setQueryDefaults.';
}

/// Cache-level options: everything a query needs to fetch and store data,
/// independent of who is observing it.
///
/// Every field is nullable and null always means "not set", so merging
/// defaults is a plain `??` per field. Options with an explicit "off" value
/// (no retries, never stale, never collected) say so with a value type rather
/// than null — see [option_values.dart].
@immutable
class QueryOptions<TQueryData> {
  const QueryOptions({
    required this.queryKey,
    this.queryFn,
    this.gcTime,
    this.retry,
    this.retryDelay,
    this.networkMode,
    this.initialData,
    this.initialDataUpdatedAt,
    this.structuralSharing,
    this.meta,
  });

  final QueryKey queryKey;
  final QueryFn<TQueryData>? queryFn;
  final GcDuration? gcTime;
  final RetryOption? retry;
  final RetryDelay? retryDelay;
  final NetworkMode? networkMode;

  /// Seeds the cache entry when it is first created. Returning null means
  /// "no initial data", matching upstream's `undefined`.
  final TQueryData? Function()? initialData;

  /// When [initialData] came from, so seeded data does not look freshly
  /// fetched. Returning null falls back to now.
  final DateTime? Function()? initialDataUpdatedAt;

  /// Optional replacement for new data, given the old — the escape hatch for
  /// preserving references across fetches. Off by default.
  final TQueryData Function(TQueryData? oldData, TQueryData newData)?
      structuralSharing;

  final Object? meta;
}

/// Options for a single observer of a query: the cache-level options plus
/// everything about how *this* observer wants to watch it.
@immutable
class QueryObserverOptions<TQueryData, TData> extends QueryOptions<TQueryData> {
  const QueryObserverOptions({
    required super.queryKey,
    super.queryFn,
    super.gcTime,
    super.retry,
    super.retryDelay,
    super.networkMode,
    super.initialData,
    super.initialDataUpdatedAt,
    super.structuralSharing,
    super.meta,
    this.enabled,
    this.staleTime,
    this.refetchOnMount,
    this.refetchOnAppFocus,
    this.refetchOnReconnect,
    this.refetchInterval,
    this.refetchIntervalInBackground,
    this.retryOnMount,
    this.select,
  });

  final Enabled? enabled;
  final StaleDuration? staleTime;
  final RefetchOn? refetchOnMount;
  final RefetchOn? refetchOnAppFocus;
  final RefetchOn? refetchOnReconnect;
  final RefetchInterval? refetchInterval;
  final bool? refetchIntervalInBackground;
  final Enabled? retryOnMount;

  /// Derives what this observer exposes from what the cache holds. Two
  /// observers can select different shapes from one cache entry, and only the
  /// selected value drives their rebuilds.
  final TData Function(TQueryData data)? select;

  QueryObserverOptions<TQueryData, TNew> withSelect<TNew>(
    TNew Function(TQueryData data) select,
  ) {
    return QueryObserverOptions<TQueryData, TNew>(
      queryKey: queryKey,
      queryFn: queryFn,
      gcTime: gcTime,
      retry: retry,
      retryDelay: retryDelay,
      networkMode: networkMode,
      initialData: initialData,
      initialDataUpdatedAt: initialDataUpdatedAt,
      structuralSharing: structuralSharing,
      meta: meta,
      enabled: enabled,
      staleTime: staleTime,
      refetchOnMount: refetchOnMount,
      refetchOnAppFocus: refetchOnAppFocus,
      refetchOnReconnect: refetchOnReconnect,
      refetchInterval: refetchInterval,
      refetchIntervalInBackground: refetchIntervalInBackground,
      retryOnMount: retryOnMount,
      select: select,
    );
  }
}

/// Defaults that apply to many queries at once — the client-wide defaults and
/// anything registered with `setQueryDefaults`.
///
/// Untyped, because one bag covers queries of different data types. The
/// typed-only options ([QueryObserverOptions.select],
/// [QueryOptions.initialData]) deliberately have no entry here: they are
/// per-observer by nature.
@immutable
class QueryDefaults {
  const QueryDefaults({
    this.queryFn,
    this.gcTime,
    this.retry,
    this.retryDelay,
    this.networkMode,
    this.enabled,
    this.staleTime,
    this.refetchOnMount,
    this.refetchOnAppFocus,
    this.refetchOnReconnect,
    this.refetchInterval,
    this.refetchIntervalInBackground,
    this.retryOnMount,
    this.meta,
  });

  static const QueryDefaults empty = QueryDefaults();

  final QueryFn<Object?>? queryFn;
  final GcDuration? gcTime;
  final RetryOption? retry;
  final RetryDelay? retryDelay;
  final NetworkMode? networkMode;
  final Enabled? enabled;
  final StaleDuration? staleTime;
  final RefetchOn? refetchOnMount;
  final RefetchOn? refetchOnAppFocus;
  final RefetchOn? refetchOnReconnect;
  final RefetchInterval? refetchInterval;
  final bool? refetchIntervalInBackground;
  final Enabled? retryOnMount;
  final Object? meta;

  /// Layers [other] on top of this bag; anything [other] leaves unset keeps
  /// this bag's value. Later registrations win, as upstream.
  QueryDefaults mergedWith(QueryDefaults? other) {
    if (other == null) {
      return this;
    }
    return QueryDefaults(
      queryFn: other.queryFn ?? queryFn,
      gcTime: other.gcTime ?? gcTime,
      retry: other.retry ?? retry,
      retryDelay: other.retryDelay ?? retryDelay,
      networkMode: other.networkMode ?? networkMode,
      enabled: other.enabled ?? enabled,
      staleTime: other.staleTime ?? staleTime,
      refetchOnMount: other.refetchOnMount ?? refetchOnMount,
      refetchOnAppFocus: other.refetchOnAppFocus ?? refetchOnAppFocus,
      refetchOnReconnect: other.refetchOnReconnect ?? refetchOnReconnect,
      refetchInterval: other.refetchInterval ?? refetchInterval,
      refetchIntervalInBackground:
          other.refetchIntervalInBackground ?? refetchIntervalInBackground,
      retryOnMount: other.retryOnMount ?? retryOnMount,
      meta: other.meta ?? meta,
    );
  }

  /// Adapts the untyped default query function to a typed one. The cast fails
  /// loudly at fetch time if a default function is used with a query whose
  /// data type it does not produce.
  QueryFn<TQueryData>? typedQueryFn<TQueryData>() {
    final fn = queryFn;
    if (fn == null) {
      return null;
    }
    return (context) async => await fn(context) as TQueryData;
  }
}

/// Cache-level options with every default applied.
///
/// This type is the port of upstream's `_defaulted` marker: instead of a
/// boolean flag on an options object, "already defaulted" is a distinct type
/// that only the client can produce, so nothing downstream can be handed
/// half-resolved options.
@immutable
class DefaultedQueryOptions<TQueryData> {
  const DefaultedQueryOptions({
    required this.queryKey,
    required this.gcTime,
    required this.retry,
    required this.retryDelay,
    required this.networkMode,
    this.queryFn,
    this.initialData,
    this.initialDataUpdatedAt,
    this.structuralSharing,
    this.meta,
  });

  final QueryKey queryKey;
  final GcDuration gcTime;
  final RetryOption retry;
  final RetryDelay retryDelay;
  final NetworkMode networkMode;
  final QueryFn<TQueryData>? queryFn;
  final TQueryData? Function()? initialData;
  final DateTime? Function()? initialDataUpdatedAt;
  final TQueryData Function(TQueryData? oldData, TQueryData newData)?
      structuralSharing;
  final Object? meta;
}

/// Observer options with every default applied.
@immutable
class DefaultedQueryObserverOptions<TQueryData, TData>
    extends DefaultedQueryOptions<TQueryData> {
  const DefaultedQueryObserverOptions({
    required super.queryKey,
    required super.gcTime,
    required super.retry,
    required super.retryDelay,
    required super.networkMode,
    required this.enabled,
    required this.staleTime,
    required this.refetchOnMount,
    required this.refetchOnAppFocus,
    required this.refetchOnReconnect,
    required this.refetchInterval,
    required this.refetchIntervalInBackground,
    required this.retryOnMount,
    super.queryFn,
    super.initialData,
    super.initialDataUpdatedAt,
    super.structuralSharing,
    super.meta,
    this.select,
  });

  final Enabled enabled;
  final StaleDuration staleTime;
  final RefetchOn refetchOnMount;
  final RefetchOn refetchOnAppFocus;
  final RefetchOn refetchOnReconnect;
  final RefetchInterval refetchInterval;
  final bool refetchIntervalInBackground;
  final Enabled retryOnMount;
  final TData Function(TQueryData data)? select;

  /// Field-wise equality, the port of upstream's
  /// `shallowEqualObjects(this.options, prevOptions)`. An observer uses it to
  /// tell a genuine options change from a rebuild that passed the same values
  /// in a fresh object.
  ///
  /// Function-valued fields compare by identity, so a `select` written inline
  /// counts as a change on every rebuild — the same caveat upstream has, and
  /// the reason to hoist such closures out of the build method.
  @override
  bool operator ==(Object other) =>
      other is DefaultedQueryObserverOptions<TQueryData, TData> &&
      queryKey == other.queryKey &&
      gcTime == other.gcTime &&
      retry == other.retry &&
      retryDelay == other.retryDelay &&
      networkMode == other.networkMode &&
      queryFn == other.queryFn &&
      initialData == other.initialData &&
      initialDataUpdatedAt == other.initialDataUpdatedAt &&
      structuralSharing == other.structuralSharing &&
      meta == other.meta &&
      enabled == other.enabled &&
      staleTime == other.staleTime &&
      refetchOnMount == other.refetchOnMount &&
      refetchOnAppFocus == other.refetchOnAppFocus &&
      refetchOnReconnect == other.refetchOnReconnect &&
      refetchInterval == other.refetchInterval &&
      refetchIntervalInBackground == other.refetchIntervalInBackground &&
      retryOnMount == other.retryOnMount &&
      select == other.select;

  @override
  int get hashCode => Object.hash(
        queryKey,
        gcTime,
        retry,
        retryDelay,
        networkMode,
        queryFn,
        initialData,
        initialDataUpdatedAt,
        structuralSharing,
        meta,
        enabled,
        staleTime,
        refetchOnMount,
        refetchOnAppFocus,
        refetchOnReconnect,
        refetchInterval,
        refetchIntervalInBackground,
        retryOnMount,
        select,
      );
}

/// The library-wide fallbacks, applied when neither the caller nor any
/// registered default says otherwise.
abstract final class QueryOptionDefaults {
  static const GcDuration gcTime = GcDuration.of(Duration(minutes: 5));
  static const RetryOption retry = RetryOption.count(3);
  static const RetryDelay retryDelay = RetryDelay.exponential;
  static const NetworkMode networkMode = NetworkMode.online;
  static const StaleDuration staleTime = StaleDuration.zero;
  static const RefetchOn refetchOn = RefetchOn.ifStale;
  static const RefetchInterval refetchInterval = RefetchInterval.off;
}

/// Resolves [options] against [defaults] — the merge at the heart of the
/// three-level chain (library fallbacks, then registered defaults, then what
/// the caller passed).
///
/// [defaults] is expected to be pre-merged by the client: client-wide defaults
/// with every matching key default layered on in registration order.
DefaultedQueryObserverOptions<TQueryData, TData>
    resolveQueryObserverOptions<TQueryData, TData>(
  QueryObserverOptions<TQueryData, TData> options, {
  QueryDefaults defaults = QueryDefaults.empty,
}) {
  final networkMode = options.networkMode ??
      defaults.networkMode ??
      QueryOptionDefaults.networkMode;

  return DefaultedQueryObserverOptions<TQueryData, TData>(
    queryKey: options.queryKey,
    queryFn: options.queryFn ?? defaults.typedQueryFn<TQueryData>(),
    gcTime: options.gcTime ?? defaults.gcTime ?? QueryOptionDefaults.gcTime,
    retry: options.retry ?? defaults.retry ?? QueryOptionDefaults.retry,
    retryDelay: options.retryDelay ??
        defaults.retryDelay ??
        QueryOptionDefaults.retryDelay,
    networkMode: networkMode,
    enabled: options.enabled ?? defaults.enabled ?? Enabled.on,
    staleTime: options.staleTime ??
        defaults.staleTime ??
        QueryOptionDefaults.staleTime,
    refetchOnMount: options.refetchOnMount ??
        defaults.refetchOnMount ??
        QueryOptionDefaults.refetchOn,
    refetchOnAppFocus: options.refetchOnAppFocus ??
        defaults.refetchOnAppFocus ??
        QueryOptionDefaults.refetchOn,
    // Depends on the resolved network mode: a query that ignores connectivity
    // has no reason to refetch when it returns.
    refetchOnReconnect: options.refetchOnReconnect ??
        defaults.refetchOnReconnect ??
        (networkMode == NetworkMode.always
            ? RefetchOn.never
            : QueryOptionDefaults.refetchOn),
    refetchInterval: options.refetchInterval ??
        defaults.refetchInterval ??
        QueryOptionDefaults.refetchInterval,
    refetchIntervalInBackground: options.refetchIntervalInBackground ??
        defaults.refetchIntervalInBackground ??
        false,
    retryOnMount: options.retryOnMount ?? defaults.retryOnMount ?? Enabled.on,
    initialData: options.initialData,
    initialDataUpdatedAt: options.initialDataUpdatedAt,
    structuralSharing: options.structuralSharing,
    meta: options.meta ?? defaults.meta,
    select: options.select,
  );
}
