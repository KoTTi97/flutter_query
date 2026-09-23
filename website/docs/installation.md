---
title: Installation
description: Which package to add, what it depends on, the Dart and Flutter floors, and the analyzer settings that make the types work for you.
---

# Installation

query_kit comes as two packages, and you add the one that matches what you
are building:

| Package | For | Depends on |
|---|---|---|
| `query_kit` | Pure Dart: a CLI, a server, a shared data package | `clock`, `meta` |
| `query_kit_flutter` | A Flutter app | Flutter, `meta`, `query_kit` |

## In a Flutter app

```bash
flutter pub add query_kit_flutter
```

Or by hand, in `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  query_kit_flutter: ^1.0.0
```

The binding re-exports the core, so one import gives you the whole surface —
the client, the options, the results and the widgets:

```dart snippet="prose-only: the one import line, which every other sample already shows in context"
import 'package:query_kit_flutter/query_kit_flutter.dart';
```

If a file of yours imports `package:query_kit/query_kit.dart` directly — a
data layer you keep free of Flutter, say — list `query_kit` in your
`pubspec.yaml` as well. Dart's `depend_on_referenced_packages` lint asks for
it, and it is right to: a package you import is a package you depend on.

## In pure Dart

```bash
dart pub add query_kit
```

```dart snippet="prose-only: the one import line, which every other sample already shows in context"
import 'package:query_kit/query_kit.dart';
```

Everything the cache does — staleness, retries, cancellation, mutations,
infinite queries — is in the core. What the binding adds is the Flutter side:
the provider that maps the app lifecycle onto focus, and the four ways to
read a query in a widget. Without it, you call `client.mount()` yourself; see
[using the core without Flutter](guides/pure-dart.md).

A common split in a larger app: a `data` package that depends on `query_kit`
only and holds the keys and the options functions, and the app, which depends
on `query_kit_flutter` and reads them. The data package then runs its tests
with `dart test`, no Flutter needed.

## No third-party dependency

Neither package pulls in anything beyond the Dart team's `clock` and `meta` —
not `flutter_hooks`, not a signals package, not `connectivity_plus`, not an
HTTP client. You bring the HTTP client ([query
functions](guides/query-functions.md) shows dio and `package:http`) and, if
you want reconnect refetches, the connectivity source ([connectivity](guides/connectivity.md)
shows how to plug any package in). You should not have to adopt somebody's
state management to use a cache.

## Requirements

|  | Floor | Notes |
|---|---|---|
| `query_kit` | Dart SDK `^3.6.0` | No Flutter. Runs on the VM and compiled to JavaScript; both are tested. |
| `query_kit_flutter` | Flutter `>=3.27.0` (which ships Dart 3.6) | Tested on 3.27 as well as current stable. |

Platforms: the core runs everywhere Dart does. The binding is exercised on the
web by the examples' end-to-end suites; the other platforms are untested
rather than unsupported — it uses nothing platform-specific beyond
`AppLifecycleState`.

## Recommended analyzer settings

Most of the type safety is there without configuration. Three analyzer
settings make the rest of it visible, and the packages themselves are built
with them:

```yaml
# analysis_options.yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true

linter:
  rules:
    - unawaited_futures
```

- **`strict-inference`** reports the one options literal inference cannot
  type: a key-only one with neither a `queryFn` nor a type argument, which
  Dart would otherwise make `dynamic`. See [type safety in
  Dart](dart-type-safety.md).
- **`strict-raw-types`** reports a `QueryResult` or `QueryObserverOptions`
  written without its type argument.
- **`unawaited_futures`** reports a `client.invalidateQueries(...)` or
  `client.query(...)` whose future nobody awaits. Await it, or mark a
  deliberate fire-and-forget with `unawaited(...)` from `dart:async`.

## Next

The [quick start](quick-start.md) — a provider, a first query, and a write
that refreshes it.

:::note[In React Query]
The split mirrors `@tanstack/query-core` and `@tanstack/react-query`, except
that the Flutter package re-exports the core, so an app needs one import. See
[differences from TanStack Query](reference/differences-from-tanstack.md).
:::
