/// Upstream's `auto-refetching` example: a list polled on an interval, with
/// the interval turned live between `off`, two fixed values and a `dynamic`
/// one that reads the data it is deciding about. Two writes — `Add tick` and
/// `Clear ticks` — invalidate the list, so a poll is not the only way it
/// changes.
///
/// The list is read with a `QueryBuilder` and the writes go through
/// `context.mutation`.
///
/// `refetchIntervalInBackground` is the second knob: an armed interval fires
/// while the app is in the background only when it is on. The Flutter binding
/// feeds the client's focus from `AppLifecycleListener`, and a headless
/// browser never reports a lifecycle change — so the screen drives
/// `client.focusManager.setFocused` itself, which is exactly what the binding
/// does on a lifecycle event, and the flag becomes provable in a browser.
///
/// Proofs (widget tests in `test/features/auto_refetching_test.dart`,
/// end-to-end in `e2e/tests/auto_refetching.spec.ts`): with `off` the list is
/// fetched once and stays; with `500 ms` the strip's `fetches` grows and going
/// back to `off` freezes it; a tick added while polling is on screen by the
/// next poll at the latest and clearing empties the list; unfocused, the
/// interval fires without fetching until `Poll in the background` is on; and
/// the `dynamic` interval polls while the list is short, stops itself at the
/// third tick and starts again once the list is cleared.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/debug_strip.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/models.dart';
import '../../shared/scope.dart';
import '../../shared/theme.dart';

const Feature autoRefetchingFeature = Feature(
  id: 'auto-refetching',
  title: 'Auto refetching',
  summary: 'Polling on an interval, in the foreground or not.',
  upstream: 'auto-refetching',
);

/// The polled list. Owned by this screen, so it lives here rather than in
/// `ShowcaseKeys`.
final QueryKey ticksKey = QueryKey(const <Object?>['ticks']);

QueryFilters get _ticksFilter => QueryFilters(queryKey: ticksKey);

/// How many ticks the `dynamic` interval keeps polling for.
const int _pollUntil = 3;

/// The `dynamic` interval's rule, as a top-level function so the value below
/// can be a `const`: `RefetchInterval.dynamic` compares by the identity of its
/// function, and an inline closure would be a different value on every build.
Duration? _whileTheListIsShort(Query<Object?> query) {
  final data = query.state.data;
  final count = data is List<Tick> ? data.length : 0;
  return count < _pollUntil ? const Duration(milliseconds: 500) : null;
}

const RefetchInterval _dynamicInterval =
    RefetchInterval.dynamic(_whileTheListIsShort);

/// The screen's one query, with the two knobs it turns.
QueryObserverOptions<List<Tick>> ticksQuery(
  ShowcaseApi api, {
  required RefetchInterval refetchInterval,
  required bool refetchIntervalInBackground,
}) =>
    QueryObserverOptions<List<Tick>>(
      queryKey: ticksKey,
      queryFn: (context) => api.ticks(signal: context.signal),
      refetchInterval: refetchInterval,
      refetchIntervalInBackground: refetchIntervalInBackground,
    );

/// Both writes invalidate the list. `onSuccess` returns the invalidation's
/// future, upstream's idiom: the mutation stays pending until the refetch has
/// landed, so the button comes back enabled only once the list on screen is
/// the list the backend holds.
MutationOptions<Tick, void, void> addTickMutation(
  QueryClient client,
  ShowcaseApi api,
) =>
    MutationOptions.simple<Tick, void>(
      mutationFn: (_) => api.addTick(),
      onSuccess: (_, __, ___) =>
          client.invalidateQueries(filters: _ticksFilter),
    );

MutationOptions<int, void, void> clearTicksMutation(
  QueryClient client,
  ShowcaseApi api,
) =>
    MutationOptions.simple<int, void>(
      mutationFn: (_) => api.clearTicks(),
      onSuccess: (_, __, ___) =>
          client.invalidateQueries(filters: _ticksFilter),
    );

class AutoRefetchingScreen extends StatefulWidget {
  const AutoRefetchingScreen({super.key});

  @override
  State<AutoRefetchingScreen> createState() => _AutoRefetchingScreenState();
}

class _AutoRefetchingScreenState extends State<AutoRefetchingScreen> {
  static const List<(String, RefetchInterval)> _intervals =
      <(String, RefetchInterval)>[
    ('off', RefetchInterval.off),
    ('500 ms', RefetchInterval.every(Duration(milliseconds: 500))),
    ('2 s', RefetchInterval.every(Duration(seconds: 2))),
    ('dynamic', _dynamicInterval),
  ];

  RefetchInterval _interval = RefetchInterval.off;
  bool _inBackground = false;

  /// Mirrors the client's focus, which this screen is the only one to move.
  bool _focused = true;

  String get _intervalLabel =>
      _intervals.firstWhere((entry) => entry.$2 == _interval).$1;

  void _setFocused(bool focused) {
    QueryClientProvider.read(context).focusManager.setFocused(focused);
    setState(() => _focused = focused);
  }

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    final client = QueryClientProvider.of(context);
    final small = Theme.of(context).textTheme.bodySmall;

    final add = context.mutation(addTickMutation(client, api), id: 'add');
    final clear =
        context.mutation(clearTicksMutation(client, api), id: 'clear');
    final writing = add.value.isPending || clear.value.isPending;

    return FeatureScaffold(
      feature: autoRefetchingFeature,
      children: <Widget>[
        SectionCard(
          title: 'Polling',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Interval', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              // Scrolls sideways rather than overflowing on a narrow phone.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  label: 'interval',
                  child: SegmentedButton<RefetchInterval>(
                    key: const ValueKey<String>('interval'),
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: <ButtonSegment<RefetchInterval>>[
                      for (final (label, value) in _intervals)
                        ButtonSegment<RefetchInterval>(
                          value: value,
                          label: Text(label),
                        ),
                    ],
                    selected: <RefetchInterval>{_interval},
                    onSelectionChanged: (selection) =>
                        setState(() => _interval = selection.single),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'dynamic polls every 500 ms while the list has fewer than '
                '$_pollUntil ticks and returns null after that, so the poll '
                'stops itself — and starts again when the list is cleared.',
                style: small,
              ),
              const Divider(height: 24),
              SwitchListTile(
                key: const ValueKey<String>('in-background'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Poll in the background'),
                value: _inBackground,
                onChanged: (value) => setState(() => _inBackground = value),
              ),
              Text(
                'An armed interval fires either way; without this it only '
                'fetches while the app is focused. The binding feeds focus '
                'from the app lifecycle, and a headless browser reports none '
                '— so these two buttons move it by hand, exactly as the '
                'binding does. Focusing again also refetches the stale list, '
                'which is refetchOnWindowFocus, not the interval.',
                style: small,
              ),
              const SizedBox(height: 8),
              Semantics(
                container: true,
                explicitChildNodes: true,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    OutlinedButton(
                      onPressed: _focused ? () => _setFocused(false) : null,
                      child: const Text('Unfocus'),
                    ),
                    OutlinedButton(
                      onPressed: _focused ? null : () => _setFocused(true),
                      child: const Text('Focus'),
                    ),
                    _Fact('interval=$_intervalLabel'),
                    _Fact('background=$_inBackground'),
                    _Fact('focused=$_focused'),
                  ],
                ),
              ),
            ],
          ),
        ),
        QueryBuilder<List<Tick>>(
          options: ticksQuery(
            api,
            refetchInterval: _interval,
            refetchIntervalInBackground: _inBackground,
          ),
          builder: (context, ticks) => _TicksCard(
            ticks: ticks,
            writing: writing,
            onAdd: writing ? null : () => add.mutate(null),
            onClear: writing ? null : () => clear.mutate(null),
          ),
        ),
        QueryDebugStrip(queryKey: ticksKey, label: 'ticks'),
      ],
    );
  }
}

/// The list, its count and the two writes.
class _TicksCard extends StatelessWidget {
  const _TicksCard({
    required this.ticks,
    required this.writing,
    required this.onAdd,
    required this.onClear,
  });

  final QueryResult<List<Tick>> ticks;
  final bool writing;
  final VoidCallback? onAdd;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final rows = ticks.dataOrNull;
    return SectionCard(
      title: 'Ticks',
      trailing: ticks.isFetching ? const Pill('polling') : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            container: true,
            explicitChildNodes: true,
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                FilledButton(
                  onPressed: onAdd,
                  child: const Text('Add tick'),
                ),
                OutlinedButton(
                  onPressed: onClear,
                  child: const Text('Clear ticks'),
                ),
                _Fact('ticks=${rows?.length ?? 0}'),
                if (writing) const _Fact('writing=true'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          switch (ticks) {
            QueryPending() => const SkeletonBox(width: 200),
            QueryError(:final error, staleData: null) =>
              Notice('$error', error: true),
            QuerySuccess(:final data) ||
            QueryError(staleData: final data!) =>
              // Bounded and eager: the strip below must stay reachable in the
              // lazy `ListView` the scaffold lays its children out in, and a
              // row a poll appended has to be findable without scrolling
              // logic in the tests.
              SizedBox(
                height: 180,
                child: data.isEmpty
                    ? const Align(
                        alignment: Alignment.topLeft,
                        child: Text('No ticks yet.'),
                      )
                    : SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            for (final tick in data)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Text('tick ${tick.id}'),
                              ),
                          ],
                        ),
                      ),
              ),
          },
        ],
      ),
    );
  }
}

/// One `key=value` fact, in the monospace the debug strip uses.
class _Fact extends StatelessWidget {
  const _Fact(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      );
}
