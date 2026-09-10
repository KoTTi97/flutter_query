---
title: The name, and releasing
sidebar_position: 3
description: Why query_kit is a codename, how the rename works, and what publishing to pub.dev looks like.
---

# The name, and releasing

## `query_kit` is a codename

A package name on pub.dev is **permanent**. The policy disallows unpublishing
except in a few narrow cases; the alternative is marking a package
discontinued, which keeps it published and keeps the name taken. Nobody else
can have it, and neither can you, once it is spent.

So the name is the last decision, not the first. Everything else is made ready
around a placeholder, and the placeholder is swappable:

```bash
dart run tool/rename_packages.dart --core <core> --flutter <core>_flutter
```

That is the same command that produced the current names, so the path is
already exercised. It rewrites the pubspecs, every import, every path that
carries the name and every mention in prose, moves the two package directories
and their library entrypoints, and drops the stale `.dart_tool` so the first
`pub get` afterwards is honest. Then the whole gate runs — the names reach the
tests, the examples, both workflows and this website.

The one file it leaves alone is the naming research: the names in its
availability table are a record of what pub.dev held on a particular day, not
references to this package.

### What the research says

[`docs/research/package-naming-and-affiliation.md`](https://github.com/KoTTi97/flutter_query/blob/main/docs/research/package-naming-and-affiliation.md)
has the facts the decision rests on, gathered rather than assumed:

- which candidate names were free on pub.dev, and who owns the taken ones —
  seven of them are Dart libraries that describe themselves as
  TanStack/React-Query inspired;
- pub.dev's naming, squatting and verified-publisher rules, quoted;
- what TanStack has and has not said about community ports: the accepted answer
  in discussion #3475 is a maintainer telling someone to start with
  `query-core`, and there is no trademark policy, no naming rule for third-party
  projects, and no docs page that lists or objects to any non-JS port;
- how ports in Swift, Kotlin, Rust, .NET and Python named themselves — outside
  Dart, every one chose a framework-flavoured name and an "inspired by" line;
- what the MIT licence obliges: a port that translates `query-core` and its
  suite line by line is a copy of substantial portions, so Tanner Linsley's
  copyright line and the MIT permission notice travel with it. Each package
  keeps them in `LICENSE-TANSTACK`.

## Publishing

Two packages, in a fixed order, from a tag each.

1. **The core first.** The binding depends on it by version, and pub.dev will
   not accept a package whose dependency it cannot resolve.
2. **The binding second**, once the core version is visible on pub.dev.

The examples are never published (`publish_to: none`).

Before tagging: both pubspecs carry the release version with no `-dev`, both
changelogs have a heading for exactly that version, and CI is green on `main`.

One tag per package, named after the package and the version
(`query_kit-v0.1.0`). Pushing it runs `.github/workflows/publish.yml`, which
publishes via pub.dev's automated publishing — GitHub OIDC, no secrets. **That
only works once the package's pub.dev admin page has automated publishing
enabled** for this repository and that tag pattern, and the *first* publish of
a new package cannot be automated at all: it has to be `dart pub publish` by
hand, which is also what creates the package.

The full checklist is
[`docs/releasing.md`](https://github.com/KoTTi97/flutter_query/blob/main/docs/releasing.md)
in the repository.
