# flutter_query

A Dart/Flutter port of [TanStack Query](https://github.com/TanStack/query)'s
`query-core`, with a Flutter binding on top.

> **The package name is a codename.** `query_kit` and `query_kit_flutter` are
> placeholders: a name on pub.dev is permanent, so the real one is chosen right
> before the first `dart pub publish`. Changing it is one command —
> [`docs/releasing.md`](docs/releasing.md).

The bet is fidelity: rather than reimplementing the *idea* of TanStack Query,
this ports the behavioral core and then ports upstream's test suite against it,
so the subtle things — request dedup across observers, revert-on-cancel, stale
timing, garbage collection, optimistic rollback — behave the way people who know
the library expect. Several existing Dart packages cover the idea; none has done
the fidelity work.

## Where this comes from, and what it is not

**This is a port of [TanStack Query](https://tanstack.com/query)** — not a
library that was inspired by it in passing. The behaviour is upstream's, the
architecture is upstream's, and upstream's own test suite is ported case for
case and run against this code. That is the entire point of the project.

**Thank you to Tanner Linsley and to everyone who has built, maintained and
supported TanStack Query.** This repository exists for one reason: we used
TanStack Query, we loved it, and we wanted the same thing in Flutter. Every
good idea in here is theirs. It is published under their MIT licence, whose
notice each package keeps in `LICENSE-TANSTACK`.

**It is not theirs, though.** This project is *not affiliated with, endorsed
by, reviewed by, or connected in any way to* Tanner Linsley, the TanStack team,
or the TanStack organisation. They have not seen it and are not responsible for
it. **Please do not take problems with this package to them** — bugs, questions
and complaints belong in
[this repository's issues](https://github.com/KoTTi97/flutter_query/issues).

**And: this is an AI-written project.** Effectively all of the code, the tests
and the documentation here were written by AI agents, working from a plan the
agents also wrote. A human set the destination and ruled on a small number of
questions — the binding's API shape, and that neither published package may
require a third-party dependency — and then deliberately stayed out of the
loop; the standing rule in [CLAUDE.md](CLAUDE.md) is that every decision ticket
is settled by the agent, with the options and the reasoning recorded so the
call can be reopened from the record alone. What stands in for human review is
adversarial: upstream's test suite, nine external deep-dive reviews, and a
rule that no reported finding is acted on until it has been reproduced.

Judge it on that basis. The evidence is all in the repository.

## What is here

| | |
|---|---|
| [`packages/query_kit/`](packages/query_kit) | The pure-Dart core: queries, mutations, infinite queries, observers, client and caches. No Flutter dependency. Every applicable upstream suite ported case-for-case; the audit is [PORTING_NOTES.md](packages/query_kit/test/PORTING_NOTES.md). |
| [`packages/query_kit_flutter/`](packages/query_kit_flutter) | The Flutter binding: `QueryClientProvider`, listenable controllers, builder widgets, a `State` mixin and `context.query(...)`. Four equal call styles, no dependency beyond Flutter. |
| [`examples/showcase/`](examples/showcase) | Every feature of the library as its own screen — 26 of them, on a dummy backend built for it, each with widget tests and Playwright end-to-end tests in a real browser. The catalogue is its README. |
| [`examples/sensor_demo/`](examples/sensor_demo) | The legacy example: a sensor manager against a deliberately slow gateway with scripted failures, and an acceptance test per row of its feature checklist. |
| [`website/`](website) | The documentation site — Docusaurus, built in CI, deployed nowhere yet. `npm ci && npm start`. |
| [`examples/doc_snippets/`](examples/doc_snippets) | Every Dart sample on that site, as code the analyzer sees, so a sample that stops compiling fails the build. |
| [`tool/`](tool) | `rename_packages.dart`, which is what makes the codename safe. |

Upstream is pinned at `50680b98c`; the `query/` checkout it needs is a nested,
gitignored clone (see [CLAUDE.md](CLAUDE.md) for the clone command).

## Documentation

The site under [`website/`](website) is the long form: getting started, a guide
per topic, the JavaScript-to-Dart name map, the feature matrix and how the
fidelity claim is checked. It is not deployed anywhere yet — run it locally:

```bash
cd website && npm ci && npm start
```

The two package READMEs are the short form, and are what pub.dev will show.

## Quick start

```bash
cd packages/query_kit && dart test
```

```bash
cd packages/query_kit_flutter && flutter test
```

```bash
cd examples/showcase && flutter test
```

The showcase's README says how to run it against its backend and how to run
its end-to-end suite; the legacy demo's README does the same for the gateway.

## Requirements and platforms

The core is pure Dart (SDK `^3.6.0`). The binding and the examples need
**Flutter 3.27 or later**; CI runs the tests on that floor and on current
stable. The examples have been run on the web and (the legacy demo) on the iOS
simulator; other platforms are untested. The legacy demo's UI is German, like
the React demo it mirrors; the showcase is English. The backends the examples
talk to are Node (23.6 or later, for TypeScript type stripping).

## Coming from TanStack Query (JS)

[`docs/coming-from-react-query.md`](docs/coming-from-react-query.md) maps the
JavaScript names to the Dart ones — `useQuery` to the four equal call styles,
`fetchQuery` to `QueryClient.query`, `staleTime: Infinity` to
`StaleTime.infinite`, and the rest.

## Deliberately not in 0.1

Each row is recorded, with its reason, in
[PORTING_NOTES.md](packages/query_kit/test/PORTING_NOTES.md).

| Upstream | Here |
|---|---|
| Persistence and hydration (`hydrate`, `dehydrate`, `persister`, `isRestoring`) | not in 0.1; `Query.setState` is the door a persister would use |
| `notifyOnChangeProps`, `trackResult` | `select`, plus `buildWhen` on the builders |
| `throwOnError` | errors live in the sealed result (`QueryError`) |
| `queryKeyHashFn` | `QueryKey` is a value type |
| `structuralSharing` via `replaceEqualDeep` | deep value equality for lists, maps and sets, `==` for everything else (typed models need `==`/`hashCode`), plus an optional `structuralSharing` hook |
| `useQueries` / `QueriesObserver` | not ported |
| `streamedQuery` | not ported |
| `experimental_prefetchInRender`, Suspense, `fetchOptimistic` | React-only, not ported |
| `select` on `fetchQuery` | map the future |
| `initialDataUpdatedAt` as a function | `DateTime?` only |
| SSR: `isServer`, `environmentManager`, `timeoutManager` | not ported |
| `MutationFunctionContext` | not ported; a mutation function takes its variables only |
| Callbacks in `setMutationDefaults` | not ported |
| Devtools | none |

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

## Contributing

[CONTRIBUTING.md](CONTRIBUTING.md) leads with the rule that is actually unusual
here — a failing ported test means the port is wrong until shown otherwise —
and then the gate. Security reports go through
[SECURITY.md](SECURITY.md), never a public issue.

## Licence

MIT — see the `LICENSE` in each package. The ported tests are derived from
upstream TanStack Query's MIT-licensed suite; its licence is `LICENSE-TANSTACK`
in each package.
