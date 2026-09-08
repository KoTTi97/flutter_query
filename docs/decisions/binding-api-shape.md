# The Flutter binding's API shape — builders, hooks, or a controller

**For Christian to decide ([#21](https://github.com/KoTTi97/flutter_query/issues/21)).**
Everything else on the map is decided AFK; this one you asked to be part of, and
nothing in `packages/tanstack_query_flutter/` gets written until it is settled.

The core is finished and proven: 380 tests, every applicable upstream suite
ported. It has no opinion about widgets. This decision is only about what a
screen types.

---

## The screen we are pricing

The sensor **detail** screen from the React demo, because it is the busiest one:

- one query for the sensor (`staleTime: 45s`, a conditional 500 ms poll while a
  Matter write is unconfirmed, seeded from the list cache),
- a **rename** mutation with an optimistic patch and a rollback,
- a **Matter-forwarding** toggle mutation with its own optimistic patch,
- and, on the header, a *second* query on the list key that uses `select` to
  count connected sensors — the same cache entry, a different shape, no extra
  request.

That is `useQuery` × 2 and `useMutation` × 2 on one route. If a shape survives
this screen it survives the app.

---

## Variant A — builder widgets

No new dependency. `QueryBuilder` is to a query what `StreamBuilder` is to a
stream, and Flutter developers already know the shape.

```dart
class SensorDetail extends StatelessWidget {
  const SensorDetail({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    return QueryBuilder<Sensor>(
      options: sensorQuery(id),
      builder: (context, result) => switch (result) {
        QueryPending() => const SensorDetailSkeleton(),
        QueryError(:final error, :final staleData) when staleData == null =>
          ErrorBanner(error),
        QuerySuccess(:final data) || QueryError(staleData: final data!) =>
          MutationBuilder<Sensor, RenameInput>(
            options: renameSensor(),
            builder: (context, rename) => MutationBuilder<Sensor, MatterInput>(
              options: setMatterForwarding(),
              builder: (context, matter) => SensorDetailView(
                sensor: data,
                onRename: (name) => rename.mutate((id: id, name: name)),
                renameError: rename.errorOrNull,
                onMatterChanged: (value) => matter.mutate((id: id, value: value)),
                matterPending: matter.isPending,
              ),
            ),
          ),
      },
    );
  }
}
```

**What it costs.** Three builders nested three deep, and every piece of data has
to be threaded down by hand. The pattern-match on the result is genuinely nice —
that is the sealed `QueryResult` paying off — but the pyramid is real, and this
screen is not the worst case in a real app.

**What it buys.** No dependency, no rules to learn, works in a
`StatelessWidget`, and rebuild scope is exactly the subtree under each builder:
a rename result landing does not rebuild the sensor card.

---

## Variant B — hooks (`flutter_hooks`)

```dart
class SensorDetail extends HookWidget {
  const SensorDetail({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context) {
    final sensor = useQuery(sensorQuery(id));
    final rename = useMutation(renameSensor());
    final matter = useMutation(setMatterForwarding());

    return switch (sensor) {
      QueryPending() => const SensorDetailSkeleton(),
      QueryError(:final error, staleData: null) => ErrorBanner(error),
      QuerySuccess(:final data) || QueryError(staleData: final data!) =>
        SensorDetailView(
          sensor: data,
          onRename: (name) => rename.mutate((id: id, name: name)),
          renameError: rename.errorOrNull,
          onMatterChanged: (value) => matter.mutate((id: id, value: value)),
          matterPending: matter.isPending,
        ),
    };
  }
}
```

Flat. It is the React file with different punctuation — and the demo port
becomes a transcription rather than a re-architecture. Custom hooks compose the
same way `queries.ts` composes today:

```dart
QueryResult<Sensor> useSensor(String id) => useQuery(sensorQuery(id));
```

**What it costs.** A dependency on `flutter_hooks` — for *every consumer*, not
just for us, because the widget must extend `HookWidget`. Its numbers, checked
today: 0.21.3+1, published 2025-08-19, 2 429 likes, ~330 k downloads a month,
150/160 pub points, 71 versions since 2019 — healthy and widely used, but still
pre-1.0 and effectively one maintainer. And the rules of hooks (same order every
build, never inside a conditional) are enforced by nothing: React has an eslint
plugin, Dart has no equivalent lint, so a misplaced `useQuery` inside an `if`
fails at runtime with a confusing error.

---

## Variant C — a controller you own

```dart
class _SensorDetailState extends State<SensorDetail> {
  late QueryController<Sensor> _sensor;
  late final _rename = MutationController(client, renameSensor());
  late final _matter = MutationController(client, setMatterForwarding());

  @override
  void initState() {
    super.initState();
    _sensor = QueryController(client, sensorQuery(widget.id));
  }

  @override
  void didUpdateWidget(SensorDetail old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) _sensor.setOptions(sensorQuery(widget.id));
  }

  @override
  void dispose() {
    _sensor.dispose();
    _rename.dispose();
    _matter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge(<Listenable>[_sensor, _rename, _matter]),
        builder: (context, _) => switch (_sensor.result) { /* … as above … */ },
      );
}
```

**What it costs.** The most typing by a wide margin, and the lifecycle is the
caller's problem — a forgotten `dispose` is a leaked observer, a forgotten
`didUpdateWidget` is a screen stuck on the previous sensor.

**What it buys.** Nothing hidden. It is a `ChangeNotifier`, so it drops straight
into `provider`, `riverpod`, `bloc`, `ValueListenableBuilder`, or a test with no
widgets at all. Whatever else we ship, **this object has to exist underneath it**
— A and B are both thin wrappers around it.

---

## What I would ship

**C is not optional** — it is the layer A and B are made of, so the only real
question is which of A and B is the *default* the docs teach.

My recommendation: **A as the default, B as a separate opt-in package.**

- `tanstack_query_flutter` ships `QueryBuilder`, `MutationBuilder`,
  `QueryClientProvider`, and the controllers underneath. Zero dependencies
  beyond Flutter, so nobody is forced into a state-management opinion to use a
  cache.
- `tanstack_query_flutter_hooks` ships `useQuery` / `useMutation` /
  `useInfiniteQuery`, ~200 lines over the controllers, and depends on
  `flutter_hooks`. Teams that already use hooks get the flat call site; teams
  that don't never see it.

That also settles the builder pyramid honestly: a screen with three queries uses
the controller (or hooks), not three nested builders, and the docs say so.

**The one thing I would not do** is make `flutter_hooks` a hard dependency of
the main package. It is a good library, but forcing a pre-1.0 third-party
widget base class on everyone who wants a query cache is a big ask, and it is
the kind of decision that is very hard to walk back after publication.

**If you would rather have hooks as the headline** — you were the one who found
them interesting — the mirror image also works: hooks in the main package,
builders alongside. It costs the dependency and buys call sites that read like
the React app. I will build whichever you pick; I would just rather the default
not force the choice on consumers.

---

## Two smaller things that ride along

1. **Type parameters at the call site.** The core's observer options are
   `QueryObserverOptions<TQueryData, TData>` — the second only matters when you
   use `select`. Writing `QueryObserverOptions<Sensor, Sensor>` everywhere is
   noise, so the binding should offer a one-parameter constructor for the common
   case and keep the two-parameter one for `select`. No decision needed from you
   unless you dislike that.
2. **Where the client lives.** An `InheritedWidget` (`QueryClientProvider`) is
   the obvious answer and does not depend on which variant wins. Also AFK unless
   you want a say.

---

## What happens next

Say the word — "builders", "hooks", or "both, builders default" — and the
binding gets built on it, with
[#22](https://github.com/KoTTi97/flutter_query/issues/22) (lifecycle: when the
observer subscribes, what a key change does, how `AppLifecycleState` maps to
focus) decided AFK right after, since most of it is shape-independent.
