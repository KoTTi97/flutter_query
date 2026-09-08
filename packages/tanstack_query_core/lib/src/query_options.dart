/// Query options and the query-function contract. Ports the query half of
/// `query-core/src/types.ts` at upstream `50680b98c`.
///
/// Two rules run through this file
/// (https://github.com/KoTTi97/flutter_query/issues/10):
/// `null` means "not configured" on every field, so merging defaults is a
/// per-field `??`; and anything upstream expresses as a union is a sealed
/// value type, so "off" is a value rather than a null.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import 'cancel_token.dart';
import 'option_values.dart';
import 'query.dart';
import 'query_client.dart';
import 'query_key.dart';

/// What a query function is handed.
///
/// Reading [signal] marks the fetch as cancellable — a Dart getter doing
/// exactly what upstream's `Object.defineProperty` getter does. If the query
/// function never touches it, losing the last observer stops the retry loop but
/// lets the in-flight request finish and populate the cache.
class QueryFunctionContext {
  QueryFunctionContext({
    required this.client,
    required this.queryKey,
    required QueryCancelToken signal,
    this.meta,
    this.pageParam,
    this.direction,
    void Function()? onSignalRead,
  })  : _signal = signal,
        _onSignalRead = onSignalRead;

  final QueryClient client;
  final QueryKey queryKey;
  final Object? meta;

  /// Set for infinite queries only.
  final Object? pageParam;

  /// Set for infinite queries only: which end of the pages is being fetched.
  final FetchDirection? direction;

  final QueryCancelToken _signal;

  /// Told the moment [signal] is read, so the query can react *during* the
  /// fetch rather than after it — upstream's `#abortSignalConsumed` is set by
  /// the same getter.
  final void Function()? _onSignalRead;
  bool _signalConsumed = false;

  QueryCancelToken get signal {
    _signalConsumed = true;
    _onSignalRead?.call();
    return _signal;
  }

  /// Whether the query function read [signal].
  @internal
  bool get signalConsumed => _signalConsumed;
}

/// Which end of an infinite query is being fetched.
enum FetchDirection { forward, backward }

/// The function a query runs to get its data.
typedef QueryFn<TQueryData> = FutureOr<TQueryData> Function(
    QueryFunctionContext context);

/// Replaces the whole result with a shared instance when nothing changed.
///
/// Upstream's `replaceEqualDeep` walks plain JSON, which cannot reconstruct
/// typed Dart models, so this optional hook replaces it
/// (https://github.com/KoTTi97/flutter_query/issues/12).
typedef StructuralSharing<TQueryData> = TQueryData Function(
    TQueryData? previous, TQueryData next);

/// Seed data written into the cache, as if it had been fetched.
@immutable
sealed class InitialData<TQueryData> {
  const InitialData();

  const factory InitialData.value(TQueryData data) =
      InitialDataValue<TQueryData>;

  const factory InitialData.compute(TQueryData? Function() compute) =
      InitialDataCompute<TQueryData>;

  /// The seed, or `null` for "no data after all".
  TQueryData? resolve() => switch (this) {
        InitialDataValue<TQueryData>(:final data) => data,
        InitialDataCompute<TQueryData>(:final compute) => compute(),
      };
}

final class InitialDataValue<TQueryData> extends InitialData<TQueryData> {
  const InitialDataValue(this.data);
  final TQueryData data;
}

final class InitialDataCompute<TQueryData> extends InitialData<TQueryData> {
  const InitialDataCompute(this.compute);
  final TQueryData? Function() compute;
}

/// Data shown while the real data is missing. Never written to the cache.
@immutable
sealed class PlaceholderData<TQueryData> {
  const PlaceholderData();

  const factory PlaceholderData.value(TQueryData data) =
      PlaceholderDataValue<TQueryData>;

  /// The callback form, which also covers upstream's removed
  /// `keepPreviousData`: return [previousData] to keep the last page's content
  /// on screen while the new key loads.
  const factory PlaceholderData.compute(
    TQueryData? Function(
            TQueryData? previousData, Query<TQueryData>? previousQuery)
        compute,
  ) = PlaceholderDataCompute<TQueryData>;

  TQueryData? resolve(
          TQueryData? previousData, Query<TQueryData>? previousQuery) =>
      switch (this) {
        PlaceholderDataValue<TQueryData>(:final data) => data,
        PlaceholderDataCompute<TQueryData>(:final compute) => compute(
            previousData,
            previousQuery,
          ),
      };
}

final class PlaceholderDataValue<TQueryData>
    extends PlaceholderData<TQueryData> {
  const PlaceholderDataValue(this.data);
  final TQueryData data;
}

final class PlaceholderDataCompute<TQueryData>
    extends PlaceholderData<TQueryData> {
  const PlaceholderDataCompute(this.compute);
  final TQueryData? Function(
    TQueryData? previousData,
    Query<TQueryData>? previousQuery,
  ) compute;
}

/// Everything that describes a query, at the cache layer.
@immutable
class QueryOptions<TQueryData> {
  const QueryOptions({
    this.queryKey,
    this.queryFn,
    this.enabled,
    this.staleTime,
    this.gcTime,
    this.retry,
    this.retryDelay,
    this.networkMode,
    this.initialData,
    this.initialDataUpdatedAt,
    this.structuralSharing,
    this.meta,
    this.behavior,
  });

  final QueryKey? queryKey;
  final QueryFn<TQueryData>? queryFn;
  final Enabled? enabled;
  final StaleTime? staleTime;
  final GcTime? gcTime;
  final RetryPolicy? retry;
  final RetryDelay? retryDelay;
  final NetworkMode? networkMode;
  final InitialData<TQueryData>? initialData;
  final DateTime? initialDataUpdatedAt;
  final StructuralSharing<TQueryData>? structuralSharing;

  /// Arbitrary data carried along for logging, devtools or a query function.
  final Object? meta;

  /// Rewrites how the fetch runs. Set by the library for infinite queries;
  /// users never set it.
  @internal
  final FetchBehavior<TQueryData>? behavior;

  QueryOptions<TQueryData> copyWith({
    QueryKey? queryKey,
    QueryFn<TQueryData>? queryFn,
    Enabled? enabled,
    StaleTime? staleTime,
    GcTime? gcTime,
    RetryPolicy? retry,
    RetryDelay? retryDelay,
    NetworkMode? networkMode,
    InitialData<TQueryData>? initialData,
    DateTime? initialDataUpdatedAt,
    StructuralSharing<TQueryData>? structuralSharing,
    Object? meta,
    FetchBehavior<TQueryData>? behavior,
  }) =>
      QueryOptions<TQueryData>(
        queryKey: queryKey ?? this.queryKey,
        queryFn: queryFn ?? this.queryFn,
        enabled: enabled ?? this.enabled,
        staleTime: staleTime ?? this.staleTime,
        gcTime: gcTime ?? this.gcTime,
        retry: retry ?? this.retry,
        retryDelay: retryDelay ?? this.retryDelay,
        networkMode: networkMode ?? this.networkMode,
        initialData: initialData ?? this.initialData,
        initialDataUpdatedAt: initialDataUpdatedAt ?? this.initialDataUpdatedAt,
        structuralSharing: structuralSharing ?? this.structuralSharing,
        meta: meta ?? this.meta,
        behavior: behavior ?? this.behavior,
      );
}

/// Query options plus everything only an observer cares about.
@immutable
class QueryObserverOptions<TQueryData, TData> extends QueryOptions<TQueryData> {
  const QueryObserverOptions({
    super.queryKey,
    super.queryFn,
    super.enabled,
    super.staleTime,
    super.gcTime,
    super.retry,
    super.retryDelay,
    super.networkMode,
    super.initialData,
    super.initialDataUpdatedAt,
    super.structuralSharing,
    super.meta,
    super.behavior,
    this.select,
    this.placeholderData,
    this.refetchOnMount,
    this.refetchOnWindowFocus,
    this.refetchOnReconnect,
    this.refetchInterval,
    this.refetchIntervalInBackground,
    this.retryOnMount,
  });

  /// Narrows what the observer reports — and therefore what a change in the
  /// cached data has to touch before a listener is notified.
  final TData Function(TQueryData data)? select;

  final PlaceholderData<TQueryData>? placeholderData;

  final RefetchOn? refetchOnMount;
  final RefetchOn? refetchOnWindowFocus;
  final RefetchOn? refetchOnReconnect;
  final RefetchInterval? refetchInterval;
  final bool? refetchIntervalInBackground;

  /// Whether a query that ended in an error retries when an observer mounts.
  final bool? retryOnMount;

  @override
  QueryObserverOptions<TQueryData, TData> copyWith({
    QueryKey? queryKey,
    QueryFn<TQueryData>? queryFn,
    Enabled? enabled,
    StaleTime? staleTime,
    GcTime? gcTime,
    RetryPolicy? retry,
    RetryDelay? retryDelay,
    NetworkMode? networkMode,
    InitialData<TQueryData>? initialData,
    DateTime? initialDataUpdatedAt,
    StructuralSharing<TQueryData>? structuralSharing,
    Object? meta,
    FetchBehavior<TQueryData>? behavior,
    TData Function(TQueryData data)? select,
    PlaceholderData<TQueryData>? placeholderData,
    RefetchOn? refetchOnMount,
    RefetchOn? refetchOnWindowFocus,
    RefetchOn? refetchOnReconnect,
    RefetchInterval? refetchInterval,
    bool? refetchIntervalInBackground,
    bool? retryOnMount,
  }) =>
      QueryObserverOptions<TQueryData, TData>(
        queryKey: queryKey ?? this.queryKey,
        queryFn: queryFn ?? this.queryFn,
        enabled: enabled ?? this.enabled,
        staleTime: staleTime ?? this.staleTime,
        gcTime: gcTime ?? this.gcTime,
        retry: retry ?? this.retry,
        retryDelay: retryDelay ?? this.retryDelay,
        networkMode: networkMode ?? this.networkMode,
        initialData: initialData ?? this.initialData,
        initialDataUpdatedAt: initialDataUpdatedAt ?? this.initialDataUpdatedAt,
        structuralSharing: structuralSharing ?? this.structuralSharing,
        meta: meta ?? this.meta,
        behavior: behavior ?? this.behavior,
        select: select ?? this.select,
        placeholderData: placeholderData ?? this.placeholderData,
        refetchOnMount: refetchOnMount ?? this.refetchOnMount,
        refetchOnWindowFocus: refetchOnWindowFocus ?? this.refetchOnWindowFocus,
        refetchOnReconnect: refetchOnReconnect ?? this.refetchOnReconnect,
        refetchInterval: refetchInterval ?? this.refetchInterval,
        refetchIntervalInBackground:
            refetchIntervalInBackground ?? this.refetchIntervalInBackground,
        retryOnMount: retryOnMount ?? this.retryOnMount,
      );
}

/// Options with every default resolved.
///
/// Only [QueryClient] can produce one, so nothing downstream can be handed
/// half-resolved options, and no internal code has to ask whether defaults were
/// applied. Fields that always have a value are non-nullable here — the type
/// carries the guarantee instead of a comment.
@immutable
class DefaultedQueryOptions<TQueryData> {
  @internal
  const DefaultedQueryOptions({
    required this.queryKey,
    required this.queryFn,
    required this.enabled,
    required this.staleTime,
    required this.gcTime,
    required this.retry,
    required this.retryDelay,
    required this.networkMode,
    required this.initialData,
    required this.initialDataUpdatedAt,
    required this.structuralSharing,
    required this.meta,
    required this.behavior,
  });

  final QueryKey queryKey;
  final QueryFn<TQueryData>? queryFn;
  final Enabled enabled;
  final StaleTime staleTime;
  final GcTime gcTime;
  final RetryPolicy retry;
  final RetryDelay retryDelay;
  final NetworkMode networkMode;
  final InitialData<TQueryData>? initialData;
  final DateTime? initialDataUpdatedAt;
  final StructuralSharing<TQueryData>? structuralSharing;
  final Object? meta;
  final FetchBehavior<TQueryData>? behavior;

  /// Field-by-field equality, functions compared by identity — the direct
  /// analogue of upstream's `shallowEqualObjects` over defaulted options. It
  /// is what tells a rebuild that nothing actually changed.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DefaultedQueryOptions<TQueryData> &&
          other.runtimeType == runtimeType &&
          other.queryKey == queryKey &&
          other.queryFn == queryFn &&
          other.enabled == enabled &&
          other.staleTime == staleTime &&
          other.gcTime == gcTime &&
          other.retry == retry &&
          other.retryDelay == retryDelay &&
          other.networkMode == networkMode &&
          other.initialData == initialData &&
          other.initialDataUpdatedAt == initialDataUpdatedAt &&
          other.structuralSharing == structuralSharing &&
          other.meta == meta &&
          other.behavior == behavior;

  @override
  int get hashCode => Object.hash(
        queryKey,
        queryFn,
        enabled,
        staleTime,
        gcTime,
        retry,
        retryDelay,
        networkMode,
        initialData,
        initialDataUpdatedAt,
        structuralSharing,
        meta,
        behavior,
      );

  /// This, with a different [retry]. Used by `QueryClient.query`, whose
  /// imperative path disables retries the caller did not ask for.
  @internal
  DefaultedQueryOptions<TQueryData> withRetry(RetryPolicy retry) =>
      DefaultedQueryOptions<TQueryData>(
        queryKey: queryKey,
        queryFn: queryFn,
        enabled: enabled,
        staleTime: staleTime,
        gcTime: gcTime,
        retry: retry,
        retryDelay: retryDelay,
        networkMode: networkMode,
        initialData: initialData,
        initialDataUpdatedAt: initialDataUpdatedAt,
        structuralSharing: structuralSharing,
        meta: meta,
        behavior: behavior,
      );
}

/// [DefaultedQueryOptions] plus the observer-only options.
@immutable
final class DefaultedQueryObserverOptions<TQueryData, TData>
    extends DefaultedQueryOptions<TQueryData> {
  @internal
  const DefaultedQueryObserverOptions({
    required super.queryKey,
    required super.queryFn,
    required super.enabled,
    required super.staleTime,
    required super.gcTime,
    required super.retry,
    required super.retryDelay,
    required super.networkMode,
    required super.initialData,
    required super.initialDataUpdatedAt,
    required super.structuralSharing,
    required super.meta,
    required super.behavior,
    required this.select,
    required this.placeholderData,
    required this.refetchOnMount,
    required this.refetchOnWindowFocus,
    required this.refetchOnReconnect,
    required this.refetchInterval,
    required this.refetchIntervalInBackground,
    required this.retryOnMount,
  });

  final TData Function(TQueryData data)? select;
  final PlaceholderData<TQueryData>? placeholderData;
  final RefetchOn refetchOnMount;
  final RefetchOn refetchOnWindowFocus;
  final RefetchOn refetchOnReconnect;
  final RefetchInterval refetchInterval;
  final bool refetchIntervalInBackground;
  final bool retryOnMount;

  /// The cache-layer view of these options.
  DefaultedQueryOptions<TQueryData> get queryOptions =>
      DefaultedQueryOptions<TQueryData>(
        queryKey: queryKey,
        queryFn: queryFn,
        enabled: enabled,
        staleTime: staleTime,
        gcTime: gcTime,
        retry: retry,
        retryDelay: retryDelay,
        networkMode: networkMode,
        initialData: initialData,
        initialDataUpdatedAt: initialDataUpdatedAt,
        structuralSharing: structuralSharing,
        meta: meta,
        behavior: behavior,
      );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DefaultedQueryObserverOptions<TQueryData, TData> &&
          super == other &&
          other.select == select &&
          other.placeholderData == placeholderData &&
          other.refetchOnMount == refetchOnMount &&
          other.refetchOnWindowFocus == refetchOnWindowFocus &&
          other.refetchOnReconnect == refetchOnReconnect &&
          other.refetchInterval == refetchInterval &&
          other.refetchIntervalInBackground == refetchIntervalInBackground &&
          other.retryOnMount == retryOnMount;

  @override
  int get hashCode => Object.hash(
        super.hashCode,
        select,
        placeholderData,
        refetchOnMount,
        refetchOnWindowFocus,
        refetchOnReconnect,
        refetchInterval,
        refetchIntervalInBackground,
        retryOnMount,
      );
}
