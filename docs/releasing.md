# Releasing

Two packages go to pub.dev, in a fixed order, from a tag each.

**[`scripts/release.sh`](../scripts/release.sh) walks the whole procedure.** It
is this document as a path rather than as prose: it refuses to start unless the
tree is releasable, signs the CLI in, publishes the core and then the binding in
order, waits for pub.dev in between, opens both admin pages for the
automated-publishing switch, and tags without firing the publish workflow. It is
resumable — a version already on pub.dev is skipped, not retried.

```bash
./scripts/release.sh
```

The rest of this file is what it does and why, which is what you need when a
step has to be done by hand.

## Order

1. **`query_kit` first.** The binding depends on it by version, and
   pub.dev will not accept a package whose dependency it cannot resolve.
2. **`query_kit_flutter` second**, once the core version is visible on
   pub.dev (a minute or two after publishing).

The examples (`examples/showcase`, `examples/task_manager`) are never published
(`publish_to: none`).

## Before tagging

- Both `pubspec.yaml` files carry the release version (no `-dev`), and the
  binding's `query_kit` constraint names it (`^1.0.0`).
- Both `CHANGELOG.md` files have a heading for exactly that version; pub
  validates it.
- CI is green on `main` for the commit being tagged — every job of
  `ci.yml`: `gates` (the five test suites, the core's also compiled to
  JavaScript, the analyzer, the formatter, `dart doc --validate-links`,
  `dart pub publish --dry-run` for both packages, a web build of each
  example), `floors` (the suites on Flutter 3.27.4), `website` and both `e2e`
  legs. The wizard's preflight looks this up for `HEAD` and refuses a red or
  unfinished run.

## Verified publisher

Both packages are published under the verified publisher **dualmeta.io**
(DualMeta GmbH), not under a personal account. The publisher has to exist
before the first release:

1. Verify `dualmeta.io` as a *Domain property* in the
   [Google Search Console](https://search.google.com/search-console) with the
   Google account that will publish (a DNS TXT record).
2. Create the publisher at <https://pub.dev/create-publisher> with that
   domain, signed in with the same account.
3. Add further admins under the publisher's *Members* page if more than one
   person should be able to publish.

A package's first publish lands under the signed-in account; the wizard's
stage 7 then moves both packages to the publisher from each package's admin
page (*Transfer to publisher*). Automated publishing (stage 8) is configured
on the same admin pages and is unaffected by the move.

## Tags

One tag per package, named after the package and the version:

```
query_kit-v1.0.0
query_kit_flutter-v1.0.0
```

Pushing a tag runs [`.github/workflows/publish.yml`](../.github/workflows/publish.yml),
which publishes the package under that prefix from its directory via pub.dev's
automated publishing (GitHub OIDC, no secrets). It is pub.dev's documented
*custom* workflow, not `dart-lang/setup-dart`'s reusable one: that one installs
the Dart SDK only, and both packages resolve inside the root workspace, whose
members need Flutter — the binding cannot even be validated without it. So
`setup-dart` only registers the OIDC-issued pub.dev token, Flutter is
installed after it, and `flutter pub publish --force` runs in the package's
directory. **That only works once the
package's pub.dev admin page has automated publishing enabled for this
repository and the tag pattern** — until then the workflow fails at the
publish step and nothing is published. The first publish of a new package
cannot be automated at all: it has to be `dart pub publish` by hand from the
package directory (which also creates the package), after which automated
publishing can be switched on.

**The bootstrap release costs one contortion.** Its versions are published by
hand, so pushing their tags afterwards would start `publish.yml`, which would
try to publish the same version again and fail — two red runs on the very first
release. No ordering avoids it: before the pub.dev switch is on the run fails
for want of authorization, after it for the duplicate version. So the wizard
disables the workflow, pushes the tags, and enables it again, verifying the
state on both sides and re-enabling from a trap if it exits in between. The tags
land, no run fires, and the automated path is exercised for real from the next
version on.

Manual fallback, in order:

```bash
cd packages/query_kit && dart pub publish
```

```bash
cd packages/query_kit_flutter && flutter pub publish
```

(`dart pub publish` works too when `dart` is the Flutter SDK's, which is what
the wizard assumes.)

## What the archives hold

- **Tests and `test/PORTING_NOTES.md` ship.** There is no `.pubignore` in the
  core: the notes are the fidelity audit (some 425 KB, the archive about
  400 KB compressed), the CHANGELOG points readers at them, and a user who
  `dart pub unpack`s the package can run the ported suite against the very
  version they depend on. Halving the download is not worth losing that
  (REL-21, 2026-09-23).
- **The binding's example resolves from pub.dev alone.** It is not a
  workspace member — a published `resolution: workspace` fails outside this
  repository (REL-7) — and it reaches the checkout through a committed
  `example/pubspec_overrides.yaml`, which the binding's `.pubignore` keeps out
  of the archive. After a fresh clone, `flutter pub get` in
  `packages/query_kit_flutter/example` resolves it; CI does that before the
  analyzer.
- **Throwaway probe tests** (`packages/*/test/_*_tmp_test.dart`) are
  gitignored, so they neither dirty the tree the wizard checks nor reach an
  archive.

## Naming

**The names are `query_kit` and `query_kit_flutter`, and that is the
decision** (2026-09-10). A name on pub.dev is permanent — the policy has no
way to free one — so it was deliberately left until last rather than picked
first; everything else was made ready around it in the meantime. The
candidates, which names were free, what the MIT licence obliges and what
TanStack has and has not said about ports are in
[`docs/research/package-naming-and-affiliation.md`](research/package-naming-and-affiliation.md).

Moving them is still one command, and it is the same command that produced
them, so the path stays exercised:

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
