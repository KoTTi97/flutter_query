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
// Every key is seeded before it is read, so no read ever fetches and no
// notification rebuilds a reader behind a nested builder's back: the frames
// below are exactly the ones their names say.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'harness.dart';

QueryObserverOptions<String> _opts(String key) => QueryObserverOptions(
      queryKey: QueryKey(<Object?>[key]),
      staleTime: StaleTime.infinite,
      queryFn: (_) async => '$key-fetched',
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
  const _Shape(this.name, this.build, this.partial, {this.list = false});
  final String name;
  final Widget Function(_Inputs inputs) build;

  /// What makes part of the shape re-run without its reader's own build.
  final _Partial partial;

  /// A scrolled list, whose partial frame is a scroll.
  final bool list;
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
  _Shape('StatelessWidget build', _StatelessReader.new, _Partial.tick),
  _Shape('State.build (context.query)', _StateReader.new, _Partial.tick),
  _Shape('QueryMixin', (i) => _StateReader(i, mixin: true), _Partial.tick),
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
  for (final shape in _shapes) {
    group(shape.name, () {
      for (final frame in _Frame.values) {
        queryWidgetTest(frame.name, (tester, client) async {
          final tick = ValueNotifier<int>(0);
          final width = ValueNotifier<double>(800);
          addTearDown(tick.dispose);
          addTearDown(width.dispose);
          // Seeded: no read fetches, so no notification rebuilds anything.
          for (final v in ['a', 'b']) {
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
                ValueListenableBuilder<double>(
                  valueListenable: width,
                  builder: (_, w, __) => Center(
                    child: SizedBox(
                      width: w,
                      height: 400,
                      child: mounted
                          ? shape.build(_Inputs(variant, tick, width))
                          : const SizedBox(),
                    ),
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
            await tester.pump();
            await tester.pump();
            everRead.addAll(shown().keys);
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
              await expectLive('after a partial frame');
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
            case _Frame.keySwitch:
              await tester.pumpWidget(tree('b'));
              await settle();
              expect(held().where((k) => k.startsWith('a:')), isEmpty,
                  reason: 'held ${held()}');
              expect(held(), shown().keys.toSet());
              await expectLive('after a key switch');
            case _Frame.unmount:
              if (shape.partial == _Partial.tick) tick.value++;
              if (shape.partial == _Partial.resize) width.value = 300;
              await settle();
              // The provider stays: the reader's own release is what is
              // asked, not the scope's.
              await tester.pumpWidget(tree('a', mounted: false));
              await settle();
              expect(held(), isEmpty);
          }
        });
      }
    });
  }
}
