# Shipping a widget-test helper without a regular `flutter_test` dependency

- **Date:** 2026-09-11
- **Ticket:** https://github.com/KoTTi97/flutter_query/issues/48 (part of #33)
- **Scope:** facts only. How published Dart/Flutter packages ship a
  widget-test helper, what pub.dev's `pana` does about a regular
  `flutter_test` dependency, what the SDK's `test_api` pin does to resolution,
  and what a third package would cost this repository. The decision is
  [#36](https://github.com/KoTTi97/flutter_query/issues/36)'s.

`packages/query_kit_flutter` lists `flutter_test` under `dependencies` so that
`lib/testing.dart` can export `queryWidgetTest`. Published packages split three
ways on this: a few (golden_toolkit, alchemist, patrol_finders, flame_test,
flutter_riverpod) take `flutter_test` as a regular dependency and pay for it
with the Web and WASM platform tags on pub.dev and with following
`flutter_test`'s breaking changes; the packages with the widest reach (bloc,
riverpod, mockito, mocktail) either ship a companion `_test` package or keep
the helper in the core on `test_api` alone, never on `flutter_test` or `test`;
most (provider, go_router, dio, flutter_hooks, get_it, mobx) export nothing and
document a snippet. `pana` deducts no points for the dependency itself — SDK
packages are dropped before the "up-to-date dependencies" check — but its
platform tagger follows the import to `dart:io` inside `flutter_test` and
marks the package "not compatible with platform Web" (and not WASM).
Resolution on another Flutter release is never the problem: `sdk: flutter`
binds to the consumer's own copy, and the exact `test_api` pin each release
carries clashes with other packages identically whether `flutter_test` is a
regular or a dev dependency. For this repo a third package is a permanent name
(`query_kit_flutter_test` and `query_kit_test` are both free), a workspace
row, a third publish stage and tag pattern, and a third dry-run and `dart doc`
leg in CI — for a helper whose only caller in the repository is its own test.

pub.dev lookups were made on 2026-09-11 against
`https://pub.dev/api/packages/<name>` (HTTP 200 = taken, 404 = free); package
versions, scores and platform tags are as pub.dev reported them that day.

## 1. The three patterns among published packages

### 1.1 Pattern (a): `flutter_test` as a regular dependency of the main package

| Package (version) | Why it needs it | Pub points | Web tag | Source |
|---|---|---|---|---|
| golden_toolkit 0.15.0 (discontinued) | golden-file helpers on `WidgetTester` | 150/160 | **no**: 5 of 6 platforms | https://raw.githubusercontent.com/eBay/flutter_glove_box/master/packages/golden_toolkit/pubspec.yaml, https://pub.dev/packages/golden_toolkit/score |
| alchemist 0.14.0 | golden tests | 150/160 | **no** | https://raw.githubusercontent.com/Betterment/alchemist/main/pubspec.yaml |
| patrol_finders 3.6.0 | "Streamlined, high-level API on top of flutter_test." | 150/160 | declares `platforms:` incl. web, scores 10/20 platform points because it fails WASM | https://raw.githubusercontent.com/leancodepl/patrol/master/packages/patrol_finders/pubspec.yaml |
| patrol 4.9.0 | `flutter_test` + `test_api ^0.7.0` regular | | | https://pub.dev/packages/patrol |
| flame_test 2.3.1 | `flutter_test` + `test` regular | 160/160 | **no** | https://pub.dev/packages/flame_test |
| flutter_riverpod 3.4.3 | one exported helper: `@visibleForTesting extension RiverpodWidgetTesterX on flutter_test.WidgetTester { ProviderContainer container(...) }` | 140/160 | **no**: 5 of 6 | https://github.com/rrousselGit/riverpod/blob/master/packages/flutter_riverpod/lib/src/core/provider_scope.dart |
| flutter_gherkin 2.0.0 | unmaintained | | | https://pub.dev/packages/flutter_gherkin |
| flutter_test_ui 2.0.0 | Dart 2 only | 60/160, `has:error` | | https://pub.dev/packages/flutter_test_ui |

Three packages the ticket named as candidates for (a) turned out **not** to be:
network_image_mock 2.1.1 has `flutter_test` in `dev_dependencies` (its regular
deps are `flutter` and `mockito`); mockito 5.8.1 depends on
`test_api ">=0.6.1 <0.8.0"` and `matcher`, never `flutter_test`, and is
Web-compatible; mocktail 1.0.5 likewise on `test_api` + `matcher`, 160/160,
Web and WASM.

What (a) costs in maintenance, from patrol_finders' changelog
(https://pub.dev/packages/patrol_finders/changelog): 2.0.0 "Bump minimum
supported Flutter version to 3.16 to be compatible with breaking changes in
flutter_test"; 2.1.x "Adjust pumpWidget to new flutter_test API", reverted,
then re-landed with a 3.22 minimum. A package on `flutter_test` inherits every
one of its API changes as a floor bump.

### 1.2 Pattern (b): a separate companion package

| Package (version) | Depends on | Pub points | Web tag | Source |
|---|---|---|---|---|
| bloc_test 10.0.0 | `bloc ^9.1.0`, `diff_match_patch`, `meta`, `mocktail`, `test ^1.16.0` — **no `flutter_test`** | 160/160 | yes, and WASM | https://raw.githubusercontent.com/felangel/bloc/master/packages/bloc_test/pubspec.yaml |
| flame_test 2.3.1 | companion to flame, but `flutter_test` regular | 160/160 | **no** | https://pub.dev/packages/flame_test |
| patrol_finders 3.6.0 | companion to patrol, `flutter_test` regular | 150/160 | partial (§1.1) | https://pub.dev/packages/patrol_finders |
| hive_test 1.0.1 | third-party; `flutter_test` dev only; no API typed on `flutter_test` | | | https://pub.dev/packages/hive_test |
| riverpod_test 0.1.9 | third-party, not riverpod's author, riverpod 2 | | | https://pub.dev/packages/riverpod_test |
| dio_test | `publish_to: none`, git-only | n/a | n/a | https://github.com/cfug/dio/tree/main/dio_test |

A companion package is only free of the (a) costs if it also stays off
`flutter_test` (bloc_test does; flame_test and patrol_finders do not).

**riverpod's author ships no `_test` companion.** The helper is
`ProviderContainer.test()` in the core package, which depends on `test_api`
(not `test`, not `flutter_test`):
https://pub.dev/documentation/riverpod/latest/riverpod/ProviderContainer/ProviderContainer.test.html.
The arc that led there is the clearest evidence in this survey: riverpod 3.4.2
had `test: ^1.0.0` as a regular dependency and broke consumers' solves
(https://github.com/rrousselGit/riverpod/issues/4308, 2025-09-17;
https://github.com/rrousselGit/riverpod/issues/4844, 2026-08-08: "test as a
direct dependency caps the project at analyzer 12"), fixed by
https://github.com/rrousselGit/riverpod/pull/4845 "Depend on test_api instead
of test" in 3.4.3, whose changelog says: "This removes 34 transitive packages
from the dependency graph of every project that uses Riverpod, including
analyzer". mockito walked the same path in 2019 (3.0.1 → 3.0.2 rollback →
4.0.0). Note the distinction: `test` (the runner, which drags in `analyzer`)
is what broke solves; `test_api` (the vocabulary: `expect`, `Matcher`) is
what both settled on.

### 1.3 Pattern (c): a documented snippet, nothing exported

provider 6.1.5+1, go_router 18.0.1, dio 5.11.1, flutter_bloc 9.1.1 (delegates
to bloc_test), flutter_hooks 0.21.3+1, get_it 9.2.1, mobx 2.7.0: `flutter_test`
or `test` appears only in `dev_dependencies`, and the testing story is a
README or docs section. This is the most common pattern by count and covers
the packages with the largest consumer bases in the survey.

### 1.4 Known complaints about `test_api` conflicts

Every verbatim solver failure found has `flutter_test` in the **consumer's**
`dev_dependencies` and some other package pinning `test_api` differently:

- https://github.com/flutter/flutter/issues/85560: "Because test >=1.17.6
  depends on test_api 0.4.1 and every version of flutter_test from sdk depends
  on test_api 0.3.0 … version solving failed."
- https://github.com/flutter/flutter/issues/82537,
  https://github.com/dart-lang/test/issues/1247 — the same clash.
- https://github.com/flutter/flutter/issues/83815 — mockito as the
  regular-dependency offender (pre-4.0.0 style).
- https://github.com/felangel/bloc/issues/3110 — bloc_test → test → analyzer
  chain.
- https://github.com/flutter/flutter/issues/144694 — the integration_test pin.
- https://github.com/rrousselGit/riverpod/issues/4364,
  https://github.com/rrousselGit/riverpod/issues/3092.

**No issue was found in which a package's own regular `flutter_test`
dependency broke a consumer's solve.** Such a package inherits the SDK pin
rather than fighting it (§3); its failure modes are the platform tags (§2) and
following `flutter_test`'s breaking changes (§1.1).

## 2. What `pana` does with a regular `flutter_test` dependency

**No scored section deducts for it.** "Support up-to-date dependencies" (40
points) drops every dependency whose `kind == 'sdk'` before evaluating and
only direct hosted dependencies can be "outdated"
(https://raw.githubusercontent.com/dart-lang/pana/master/lib/src/report/dependencies.dart,
lines 40–42, 130, 141–146); the transitive pins `flutter_test` brings
(`test_api`, `leak_tracker`, `vm_service`) appear only in the collapsed
"Transitive dependencies" table. Live proof: golden_toolkit scores 40/40 with
transitive `test_api` 0.7.12 against latest 0.7.14
(https://pub.dev/packages/golden_toolkit/score); patrol_finders 40/40. "Follow
Dart file conventions" (`template.dart`) and "Pass static analysis" have no
rule about it either.

**The one indirect effect is "Platform support" (20 points).** The tagger
walks regular dependencies only
(https://github.com/dart-lang/pana/blob/master/lib/src/tag/_graphs.dart, line
176 "Only considers non-dev-dependencies.", line 185) and follows imports;
`flutter_test/src/platform.dart` imports `dart:io`, so any library that
imports `flutter_test` is tagged not-Web and not-WASM. Verbatim from
golden_toolkit's analysis: "Package not compatible with platform Web. Because:
package:golden_toolkit/golden_toolkit.dart that imports: …
package:flutter_test/flutter_test.dart … package:flutter_test/src/platform.dart
that imports: dart:io" (20/20 as "5 of 6"; patrol_finders 10/20 because it
declares web but fails WASM — `multi_platform.dart`). The root cause is
https://github.com/flutter/flutter/issues/78180 "[flutter_test] flutter_test
incompatible with Flutter Web". A `platforms:` key in the pubspec overrides the
tagger (https://github.com/dart-lang/pana/issues/808, sigurdm 2023-11-23);
whether that override also survives the WASM check for a `dart:io` reached via
`flutter_test` was not verified.

The official guidance, verbatim. https://dart.dev/tools/pub/dependencies: "If
the dependency is imported from something in your lib or bin directories, it
needs to be a regular dependency. If it's only imported from test, example,
etc. it can and should be a dev dependency." — a `lib/testing.dart` is, by
that rule, a regular dependency. And
https://docs.flutter.dev/cookbook/testing/widget/introduction: "include the
flutter_test dependency in the dev_dependencies section". pub.dev's
Dependencies sidebar lists `flutter_test` (linked to api.flutter.dev) for such
a package: https://pub.dev/packages/golden_toolkit.

## 3. Resolution on a different Flutter release

**Yes, for every Flutter consumer.** `flutter_test: {sdk: flutter}` carries no
version and binds to whatever copy ships with the consumer's SDK
(https://dart.dev/tools/pub/dependencies#sdk; pub's
`lib/src/source/sdk.dart` and `lib/src/sdk/flutter.dart`). There is nothing to
solve against pub.dev.

What `flutter_test` pins, exactly, per release (each from
`packages/flutter_test/pubspec.yaml` at that tag, e.g.
https://raw.githubusercontent.com/flutter/flutter/3.27.0/packages/flutter_test/pubspec.yaml):

| Flutter | `test_api` | `matcher` |
|---|---|---|
| 3.27.0 | 0.7.3 | 0.12.16+1 |
| 3.29.0, 3.32.0 | 0.7.4 | |
| 3.35.0 | 0.7.6 | |
| 3.38.8 (local, `flutter --version`) | 0.7.7 | 0.12.17 |
| master 2026-09-11 | 0.7.14 | 0.12.20 |

The comment in that pubspec: "We depend on very specific internal
implementation details of the 'test' package, which change between versions"
(https://raw.githubusercontent.com/flutter/flutter/master/packages/flutter_test/pubspec.yaml).
The rationale is
https://github.com/dart-lang/sdk/blob/main/docs/Flutter-Pinned-Packages.md:
"By pinning its dependencies it is ensured the future release of a new
package-version will not break apps made with an old Flutter SDK."

**What breaks, and when.** A clash between that exact `test_api`/`matcher` pin
and some other package in the consumer's graph (§1.4). It is identical whether
`flutter_test` sits in the consumer's `dependencies` or `dev_dependencies`,
because pub solves both sets together for the root package. The regular-vs-dev
distinction changes two things:

1. **Downstream packages** that depend on the binding inherit `flutter_test`
   into their own regular graph even if they have no tests, and with it the
   platform tags of §2.
2. **Non-Flutter consumers** cannot resolve it at all: "Because myapp depends
   on foo from sdk which doesn't exist (the Flutter SDK is not available),
   version solving failed. Flutter users should use `flutter pub` instead of
   `dart pub`." (pub's `test/sdk_test.dart`;
   https://github.com/dart-lang/pub/issues/2454). Moot for
   `query_kit_flutter`, which already depends on `flutter: {sdk: flutter}`
   (`packages/query_kit_flutter/pubspec.yaml:23-24`).

Precedent inside Flutter's own SDK: `integration_test`, `flutter_driver` and
`flutter_goldens` all declare `flutter_test` as a **regular** dependency
(https://raw.githubusercontent.com/flutter/flutter/master/packages/integration_test/pubspec.yaml
and siblings). In `flutter/packages` all 99 published pubspecs have
`flutter_test` in `dev_dependencies`, and none ships a `lib/` test helper.

Not verified: no issue was found where the clash was triggered by a package's
regular `flutter_test` dependency; pana's `platforms:` override was not tested
against `dart:io` reached via `flutter_test`.

## 4. What a third package would cost this repository

Everything below is the state of `main` on 2026-09-11.

**What is there today.**

- `packages/query_kit_flutter/pubspec.yaml:25-28` — `flutter_test: {sdk: flutter}`
  under `dependencies`, with the comment "For `lib/testing.dart` only — a test
  file imports it, an app never does, and both are SDK packages, so nothing is
  pulled from pub.dev." The second clause is false: `flutter pub deps
  --style=compact` in `examples/showcase` shows
  `query_kit_flutter 0.1.0 [flutter flutter_test meta query_kit]` and
  `flutter_test 0.0.0 [flutter test_api matcher path fake_async clock
  stack_trace vector_math leak_tracker_flutter_testing collection meta
  stream_channel]`, with `test_api 0.7.7`, `matcher 0.12.17`,
  `leak_tracker 11.0.2`, `leak_tracker_flutter_testing 3.0.10` and
  `leak_tracker_testing 3.0.2` in the transitive list — all hosted on
  pub.dev. The same `[flutter flutter_test meta query_kit]` row appears for
  every consumer in the workspace (`query_kit_flutter_example`,
  `doc_snippets`, `task_manager`, `showcase`).
- `packages/query_kit_flutter/lib/testing.dart:22-27` imports
  `package:flutter/widgets.dart`, `package:flutter_test/flutter_test.dart`,
  `package:meta/meta.dart`, `package:query_kit/query_kit.dart` and re-exports
  `QueryClient` and `DefaultOptions`; it defines `queryWidgetTest` (line 45)
  and `tearDownQueryClient` (line 79), and nothing else. Its own dartdoc
  (lines 18–19) says "This library pulls in `flutter_test`, so import it from
  `test/` only — never from `lib/`."
- `packages/query_kit_flutter/README.md:7` — "**No dependency beyond Flutter
  itself.** Not `flutter_hooks`, not a signals package, not
  `connectivity_plus`." The dependency list above makes that claim false as
  written; `flutter_test` is an SDK package, but what it pulls in is not.
- **Callers.** `queryWidgetTest` is called from exactly one file in the
  repository, the helper's own test
  (`packages/query_kit_flutter/test/testing_helper_test.dart:10,32`).
  `examples/showcase` and `examples/task_manager` do not use it; each has its
  own harness (`showcaseTest` in `examples/showcase/test/harness.dart`, per
  `CLAUDE.md`). The other mentions are documentation:
  `website/docs/guides/testing.md:18-47`,
  `website/docs/reference/feature-matrix.md:29`,
  `website/docs/reference/api.md:46`, `packages/query_kit_flutter/README.md:362-377`,
  `packages/query_kit_flutter/CHANGELOG.md:15-16`, `CLAUDE.md:80`.
- **Web today.** CI builds the showcase for the web on every push
  (`.github/workflows/ci.yml`, per `CLAUDE.md`), so the loss in §2 is pub.dev's
  *tag*, not the ability to compile; the port's fidelity story ("run on the VM
  and compiled to JavaScript", `CLAUDE.md`) is unaffected in fact but
  contradicted on the package page.

**What a companion package adds.**

| Cost | Where | Today |
|---|---|---|
| A permanent pub.dev name | — | `query_kit_flutter_test`, `query_kit_test`, `query_kit_flutter_testing`, `query_kit_testing` all returned 404 (free) on 2026-09-11; so did `query_kit` and `query_kit_flutter` themselves (nothing is published yet) |
| A workspace member | `pubspec.yaml:7-13` (root) | six members; a seventh row |
| A row in the publish order | `docs/releasing.md:19-27` | "Two packages go to pub.dev, in a fixed order" (line 3); core, then binding. A companion depending on `query_kit_flutter: ^x` goes third and waits for the binding to be resolvable, i.e. a second wait stage |
| A tag pattern and a job | `.github/workflows/publish.yml:9-10,13-26` | one `on.push.tags` glob and one job per package; a third of each |
| Wizard stages | `scripts/release.sh` below the `STAGES` marker (line 178) | `TOTAL_STAGES=9` (183); package constants (186–189); the version-equality and `^VERSION` checks (271–280); CHANGELOG check loop (282–285); two `dry_run` calls (312–313); stage 3 opens both names (334–335); stages 4–6 publish core, wait, publish binding (347–379); stage 7 opens two admin pages (386–398); stage 8 tags both (407–408, 465–467); stage 9 verifies both (476–483). A third package means a third constant set, a third dry-run, a third name tab, a second wait + publish pair, a third admin page, a third tag and a third verify row — 9 stages become 11, and every "both" in the prose becomes "all three" |
| CI legs | `.github/workflows/ci.yml:42-47` (publish dry-run), `:53-57` (`dart doc --validate-links`), `:81-84` (floors) | one leg per package in each; a third |
| The rename tool | `tool/rename_packages.dart` | takes `--core` and `--flutter`; a third name to derive and rewrite |
| Its own CHANGELOG, README, LICENSE and version lock-step | `packages/<name>/` | the wizard already refuses to run when the two versions differ (`release.sh:274-276`) |

**What it does not add.** Nothing changes in the consumer's own resolution
(§3): every Flutter app template already has `flutter_test` in
`dev_dependencies`, so `test_api` and `leak_tracker_*` are in its graph either
way (the showcase's `pubspec.yaml:22` has it). The delta is on the *package
page* of `query_kit_flutter` — the Web/WASM tags and the dependency sidebar —
and in the regular graph of any package that depends on the binding without
having widget tests.

**A cheaper variant of (b) exists and has the strongest precedent.** riverpod
(§1.2) keeps its helper in the core on `test_api` alone, which pana tags as
Web-compatible and which does not pin anything the SDK pins. It does not
transfer directly: `queryWidgetTest` wraps `testWidgets` and takes a
`WidgetTester`, both of which live only in `flutter_test`, so a `test_api`-only
version would have to drop the wrapper and keep only what needs no tester —
which, for `tearDownQueryClient`, is `client.clear()` after two pumps that
need the tester. The `flutter_test`-typed surface is exactly the part that
cannot move.

## Recommendation for this port

The facts favour pattern (c) with the helper folded into documentation, or —
if an exported helper is wanted at all — pattern (b) in the cheapest shape
that stays off `flutter_test`, and they weigh against keeping (a). Keeping (a)
buys one exported function with one caller in the repository (its own test)
at the price of a false README line, a false pubspec comment, the Web and
WASM tags on the page of a binding whose showcase is a web app and whose
fidelity story includes running compiled to JavaScript, and a floor bump every
time `flutter_test` changes its API (§1.1); no penalty in points, no
resolution failure, but a visible contradiction between what the package says
and what pub.dev shows. A companion `query_kit_flutter_test` is free to name
and clean on pub.dev only if it, like bloc_test, avoids `flutter_test` — and
this helper cannot, because `testWidgets` and `WidgetTester` are the helper;
a companion that does depend on `flutter_test` moves the not-Web tag to a
package nobody imports from `lib/`, which is the honest place for it, at the
cost in §4 of a permanent name, a third publish stage with its own wait, a
third tag, and a third leg in every CI job — real money for two functions
of forty lines. The snippet costs nothing, keeps "No dependency beyond Flutter
itself" true, and matches the packages with the widest reach (provider,
go_router, dio); its weakness is the one `CLAUDE.md` names — a user's first
widget test fails without the teardown, so the snippet has to be the first
thing on the testing page, not a footnote. Which of the three to take, and
whether the readme claim is worth more than the exported symbol, is #36's
call.

## Sources

- pub.dev API: `https://pub.dev/api/packages/<name>` and `/score` (fetched
  2026-09-11); package pages linked inline above
- https://dart.dev/tools/pub/dependencies (regular vs dev; `#sdk`)
- https://docs.flutter.dev/cookbook/testing/widget/introduction
- https://raw.githubusercontent.com/dart-lang/pana/master/lib/src/report/dependencies.dart
- https://github.com/dart-lang/pana/blob/master/lib/src/tag/_graphs.dart
- https://github.com/dart-lang/pana/issues/808
- https://github.com/flutter/flutter/issues/78180
- https://raw.githubusercontent.com/flutter/flutter/master/packages/flutter_test/pubspec.yaml
  and the same path at tags 3.27.0, 3.29.0, 3.32.0, 3.35.0
- https://github.com/dart-lang/sdk/blob/main/docs/Flutter-Pinned-Packages.md
- https://github.com/dart-lang/pub/issues/2454
- https://raw.githubusercontent.com/flutter/flutter/master/packages/integration_test/pubspec.yaml
- https://raw.githubusercontent.com/felangel/bloc/master/packages/bloc_test/pubspec.yaml
- https://github.com/rrousselGit/riverpod/issues/4308,
  https://github.com/rrousselGit/riverpod/issues/4844,
  https://github.com/rrousselGit/riverpod/pull/4845
- https://pub.dev/documentation/riverpod/latest/riverpod/ProviderContainer/ProviderContainer.test.html
- https://github.com/rrousselGit/riverpod/blob/master/packages/flutter_riverpod/lib/src/core/provider_scope.dart
- https://pub.dev/packages/patrol_finders/changelog
- The solver-failure issues listed in §1.4
- Local: `packages/query_kit_flutter/pubspec.yaml`,
  `packages/query_kit_flutter/lib/testing.dart`,
  `packages/query_kit_flutter/README.md`,
  `packages/query_kit_flutter/test/testing_helper_test.dart`, `pubspec.yaml`,
  `docs/releasing.md`, `scripts/release.sh`, `.github/workflows/publish.yml`,
  `.github/workflows/ci.yml`, `flutter pub deps --style=compact` in
  `examples/showcase` (Flutter 3.38.8, Dart 3.10.7), `flutter --version`, and
  `$FLUTTER_ROOT/packages/flutter_test/pubspec.yaml` on 2026-09-11
