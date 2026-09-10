# Releasing

Two packages go to pub.dev, in a fixed order, from a tag each.

## Order

1. **`query_kit` first.** The binding depends on it by version, and
   pub.dev will not accept a package whose dependency it cannot resolve.
2. **`query_kit_flutter` second**, once the core version is visible on
   pub.dev (a minute or two after publishing).

The examples (`examples/showcase`, `examples/task_manager`) are never published
(`publish_to: none`).

## Before tagging

- Both `pubspec.yaml` files carry the release version (no `-dev`), and the
  binding's `query_kit` constraint names it (`^0.1.0`).
- Both `CHANGELOG.md` files have a heading for exactly that version; pub
  validates it.
- CI is green on `main`: it runs the tests, the analyzer, the formatter,
  `dart doc`, `dart pub publish --dry-run` for both packages, a web build of
  each example and both Playwright suites.

## Tags

One tag per package, named after the package and the version:

```
query_kit-v0.1.0
query_kit_flutter-v0.1.0
```

Pushing a tag runs [`.github/workflows/publish.yml`](../.github/workflows/publish.yml),
which publishes the package under that prefix from its directory via pub.dev's
automated publishing (GitHub OIDC, no secrets). **That only works once the
package's pub.dev admin page has automated publishing enabled for this
repository and the tag pattern** — until then the workflow fails at the
publish step and nothing is published. The first publish of a new package
cannot be automated at all: it has to be `dart pub publish` by hand from the
package directory (which also creates the package), after which automated
publishing can be switched on.

Manual fallback, in order:

```bash
cd packages/query_kit && dart pub publish
```

```bash
cd packages/query_kit_flutter && dart pub publish
```

## Naming

**`query_kit` and `query_kit_flutter` are a codename, not the decision.** A
name on pub.dev is permanent — the policy has no way to free one — so the
choice is deliberately left until the moment before the first
`dart pub publish`, and everything else is made ready around a placeholder.
The candidates, which names are still free, what the MIT licence obliges and
what TanStack has and has not said about ports are in
[`docs/research/package-naming-and-affiliation.md`](research/package-naming-and-affiliation.md).

Changing it is one command, and it is the same command that produced the
current names, so the path is already exercised:

```bash
dart run tool/rename_packages.dart --core <core> --flutter <core>_flutter
```

It rewrites the pubspecs, every import, every path that carries the name and
every mention in prose, moves the two package directories and their library
entrypoints, and drops the stale `.dart_tool` so the first `pub get` after it
is honest. It deliberately leaves
`docs/research/package-naming-and-affiliation.md` alone: the names in that
table are a record of what pub.dev held on 2026-09-08, not references to this
package. Run the full gate afterwards — the names reach the tests, the
examples, both workflows and the website.
