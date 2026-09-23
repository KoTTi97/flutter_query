/// Query options, the resolved options the client builds from them, and the
/// context a query function receives.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import 'cancel_token.dart';
import 'option_values.dart';
import 'query.dart';
import 'query_client.dart';
import 'query_key.dart';

/// What a query function is handed: the [client], the [queryKey] being
/// fetched, the query's [meta], and a cancel token, [signal].
///
/// Reading [signal] marks the fetch as cancellable. If the query function
/// never touches it, losing the last observer stops the retry loop but lets
/// the in-flight request finish and populate the cache.
///
/// ```dart
/// Future<List<Task>> fetchTasks(QueryFunctionContext context) {
///   final filter = context.queryKey.parts[1] as String;
///   final request = api.tasks(filter: filter);
///   context.signal.onCancel(request.abort);
///   return request.result;
/// }
/// ```
///
/// An infinite query's page function is handed an `InfinitePageContext`
/// instead, which carries the page param and the direction, typed.
///
/// {@category Queries}
class QueryFunctionContext {
  /// Built by the query for each fetch; a query function receives one rather
  /// than constructing it.
  ///
  /// Construct one directly to call a query function in a test, and leave
  /// [onSignalRead] unset — it is how the query learns that [signal] was
  /// read:
  ///
  /// ```dart
  /// final tasks = await fetchTasks(QueryFunctionContext(
  ///   client: client,
  ///   queryKey: QueryKey(['tasks', 'open']),
  ///   signal: QueryCancelToken(),
  /// ));
  /// ```
  QueryFunctionContext({
    required this.client,
    required this.queryKey,
    required QueryCancelToken signal,
    this.meta,
    void Function()? onSignalRead,
  })  : _signal = signal,
        _onSignalRead = onSignalRead;

  /// The client the query lives in: the way a query function reaches the
  /// cache for related data.
  final QueryClient client;

  /// The key of the query being fetched, so one function can serve every key
  /// it is registered for.
  final QueryKey queryKey;

  /// The query's [QueryOptions.meta], if one was set.
  final Object? meta;

  final QueryCancelToken _signal;

  /// Told the moment [signal] is first read, so the query can react *during*
  /// the fetch rather than after it.
  final void Function()? _onSignalRead;
  bool _signalConsumed = false;

  /// The cancel token for this fetch (TanStack Query: the `AbortSignal`).
  ///
  /// Reading it marks the fetch as cancellable: from then on, losing the last
  /// observer or a `cancelQueries` cancels the token and the query function
  /// is expected to stop. A function that never reads it is left to finish.
  ///
  /// The first read is what counts; reading it again changes nothing and
  /// returns the same token. Each retry gets a new context, so an attempt
  /// that never touches the token is as uncancellable as a first try that
  /// did not.
  QueryCancelToken get signal {
    if (!_signalConsumed) {
      _signalConsumed = true;
      _onSignalRead?.call();
    }
    return _signal;
  }
}

/// Which end of an infinite query is being fetched.
///
/// {@category Queries}
enum FetchDirection {
  /// Appending after the last page — `fetchNextPage`.
  forward,

  /// Prepending before the first page — `fetchPreviousPage`.
  backward,
}

/// The function a query runs to get its data: handed a
/// [QueryFunctionContext], it returns the data or a future of it. A throw
/// fails the attempt, which [QueryOptions.retry] may then retry.
///
/// {@category Queries}
typedef QueryFn<TQueryData> = FutureOr<TQueryData> Function(
    QueryFunctionContext context);

/// Decides what is written into the cache when new data arrives, given what
/// was there before.
///
/// Unset, `replaceEqualDeep` applies: data that is deep-equal to the
/// previous data keeps the previous instance, so an unchanged refetch notifies
/// nobody for unchanged data alone. Lists are shared element by element;
/// maps and sets are compared deeply and shared whole, while typed models
/// use their own `==` (or `StructurallyShareable`). Set this to
/// `noStructuralSharing()` ([noStructuralSharing]) to turn sharing off, or to
/// a function of your own to reconcile typed models yourself. TanStack Query
/// spells the opt-out `structuralSharing: false`.
///
/// ```dart
/// QueryOptions<Board>(
///   queryKey: QueryKey(['board']),
///   queryFn: fetchBoard,
///   structuralSharing: (previous, next) =>
///       previous != null && previous.version == next.version
///           ? previous
///           : next,
/// );
/// ```
///
/// A hook governs the cache write and unselected placeholder data. A
/// `select`'s output goes through `replaceEqualDeep` instead, because a hook
/// typed on the raw data cannot be handed a selection of another type.
/// (TanStack Query calls its hook on the selected value as well.) Only
/// `noStructuralSharing()` turns the selection's sharing off as well: a hook
/// that *does* share, deeply or in its own way, leaves the selection at the
/// default. After removing a selector, an unselected placeholder receives no
/// previous raw value from that selection.
///
/// [previous] is `null` when nothing has been cached yet. With a nullable
/// `TQueryData` the hook cannot tell that apart from a previous value that
/// *was* `null`; a hook that needs the distinction reads
/// `query.state.hasData` instead.
///
/// {@category Structural sharing}
typedef StructuralSharing<TQueryData> = TQueryData Function(
    TQueryData? previous, TQueryData next);

/// The opt-out for [QueryOptions.structuralSharing]: every write keeps the
/// incoming value, so every refetch reports a new instance, and so does every
/// `select`. TanStack Query spells this `structuralSharing: false`.
///
/// ```dart
/// QueryOptions<List<Task>>(
///   queryKey: QueryKey(['tasks']),
///   queryFn: fetchTasks,
///   structuralSharing: noStructuralSharing(),
/// );
/// ```
///
/// Use this rather than an equivalent `(_, next) => next` of your own. The two
/// behave identically where they are called — on the cache write and on
/// unselected placeholder data — but only this one is *recognised* as the
/// opt-out, and that is what turns sharing off for a `select`'s output too:
/// no hook typed on the query's data can be handed a selection of another
/// type, so a hook of your own leaves the selection shared by the default
/// walk.
///
/// A call rather than a function to pass: it returns one hook per
/// `TQueryData`, the same instance every time, so options built with it
/// compare equal across rebuilds. Recognition is by that instance's identity.
///
/// {@category Structural sharing}
StructuralSharing<TQueryData> noStructuralSharing<TQueryData>() {
  // Memoised instances rather than a generic tear-off compared by `==`: on
  // the VM, `f<T>` instantiated inside a generic class is not `==` to the
  // `f<String>` a caller passed, even when `T` is `String`.
  final existing = _noStructuralSharingHooks[TQueryData];
  if (existing != null) {
    return existing as StructuralSharing<TQueryData>;
  }
  TQueryData keepNext(TQueryData? previous, TQueryData next) => next;
  final StructuralSharing<TQueryData> hook = keepNext;
  _noStructuralSharingHooks[TQueryData] = hook;
  _noStructuralSharingInstances.add(hook);
  return hook;
}

// One opt-out per data type, shared across clients: the hooks close over
// nothing, so the memo is a cache of pure functions, as `QueryClient`'s
// adapted defaults are.
final Map<Type, Function> _noStructuralSharingHooks = <Type, Function>{};
final Set<Function> _noStructuralSharingInstances = Set<Function>.identity();

/// Whether [sharing] is a hook [noStructuralSharing] returned — the opt-out,
/// rather than a hook of the user's own.
@internal
bool isNoStructuralSharing(Function? sharing) =>
    sharing != null && _noStructuralSharingInstances.contains(sharing);

/// Projects a query's data into what an observer reports — the `select` of a
/// [QuerySelectOptions]. It runs on the observer's side, so every observer of
/// one query may select something different from the same cached data.
///
/// {@category Queries}
typedef SelectFn<TQueryData, TData> = TData Function(TQueryData data);

/// The value of [QueryOptions.initialData]: seed data written into the cache,
/// as if it had been fetched.
///
/// Unlike [PlaceholderData], a seed *is* cached: it is shared with every
/// observer of the key, and it goes stale by `staleTime` like fetched data.
/// There is no default — unset, a query starts with no data.
///
/// - `InitialData.value(tasks)` — a seed that is always present.
/// - `InitialData.compute(() => client.getQueryData<Task>(key))` — a seed
///   computed lazily, skipped while the callback returns `null`.
///
/// {@category Option values}
@immutable
sealed class InitialData<TQueryData> {
  const InitialData();

  /// A seed that is always present (TanStack Query: `initialData: value`).
  const factory InitialData.value(TQueryData data) =
      InitialDataValue<TQueryData>;

  /// A seed computed lazily — when the query is built, and again on every
  /// options update and every fetch for as long as the query holds no data —
  /// and skipped while [compute] returns `null`. See
  /// [InitialDataCompute.compute] for when it runs. TanStack Query:
  /// `initialData: () => value`.
  const factory InitialData.compute(TQueryData? Function() compute) =
      InitialDataCompute<TQueryData>;

  /// The seed, and whether there is one.
  ///
  /// `.value(x)` always seeds — `x` may be `null` for a nullable data type,
  /// and the wrapper itself is the presence. `.compute` returning `null`
  /// means no data after all. That is the one place where Dart's single null
  /// has to carry two meanings, and the callback form is where "return
  /// `null` to skip" lives.
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
///
/// {@category Option values}
final class InitialDataValue<TQueryData> extends InitialData<TQueryData> {
  /// Seeds the cache with [data] when the query is created without data.
  const InitialDataValue(this.data);

  /// The value the cache starts with.
  final TQueryData data;

  // Value equality, like every other option value: an `InitialData.value`
  // built inline would otherwise make every `setOptions` look like a change.
  // Exact runtime types here and in the four siblings below: a covariant `is`
  // alone made `.value<num>(1) == .value<int>(1)` but not the reverse, and
  // the two hashed apart.
  @override
  bool operator ==(Object other) =>
      other is InitialDataValue<TQueryData> &&
      other.runtimeType == runtimeType &&
      other.data == data;
  @override
  int get hashCode => Object.hash(InitialDataValue<TQueryData>, data);
  @override
  String toString() => 'InitialData.value($data)';
}

/// The [InitialData.compute] variant: a seed computed lazily, for as long as
/// the query has no data.
///
/// ```dart
/// initialData: InitialData.compute(
///   () => client
///       .getQueryData<List<Task>>(QueryKey(['tasks']))
///       ?.where((task) => task.id == id)
///       .firstOrNull,
/// ),
/// ```
///
/// {@category Option values}
final class InitialDataCompute<TQueryData> extends InitialData<TQueryData> {
  /// Seeds the cache with what [compute] returns, unless that is `null`.
  const InitialDataCompute(this.compute);

  /// Called when the query is created, and again on every options update —
  /// every observer rebuild, equal options included — and every fetch, until
  /// the query holds data; once seeded or fetched it is never consulted
  /// again. That matches TanStack Query's behaviour, and it is what lets a
  /// detail seed itself from a list that arrives later.
  ///
  /// Returning `null` means "no seed after all", and the next call may still
  /// yield one. A seed that becomes available
  /// replaces an error the query holds without data. A callback that is
  /// expensive to run is the caller's to memoise.
  final TQueryData? Function() compute;

  // Equal when the function is: two tear-offs of one function compare equal
  // in Dart, two inline closures never do — so a `.compute(seedFromCache)`
  // written with a tear-off survives a rebuild as "unchanged", and an inline
  // closure is honestly a new one.
  @override
  bool operator ==(Object other) =>
      other is InitialDataCompute<TQueryData> &&
      other.runtimeType == runtimeType &&
      other.compute == compute;
  @override
  int get hashCode => Object.hash(InitialDataCompute<TQueryData>, compute);
  @override
  String toString() => 'InitialData.compute($compute)';
}

/// The value of [QueryObserverOptionsBase.placeholderData]: data an observer
/// shows while its query has none of its own.
///
/// A placeholder is never written to the cache. It belongs to the observer
/// that asked for it, the result built from it reports `isPlaceholderData`,
/// and it gives way the moment real data arrives. There is no default —
/// unset, an observer without data reports a pending result.
///
/// - `PlaceholderData.keepPrevious()` — keeps what this observer showed for
///   the previous key while the new key loads: page 2 stays on screen until
///   page 3 arrives, instead of a spinner in between.
/// - `PlaceholderData.value(Task.empty)` — a fixed placeholder.
/// - `PlaceholderData.compute((previousData, previousQuery) => ...)` — a
///   placeholder computed from what the observer showed last.
///
/// {@category Option values}
@immutable
sealed class PlaceholderData<TQueryData> {
  const PlaceholderData();

  /// Keeps the previous data while the new key loads. A previous `null`
  /// means no placeholder, just as `.compute((previous, _) => previous)`.
  const factory PlaceholderData.keepPrevious() =
      PlaceholderDataKeepPrevious<TQueryData>;

  /// A fixed placeholder, shown whenever the query has no data of its own
  /// (TanStack Query: `placeholderData: value`).
  const factory PlaceholderData.value(TQueryData data) =
      PlaceholderDataValue<TQueryData>;

  /// The callback form: return [previousData] to keep the last page's
  /// content on screen while the new key loads, or anything else derived
  /// from it. Returning `null` means no placeholder.
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

/// The [PlaceholderData.keepPrevious] variant: while the observer's new key
/// has no data, it keeps showing what it showed for the key before, flagged
/// as `isPlaceholderData`. Equal to every other `keepPrevious()` of its type,
/// so options that use it compare equal across rebuilds.
///
/// {@category Option values}
final class PlaceholderDataKeepPrevious<TQueryData>
    extends PlaceholderData<TQueryData> {
  /// Keeps the last non-null data as a placeholder.
  const PlaceholderDataKeepPrevious();

  @override
  bool operator ==(Object other) =>
      other is PlaceholderDataKeepPrevious<TQueryData> &&
      other.runtimeType == runtimeType;

  @override
  int get hashCode => (PlaceholderDataKeepPrevious<TQueryData>).hashCode;
  @override
  String toString() => 'PlaceholderData.keepPrevious()';
}

/// The [PlaceholderData.value] variant: a fixed placeholder, shown whenever
/// the query has no data of its own.
///
/// {@category Option values}
final class PlaceholderDataValue<TQueryData>
    extends PlaceholderData<TQueryData> {
  /// Shows [data] until real data arrives.
  const PlaceholderDataValue(this.data);

  /// What the observer shows while the query has no data; never cached.
  final TQueryData data;

  @override
  bool operator ==(Object other) =>
      other is PlaceholderDataValue<TQueryData> &&
      other.runtimeType == runtimeType &&
      other.data == data;
  @override
  int get hashCode => Object.hash(PlaceholderDataValue<TQueryData>, data);
  @override
  String toString() => 'PlaceholderData.value($data)';
}

/// The [PlaceholderData.compute] variant: a placeholder computed from what
/// the observer showed last (TanStack Query:
/// `placeholderData: (previousData, previousQuery) => value`).
///
/// {@category Option values}
final class PlaceholderDataCompute<TQueryData>
    extends PlaceholderData<TQueryData> {
  /// Shows what [compute] returns while the query has no data, unless that
  /// is `null`.
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
      other is PlaceholderDataCompute<TQueryData> &&
      other.runtimeType == runtimeType &&
      other.compute == compute;
  @override
  int get hashCode => Object.hash(PlaceholderDataCompute<TQueryData>, compute);
  @override
  String toString() => 'PlaceholderData.compute($compute)';
}

/// Everything the cache entry for a query needs: its [queryKey], the
/// [queryFn] that fetches it, and how long and how hard to keep it —
/// [staleTime], [gcTime], [retry], [retryDelay], [networkMode], [enabled],
/// [initialData], [structuralSharing] and [meta].
///
/// This is what the imperative [QueryClient.query] takes, which fetches once
/// and completes with the data. An observer — a widget watching the
/// query — takes [QueryObserverOptions] or [QuerySelectOptions] instead,
/// which add what only a watcher cares about: when to refetch
/// (`refetchOnMount`, `refetchOnWindowFocus`, `refetchOnReconnect`,
/// `refetchInterval`), `placeholderData`, and `select`. Both extend this
/// class, so one options helper can serve both paths.
///
/// **`null` means unset on every option field.** An unset field takes the
/// default registered for the key with [QueryClient.setQueryDefaults], then
/// the client's `DefaultOptions`, then the library default each field's
/// documentation names. An option with a real "off" value says so with a
/// value — `RefetchInterval.off`, `RetryPolicy.never`, `Enabled.no` — never
/// with `null`.
///
/// ```dart
/// QueryObserverOptions<List<Todo>> todosQuery() => QueryObserverOptions(
///       queryKey: QueryKey(['todos']),
///       queryFn: (context) => api.fetchTodos(),
///       staleTime: const StaleTime.duration(Duration(minutes: 1)),
///     );
///
/// final todos = await client.query(todosQuery());
/// ```
///
/// No value equality, on purpose: options built inline in a `build` are
/// re-applied on every build, and the observer works out what actually
/// changed by comparing the *resolved* values — so two inline closures for
/// `queryFn` do not count as a change, and neither does a fresh
/// `Enabled.when(…)`.
///
/// {@category Options}
@immutable
base class QueryOptions<TQueryData> {
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
    @internal this.behavior,
  });

  /// The key this query is cached under. Required. Bound to exactly one data
  /// type: a key read as another type — a supertype included — throws
  /// `QueryDataTypeError`.
  final QueryKey queryKey;

  /// Fetches the data. Unset, the query uses the function registered for its
  /// key with [QueryClient.setQueryDefaults]; with none there either, a
  /// fetch fails with [MissingQueryFunctionError].
  final QueryFn<TQueryData>? queryFn;

  /// Whether the query may fetch on its own. The default: [Enabled.yes]. A
  /// disabled query still serves whatever the cache holds and can still be
  /// refetched by hand.
  final Enabled? enabled;

  /// How long fetched data counts as fresh. The default: [StaleTime.zero],
  /// stale the moment it arrives, so every mount, focus and reconnect
  /// refetches.
  final StaleTime? staleTime;

  /// How long the query stays cached after its last observer leaves. The
  /// default: [GcTime.defaultValue], five minutes.
  final GcTime? gcTime;

  /// Whether a failed fetch is retried. The default: `RetryPolicy.times(3)`,
  /// three retries after the first failure (TanStack Query: `retry: 3`).
  /// [QueryClient.query] is the exception: when neither these options nor
  /// the client's defaults set [retry], its fetch is not retried.
  final RetryPolicy? retry;

  /// How long to wait between attempts. The default:
  /// [RetryDelay.defaultValue], exponential back-off from one second —
  /// one, two, four, … — capped at thirty.
  final RetryDelay? retryDelay;

  /// How connectivity gates the fetch. The default: [NetworkMode.online],
  /// an offline device pauses the fetch until it is back.
  final NetworkMode? networkMode;

  /// Data the cache starts with, as if it had been fetched — see
  /// [InitialData]. No default: unset, the query starts without data. Unlike
  /// `placeholderData` it *is* written to the cache, and it goes stale by
  /// [staleTime] from [initialDataUpdatedAt] on.
  final InitialData<TQueryData>? initialData;

  /// When [initialData] was fetched, for the staleness clock. No default:
  /// unset, the seed counts as fetched the moment it is written.
  final DateTime? initialDataUpdatedAt;

  /// Computes the seed timestamp only when data is actually seeded. No
  /// default. Mutually exclusive with [initialDataUpdatedAt]; a `null`
  /// result means now.
  final DateTime? Function()? initialDataUpdatedAtCompute;

  /// How new data is reconciled with what the cache already holds — see
  /// [StructuralSharing]. The default: `replaceEqualDeep`, which keeps every
  /// deep-equal part of the previous data. [noStructuralSharing] turns it
  /// off.
  final StructuralSharing<TQueryData>? structuralSharing;

  /// Arbitrary data carried along for logging, devtools or a query function,
  /// which receives it as [QueryFunctionContext.meta]. No default: unset,
  /// the key's registered default applies, if any.
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
        behavior: behavior,
      );

  /// What [toString] shows after the key: every field, in declaration order,
  /// with the unset (`null`) ones skipped — so a test failure or a debug
  /// print reads `QueryOptions<int>(QueryKey(["a"]), staleTime: …)` rather
  /// than `Instance of 'QueryOptions<int>'`. A subclass adds its own fields
  /// after these.
  @protected
  Map<String, Object?> get toStringFields => <String, Object?>{
        'queryFn': queryFn,
        'enabled': enabled,
        'staleTime': staleTime,
        'gcTime': gcTime,
        'retry': retry,
        'retryDelay': retryDelay,
        'networkMode': networkMode,
        'initialData': initialData,
        'initialDataUpdatedAt': initialDataUpdatedAt,
        'initialDataUpdatedAtCompute': initialDataUpdatedAtCompute,
        'structuralSharing': structuralSharing,
        'meta': meta,
        'behavior': behavior,
      };

  @override
  String toString() {
    final fields = toStringFields.entries
        .where((field) => field.value != null)
        .map((field) => ', ${field.key}: ${field.value}')
        .join();
    return '$runtimeType($queryKey$fields)';
  }
}

/// [QueryOptions] plus everything only an observer cares about: when to
/// refetch ([refetchOnMount], [refetchOnWindowFocus], [refetchOnReconnect],
/// [refetchInterval], [refetchIntervalInBackground], [retryOnMount]), what
/// to show while there is no data ([placeholderData]), and what part of the
/// data to report ([select]).
///
/// The fields [QueryOptions] declares describe the cache entry, which every
/// observer of the key shares; these describe one observer, so two widgets
/// watching one key may poll, refetch and select differently. As on
/// [QueryOptions], `null` means unset on every field, and an unset field
/// takes the key's registered default, then the client's, then the library
/// default each field names.
///
/// Sealed over exactly two shapes: [QueryObserverOptions], which has no
/// `select`, and [QuerySelectOptions], which requires one. Dart cannot infer
/// the query's data type from a `select` function alone, so a select that
/// changes the type lives on a separate options class that names both type
/// arguments; the data type an observer reports is then always anchored by
/// a required parameter — `queryFn` on the plain shape, `select` on the
/// select shape — and never silently inferred as `dynamic`. `QueryObserver`
/// and `QueryClient.defaultQueryObserverOptions` accept either shape
/// through this base.
///
/// Like [QueryOptions], deliberately without value equality: an observer is
/// handed the options a widget built on every build and compares what they
/// resolve to, so a `select` or `placeholderData` written inline is not a
/// change by itself.
///
/// {@category Options}
@immutable
sealed class QueryObserverOptionsBase<TQueryData, TData>
    extends QueryOptions<TQueryData> {
  /// The cache-layer fields plus the observer's own. Every field but
  /// [queryKey] is optional and takes the client's default.
  const QueryObserverOptionsBase({
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
    @internal super.behavior,
    this.placeholderData,
    this.refetchOnMount,
    this.refetchOnWindowFocus,
    this.refetchOnReconnect,
    this.refetchInterval,
    this.refetchIntervalInBackground,
    this.retryOnMount,
  });

  /// Narrows what the observer reports — and therefore what a change in the
  /// cached data has to touch before a listener is notified. No default:
  /// `null` on a [QueryObserverOptions], never on a [QuerySelectOptions].
  SelectFn<TQueryData, TData>? get select;

  /// Data shown while the query has none of its own — see [PlaceholderData].
  /// No default: unset, an observer without data reports a pending result.
  /// Never written to the cache: a result built from it reports
  /// `isPlaceholderData`, and it gives way the moment real data arrives.
  final PlaceholderData<TQueryData>? placeholderData;

  /// Whether this observer subscribing triggers a refetch. The default:
  /// [RefetchOn.ifStale], only when the data is older than [staleTime].
  final RefetchOn? refetchOnMount;

  /// Whether the app regaining focus triggers a refetch. The default:
  /// [RefetchOn.ifStale].
  final RefetchOn? refetchOnWindowFocus;

  /// Whether the device coming back online triggers a refetch. The default:
  /// [RefetchOn.ifStale] — except under [NetworkMode.always], where it is
  /// [RefetchOn.never]: a fetch that ignores connectivity has nothing to
  /// catch up on.
  final RefetchOn? refetchOnReconnect;

  /// Polls the query on a timer while this observer is subscribed. The
  /// default: [RefetchInterval.off].
  final RefetchInterval? refetchInterval;

  /// Whether [refetchInterval] keeps polling while the app is not focused.
  /// The default: `false`, the timer skips its turns until focus returns.
  final bool? refetchIntervalInBackground;

  /// Whether a query that ended in an error retries when an observer mounts.
  /// The default: `true`, the mount refetches, and only
  /// `retryOnMount: false` leaves the error standing until something else
  /// asks.
  final bool? retryOnMount;

  @override
  Map<String, Object?> get toStringFields => <String, Object?>{
        ...super.toStringFields,
        'select': select,
        'placeholderData': placeholderData,
        'refetchOnMount': refetchOnMount,
        'refetchOnWindowFocus': refetchOnWindowFocus,
        'refetchOnReconnect': refetchOnReconnect,
        'refetchInterval': refetchInterval,
        'refetchIntervalInBackground': refetchIntervalInBackground,
        'retryOnMount': retryOnMount,
      };

  /// This, with the given fields replaced; each shape returns its own type.
  /// `select` is not a field here — it is what tells the two shapes apart —
  /// so only [QuerySelectOptions.copyWith] accepts one.
  @override
  QueryObserverOptionsBase<TQueryData, TData> copyWith({
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
    PlaceholderData<TQueryData>? placeholderData,
    RefetchOn? refetchOnMount,
    RefetchOn? refetchOnWindowFocus,
    RefetchOn? refetchOnReconnect,
    RefetchInterval? refetchInterval,
    bool? refetchIntervalInBackground,
    bool? retryOnMount,
  });
}

/// Observer options for a plain query: no `select`, so the observer reports
/// the query's data as its own, and one type argument names both.
///
/// The type comes from `queryFn`'s return type or an explicit argument —
/// `QueryObserverOptions<Task>(…)`. Written inline with neither, [TData] has
/// nothing to infer from; the binding's controllers refuse that in debug
/// mode, and the analyzer's `strict-inference` reports it at the literal.
///
/// ```dart
/// QueryObserverOptions<List<Todo>> todosQuery() => QueryObserverOptions(
///       queryKey: QueryKey(['todos']),
///       queryFn: (context) => api.fetchTodos(),
///       refetchInterval: const RefetchInterval.every(Duration(seconds: 30)),
///     );
///
/// // Imperatively: fetch once, if stale, and read the data.
/// final todos = await client.query(todosQuery());
///
/// // Or watch it: the observer fetches on its first subscriber.
/// final observer = QueryObserver(client, todosQuery());
/// final unsubscribe = observer.subscribe((result) => print(result));
/// ```
///
/// Every field is described on [QueryOptions] and
/// [QueryObserverOptionsBase], with its default. For a query whose observers
/// see a projection of the cached data, use [QuerySelectOptions], or
/// [withSelect] on existing options.
///
/// {@category Options}
@immutable
final class QueryObserverOptions<TData>
    extends QueryObserverOptionsBase<TData, TData> {
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
    @internal super.behavior,
    super.placeholderData,
    super.refetchOnMount,
    super.refetchOnWindowFocus,
    super.refetchOnReconnect,
    super.refetchInterval,
    super.refetchIntervalInBackground,
    super.retryOnMount,
  });

  /// Always `null`: a plain query has no projection.
  @override
  SelectFn<TData, TData>? get select => null;

  @override
  QueryObserverOptions<TData> copyWith({
    QueryKey? queryKey,
    QueryFn<TData>? queryFn,
    Enabled? enabled,
    StaleTime? staleTime,
    GcTime? gcTime,
    RetryPolicy? retry,
    RetryDelay? retryDelay,
    NetworkMode? networkMode,
    InitialData<TData>? initialData,
    DateTime? initialDataUpdatedAt,
    DateTime? Function()? initialDataUpdatedAtCompute,
    StructuralSharing<TData>? structuralSharing,
    Object? meta,
    PlaceholderData<TData>? placeholderData,
    RefetchOn? refetchOnMount,
    RefetchOn? refetchOnWindowFocus,
    RefetchOn? refetchOnReconnect,
    RefetchInterval? refetchInterval,
    bool? refetchIntervalInBackground,
    bool? retryOnMount,
  }) =>
      QueryObserverOptions<TData>(
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
        behavior: behavior,
        placeholderData: placeholderData ?? this.placeholderData,
        refetchOnMount: refetchOnMount ?? this.refetchOnMount,
        refetchOnWindowFocus: refetchOnWindowFocus ?? this.refetchOnWindowFocus,
        refetchOnReconnect: refetchOnReconnect ?? this.refetchOnReconnect,
        refetchInterval: refetchInterval ?? this.refetchInterval,
        refetchIntervalInBackground:
            refetchIntervalInBackground ?? this.refetchIntervalInBackground,
        retryOnMount: retryOnMount ?? this.retryOnMount,
      );

  /// These options with a [select] added: every field carried over, so a
  /// shared options helper can serve a projecting reader without being
  /// written out again field by field. The result is a [QuerySelectOptions]
  /// on the same key, so it shares the cache entry with every other reader.
  ///
  /// ```dart
  /// final openCount = todosQuery().withSelect(
  ///   (todos) => todos.where((todo) => !todo.done).length,
  /// );
  /// final observer = QueryObserver(client, openCount); // reports an int
  /// ```
  QuerySelectOptions<TData, R> withSelect<R>(SelectFn<TData, R> select) =>
      QuerySelectOptions<TData, R>(
        queryKey: queryKey,
        select: select,
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
        placeholderData: placeholderData,
        refetchOnMount: refetchOnMount,
        refetchOnWindowFocus: refetchOnWindowFocus,
        refetchOnReconnect: refetchOnReconnect,
        refetchInterval: refetchInterval,
        refetchIntervalInBackground: refetchIntervalInBackground,
        retryOnMount: retryOnMount,
      );
}

/// Observer options for a query whose observers see a projection of the
/// cached data: what the cache holds ([TQueryData]) and what [select] makes
/// of it ([TData]) — two type arguments, both anchored, [TData] by the
/// required [select].
///
/// ```dart
/// QuerySelectOptions<Task, String> taskName(int id) => QuerySelectOptions(
///       queryKey: QueryKey(['tasks', id]),
///       queryFn: (_) => api.task(id),
///       select: (task) => task.name,
///     );
/// ```
///
/// Dart cannot infer the query's data type from a `select` function alone,
/// so a select lives on this separate options class, which names both type
/// arguments. A `select` that keeps the type (`List<Task>` → `List<Task>`)
/// is still a select and still goes here; the shape is about *whether*
/// there is a projection, not about the types being different.
///
/// The observer runs [select] on the cached data and reports only the
/// result, so a change to the cached data reaches its listeners only when
/// the selected value changes: a widget showing a task's name is not told
/// when only the task's due date changed.
/// Existing plain options gain a select with
/// [QueryObserverOptions.withSelect].
///
/// {@category Options}
@immutable
final class QuerySelectOptions<TQueryData, TData>
    extends QueryObserverOptionsBase<TQueryData, TData> {
  /// The cache-layer fields plus the observer's own, [select] required.
  /// Every other field but [queryKey] is optional and takes the client's
  /// default.
  const QuerySelectOptions({
    required super.queryKey,
    required this.select,
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
    @internal super.behavior,
    super.placeholderData,
    super.refetchOnMount,
    super.refetchOnWindowFocus,
    super.refetchOnReconnect,
    super.refetchInterval,
    super.refetchIntervalInBackground,
    super.retryOnMount,
  });

  /// Narrows what the observer reports — and therefore what a change in the
  /// cached data has to touch before a listener is notified. Required.
  @override
  final SelectFn<TQueryData, TData> select;

  @override
  QuerySelectOptions<TQueryData, TData> copyWith({
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
    PlaceholderData<TQueryData>? placeholderData,
    RefetchOn? refetchOnMount,
    RefetchOn? refetchOnWindowFocus,
    RefetchOn? refetchOnReconnect,
    RefetchInterval? refetchInterval,
    bool? refetchIntervalInBackground,
    bool? retryOnMount,
    SelectFn<TQueryData, TData>? select,
  }) =>
      QuerySelectOptions<TQueryData, TData>(
        queryKey: queryKey ?? this.queryKey,
        select: select ?? this.select,
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
        behavior: behavior,
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

/// [QueryOptions] with every default resolved: what a [Query] actually runs
/// on, read back as [Query.options].
///
/// Only [QueryClient] produces one — [QueryClient.defaultQueryOptions]
/// fills each unset field from the key's registered defaults, the client's
/// defaults and the library defaults, in that order. Nothing downstream can
/// be handed half-resolved options, and fields that always have a value are
/// non-nullable here. A user meets these when inspecting a query in the
/// cache, in a devtool or a test; building a query takes [QueryOptions].
///
/// Unlike [QueryOptions], these have value equality, which is what tells a
/// query handed new options on a rebuild that nothing actually changed.
///
/// {@category Advanced}
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

  // Sealed rather than `final` because [DefaultedQueryObserverOptions]
  // extends it; nothing outside this library can extend or implement it
  // either way, and the plain cache-layer instance is a private subclass the
  // factory redirects to.
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

  /// Field-by-field equality, functions compared by identity. It is what
  /// tells a rebuild that nothing actually changed.
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

/// [QueryObserverOptionsBase] with every default resolved:
/// [DefaultedQueryOptions] plus the observer-only options, what a
/// `QueryObserver` actually runs on.
///
/// Only [QueryClient] produces one, through
/// [QueryClient.defaultQueryObserverOptions]; an observer resolves the
/// options it is handed on construction and on every `setOptions`. Value
/// equality tells the observer whether a rebuild changed anything.
/// [queryOptions] is the part the shared cache entry receives.
///
/// {@category Advanced}
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

  /// [QuerySelectOptions.select], or `null` for a [QueryObserverOptions];
  /// there is no default.
  final SelectFn<TQueryData, TData>? select;

  /// [QueryObserverOptionsBase.placeholderData]; there is no default.
  final PlaceholderData<TQueryData>? placeholderData;

  /// [QueryObserverOptionsBase.refetchOnMount], with the default applied.
  final RefetchOn refetchOnMount;

  /// [QueryObserverOptionsBase.refetchOnWindowFocus], with the default applied.
  final RefetchOn refetchOnWindowFocus;

  /// [QueryObserverOptionsBase.refetchOnReconnect], with the default applied.
  final RefetchOn refetchOnReconnect;

  /// [QueryObserverOptionsBase.refetchInterval], with the default applied.
  final RefetchInterval refetchInterval;

  /// [QueryObserverOptionsBase.refetchIntervalInBackground], with the default
  /// applied.
  final bool refetchIntervalInBackground;

  /// [QueryObserverOptionsBase.retryOnMount], with the default applied.
  final bool retryOnMount;

  /// The cache-layer view of these options — the fourteen fields a [Query]
  /// runs on, and none of the observer's own.
  ///
  /// The narrowing is the point: a query is shared by every observer of its
  /// key, and [Query.setOptions] compares what it is handed by value.
  /// Passing the observer's full options would make two observers that
  /// differ only in `select`, `refetchOnMount` or their refetch triggers look
  /// like two different *query* configurations, and the query they share
  /// would churn between them.
  ///
  /// Built on first read and kept, so the observer hands its query the same
  /// instance on every `setOptions` and every fetch.
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
