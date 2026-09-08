# flutter_query

A Dart/Flutter port of [TanStack Query](https://github.com/TanStack/query)'s
`query-core`, with a Flutter binding on top.

The bet is fidelity: rather than reimplementing the *idea* of TanStack Query,
this ports the behavioral core and then ports upstream's test suite against it,
so the subtle things — request dedup across observers, revert-on-cancel, stale
timing, garbage collection, optimistic rollback — behave the way people who know
the library expect. Several existing Dart packages cover the idea; none has done
the fidelity work.

> An independent community port. Not affiliated with, endorsed by, or a product
> of TanStack.

## What is here

| | |
|---|---|
| [`packages/tanstack_query_core/`](packages/tanstack_query_core) | The pure-Dart core: queries, mutations, infinite queries, observers, client and caches. No Flutter dependency. Every applicable upstream suite ported case-for-case; the audit is [PORTING_NOTES.md](packages/tanstack_query_core/test/PORTING_NOTES.md). |
| [`packages/tanstack_query_flutter/`](packages/tanstack_query_flutter) | The Flutter binding: `QueryClientProvider`, listenable controllers, builder widgets, a `State` mixin and `context.query(...)`. Four equal call styles, no dependency beyond Flutter. |
| [`examples/sensor_demo/`](examples/sensor_demo) | The React demo's sensor manager rebuilt on the binding, against the same gateway and the same cache policy, with an acceptance test per row of the MVP checklist. |
| [`react-demo/`](react-demo) | The React sensor demo and its express gateway, vendored: they define the bar the Flutter demo has to meet. |

Upstream is pinned at `50680b98c`; the `query/` checkout it needs is a nested,
gitignored clone (see [CLAUDE.md](CLAUDE.md) for the clone command).

## Quick start

```bash
cd packages/tanstack_query_core && dart test
```

```bash
cd packages/tanstack_query_flutter && flutter test
```

```bash
cd examples/sensor_demo && flutter test
```

The demo's README says how to run it against the gateway.

## How it was planned

As a wayfinder map on [GitHub issue #1](https://github.com/KoTTi97/flutter_query/issues/1):
the destination, the standing rules, and one decision ticket per fork in the
road, each closed with the options, the answer and why. The research behind
those tickets is under [`docs/research/`](docs/research/), and the one decision
the maintainer kept for himself — the binding's API shape — is written up in
[`docs/decisions/binding-api-shape.md`](docs/decisions/binding-api-shape.md).

The rule that shaped everything: **closeness to upstream is a tiebreaker, not a
goal.** Where a Dart or Flutter idiom is better, the port diverges and writes
down why; the table of divergences is at the end of PORTING_NOTES.md.

## Licence

MIT — see the `LICENSE` in each package. Upstream TanStack Query is MIT as
well; the ported tests carry its notice.
