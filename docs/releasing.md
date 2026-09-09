# Releasing

Two packages go to pub.dev, in a fixed order, from a tag each.

## Order

1. **`tanstack_query_core` first.** The binding depends on it by version, and
   pub.dev will not accept a package whose dependency it cannot resolve.
2. **`tanstack_query_flutter` second**, once the core version is visible on
   pub.dev (a minute or two after publishing).

The demo (`examples/sensor_demo`) is never published (`publish_to: none`).

## Before tagging

- Both `pubspec.yaml` files carry the release version (no `-dev`), and the
  binding's `tanstack_query_core` constraint names it (`^0.1.0`).
- Both `CHANGELOG.md` files have a heading for exactly that version; pub
  validates it.
- CI is green on `main`: it runs the tests, the analyzer, the formatter,
  `dart doc`, `dart pub publish --dry-run` for both packages, a web build of
  the demo and the Playwright suite.

## Tags

One tag per package, named after the package and the version:

```
tanstack_query_core-v0.1.0
tanstack_query_flutter-v0.1.0
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
cd packages/tanstack_query_core && dart pub publish
```

```bash
cd packages/tanstack_query_flutter && dart pub publish
```

## Naming

The `tanstack_*` names are the maintainer's call and are permanent once
published (pub.dev names cannot be freed). The research behind the choice and
the fallback names (`query_kit`, `query_kit_flutter`) are in
[`docs/research/package-naming-and-affiliation.md`](research/package-naming-and-affiliation.md);
the moment to change one's mind is before the first `dart pub publish`.
