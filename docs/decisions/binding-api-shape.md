# The Flutter binding's API shape

**Decided by Christian on 2026-09-08 ([#21](https://github.com/KoTTi97/flutter_query/issues/21),
[#23](https://github.com/KoTTi97/flutter_query/issues/23)).** The ruling: no
third-party package required by the main package — not `flutter_hooks`, not
signals, not `connectivity_plus`; hooks and signals may come later as opt-in
packages. And no default in the documentation: the four call styles are
presented as equal alternatives. What follows is the comparison he decided on,
kept as the record of the reasoning.

*Revised 2026-09-08 after two findings: the builder pyramid turned out not to be
an argument for hooks, and signals reframed the question. The first version of
this document is in git history.*

The core is finished and proven: 380 tests, every applicable upstream suite
ported. It has no opinion about widgets. This decision is only about what a
screen types.

---

## The one thing that actually matters

Every variant below is a thin layer over the same object:

```
QueryObserver<TQueryData, TData>          ← in the core, no Flutter import
   ├─ a current value:  QueryResult<TData>
   └─ subscribe(listener) → unsubscribe
```

That is precisely the shape Flutter calls a **`ValueListenable`** and every
signal library calls an **external store**. So the binding's load-bearing
decision is one line:

> `QueryObserver` is exposed as `ValueListenable<QueryResult<TData>>`.

`ValueListenable` lives in `package:flutter/foundation.dart`, so that adapter
belongs to the binding package and the core stays Flutter-free
([#19](https://github.com/KoTTi97/flutter_query/issues/19)). Everything after
that is sugar, and **all of it is additive** — nothing below excludes anything
else below.

---

## The screen being priced

The sensor **detail** screen from the React demo, because it is the busiest one:
one query (45 s stale time, a conditional 500 ms poll while a Matter write is
unconfirmed, seeded from the list cache), a **rename** mutation with an
optimistic patch and rollback, and a **Matter-forwarding** toggle with its own.
Plus, on the header, a second query on the list key that uses `select` to count
connected sensors — same cache entry, different shape, no extra request.

Two queries and two mutations on one route. If a shape survives this screen it
survives the app.

---

## A — Builder widgets

```dart
QueryBuilder<Sensor>(
  options: sensorQuery(id),
  builder: (context, result) => switch (result) {
    QueryPending() => const SensorDetailSkeleton(),
    QueryError(:final error, staleData: null) => ErrorBanner(error),
    QuerySuccess(:final data) || QueryError(staleData: final data!) =>
      MutationBuilder<Sensor, RenameInput>(
        options: renameSensor(),
        builder: (context, rename) => MutationBuilder<Sensor, MatterInput>(
          options: setMatterForwarding(),
          builder: (context, matter) => SensorDetailView(
            sensor: data,
            onRename: (name) => rename.mutate((id: id, name: name)),
            renameError: rename.errorOrNull,
            onMatterChanged: (v) => matter.mutate((id: id, value: v)),
            matterPending: matter.isPending,
          ),
        ),
      ),
  },
)
```

**Costs:** three builders nested three deep; data threaded down by hand. This
screen is not the worst case a real app has.
**Buys:** no dependency, nothing to learn, works in a `StatelessWidget`, and
rebuild scope is exactly each builder's subtree — a rename result landing does
not rebuild the sensor card.

---

## B — a `State` mixin

```dart
class _SensorDetailState extends State<SensorDetail> with QueryMixin {
  @override
  Widget build(BuildContext context) {
    final sensor = watchQuery(sensorQuery(widget.id));
    final rename = watchMutation(renameSensor());
    final matter = watchMutation(setMatterForwarding());

    return switch (sensor) { /* … flat, no builders … */ };
  }
}
```

The mixin keeps a `Map<QueryKey, QueryObserver>`, creates an observer on first
use, subscribes it against `setState`, and destroys everything in `dispose()`.
About 60 lines.

**The important part:** entries are identified by **`QueryKey`, not by call
order**, so there are no rules of hooks. `if (x) watchQuery(...)` is legal.

**Costs:** `StatefulWidget` required; an observer for a key that stops being
read stays until the widget unmounts (`gcTime` cleans up after).
**Buys:** flat call sites with zero dependencies.

---

## C — `context.query(...)`

```dart
class SensorDetail extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sensor = context.query(sensorQuery(id));
    final rename = context.mutation(renameSensor());
    final matter = context.mutation(setMatterForwarding());

    return switch (sensor) { /* … flat, and in a StatelessWidget … */ };
  }
}
```

This is the mechanism `provider` uses for `context.watch<T>()`, built directly
on Flutter instead of on provider. Verified in the SDK
(`packages/flutter/lib/src/widgets/framework.dart`):

- `InheritedElement.removeDependent(Element)` is `@protected` and overridable,
  and Flutter calls it for every dependent at unmount (`_ensureDeactivated`) —
  so the scope knows exactly when to unsubscribe an observer. Ref-counting is
  precise, not guesswork.
- `setDependencies` / `getDependencies` store a per-dependent aspect set;
  `InheritedModel<QueryKey>` already does exactly this.

**Buys, uniquely: per-key rebuild granularity.** When query A changes, only the
widgets that read A rebuild. Hooks always rebuild the whole `HookWidget`; a
builder rebuilds its whole subtree.

**Costs:** the most machinery *inside* the package (~150 lines of
`InheritedElement` subclassing). One honest wart: Flutter clears an element's
dependencies in `activate()`, not on every rebuild, so a conditionally-read
query stays subscribed until unmount — same over-retention as B, same `gcTime`
backstop.

---

## D — controllers you own

```dart
late final _sensor = QueryController(client, sensorQuery(widget.id));
late final _rename = MutationController(client, renameSensor());
late final _matter = MutationController(client, setMatterForwarding());

@override
Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_sensor, _rename, _matter]),
      builder: (context, _) => switch (_sensor.result) { /* … */ },
    );
```

Plus `didUpdateWidget` for key changes and `dispose` for all three.

**Costs:** the most typing, and the lifecycle is the caller's problem — a
forgotten `dispose` leaks an observer, a forgotten `didUpdateWidget` pins the
screen to the previous sensor.
**Buys:** nothing hidden; testable with no widgets at all. **This layer exists
regardless** — A, B and C are all built on it.

---

## E — hooks (`flutter_hooks`, optional package)

```dart
class SensorDetail extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final sensor = useQuery(sensorQuery(id));
    final rename = useMutation(renameSensor());
    final matter = useMutation(setMatterForwarding());
    return switch (sensor) { /* … */ };
  }
}
```

Custom hooks compose the way `queries.ts` composes today:
`QueryResult<Sensor> useSensor(String id) => useQuery(sensorQuery(id));`

**What changed since the first draft:** flat call sites are no longer a reason
to reach for hooks — B and C are just as flat with no dependency. What hooks
still buy is the **rest of the ecosystem** (`useState`, `useEffect`, `useMemo`,
`useTextEditingController`) and familiarity for people arriving from React.

**Costs:** the dependency lands on *every consumer*, because the widget must
extend `HookWidget`; and the rules of hooks (same order every build, never
inside a conditional) are enforced by no Dart lint — React has an eslint plugin,
we would have nothing.

---

## F — signals (optional package)

```dart
final sensor    = client.observe(sensorQuery(id)).asValueListenable().toSignal();
final connected = computed(() => sensor.value.dataOrNull?.connected ?? false);
```

**This one is nearly free**, because of the decision at the top: `signals_flutter`
ships `valueListenableToSignal<T>()`, `ValueListenableSignalMixin<T>` and
`SignalValueListenableUtils`. If we expose a `ValueListenable`, signals users are
served without us depending on anything.

**Buys, uniquely:** `computed` with automatic dependency tracking — derived state
**across several queries** that only recomputes when what it actually read
changed. `select` covers one query; upstream's answer for several (`useQueries`)
is still fog on our map. Signals cover it today.

**Precedent:** three of upstream's five adapters are already signal-based —
`angular-query-experimental/src/create-base-query.ts` builds its result from
`signal()` and a `signalProxy`; Solid and Svelte the same. "Query as a signal" is
how TanStack works outside React.

---

## The numbers, checked 2026-09-08

| package | likes | downloads / 30 d | latest | licence |
|---|---|---|---|---|
| `flutter_hooks` | 2 430 | 330 k | 0.21.3+1, 12 months ago | MIT |
| `signals` | 705 | 20.6 k | 7.1.0, 3 months ago | Apache-2.0 |
| `state_beacon` | 48 | 3.77 k | 3.1.2, 13 days ago | MIT |

As a **hard dependency**, `signals` is a weaker bet than hooks — a sixteenth of
the downloads, and with `state_beacon`, `solidart` and Flutter's own
`ValueNotifier` direction the field is not settled. As an **interop target**,
both cost nothing.

---

## Side by side

| | A builders | B mixin | C `context.query` | D controllers | E hooks | F signals |
|---|---|---|---|---|---|---|
| this screen | 3 levels deep | flat | flat | flat, +25 lines lifecycle | flat | flat |
| dependency | none | none | none | none | `flutter_hooks`, on every consumer | `signals`, opt-in only |
| widget base | any | `StatefulWidget` | any | any | `HookWidget` | any |
| rules to learn | none | none | none | dispose + `didUpdateWidget` | rules of hooks, unlinted | signal lifetimes |
| rebuild scope | builder subtree | whole widget | **per query key** | what you wrap | whole widget | **per signal** |
| derived across queries | manual | manual | manual | manual | manual | **`computed`** |
| demo port reads as | re-architecture | close to the React file | close to the React file | re-architecture | transcription | transcription |
| our code to write | ~120 lines | ~60 | ~150 | ~200 (the base) | ~200 | ~40 |

---

## What I would ship

**D is not optional** — it is the layer everything else is made of, and it is
what makes `ValueListenable` exposure possible in the first place.

On top of that, my recommendation:

1. **`query_kit_flutter` ships D + C + A**, no dependencies beyond Flutter.
   `context.query(...)` is the default the docs teach, `QueryBuilder` stays for
   people who want an explicit widget, controllers are documented for anyone
   integrating with bloc/riverpod/provider.
2. **`query_kit_flutter_hooks`** — ~200 lines, opt-in, for teams already on
   hooks.
3. **Signals need no package from us at all**, only a paragraph in the README
   showing `valueListenableToSignal`. If it turns out people want more, a
   `..._signals` package is ~40 lines later.

**The one thing I would still not do** is make `flutter_hooks` a hard dependency
of the main package. Forcing a pre-1.0 third-party widget base class on
everyone who wants a query cache is very hard to walk back after publication —
and it now buys nothing that B and C do not already give for free.

**If you would rather teach hooks or signals as the headline**, both are
buildable and neither is wrong; it costs the dependency (hooks) or a bet on a
smaller ecosystem (signals). I will build whichever you pick.

---

## Two smaller things that ride along (AFK unless you object)

1. **Type parameters at the call site.** The core's observer options are
   `QueryObserverOptions<TQueryData, TData>`, and the second only matters with
   `select`. The binding should offer a one-parameter form for the common case.
2. **Where the client lives.** A `QueryClientProvider` `InheritedWidget`, which
   is the same answer under every variant.

---

## What happens next

Say the word — a variant letter, or "your recommendation" — and the binding gets
built on it, with [#22](https://github.com/KoTTi97/flutter_query/issues/22)
(observer lifetime, key changes, `AppLifecycleState` → focus, the connectivity
adapter) decided AFK right after, since most of it is shape-independent.
