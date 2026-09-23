---
title: Installation
description: Which package to add, what it depends on, and which SDK versions are the floor.
---

# Installation

Two packages. Add the one that matches what you are building.

## In a Flutter app

```bash
flutter pub add query_kit_flutter
```

That pulls in `query_kit` as well; you get the whole surface from one import.

```dart snippet="prose-only: the one import line, which every other sample already shows in context"
import 'package:query_kit_flutter/query_kit_flutter.dart';
```

**No third-party dependency** — not `flutter_hooks`, not a signals package,
not `connectivity_plus`. The core depends only on the Dart team's `clock` and
`meta`; the binding adds nothing beyond Flutter. You should not have to adopt
somebody's state management to use a cache.
[Connectivity](guides/connectivity.md) is opt-in and stays your dependency.

## In pure Dart

A CLI, a server, a shared package with no Flutter in it:

```bash
dart pub add query_kit
```

```dart snippet="prose-only: the one import line, which every other sample already shows in context"
import 'package:query_kit/query_kit.dart';
```

See [using the core without Flutter](guides/pure-dart.md) — the one thing you
have to do yourself there is `client.mount()`.

## Requirements

|  | Floor | Notes |
|---|---|---|
| `query_kit` | Dart SDK `^3.6.0` | No Flutter. Runs on the VM and compiled to JavaScript; both are tested. |
| `query_kit_flutter` | Flutter **3.27** | Tested on 3.27 as well as current stable. |

Platforms: the core supports all six pub.dev platforms. The binding is
exercised on the web by the examples' end-to-end suites; the other platforms
are untested rather than unsupported.

## Recommended analyzer setting

One options literal cannot be typed by inference: a key-only one with neither
a `queryFn` nor a type argument. The analyzer reports it at the literal once
your `analysis_options.yaml` asks for strict inference — see [type safety in
Dart](dart-type-safety.md):

```yaml
analyzer:
  language:
    strict-inference: true
```

## Next

The [quick start](quick-start.md) — a provider, an options function, and a
widget that reads it.
