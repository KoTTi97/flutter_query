# query_kit

TanStack Query for Dart and Flutter: cached server state with background
refetching, retries, cancellation, mutations and infinite queries — a port of
TanStack Query's `query-core`, checked against upstream's own test suite,
ported case by case.

> **query_kit is an entirely AI-coded project: all code, tests and
> documentation were written by AI coding agents (Anthropic's Claude). A human
> maintainer set the goals and reviews releases, but did not write the
> code.** What stands in for a human author is adversarial checking:
> upstream's test suite ported case for case, repeated review rounds run by
> independent AI agents, and a rule that no reported finding is acted on
> before it has been reproduced. Judge it on that basis; the evidence is in
> this repository.

## Packages

| Package | What it is |
|---|---|
| [`query_kit`](packages/query_kit) | The pure-Dart core: queries, mutations, infinite queries, observers, the client and its caches. No Flutter dependency. |
| [`query_kit_flutter`](packages/query_kit_flutter) | The Flutter binding: `QueryClientProvider`, controllers, builder widgets, a `State` mixin and `context.query(...)`. Four equal call styles, no dependency beyond Flutter. Re-exports the core. |

## Install

In a Flutter app:

```bash
flutter pub add query_kit_flutter
```

In pure Dart (a server, a command-line tool):

```bash
dart pub add query_kit
```

The core needs Dart 3.6 or later, the binding Flutter 3.27 or later. Each
package README has a quick start.

## Documentation

The documentation site — getting started, a guide per concept, examples, the
JavaScript-to-Dart name map and troubleshooting — is built from
[`website/`](website). It will be published at
<https://kotti97.github.io/query_kit/>; until then, run it locally:

```bash
cd website && npm ci && npm start
```

Coming from React Query? The
[name map](website/docs/coming-from-react-query.md) takes the
JavaScript names to the Dart ones — `useQuery` to the four call styles,
`fetchQuery` to `QueryClient.query`, `staleTime: Infinity` to
`StaleTime.infinite`, and the rest.

Not in 1.0: persistence and hydration, `streamedQuery`, server-side
rendering and devtools.

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
[this repository's issues](https://github.com/KoTTi97/query_kit/issues).

## Repository

For contributors. [CONTRIBUTING.md](CONTRIBUTING.md) leads with the rule that
is unusual here — a failing ported test means the port is wrong until shown
otherwise — and then the gate. Security reports go through
[SECURITY.md](SECURITY.md), never a public issue.

| Path | What it is |
|---|---|
| [`packages/query_kit/`](packages/query_kit) | The core. Its fidelity audit — every ported upstream case, every omission and every divergence, with its reason — is [PORTING_NOTES.md](packages/query_kit/test/PORTING_NOTES.md). |
| [`packages/query_kit_flutter/`](packages/query_kit_flutter) | The binding, and its one-file example. |
| [`examples/showcase/`](examples/showcase) | Every feature as its own screen, on a dummy backend built for it, each with widget tests and Playwright end-to-end tests in a real browser. |
| [`examples/task_manager/`](examples/task_manager) | One whole small app: a to-do manager against a deliberately slow backend with scripted failures. |
| [`examples/doc_snippets/`](examples/doc_snippets) | Every Dart sample on the site and in the package READMEs, as code the analyzer sees, so a sample that stops compiling fails the build. |
| [`website/`](website) | The documentation site (Docusaurus), built in CI. |
| [`docs/`](docs) | Decisions (`adr/`), research, release instructions and history. |
| [`tool/`](tool) | `rename_packages.dart`, the pass that set the package names. |

Working on the port needs the upstream checkout, a nested, gitignored clone
pinned to the revision the ported tests were taken from (see
[CONTRIBUTING.md](CONTRIBUTING.md)).

Running the tests:

```bash
flutter pub get
```

```bash
cd packages/query_kit && dart test
```

```bash
cd packages/query_kit_flutter && flutter test
```

```bash
cd examples/showcase && flutter test
```

```bash
cd examples/task_manager && flutter test
```

```bash
cd examples/doc_snippets && flutter test
```

The examples' READMEs say how to run them against their backends and how to
run their end-to-end suites. The project was planned as wayfinder maps on
GitHub issues, starting with
[issue #1](https://github.com/KoTTi97/query_kit/issues/1); the one rule
that shaped everything is that closeness to upstream is a tiebreaker, not a
goal — where a Dart or Flutter idiom is better, the port diverges and writes
down why.

## Licence

MIT — see the `LICENSE` in each package. The ported tests are derived from
upstream TanStack Query's MIT-licensed suite; its licence is `LICENSE-TANSTACK`
in each package.
