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
///
/// An infinite query's page function is handed an `InfinitePageContext`
/// instead, which carries the page param and the direction, typed.
class QueryFunctionContext {
  /// Built by the query for each fetch; a query function receives one rather
  /// than constructing it. [onSignalRead] is how the query learns that
  /// [signal] was consumed.
  @internal
  QueryFunctionContext({
    required this.client,
    required this.queryKey,
    required QueryCancelToken signal,
    this.meta,
    void Function()? onSignalRead,
  })  : _signal = signal,
        _onSignalRead = onSignalRead;

  /// The client the query lives in — upstream's `client` on the context, and
  /// the way a query function reaches the cache for related data.
  final QueryClient client;

  /// The key of the query being fetched — upstream's `queryKey` — so one
  /// function can serve every key it is registered for.
  final QueryKey queryKey;

  /// The query's [QueryOptions.meta], if one was set.
  final Object? meta;

  final QueryCancelToken _signal;

  /// Told the moment [signal] is read, so the query can react *during* the
  /// fetch rather than after it — upstream's `#abortSignalConsumed` is set by
  /// the same getter.
  final void Function()? _onSignalRead;

  /// The cancel token for this fetch — upstream's `AbortSignal`.
  ///
  /// Reading it marks the fetch as cancellable: from then on, losing the last
  /// observer or a `cancelQueries` cancels the token and the query function
  /// is expected to stop. A function that never reads it is left to finish.
  QueryCancelToken get signal {
    _onSignalRead?.call();
    return _signal;
  }
}

/// Which end of an infinite query is being fetched.
enum FetchDirection {
  /// Appending after the last page — `fetchNextPage`.
  forward,

  /// Prepending before the first page — `fetchPreviousPage`.
  backward,
}

/// The function a query runs to get its data.
typedef QueryFn<TQueryData> = FutureOr<TQueryData> Function(
    QueryFunctionContext context);

/// Decides what is written into the cache when new data arrives, given what
/// was there before.
///
/// Unset, the port applies `replaceEqualDeep`: data that is deep-equal to the
/// previous data keeps the previous instance, so an unchanged refetch notifies
/// nobody. Lists are shared element by element; maps, sets and typed models
/// are shared whole, by their own `==`. Set this to `(_, next) => next` to
/// turn sharing off — upstream's `structuralSharing: false` — or to a function
/// of your own to reconcile typed models yourself
/// (https://github.com/KoTTi97/flutter_query/issues/12). The hook governs the
/// cache write; what `select` and `placeholderData` produce always goes
/// through `replaceEqualDeep`, because the hook is typed on the cache's data
/// and a selector's output is another type.
///
/// [previous] is `null` when nothing has been cached yet. With a nullable
/// `TQueryData` the hook cannot tell that apart from a previous value that
/// *was* `null`; a hook that needs the distinction reads
/// `query.state.hasData` instead.
typedef StructuralSharing<TQueryData> = TQueryData Function(
    TQueryData? previous, TQueryData next);

/// Seed data written into the cache, as if it had been fetched.
@immutable
sealed class InitialData<TQueryData> {
  const InitialData();

  /// A seed that is always present — upstream's `initialData: value`.
  const factory InitialData.value(TQueryData data) =
      InitialDataValue<TQueryData>;

  /// A seed computed when the query is first built, and skipped when
  /// [compute] returns `null` — upstream's `initialData: () => value`.
  const factory InitialData.compute(TQueryData? Function() compute) =
      InitialDataCompute<TQueryData>;

  /// The seed, and whether there is one.
  ///
  /// `.value(x)` always seeds — `x` may be `null` for a nullable data type,
  /// and the wrapper itself is the presence. `.compute` returning `null` is
  /// upstream's `undefined`: no data after all. That is the one place where
  /// Dart's single null has to carry two meanings, and the callback form is
  /// where upstream's own "return undefined to skip" idiom lives.
  ({bool hasData, TQueryData? data}) seed() => switch (this) {
        InitialDataValue<TQueryData>(:final data) => (
            hasData: true,
            data: data
          ),
        InitialDataCompute<TQueryData>(:final compute) => switch (compute()) {
            null => (hasData: false, data: null),
            final data => (hasData: true, data: data),
          },
      };
}

/// The [InitialData.value] variant: a seed that is always present, even when
/// [data] is `null` for a nullable data type.
final class InitialDataValue<TQueryData> extends InitialData<TQueryData> {
  /// Seeds the cache with [data].
  const InitialDataValue(this.data);

  /// The seed.
  final TQueryData data;

  // Value equality, like every other option value: an `InitialData.value`
  // built inline would otherwise make every `setOptions` look like a change.
  @override
  bool operator ==(Object other) =>
      other is InitialDataValue<TQueryData> && other.data == data;
  @override
  int get hashCode => Object.hash(InitialDataValue<TQueryData>, data);
}

/// The [InitialData.compute] variant: a seed computed lazily, once, when the
/// query is first built — upstream's `initialData: () => value`.
final class InitialDataCompute<TQueryData> extends InitialData<TQueryData> {
  /// Seeds the cache with what [compute] returns, unless that is `null`.
  const InitialDataCompute(this.compute);

  /// Called once, when the query is created. Returning `null` means "no seed
  /// after all" — upstream's `undefined`.
  final TQueryData? Function() compute;

  // Equal when the function is: two tear-offs of one function compare equal
  // in Dart, two inline closures never do — so a `.compute(seedFromCache)`
  // written with a tear-off survives a rebuild as "unchanged", and an inline
  // closure is honestly a new one.
  @override
  bool operator ==(Object other) =>
      other is InitialDataCompute<TQueryData> && other.compute == compute;
  @override
  int get hashCode => Object.hash(InitialDataCompute<TQueryData>, compute);
}

/// Data shown while the real data is missing. Never written to the cache.
@immutable
sealed class PlaceholderData<TQueryData> {
  const PlaceholderData();

  /// Keeps the previous data while the new key loads. A previous `null`
  /// means no placeholder, just as `.compute((previous, _) => previous)`.
  const factory PlaceholderData.keepPrevious() =
      PlaceholderDataKeepPrevious<TQueryData>;

  /// A fixed placeholder, shown whenever the query has no data of its own —
  /// upstream's `placeholderData: value`.
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

  /// The placeholder, and whether there is one. Same rule as
  /// [InitialData.seed]: `.value(null)` is a placeholder of `null`, while
  /// `.compute` returning `null` means "none".
  ({bool hasData, TQueryData? data}) provide(
    TQueryData? previousData,
    Query<TQueryData>? previousQuery,
  ) =>
      switch (this) {
        PlaceholderDataKeepPrevious<TQueryData>() => (
            hasData: previousData != null,
            data: previousData,
          ),
        PlaceholderDataValue<TQueryData>(:final data) => (
            hasData: true,
            data: data,
          ),
        PlaceholderDataCompute<TQueryData>(:final compute) => switch (
              compute(previousData, previousQuery)) {
            null => (hasData: false, data: null),
            final data => (hasData: true, data: data),
          },
      };
}

/// The [PlaceholderData.keepPrevious] variant, with no callback allocation.
final class PlaceholderDataKeepPrevious<TQueryData>
    extends PlaceholderData<TQueryData> {
  /// Keeps the last non-null data as a placeholder.
  const PlaceholderDataKeepPrevious();

  @override
  bool operator ==(Object other) =>
      other is PlaceholderDataKeepPrevious<TQueryData>;

  @override
  int get hashCode => (PlaceholderDataKeepPrevious<TQueryData>).hashCode;
}

/// The [PlaceholderData.value] variant: a fixed placeholder, shown whenever
/// the query has no data of its own.
final class PlaceholderDataValue<TQueryData>
    extends PlaceholderData<TQueryData> {
  /// Shows [data] until real data arrives.
  const PlaceholderDataValue(this.data);

  /// The placeholder.
  final TQueryData data;

  @override
  bool operator ==(Object other) =>
      other is PlaceholderDataValue<TQueryData> && other.data == data;
  @override
  int get hashCode => Object.hash(PlaceholderDataValue<TQueryData>, data);
}

/// The [PlaceholderData.compute] variant: a placeholder computed from what
/// the observer showed last — upstream's
/// `placeholderData: (previousData, previousQuery) => value`.
final class PlaceholderDataCompute<TQueryData>
    extends PlaceholderData<TQueryData> {
  /// Shows what [compute] returns, unless that is `null`.
  const PlaceholderDataCompute(this.compute);

  /// Called whenever the observer needs a placeholder. `previousData` and
  /// `previousQuery` are what this observer last showed and the query it
  /// showed it for — `null` on the first build. Returning `null` means "no
  /// placeholder".
  final TQueryData? Function(
    TQueryData? previousData,
    Query<TQueryData>? previousQuery,
  ) compute;

  // See `InitialDataCompute`: equal when the function is.
  @override
  bool operator ==(Object other) =>
      other is PlaceholderDataCompute<TQueryData> && other.compute == compute;
  @override
  int get hashCode => Object.hash(PlaceholderDataCompute<TQueryData>, compute);
}

/// Everything that describes a query, at the cache layer.
///
/// No value equality, on purpose: options built inline in a `build` are
/// re-applied on every build, as upstream re-applies them on every render,
/// and the observer works out what actually changed by comparing the
/// *resolved* values — so two inline closures for `queryFn` do not count as a
/// change, and neither does a fresh `Enabled.when(…)`.
@immutable
class QueryOptions<TQueryData> {
  /// Every field but [queryKey] is optional; an unset field takes the
  /// client's default when the query is built.
  const QueryOptions({
    required this.queryKey,
    this.queryFn,
    this.enabled,
    this.staleTime,
    this.gcTime,
    this.retry,
    this.retryDelay,
    this.networkMode,
    this.initialData,
    this.initialDataUpdatedAt,
    this.initialDataUpdatedAtCompute,
    this.structuralSharing,
    this.meta,
    this.behavior,
  });

  /// The key this query is cached under. Bound to exactly one data type: a
  /// key read as another type — a supertype included — throws
  /// `QueryDataTypeError`.
  final QueryKey queryKey;

  /// Fetches the data. Left unset, the query uses the function registered for
  /// its key with [QueryClient.setQueryDefaults], and a fetch with no function
  /// at all fails with [MissingQueryFunctionError].
  final QueryFn<TQueryData>? queryFn;

  /// Whether the query may fetch on its own. Default [Enabled.yes]. A disabled
  /// query still serves whatever the cache holds and can still be refetched
  /// by hand.
  final Enabled? enabled;

  /// How long fetched data counts as fresh. Default [StaleTime.zero]: stale
  /// the moment it arrives, so every mount, focus and reconnect refetches.
  final StaleTime? staleTime;

  /// How long the query stays cached after its last observer leaves. Default
  /// [GcTime.defaultValue], five minutes.
  final GcTime? gcTime;

  /// Whether a failed fetch is retried. Default `RetryPolicy.times(3)` —
  /// upstream's `retry: 3`, three retries after the first failure.
  final RetryPolicy? retry;

  /// How long to wait between attempts. Default [RetryDelay.defaultValue]:
  /// exponential back-off from one second, capped at thirty.
  final RetryDelay? retryDelay;

  /// How connectivity gates the fetch. Default [NetworkMode.online]: an
  /// offline device pauses the fetch until it is back.
  final NetworkMode? networkMode;

  /// Data the cache starts with, as if it had been fetched. Unlike
  /// `placeholderData` it *is* written to the cache, and it goes stale by
  /// [staleTime] from [initialDataUpdatedAt] on.
  final InitialData<TQueryData>? initialData;

  /// When [initialData] was fetched, for the staleness clock. Unset, the seed
  /// counts as fetched the moment the query is created.
  final DateTime? initialDataUpdatedAt;

  /// Computes the seed timestamp only when data is actually seeded.
  /// Mutually exclusive with [initialDataUpdatedAt]; a null result uses now.
  final DateTime? Function()? initialDataUpdatedAtCompute;

  /// How new data is reconciled with what the cache already holds — see
  /// [StructuralSharing]. Unset, the port applies `replaceEqualDeep`.
  final StructuralSharing<TQueryData>? structuralSharing;

  /// Arbitrary data carried along for logging, devtools or a query function.
  final Object? meta;

  /// Rewrites how the fetch runs. Set by the library for infinite queries;
  /// users never set it.
  @internal
  final FetchBehavior<TQueryData>? behavior;

  /// This, with the given fields replaced. Passing `null` leaves a field as it
  /// is. Supplying one seed timestamp form clears its previous alternative.
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
    DateTime? Function()? initialDataUpdatedAtCompute,
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
        initialDataUpdatedAt: initialDataUpdatedAt ??
            (initialDataUpdatedAtCompute == null
                ? this.initialDataUpdatedAt
                : null),
        initialDataUpdatedAtCompute: initialDataUpdatedAtCompute ??
            (initialDataUpdatedAt == null
                ? this.initialDataUpdatedAtCompute
                : null),
        structuralSharing: structuralSharing ?? this.structuralSharing,
        meta: meta ?? this.meta,
        behavior: behavior ?? this.behavior,
      );
}

/// Query options plus everything only an observer cares about.
///
/// Like [QueryOptions], deliberately without value equality: an observer is
/// handed the options a widget built on every build and compares what they
/// resolve to, so a `select` or `placeholderData` written inline is not a
/// change by itself.
@immutable
class QueryObserverOptions<TQueryData, TData> extends QueryOptions<TQueryData> {
  /// The cache-layer fields plus the observer's own. Every field but
  /// [queryKey] is optional and takes the client's default.
  const QueryObserverOptions({
    required super.queryKey,
    super.queryFn,
    super.enabled,
    super.staleTime,
    super.gcTime,
    super.retry,
    super.retryDelay,
    super.networkMode,
    super.initialData,
    super.initialDataUpdatedAt,
    super.initialDataUpdatedAtCompute,
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

  /// Data shown while the query has none of its own. Never written to the
  /// cache: a result built from it reports `isPlaceholderData`, and it gives
  /// way the moment real data arrives.
  final PlaceholderData<TQueryData>? placeholderData;

  /// Whether this observer subscribing triggers a refetch. Default
  /// [RefetchOn.ifStale]: only when the data is older than [staleTime].
  final RefetchOn? refetchOnMount;

  /// Whether the app regaining focus triggers a refetch. Default
  /// [RefetchOn.ifStale].
  final RefetchOn? refetchOnWindowFocus;

  /// Whether the device coming back online triggers a refetch. Default
  /// [RefetchOn.ifStale] — except under [NetworkMode.always], where it is
  /// [RefetchOn.never]: a fetch that ignores connectivity has nothing to
  /// catch up on.
  final RefetchOn? refetchOnReconnect;

  /// Polls the query on a timer while this observer is subscribed. Default
  /// [RefetchInterval.off].
  final RefetchInterval? refetchInterval;

  /// Whether [refetchInterval] keeps polling while the app is not focused.
  /// Default `false`: the timer skips its turns until focus returns.
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
    DateTime? Function()? initialDataUpdatedAtCompute,
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
        initialDataUpdatedAt: initialDataUpdatedAt ??
            (initialDataUpdatedAtCompute == null
                ? this.initialDataUpdatedAt
                : null),
        initialDataUpdatedAtCompute: initialDataUpdatedAtCompute ??
            (initialDataUpdatedAt == null
                ? this.initialDataUpdatedAtCompute
                : null),
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
///
/// Sealed rather than `final` because [DefaultedQueryObserverOptions] extends
/// it; the effect is the same — nothing outside this library can extend or
/// implement it — and the plain cache-layer instance is a private subclass
/// the constructor redirects to.
@immutable
sealed class DefaultedQueryOptions<TQueryData> {
  @internal
  const factory DefaultedQueryOptions({
    required QueryKey queryKey,
    required QueryFn<TQueryData>? queryFn,
    required Enabled enabled,
    required StaleTime staleTime,
    required GcTime gcTime,
    required RetryPolicy retry,
    required RetryDelay retryDelay,
    required NetworkMode networkMode,
    required InitialData<TQueryData>? initialData,
    required DateTime? initialDataUpdatedAt,
    required DateTime? Function()? initialDataUpdatedAtCompute,
    required StructuralSharing<TQueryData>? structuralSharing,
    required Object? meta,
    required FetchBehavior<TQueryData>? behavior,
  }) = _DefaultedQueryOptions<TQueryData>;

  const DefaultedQueryOptions._({
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
    required this.initialDataUpdatedAtCompute,
    required this.structuralSharing,
    required this.meta,
    required this.behavior,
  });

  /// [QueryOptions.queryKey].
  final QueryKey queryKey;

  /// [QueryOptions.queryFn], with the key's registered default applied. Still
  /// nullable: a query can be built without a function and fails only when it
  /// tries to fetch.
  final QueryFn<TQueryData>? queryFn;

  /// [QueryOptions.enabled], with the default applied.
  final Enabled enabled;

  /// [QueryOptions.staleTime], with the default applied.
  final StaleTime staleTime;

  /// [QueryOptions.gcTime], with the default applied.
  final GcTime gcTime;

  /// [QueryOptions.retry], with the default applied.
  final RetryPolicy retry;

  /// [QueryOptions.retryDelay], with the default applied.
  final RetryDelay retryDelay;

  /// [QueryOptions.networkMode], with the default applied.
  final NetworkMode networkMode;

  /// [QueryOptions.initialData]; there is no default.
  final InitialData<TQueryData>? initialData;

  /// [QueryOptions.initialDataUpdatedAt]; there is no default.
  final DateTime? initialDataUpdatedAt;

  /// Computes the seed timestamp only when data is actually seeded.
  /// Mutually exclusive with [initialDataUpdatedAt]; a null result uses now.
  final DateTime? Function()? initialDataUpdatedAtCompute;

  /// [QueryOptions.structuralSharing]; `null` still means `replaceEqualDeep`.
  final StructuralSharing<TQueryData>? structuralSharing;

  /// [QueryOptions.meta], with the key's registered default applied.
  final Object? meta;

  /// [QueryOptions.behavior]: set for infinite queries, `null` otherwise.
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
          other.initialDataUpdatedAtCompute == initialDataUpdatedAtCompute &&
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
        initialDataUpdatedAtCompute,
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
        initialDataUpdatedAtCompute: initialDataUpdatedAtCompute,
        structuralSharing: structuralSharing,
        meta: meta,
        behavior: behavior,
      );
}

/// The cache-layer instance: [DefaultedQueryOptions] and nothing more.
final class _DefaultedQueryOptions<TQueryData>
    extends DefaultedQueryOptions<TQueryData> {
  const _DefaultedQueryOptions({
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
    required super.initialDataUpdatedAtCompute,
    required super.structuralSharing,
    required super.meta,
    required super.behavior,
  }) : super._();
}

/// [DefaultedQueryOptions] plus the observer-only options.
@immutable
final class DefaultedQueryObserverOptions<TQueryData, TData>
    extends DefaultedQueryOptions<TQueryData> {
  /// Built by [QueryClient.defaultQueryObserverOptions]; not for callers.
  /// Not `const`, so that [queryOptions] can be built once per instance.
  @internal
  DefaultedQueryObserverOptions({
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
    required super.initialDataUpdatedAtCompute,
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
  }) : super._();

  /// [QueryObserverOptions.select]; there is no default.
  final TData Function(TQueryData data)? select;

  /// [QueryObserverOptions.placeholderData]; there is no default.
  final PlaceholderData<TQueryData>? placeholderData;

  /// [QueryObserverOptions.refetchOnMount], with the default applied.
  final RefetchOn refetchOnMount;

  /// [QueryObserverOptions.refetchOnWindowFocus], with the default applied.
  final RefetchOn refetchOnWindowFocus;

  /// [QueryObserverOptions.refetchOnReconnect], with the default applied.
  final RefetchOn refetchOnReconnect;

  /// [QueryObserverOptions.refetchInterval], with the default applied.
  final RefetchInterval refetchInterval;

  /// [QueryObserverOptions.refetchIntervalInBackground], with the default
  /// applied.
  final bool refetchIntervalInBackground;

  /// [QueryObserverOptions.retryOnMount], with the default applied.
  final bool retryOnMount;

  /// The cache-layer view of these options. Built on first read and kept:
  /// the observer hands it to its query on every `setOptions` and every
  /// fetch, and a fresh allocation each time was the only thing that
  /// changed between them (fifth review, 2026-09-09).
  late final DefaultedQueryOptions<TQueryData> queryOptions =
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
    initialDataUpdatedAtCompute: initialDataUpdatedAtCompute,
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
