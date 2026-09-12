/// Every `StaleTime` and every `GcTime` value, on one cache entry: the server
/// time (`GET /api/time`, whose `serial` grows by one per call, so a refetch
/// shows as a number and not as a clock). The reader is a `QueryController`
/// the screen creates and disposes on demand — detaching it is what leaves
/// the entry without an observer, which is when garbage collection starts,
/// and attaching a fresh one is a mount, which is when `refetchOnMount`
/// (`RefetchOn.ifStale` by default) decides whether to refetch.
///
/// Port-specific; it illustrates upstream's *Important Defaults* and *Caching*
/// guides. Upstream's `staleTime: Infinity` is two values here:
/// `StaleTime.infinite` (never stale by time, but an invalidation or a refetch
/// still fetches) and `StaleTime.static` (never refetched by any trigger —
/// mount, focus, reconnect, invalidation and `refetchQueries` all skip it).
/// What `static` does *not* block is the observer's own `refetch()` — the
/// `Refetch` button — and that is asserted here rather than the opposite.
///
/// Proofs (widget tests in `test/features/stale_and_gc_test.dart`, end-to-end
/// in `e2e/tests/stale_and_gc.spec.ts`): with `zero` the data is stale the
/// moment it arrives and re-attaching the reader refetches; with `5 s` it is
/// fresh, stale five seconds later, and re-attaching refetches only once it
/// is; with `static` neither re-attaching nor invalidating fetches, only
/// `Refetch` does, while with `infinite` invalidating does too; an
/// invalidation while a reader is attached refetches at once, and one while
/// detached is honoured on the next attach; a detached entry with `5 s` gc is
/// gone after five seconds and one with `never` is still there ten minutes
/// on, and attaching after a collection starts from scratch; the `dynamic`
/// stale time is fresh after an odd serial and stale after an even one.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/chrome.dart';
import '../../shared/controls.dart';
import '../../shared/debug_strip.dart';
import '../../shared/fact_group.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';

const Feature staleAndGcFeature = Feature(
  id: 'stale-and-gc',
  title: 'Stale time and garbage collection',
  summary: 'When data goes stale, and when an unused entry is dropped.',
);

const StaleTime _fiveSeconds = StaleTime.duration(Duration(seconds: 5));

/// `StaleTime.dynamic` is compared by the identity of its function, so the
/// function is a top-level one and the value a `const`: the segmented button
/// finds it selected again on every build.
const StaleTime _dynamic = StaleTime.dynamic(_freshWhileOdd);

/// Fresh for five seconds after an odd serial, stale at once after an even
/// one — a stale time that reads the data it is deciding about.
StaleTime _freshWhileOdd(Query<Object?> query) {
  final data = query.state.data;
  return data is ServerTime && data.serial.isOdd
      ? _fiveSeconds
      : StaleTime.zero;
}

/// The screen's one query, with the two knobs the screen turns.
QueryObserverOptions<ServerTime> serverTimeQuery(
  ShowcaseApi api, {
  required StaleTime staleTime,
  required GcTime gcTime,
}) =>
    QueryObserverOptions<ServerTime>(
      queryKey: ShowcaseKeys.time,
      queryFn: (context) => api.time(signal: context.signal),
      staleTime: staleTime,
      gcTime: gcTime,
    );

class StaleAndGcScreen extends StatefulWidget {
  const StaleAndGcScreen({super.key});

  @override
  State<StaleAndGcScreen> createState() => _StaleAndGcScreenState();
}

class _StaleAndGcScreenState extends State<StaleAndGcScreen> {
  static const List<(String, StaleTime)> _staleTimes = <(String, StaleTime)>[
    ('zero', StaleTime.zero),
    ('5 s', _fiveSeconds),
    ('infinite', StaleTime.infinite),
    ('static', StaleTime.static),
    ('dynamic', _dynamic),
  ];

  static const List<(String, GcTime)> _gcTimes = <(String, GcTime)>[
    ('5 s', GcTime.duration(Duration(seconds: 5))),
    ('never', GcTime.never),
  ];

  StaleTime _staleTime = StaleTime.zero;
  GcTime _gcTime = _gcTimes.first.$2;

  late final ShowcaseApi _api;
  late final QueryClient _client;
  bool _initialised = false;

  /// The reader, or null while detached. Created here rather than in
  /// `initState` because the api and the client are inherited widgets.
  QueryController<ServerTime, ServerTime>? _reader;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialised) {
      _initialised = true;
      _api = ShowcaseScope.apiOf(context);
      _client = QueryClientProvider.of(context);
      _reader = QueryController.create<ServerTime>(_client, _options);
    }
  }

  @override
  void dispose() {
    _reader?.dispose();
    super.dispose();
  }

  QueryObserverOptions<ServerTime> get _options =>
      serverTimeQuery(_api, staleTime: _staleTime, gcTime: _gcTime);

  void _attach() {
    setState(() {
      // A new controller is a new observer: subscribing it is a mount.
      _reader = QueryController.create<ServerTime>(_client, _options);
    });
  }

  void _detach() {
    setState(() {
      // Disposing destroys the observer; the entry has none left and its gc
      // timer starts.
      _reader?.dispose();
      _reader = null;
    });
  }

  void _invalidate() {
    _client
        .invalidateQueries(filters: QueryFilters(queryKey: ShowcaseKeys.time))
        .ignore();
  }

  void _remove() {
    _client.removeQueries(filters: QueryFilters(queryKey: ShowcaseKeys.time));
  }

  /// A changed option reaches a live reader through `setOptions`; a detached
  /// one picks it up on the next attach.
  void _applyOptions() {
    setState(() {
      _reader?.setOptions(_options);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reader = _reader;
    final small = Theme.of(context).textTheme.bodySmall;
    // One card, and the strip right under it: the widget tests run in a
    // 600 px window and a `ListView` only builds what is near the viewport.
    return FeatureScaffold(
      feature: staleAndGcFeature,
      children: <Widget>[
        SectionCard(
          title: 'Server time',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: 'Refetch',
                onPressed: reader?.refetch,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Detach reader',
                onPressed: reader == null ? null : _detach,
                icon: const Icon(Icons.visibility_off),
              ),
              IconButton(
                tooltip: 'Attach reader',
                onPressed: reader == null ? _attach : null,
                icon: const Icon(Icons.visibility),
              ),
              IconButton(
                tooltip: 'Invalidate',
                onPressed: _invalidate,
                icon: const Icon(Icons.restart_alt),
              ),
              IconButton(
                tooltip: 'Remove entry',
                onPressed: reader == null ? _remove : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (reader == null)
                const _Reading(
                  facts: <String>['reader=detached'],
                  child: Text(
                    'No reader: the entry stays cached until its gc time '
                    'runs out — watch the strip.',
                  ),
                )
              else
                ListenableBuilder(
                  listenable: reader,
                  builder: (context, _) {
                    final time = reader.value;
                    final data = time.dataOrNull;
                    return _Reading(
                      facts: <String>[
                        'reader=attached',
                        if (data != null) 'serial=${data.serial}',
                        'isStale=${time.isStale}',
                      ],
                      child: switch (time) {
                        QueryPending() => const SkeletonBox(width: 200),
                        QueryError(:final error, staleData: null) =>
                          Notice('$error', error: true),
                        QuerySuccess(:final data) ||
                        QueryError(staleData: final data!) =>
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  'Server clock ${hhmmss(data.now)}',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              if (time.isFetching) const Pill('refreshing'),
                            ],
                          ),
                      },
                    );
                  },
                ),
              const Divider(height: 24),
              knob<StaleTime>(
                context,
                title: 'Stale time',
                name: 'stale-time',
                choices: _staleTimes,
                selected: _staleTime,
                onChanged: (value) {
                  _staleTime = value;
                  _applyOptions();
                },
              ),
              const SizedBox(height: 4),
              Text(
                'dynamic: fresh for 5 s after an odd serial, stale at once '
                'after an even one. static blocks every trigger, invalidation '
                'included; infinite still honours an invalidation.',
                style: small,
              ),
              const SizedBox(height: 8),
              knob<GcTime>(
                context,
                title: 'GC time',
                name: 'gc-time',
                choices: _gcTimes,
                selected: _gcTime,
                onChanged: (value) {
                  _gcTime = value;
                  _applyOptions();
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Counted from the moment the last reader leaves. An entry '
                'keeps the longest gc time a reader ever gave it, so after '
                'never only removing the entry brings 5 s back.',
                style: small,
              ),
            ],
          ),
        ),
        QueryDebugStrip(queryKey: ShowcaseKeys.time, label: 'time'),
      ],
    );
  }
}

/// What the reader shows, and its own facts as `key=value` texts in a
/// semantics group of their own, so a test tells the reader's `isStale` apart
/// from the strip's.
class _Reading extends StatelessWidget {
  const _Reading({required this.facts, required this.child});

  final List<String> facts;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          child,
          const SizedBox(height: 8),
          FactGroup(name: 'reader', facts: facts, dense: true),
        ],
      );
}
