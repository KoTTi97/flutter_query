/// `refetchOnWindowFocus` and `refetchOnMount`, on two entries of the server
/// time (`GET /api/time`, whose `serial` grows by one per call, so a refetch
/// shows as a number and not as a clock) that hold the same data under two
/// different policies.
///
/// Entry A is a `QueryController` created in `initState` and read through a
/// `ListenableBuilder`, so turning a knob reaches a live reader through
/// `setOptions`. Entry B is a `QueryBuilder` that can be detached and
/// re-attached, because a fresh observer is a mount and that is when
/// `refetchOnMount` decides.
///
/// Where focus comes from: in a real app `QueryClientProvider` installs an
/// `AppLifecycleListener` and maps every `AppLifecycleState` onto
/// `client.focusManager.setFocused(...)` — `resumed` and `inactive` are
/// focused, `hidden`, `paused` and `detached` are not. A headless browser
/// never reports a Flutter lifecycle transition, so the screen's own
/// `App focused` switch calls `setFocused` directly and *is* the focus source
/// the tests drive.
///
/// Port-specific; it illustrates upstream's *Window Focus Refetching* guide.
/// `RefetchOn.when` is upstream's `(query) => boolean | 'always'`, and the
/// rule shown here is "refetch on focus only while the data is older than
/// ten seconds" — `query.isStaleByTime`, which reads the clock the library
/// reads, so it is right under a widget test's fake one too.
///
/// Proofs (widget tests in `test/features/focus_refetch_test.dart`, end-to-end
/// in `e2e/tests/focus_refetch.spec.ts`): `always` refetches on focus although
/// the data is fresh; `never` refetches on nothing, stale data included;
/// `ifStale` waits for the data to go stale, by the clock or by the stale-time
/// knob; `when` skips a focus five seconds in and takes one eleven seconds in;
/// detaching and re-attaching entry B fetches under `always`, not under
/// `never`, and under `ifStale` only once the data is stale; and one focus
/// event reaches both entries, each answering with its own knob.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

import '../../shared/api.dart';
import '../../shared/debug_strip.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';
import '../../shared/theme.dart';

const Feature focusRefetchFeature = Feature(
  id: 'focus-refetch',
  title: 'Focus refetch',
  summary: 'What happens when the app comes back to the foreground.',
);

/// The two entries. Separate keys, so the two policies sit side by side on the
/// same data rather than sharing one cache entry — a query has one state, and
/// the first observer that wants a focus refetch would fetch for both.
QueryKey get focusKeyA => QueryKey(const <Object?>['focus', 'a']);
QueryKey get focusKeyB => QueryKey(const <Object?>['focus', 'b']);

const StaleTime _thirtySeconds = StaleTime.duration(Duration(seconds: 30));

/// The `RefetchOn.when` on offer. Compared by the identity of its function, so
/// the function is a top-level one and the value a `const`: the segmented
/// button finds it selected again on every build.
const RefetchOn _whenOlderThanTenSeconds = RefetchOn.when(_olderThanTenSeconds);

/// Refetch on focus only while the data is older than ten seconds.
///
/// [Query.isStaleByTime] answers exactly that question against the library's
/// own clock, and it is independent of the `staleTime` the query runs under —
/// which is the point of a `when`: a rule of its own, not the stale time
/// again.
RefetchOn _olderThanTenSeconds(Query<Object?> query) =>
    query.isStaleByTime(const StaleTime.duration(Duration(seconds: 10)))
        ? RefetchOn.always
        : RefetchOn.never;

/// One entry's query: the same server time, under the knobs the screen turns.
QueryObserverOptions<ServerTime, ServerTime> focusTimeQuery(
  ShowcaseApi api, {
  required QueryKey queryKey,
  required RefetchOn onFocus,
  required RefetchOn onMount,
  required StaleTime staleTime,
}) =>
    QueryObserverOptions<ServerTime, ServerTime>(
      queryKey: queryKey,
      queryFn: (context) => api.time(signal: context.signal),
      staleTime: staleTime,
      refetchOnWindowFocus: onFocus,
      refetchOnMount: onMount,
    );

class FocusRefetchScreen extends StatefulWidget {
  const FocusRefetchScreen({super.key});

  @override
  State<FocusRefetchScreen> createState() => _FocusRefetchScreenState();
}

class _FocusRefetchScreenState extends State<FocusRefetchScreen> {
  static const List<(String, RefetchOn)> _onFocusChoices =
      <(String, RefetchOn)>[
    ('never', RefetchOn.never),
    ('ifStale', RefetchOn.ifStale),
    ('always', RefetchOn.always),
    ('when', _whenOlderThanTenSeconds),
  ];

  static const List<(String, RefetchOn)> _onMountChoices =
      <(String, RefetchOn)>[
    ('never', RefetchOn.never),
    ('ifStale', RefetchOn.ifStale),
    ('always', RefetchOn.always),
  ];

  static const List<(String, StaleTime)> _staleTimes = <(String, StaleTime)>[
    ('0', StaleTime.zero),
    ('30 s', _thirtySeconds),
  ];

  // The library's own defaults for both events, so the screen starts by
  // showing what a query does when nobody says otherwise.
  RefetchOn _onFocusA = RefetchOn.ifStale;
  RefetchOn _onFocusB = RefetchOn.ifStale;
  RefetchOn _onMountB = RefetchOn.ifStale;

  // Thirty seconds rather than zero, so the first frame already shows fresh
  // data: with a zero stale time every policy but `never` looks the same.
  StaleTime _staleTime = _thirtySeconds;

  bool _attachedB = true;

  late final ShowcaseApi _api;
  late final QueryClient _client;
  bool _initialised = false;

  QueryController<ServerTime, ServerTime>? _readerA;
  void Function()? _unsubscribeFocus;
  bool _rebuildScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialised) {
      _initialised = true;
      _api = ShowcaseScope.apiOf(context);
      _client = QueryClientProvider.of(context);
      _readerA = QueryController.of<ServerTime>(_client, _optionsA);
      // The switch shows what the focus manager holds, not what this screen
      // last set: a test that calls `setFocused` straight on the client, or a
      // real lifecycle transition, moves it too.
      _unsubscribeFocus = _client.focusManager.subscribe((_) => _rebuild());
    }
  }

  @override
  void dispose() {
    _unsubscribeFocus?.call();
    _readerA?.dispose();
    super.dispose();
  }

  /// A focus event arrives from wherever the platform raised it, which can be
  /// inside a frame's build phase; a `setState` there has to wait for the
  /// frame to end.
  void _rebuild() {
    if (!mounted || _rebuildScheduled) {
      return;
    }
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      _rebuildScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _rebuildScheduled = false;
        if (mounted) {
          setState(() {});
        }
      });
    } else {
      setState(() {});
    }
  }

  QueryObserverOptions<ServerTime, ServerTime> get _optionsA => focusTimeQuery(
        _api,
        queryKey: focusKeyA,
        onFocus: _onFocusA,
        // Entry A is never detached, so its mount policy never comes up; the
        // default is left in place rather than made a knob nobody turns.
        onMount: RefetchOn.ifStale,
        staleTime: _staleTime,
      );

  QueryObserverOptions<ServerTime, ServerTime> get _optionsB => focusTimeQuery(
        _api,
        queryKey: focusKeyB,
        onFocus: _onFocusB,
        onMount: _onMountB,
        staleTime: _staleTime,
      );

  /// A changed knob reaches entry A's live reader through `setOptions`; entry
  /// B's builder re-applies its options on the rebuild this schedules.
  void _applyOptions() {
    setState(() {
      _readerA?.setOptions(_optionsA);
    });
  }

  /// The focus source of this screen. In an app the `AppLifecycleListener`
  /// inside `QueryClientProvider` calls this; here the switch does.
  void _setFocused(bool focused) {
    _client.focusManager.setFocused(focused);
  }

  static String _clock(DateTime at) {
    final local = at.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  /// One knob: its name, and a segmented button in a named semantics group, so
  /// a test can pick one button's `never` apart from another's.
  Widget _knob<T extends Object>(
    BuildContext context, {
    required String name,
    required String semanticsKey,
    required List<(String, T)> choices,
    required T selected,
    required ValueChanged<T> onChanged,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(name, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          // Scrolls sideways rather than overflowing on a narrow phone.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              label: semanticsKey,
              child: SegmentedButton<T>(
                key: ValueKey<String>(semanticsKey),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: <ButtonSegment<T>>[
                  for (final (label, value) in choices)
                    ButtonSegment<T>(value: value, label: Text(label)),
                ],
                selected: <T>{selected},
                onSelectionChanged: (selection) => onChanged(selection.single),
              ),
            ),
          ),
        ],
      );

  Widget _reading(
    BuildContext context, {
    required String group,
    required QueryResult<ServerTime> result,
    required List<String> extraFacts,
  }) =>
      _Reading(
        group: group,
        facts: <String>[
          ...extraFacts,
          if (result.dataOrNull case final ServerTime data)
            'serial=${data.serial}',
          'isStale=${result.isStale}',
        ],
        child: switch (result) {
          QueryPending() => const SkeletonBox(width: 200),
          QueryError(:final error, staleData: null) =>
            Notice('$error', error: true),
          QuerySuccess(:final data) ||
          QueryError(staleData: final data!) =>
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Server clock ${_clock(data.now)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (result.isFetching) const Pill('refreshing'),
              ],
            ),
        },
      );

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final readerA = _readerA;
    return FeatureScaffold(
      feature: focusRefetchFeature,
      children: <Widget>[
        SectionCard(
          title: 'App focus',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'In a real app QueryClientProvider installs an '
                'AppLifecycleListener and maps every state onto the focus '
                'manager: resumed and inactive are focused, hidden, paused '
                'and detached are not. A headless browser reports no such '
                'transition, so this switch calls '
                'client.focusManager.setFocused(false) and (true) itself, and '
                'is the focus source the tests drive.',
                style: small,
              ),
              SwitchListTile(
                key: const ValueKey<String>('app-focused'),
                contentPadding: EdgeInsets.zero,
                title: const Text('App focused'),
                value: _client.focusManager.isFocused(),
                onChanged: _setFocused,
              ),
              _Facts(
                group: 'focus-state',
                facts: <String>['focused=${_client.focusManager.isFocused()}'],
              ),
              const Divider(height: 24),
              _knob<StaleTime>(
                context,
                name: 'Stale time',
                semanticsKey: 'stale-time',
                choices: _staleTimes,
                selected: _staleTime,
                onChanged: (value) {
                  _staleTime = value;
                  _applyOptions();
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Shared by both entries: it decides what "stale" means for '
                'ifStale, on focus and on mount alike.',
                style: small,
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Entry A · QueryController',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (readerA != null)
                ListenableBuilder(
                  listenable: readerA,
                  builder: (context, _) => _reading(
                    context,
                    group: 'reader-a',
                    result: readerA.value,
                    extraFacts: const <String>[],
                  ),
                ),
              const Divider(height: 24),
              _knob<RefetchOn>(
                context,
                name: 'On focus',
                semanticsKey: 'on-focus-a',
                choices: _onFocusChoices,
                selected: _onFocusA,
                onChanged: (value) {
                  _onFocusA = value;
                  _applyOptions();
                },
              ),
              const SizedBox(height: 4),
              Text(
                'when: refetch on focus only while the data is older than '
                '10 s — a rule of its own, whatever the stale time says.',
                style: small,
              ),
            ],
          ),
        ),
        QueryDebugStrip(queryKey: focusKeyA, label: 'focus-a'),
        SectionCard(
          title: 'Entry B · QueryBuilder',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: 'Detach entry B',
                onPressed: _attachedB
                    ? () => setState(() => _attachedB = false)
                    : null,
                icon: const Icon(Icons.visibility_off),
              ),
              IconButton(
                tooltip: 'Attach entry B',
                onPressed:
                    _attachedB ? null : () => setState(() => _attachedB = true),
                icon: const Icon(Icons.visibility),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (!_attachedB)
                const _Reading(
                  group: 'reader-b',
                  facts: <String>['reader=detached'],
                  child: Text(
                    'No reader: the entry keeps its data, and attaching one '
                    'again is a mount.',
                  ),
                )
              else
                QueryBuilder<ServerTime>(
                  options: _optionsB,
                  builder: (context, result) => _reading(
                    context,
                    group: 'reader-b',
                    result: result,
                    extraFacts: const <String>['reader=attached'],
                  ),
                ),
              const Divider(height: 24),
              _knob<RefetchOn>(
                context,
                name: 'On focus',
                semanticsKey: 'on-focus-b',
                choices: _onFocusChoices,
                selected: _onFocusB,
                onChanged: (value) {
                  _onFocusB = value;
                  _applyOptions();
                },
              ),
              const SizedBox(height: 8),
              _knob<RefetchOn>(
                context,
                name: 'On mount',
                semanticsKey: 'on-mount-b',
                choices: _onMountChoices,
                selected: _onMountB,
                onChanged: (value) {
                  _onMountB = value;
                  _applyOptions();
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Detach and attach again to see it: a new observer is a '
                'mount, and the entry keeps its data while nobody reads it.',
                style: small,
              ),
            ],
          ),
        ),
        QueryDebugStrip(queryKey: focusKeyB, label: 'focus-b'),
      ],
    );
  }
}

/// What one entry shows, with its own facts underneath.
class _Reading extends StatelessWidget {
  const _Reading({
    required this.group,
    required this.facts,
    required this.child,
  });

  final String group;
  final List<String> facts;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          child,
          const SizedBox(height: 8),
          _Facts(group: group, facts: facts),
        ],
      );
}

/// A row of `key=value` texts in a semantics group of its own: both entries
/// show an `isStale=`, and so does every strip.
class _Facts extends StatelessWidget {
  const _Facts({required this.group, required this.facts});

  final String group;
  final List<String> facts;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        explicitChildNodes: true,
        label: group,
        child: Wrap(
          key: ValueKey<String>('$group-facts'),
          spacing: 12,
          children: <Widget>[
            for (final fact in facts)
              Text(
                fact,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
          ],
        ),
      );
}
