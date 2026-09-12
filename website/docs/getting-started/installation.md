---
title: Installation
sidebar_position: 1
description: Which package to add, what it depends on, and which SDK versions are the floor.
---

# Installation

Two packages. Add the one that matches what you are building.

:::warning Not published yet
Nothing is on pub.dev at the time of writing. The snippets below are what
installation looks like once `0.1.0` is published; a git dependency is not an
alternative, because the binding depends on a hosted `query_kit`.
:::

## In a Flutter app

```bash
flutter pub add query_kit_flutter
```

That pulls in `query_kit` as well; you get the whole surface from one import.

```dart snippet="prose-only: the one import line, which every other sample already shows in context"
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

```dart snippet="prose-only: the one import line, which every other sample already shows in context"
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

## Next

[Your first query](first-query.md) — a provider, an options function, and a
widget that reads it.
