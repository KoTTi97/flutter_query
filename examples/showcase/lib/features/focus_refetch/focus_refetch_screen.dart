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
/// `client.focusManager.setFocused(...)` — `resumed` is focused, `hidden`,
/// `paused` and `detached` are not, and `inactive` depends on the platform:
/// an interruption that counts as focused on iOS, Android and Fuchsia, the
/// window losing focus — unfocused — on macOS, Windows and Linux (the
/// provider's class doc has the reasoning; `isAppShown` overrides it). A
/// headless browser raises no lifecycle transition of its own, so the
/// screen's own `App focused` switch calls `setFocused` directly and *is*
/// the focus source most of the tests drive — a `blur` dispatched on the
/// window is one, though, and entry C's `isAppShown` proof uses it.
///
/// Entry C is the port's own `AppFocusManager(refetchMinBackgroundDuration:)`:
/// a return to the foreground after an absence *shorter* than the threshold
/// raises the focus event but suppresses the new refetches it would have
/// started; paused work still resumes, and reconnect refetching is never
/// touched. The threshold belongs to the focus manager, and a manager belongs
/// to a client at construction — the app's client is built in `main` before
/// any screen exists, so it cannot be given one afterwards. Entry C therefore
/// runs on a client of its own under a nested `QueryClientProvider.create`:
/// the provider builds the client, owns it, and clears it when it unmounts,
/// and a different `key` is a different client — which is how the threshold
/// knob and the `initialOnlineStatus` knob swap it. Because the client is its
/// own, so is the cache: entry C counts its own fetches off
/// `queryCache.subscribe` rather than through the app's `QueryDebugStrip`,
/// which reads the app client's counters.
///
/// The same nested provider carries the two other things a provider decides.
/// `isAppShown` is the mapping from lifecycle states to focus: `platform` is
/// the built-in one, `shown` and `hidden` say what `inactive` means outright,
/// and the mapping given on the latest build is the one in force, without a
/// new client. `initialOnlineStatus` is what the client assumes before any
/// connectivity source has spoken: `offline` mounts entry C paused, and its
/// own `Entry C online` switch is the source that lets the fetch continue.
/// And `QueryClientProvider.maybeOf` — `of` for a widget that can do without
/// a provider — answers with the nearest one: the app's client on the screen,
/// entry C's under the nested provider, as the `nearest=` facts show.
///
/// `shouldRefetchOnFocus` reports what the *most recent* focus notification
/// permitted, so it is read right after a return: it is `true` again as soon
/// as the app leaves the foreground.
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
/// `never`, and under `ifStale` only once the data is stale; one focus
/// event reaches both entries, each answering with its own knob; and, on
/// entry C, a full absence-and-return under the `long` threshold leaves
/// `shouldRefetchOnFocus=false` with its fetch count unmoved, the same
/// sequence under `none` refetches, and an `inactive`-only blip — which maps
/// to focused on the test binding's default platform, Android, so it is no
/// absence at all — changes nothing under either; under `isAppShown`
/// `hidden` the same blip *is* an absence and refetches, under `shown` it is
/// not, whatever the platform; `initialOnlineStatus` `offline` mounts entry C
/// with its fetch paused and no request sent until its switch puts it online;
/// and `maybeOf` names the app's client on the screen and entry C's below.
/// The threshold is measured with `package:clock`, which under a widget test
/// is real time, not pumped time: the tests use an hour, so every absence
/// they stage is short, and `Duration.zero` for the other side.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

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

/// Entry C's key. It lives in a client of its own, so it could reuse either
/// of the two above; a key of its own keeps the cache inspector honest.
QueryKey get focusKeyC => QueryKey(const <Object?>['focus', 'c']);

/// Entry C's `refetchMinBackgroundDuration` choices.
///
/// An hour rather than a handful of seconds: the threshold is measured with
/// `package:clock`, which is wall-clock time even under a widget test's fake
/// async, so "short" has to mean "shorter than any absence a test or a
/// visitor can stage". [Duration.zero] is the library's default and upstream's
/// behaviour — every return refetches.
const Duration longBackground = Duration(hours: 1);

/// What `inactive` means: the `isAppShown` knob's choices. [platform] is the
/// provider's built-in mapping, which reads `inactive` per platform; the
/// other two say it outright.
enum InactiveRule { platform, shown, hidden }

/// `inactive` counts as the app being looked at — a phone's notification
/// shade or an incoming call. A top-level function, like the retry and focus
/// predicates: the provider re-applies the mapping whenever the function
/// differs from the last build's, and a closure would differ every build.
bool inactiveIsShown(AppLifecycleState state) =>
    state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;

/// Only `resumed` is the app being looked at: `inactive` is an absence, as
/// the window losing focus is on a desktop.
bool onlyResumedIsShown(AppLifecycleState state) =>
    state == AppLifecycleState.resumed;

/// The mapping a rule stands for; `null` is the provider's own.
bool Function(AppLifecycleState state)? isAppShownFor(InactiveRule rule) =>
    switch (rule) {
      InactiveRule.platform => null,
      InactiveRule.shown => inactiveIsShown,
      InactiveRule.hidden => onlyResumedIsShown,
    };

/// Entry C's query, in its own client. `always`, so nothing but the threshold
/// can decide whether a return to the foreground refetches.
///
/// It reads `GET /api/counter`, not `/api/time` like the other two, on
/// purpose: entries A and B are counted through the request log, and a third
/// entry that mounts with the screen would move every one of those totals.
/// The reading itself is not the point here — `fetches` and
/// `shouldRefetchOnFocus` are.
QueryObserverOptions<int> thresholdCounterQuery(ShowcaseApi api) =>
    QueryObserverOptions<int>(
      queryKey: focusKeyC,
      queryFn: (context) => api.counter(signal: context.signal),
      staleTime: StaleTime.zero,
      refetchOnWindowFocus: RefetchOn.always,
    );

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
QueryObserverOptions<ServerTime> focusTimeQuery(
  ShowcaseApi api, {
  required QueryKey queryKey,
  required RefetchOn onFocus,
  required RefetchOn onMount,
  required StaleTime staleTime,
}) =>
    QueryObserverOptions<ServerTime>(
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

  static const List<(String, Duration)> _minBackgrounds = <(String, Duration)>[
    ('none', Duration.zero),
    ('long', longBackground),
  ];

  static const List<(String, InactiveRule)> _inactiveRules =
      <(String, InactiveRule)>[
    ('platform', InactiveRule.platform),
    ('shown', InactiveRule.shown),
    ('hidden', InactiveRule.hidden),
  ];

  static const List<(String, bool)> _initialOnlineChoices = <(String, bool)>[
    ('online', true),
    ('offline', false),
  ];

  bool _attachedB = true;

  /// Entry C's threshold. A manager takes its threshold at construction, so
  /// a new threshold is a new manager, a new manager is a new client — and
  /// the nested provider's key carries it, so the provider builds one.
  Duration _minBackground = Duration.zero;

  /// Entry C's `isAppShown`. Not in the provider's key: a mapping given on a
  /// later build is applied to the client as it stands.
  InactiveRule _inactiveRule = InactiveRule.platform;

  /// Entry C's `initialOnlineStatus`. In the key: it is what a client assumes
  /// at its mount, so showing it again means a new client.
  bool _initialOnline = true;

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
      _readerA = QueryController.create<ServerTime>(_client, _optionsA);
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
    // Entry C's client is the nested provider's to clear: it goes with the
    // tree, after the observers under it — which is what `create` is for.
    super.dispose();
  }

  /// A client whose focus manager carries [minBackground] — what the nested
  /// provider's `create` builds, once per key.
  ///
  /// Focused up front: the nested provider's mount reads the app's current
  /// lifecycle state and sets the focus from it, and a manager that starts
  /// with no opinion would count that as a change and raise a focus event
  /// nobody asked for.
  QueryClient _newThresholdClient(Duration minBackground) => QueryClient(
        focusManager: AppFocusManager(
          refetchMinBackgroundDuration: minBackground,
        )..setFocused(true),
      );

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

  QueryObserverOptions<ServerTime> get _optionsA => focusTimeQuery(
        _api,
        queryKey: focusKeyA,
        onFocus: _onFocusA,
        // Entry A is never detached, so its mount policy never comes up; the
        // default is left in place rather than made a knob nobody turns.
        onMount: RefetchOn.ifStale,
        staleTime: _staleTime,
      );

  QueryObserverOptions<ServerTime> get _optionsB => focusTimeQuery(
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
                'manager: resumed is focused, hidden, paused and detached '
                'are not, and inactive is focused on a phone (an '
                'interruption) but not on a desktop (the window lost '
                'focus). A headless browser reports no such '
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
                facts: <String>[
                  'focused=${_client.focusManager.isFocused()}',
                  // `maybeOf` on the screen's own context: the app's provider
                  // is the nearest one here.
                  'nearest=${_nearest(context, appClient: _client)}',
                ],
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
        SectionCard(
          title: 'Entry C · a nested provider of its own',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'A focus manager takes refetchMinBackgroundDuration at '
                'construction, and the app\'s client is built before any '
                'screen exists — so this entry runs on a client of its own, '
                'under a nested QueryClientProvider.create: the provider '
                'builds the client, owns it and clears it when it goes, and '
                'a different key is a different client. Its query is always, '
                'so nothing but the threshold decides. none is the library '
                'default: every return refetches. long is an hour, so every '
                'absence you can stage here is short, the return raises the '
                'focus event with shouldRefetchOnFocus=false, and no new '
                'refetch starts. Paused work would resume either way, and '
                'reconnect refetching is never touched.',
                style: small,
              ),
              const SizedBox(height: 12),
              _knob<Duration>(
                context,
                name: 'Min background',
                semanticsKey: 'min-background',
                choices: _minBackgrounds,
                selected: _minBackground,
                onChanged: (value) => setState(() => _minBackground = value),
              ),
              const SizedBox(height: 12),
              _knob<InactiveRule>(
                context,
                name: 'Inactive is',
                semanticsKey: 'inactive-is',
                choices: _inactiveRules,
                selected: _inactiveRule,
                onChanged: (value) => setState(() => _inactiveRule = value),
              ),
              const SizedBox(height: 4),
              Text(
                'isAppShown: which lifecycle states count as the app being '
                'looked at. platform is the built-in mapping — inactive is '
                'shown on a phone, hidden on a desktop. shown and hidden say '
                'it outright: under hidden a notification shade, or a '
                'browser window losing focus, is an absence like any other. '
                'The mapping on the latest build is the one in force; the '
                'client stays.',
                style: small,
              ),
              const SizedBox(height: 12),
              _knob<bool>(
                context,
                name: 'Initial online status',
                semanticsKey: 'initial-online',
                choices: _initialOnlineChoices,
                selected: _initialOnline,
                onChanged: (value) => setState(() => _initialOnline = value),
              ),
              const SizedBox(height: 4),
              Text(
                'initialOnlineStatus: what the client assumes before any '
                'connectivity source has spoken — online, unless told '
                'otherwise. offline mounts a new entry C with its first fetch '
                'paused and nothing sent; the Entry C online switch below is '
                'its connectivity source, and turning it on lets the fetch '
                'continue.',
                style: small,
              ),
              const SizedBox(height: 12),
              QueryClientProvider.create(
                // The threshold and the initial online status are read at
                // the client's construction and mount: a change of either is
                // a new key, so a new client. The `isAppShown` mapping is
                // not: it reaches the client as it stands.
                key: ValueKey<String>(
                  'entry-c ${_minBackground.inSeconds} '
                  '${_initialOnline ? 'online' : 'offline'}',
                ),
                create: () => _newThresholdClient(_minBackground),
                initialOnlineStatus: _initialOnline,
                isAppShown: isAppShownFor(_inactiveRule),
                child: _ThresholdEntry(api: _api, appClient: _client),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Which provider is nearest to [context], named: the app's client, the
/// nested one, or none at all — `QueryClientProvider.maybeOf`, the lookup for
/// a widget that can do without a provider, where `of` would throw.
String _nearest(BuildContext context, {required QueryClient appClient}) {
  final nearest = QueryClientProvider.maybeOf(context);
  if (nearest == null) {
    return 'none';
  }
  return identical(nearest, appClient) ? 'app' : 'entry C';
}

/// Entry C: one query on a client of its own, so the focus manager under it
/// can carry a `refetchMinBackgroundDuration`.
///
/// It counts its own fetches — the app's `CacheStats`, which every
/// `QueryDebugStrip` reads, listens to the app's client and would show zero
/// for this one — and rebuilds on its client's focus and online events, so
/// `shouldRefetchOnFocus` is what the last notification actually permitted
/// and `online=` is what the client believes right now.
class _ThresholdEntry extends StatefulWidget {
  const _ThresholdEntry({required this.api, required this.appClient});

  final ShowcaseApi api;

  /// The app's client, so the `nearest=` fact can tell it from this entry's.
  final QueryClient appClient;

  @override
  State<_ThresholdEntry> createState() => _ThresholdEntryState();
}

class _ThresholdEntryState extends State<_ThresholdEntry> {
  QueryClient? _client;
  void Function()? _unsubscribeFocus;
  void Function()? _unsubscribeOnline;
  void Function()? _unsubscribeCache;
  int _fetches = 0;
  bool _rebuildScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = QueryClientProvider.of(context);
    if (client == _client) {
      return;
    }
    _unsubscribe();
    _client = client;
    // A new client is a new cache: the count starts again with it, which is
    // what makes the knob's two sides comparable.
    _fetches = 0;
    _unsubscribeFocus = client.focusManager.subscribe((_) => _rebuild());
    _unsubscribeOnline = client.onlineManager.subscribe((_) => _rebuild());
    _unsubscribeCache = client.queryCache.subscribe(_onCacheEvent);
  }

  void _unsubscribe() {
    _unsubscribeFocus?.call();
    _unsubscribeFocus = null;
    _unsubscribeOnline?.call();
    _unsubscribeOnline = null;
    _unsubscribeCache?.call();
    _unsubscribeCache = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  /// Only the state-changing events. Every build re-applies the options and
  /// an inline `queryFn` is never equal, so rebuilding on
  /// `QueryObserverOptionsUpdated` would feed itself.
  void _onCacheEvent(QueryCacheEvent event) {
    if (event is! QueryUpdated) {
      return;
    }
    if (event.action is QueryFetchAction) {
      _fetches++;
    }
    _rebuild();
  }

  /// A focus or cache event arrives from wherever it was raised, which can be
  /// inside a frame's build phase; a `setState` there has to wait.
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

  @override
  Widget build(BuildContext context) {
    final client = _client!;
    final focus = client.focusManager;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SwitchListTile(
          key: const ValueKey<String>('app-focused-c'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Entry C focused'),
          value: focus.isFocused(),
          onChanged: focus.setFocused,
        ),
        // This client's own connectivity source, like the offline screen's
        // switch is the app client's; the app's online state is untouched.
        SwitchListTile(
          key: const ValueKey<String>('entry-c-online'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Entry C online'),
          value: client.onlineManager.isOnline(),
          onChanged: client.onlineManager.setOnline,
        ),
        QueryBuilder<int>(
          options: thresholdCounterQuery(widget.api),
          builder: (context, result) => _Reading(
            group: 'reader-c',
            facts: <String>[
              'focused=${focus.isFocused()}',
              'shouldRefetchOnFocus=${focus.shouldRefetchOnFocus}',
              'fetches=$_fetches',
              'online=${client.onlineManager.isOnline()}',
              'fetchStatus=${result.fetchStatus.name}',
              'nearest=${_nearest(context, appClient: widget.appClient)}',
            ],
            child: switch (result) {
              QueryPending() => const SkeletonBox(width: 200),
              QueryError(:final error, staleData: null) =>
                Notice('$error', error: true),
              QuerySuccess(:final data) ||
              QueryError(staleData: final data!) =>
                Text('Server counter $data'),
            },
          ),
        ),
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
