---
title: Installation
sidebar_position: 1
description: Which package to add, what it depends on, and which SDK versions are the floor.
---

# Installation

Two packages. Add the one that matches what you are building.

:::warning Not published yet
Nothing is on pub.dev at the time of writing. The `pubspec.yaml` snippets below
are what installation *will* look like; the [git
dependency](#before-the-first-publish) below is what works today.
:::

## In a Flutter app

```bash
flutter pub add query_kit_flutter
```

That pulls in `query_kit` as well; you get the whole surface from one import.

```dart
import 'package:query_kit_flutter/query_kit_flutter.dart';
```

**No dependency beyond Flutter itself** — not `flutter_hooks`, not a signals
package, not `connectivity_plus`. You should not have to adopt somebody's state
management to use a cache. [Connectivity](../guides/lifecycle-and-connectivity.md#connectivity)
is opt-in and stays your dependency.

## In pure Dart

A CLI, a server, a shared package with no Flutter in it:

```bash
dart pub add query_kit
```

```dart
import 'package:query_kit/query_kit.dart';
```

See [using the core without Flutter](../guides/pure-dart.md) — the one thing
you have to do yourself there is `client.mount()`.

## Requirements

|  | Floor | Notes |
|---|---|---|
| `query_kit` | Dart SDK `^3.6.0` | No Flutter. Runs on the VM and compiled to JavaScript; both are in CI. |
| `query_kit_flutter` | Flutter **3.27** | CI runs the whole suite on 3.27.4 as well as current stable, because a floor nobody tests is a guess. |

Platforms: the core supports all six pub.dev platforms. The binding is exercised
on the web and on the iOS simulator by the examples' end-to-end suites; the
others are untested rather than unsupported.

## Before the first publish

Until the packages are on pub.dev, depend on the repository:

```yaml
dependencies:
  query_kit_flutter:
    git:
      url: https://github.com/KoTTi97/flutter_query.git
      path: packages/query_kit_flutter
      ref: main
```

Pin `ref` to a commit rather than `main` if you want a build that does not
move under you.

## Next

[Your first query](first-query.md) — a provider, an options function, and a
widget that reads it.
