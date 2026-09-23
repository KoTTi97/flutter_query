// The keyless reads' release rule, held against every reader shape at once
// (release review 2026-09-23, third pass, V3-1/V3-2).
//
// Three rounds moved the edge where an element-bound read is released — too
// early (BIND-1, V3-1, V3-2: visible data that stopped updating) or never
// (BIND-2). Each fix was proven on the shape its finding named and broke a
// shape next to it. This file asks the same three questions of every shape
// after every kind of frame:
//
// * everything on screen is subscribed: a `setQueryData` reaches it;
// * nothing is held beyond the bound the docs state — exactly what is shown
//   after the reader's own build (or its parent's rebuild), at most what it
//   has read since then otherwise;
// * unmounting the reader releases everything.
//
// Every table runs twice (fourth pass, V4-1). **Seeded**: every key is
// written before it is read, so no read fetches and no notification rebuilds
// a reader behind a nested builder's back — the frames are exactly the ones
// their names say. **Polling**: no key is seeded and every read polls every
// second, so each new read fetches and its result is a notification that
// rebuilds the reader — the frame a `LayoutBuilder` whose key depends on
// something it reads goes through. That table also asks the cost question:
// after every frame, a key nobody holds is not fetched again.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'harness.dart';

/// Fetches per key, for the polling table.
final _fetches = <String, int>{};

/// Whether reads poll; set per test.
var _polling = false;

QueryObserverOptions<String> _opts(String key) => QueryObserverOptions(
      queryKey: QueryKey(<Object?>[key]),
      staleTime: StaleTime.infinite,
      refetchInterval:
          _polling ? const RefetchInterval.every(Duration(seconds: 1)) : null,
      queryFn: (_) async {
        _fetches[key] = (_fetches[key] ?? 0) + 1;
        return '$key-fetched';
      },
    );

/// `key=value`, the one text format every shape shows its data in.
Text _show(String key, QueryResult<String> result) =>
    Text('$key=${result.dataOrNull}');

/// What a shape is given: the variant a parent picks (a key switch changes
/// it), a tick only a nested part listens to, and the width its box has.
class _Inputs {
  _Inputs(this.variant, this.tick, this.width);
  final String variant;
  final ValueNotifier<int> tick;
  final ValueNotifier<double> width;
  String k(String name) => '$variant:$name';
}

/// How one shape is built, and what its partial frame is.
class _Shape {
  const _Shape(
    this.name,
    this.build,
    this.partial, {
    this.list = false,
    this.exactAfterPartial = false,
  });
  final String name;
  final Widget Function(_Inputs inputs) build;

  /// What makes part of the shape re-run without its reader's own build.
  final _Partial partial;

  /// A scrolled list, whose partial frame is a scroll.
  final bool list;

  /// Whether the partial frame is the reader's own build after all, so it
  /// holds exactly what it shows afterwards: a reader with no nested part,
  /// a list whose rows are readers of their own, and a `LayoutBuilder`
  /// whose builder a resize re-runs (V4-1).
  final bool exactAfterPartial;
}

enum _Partial { tick, resize, scroll }

class _StatelessReader extends StatelessWidget {
  const _StatelessReader(this.inputs);
  final _Inputs inputs;
  @override
  Widget build(BuildContext context) {
    final k = inputs.k('outer');
    return _show(k, context.query(_opts(k)));
  }
}

class _StateReader extends StatefulWidget {
  const _StateReader(this.inputs, {this.mixin = false, this.nested = false});
  final _Inputs inputs;
  final bool mixin;
  final bool nested;
  @override
  State<_StateReader> createState() => _StateReaderState();
}

class _StateReaderState extends State<_StateReader> with QueryMixin {
  QueryResult<String> _read(String key) =>
      widget.mixin ? watchQuery(_opts(key)) : context.query(_opts(key));

  @override
  Widget build(BuildContext context) {
    final inputs = widget.inputs;
    final outer = inputs.k('outer');
    final shown = _show(outer, _read(outer));
    if (!widget.nested) return shown;
    return Column(children: [
      shown,
      ValueListenableBuilder<int>(
        valueListenable: inputs.tick,
        builder: (_, t, __) {
          final inner = inputs.k('inner$t');
          return _show(inner, _read(inner));
        },
      ),
    ]);
  }
}

class _Row extends StatelessWidget {
  const _Row(this.name);
  final String name;
  @override
  Widget build(BuildContext context) => _show(name, context.query(_opts(name)));
}

const _rows = 60;

final _shapes = <_Shape>[
  _Shape(
    'StatelessWidget build',
    _StatelessReader.new,
    _Partial.tick,
    exactAfterPartial: true,
  ),
  _Shape(
    'State.build (context.query)',
    _StateReader.new,
    _Partial.tick,
    exactAfterPartial: true,
  ),
  _Shape(
    'QueryMixin',
    (i) => _StateReader(i, mixin: true),
    _Partial.tick,
    exactAfterPartial: true,
  ),
  _Shape(
    'nested Builder with the outer context',
    (i) => Builder(builder: (context) {
      final outer = i.k('outer');
      return Column(children: [
        _show(outer, context.query(_opts(outer))),
        ListenableBuilder(
          listenable: i.tick,
          builder: (_, __) => Builder(builder: (_) {
            final inner = i.k('inner${i.tick.value}');
            return _show(inner, context.query(_opts(inner)));
          }),
        ),
      ]);
    }),
    _Partial.tick,
  ),
  _Shape('ValueListenableBuilder with the outer context',
      (i) => _StateReader(i, nested: true), _Partial.tick),
  _Shape('ValueListenableBuilder in a QueryMixin build',
      (i) => _StateReader(i, mixin: true, nested: true), _Partial.tick),
  _Shape(
    'LayoutBuilder, its own context',
    (i) => LayoutBuilder(builder: (context, c) {
      final key = i.k(c.maxWidth > 600 ? 'wide' : 'narrow');
      return _show(key, context.query(_opts(key)));
    }),
    _Partial.resize,
    exactAfterPartial: true,
  ),
  _Shape(
    'a nested builder inside a LayoutBuilder, its context',
    (i) => LayoutBuilder(builder: (context, c) {
      final outer = i.k('outer');
      return Column(children: [
        _show(outer, context.query(_opts(outer))),
        ValueListenableBuilder<int>(
          valueListenable: i.tick,
          builder: (_, t, __) {
            final inner = i.k('inner$t');
            return _show(inner, context.query(_opts(inner)));
          },
        ),
      ]);
    }),
    _Partial.tick,
  ),
  _Shape(
    'ListView.builder rows as widgets of their own',
    (i) => ListView.builder(
      itemExtent: 50,
      itemCount: _rows,
      itemBuilder: (_, r) => _Row(i.k('r$r')),
    ),
    _Partial.scroll,
    list: true,
    exactAfterPartial: true,
  ),
  _Shape(
    'itemBuilder reading through an enclosing LayoutBuilder context',
    (i) => LayoutBuilder(
      builder: (context, c) => ListView.builder(
        itemExtent: 50,
        itemCount: _rows,
        itemBuilder: (_, r) {
          final key = i.k('r$r');
          return _show(key, context.query(_opts(key)));
        },
      ),
    ),
    _Partial.scroll,
    list: true,
  ),
];

enum _Frame { partial, full, keySwitch, unmount }

void main() {
  for (final polling in [false, true]) {
    group(polling ? 'polling' : 'seeded', () {
      _table(polling: polling);
    });
  }
}

void _table({required bool polling}) {
  for (final shape in _shapes) {
    group(shape.name, () {
      for (final frame in _Frame.values) {
        queryWidgetTest(frame.name, (tester, client) async {
          _polling = polling;
          _fetches.clear();
          final tick = ValueNotifier<int>(0);
          final width = ValueNotifier<double>(800);
          addTearDown(tick.dispose);
          addTearDown(width.dispose);
          // Seeded: no read fetches, so no notification rebuilds anything.
          for (final v in polling ? const <String>[] : ['a', 'b']) {
            for (final name in [
              'outer',
              'inner0',
              'inner1',
              'wide',
              'narrow',
              for (var r = 0; r < _rows; r++) 'r$r',
            ]) {
              client.setQueryData<String>(
                  QueryKey(<Object?>['$v:$name']), '$v:$name-0');
            }
          }
          Widget tree(String variant, {bool mounted = true}) => app(
                client,
                // The shape is the builder's `child`: a resize re-lays it
                // out without handing it a new widget, so a `LayoutBuilder`'s
                // builder re-runs on its own (fourth pass, V4-1).
                ValueListenableBuilder<double>(
                  valueListenable: width,
                  child: mounted
                      ? shape.build(_Inputs(variant, tick, width))
                      : const SizedBox(),
                  builder: (_, w, child) => Center(
                    child: SizedBox(width: w, height: 400, child: child),
                  ),
                ),
              );

          Set<String> held() => {
                for (final q in client.queryCache.findAll())
                  if (q.observersCount > 0) q.queryKey.parts.single as String,
              };
          Map<String, String> shown() {
            final texts = <String, String>{};
            for (final e in find.byType(Text, skipOffstage: false).evaluate()) {
              final data = (e.widget as Text).data ?? '';
              final eq = data.indexOf('=');
              if (eq > 0 && data.contains(':')) {
                texts[data.substring(0, eq)] = data.substring(eq + 1);
              }
            }
            return texts;
          }

          final everRead = <String>{};
          var updates = 0;
          Future<void> settle() async {
            // Enough for a fetch to resolve and its notification's rebuild
            // to run, and for that rebuild's reads to resolve in turn.
            for (var i = 0; i < 4; i++) {
              await tester.pump();
            }
            everRead.addAll(shown().keys);
          }

          /// Polling only: over three intervals, every key shown is fetched
          /// again and no key outside the held ones is.
          Future<void> expectPollingOnlyHeld(String when) async {
            if (!polling) return;
            final heldNow = held();
            final before = Map.of(_fetches);
            for (var s = 0; s < 3; s++) {
              await tester.pump(const Duration(seconds: 1));
            }
            for (final key in {...before.keys, ..._fetches.keys}) {
              final more = (_fetches[key] ?? 0) - (before[key] ?? 0);
              if (heldNow.contains(key)) {
                expect(more, greaterThan(0), reason: '$when: $key not polled');
              } else {
                expect(more, 0, reason: '$when: $key polled, held $heldNow');
              }
            }
          }

          /// Everything shown is subscribed, and a write reaches it.
          Future<void> expectLive(String when) async {
            final visible = shown().keys.toSet();
            expect(visible, isNotEmpty, reason: when);
            expect(held().containsAll(visible), isTrue,
                reason: '$when: shown $visible, held ${held()}');
            for (final key in visible) {
              final value = 'upd${++updates}';
              client.setQueryData<String>(QueryKey(<Object?>[key]), value);
              await tester.pump();
              await tester.pump();
              expect(shown()[key], value, reason: '$when: $key');
            }
          }

          await tester.pumpWidget(tree('a'));
          await settle();
          expect(held(), shown().keys.toSet(), reason: 'after mount');
          await expectLive('after mount');
          await expectPollingOnlyHeld('after mount');

          switch (frame) {
            case _Frame.partial:
              switch (shape.partial) {
                case _Partial.tick:
                  tick.value++;
                case _Partial.resize:
                  width.value = 300;
                case _Partial.scroll:
                  await tester.drag(
                      find.byType(ListView), const Offset(0, -120));
              }
              await settle();
              // Additive: bounded by what the reader has read, never less
              // than what it shows.
              expect(everRead.containsAll(held()), isTrue,
                  reason: 'held ${held()}, ever read $everRead');
              // Polling, the new read's fetch is a notification, and the
              // rebuild it asks for is the reader's own build — which reads
              // everything shown again and lets go of the rest (V4-1).
              if (shape.exactAfterPartial || polling) {
                expect(held(), shown().keys.toSet(),
                    reason: 'the partial frame is an own build');
              }
              await expectLive('after a partial frame');
              await expectPollingOnlyHeld('after a partial frame');
            case _Frame.full:
              if (shape.partial == _Partial.tick) tick.value++;
              if (shape.partial == _Partial.resize) width.value = 300;
              if (shape.list) {
                await tester.drag(find.byType(ListView), const Offset(0, -120));
              }
              await settle();
              // The parent hands every widget a new instance.
              await tester.pumpWidget(tree('a'));
              await settle();
              expect(held(), shown().keys.toSet(),
                  reason: 'a rebuild by the parent is a generation');
              await expectLive('after a full rebuild');
              await expectPollingOnlyHeld('after a full rebuild');
            case _Frame.keySwitch:
              await tester.pumpWidget(tree('b'));
              await settle();
              expect(held().where((k) => k.startsWith('a:')), isEmpty,
                  reason: 'held ${held()}');
              expect(held(), shown().keys.toSet());
              await expectLive('after a key switch');
              await expectPollingOnlyHeld('after a key switch');
            case _Frame.unmount:
              if (shape.partial == _Partial.tick) tick.value++;
              if (shape.partial == _Partial.resize) width.value = 300;
              await settle();
              // The provider stays: the reader's own release is what is
              // asked, not the scope's.
              await tester.pumpWidget(tree('a', mounted: false));
              await settle();
              expect(held(), isEmpty);
              await expectPollingOnlyHeld('after unmount');
          }
        });
      }
    });
  }
}
