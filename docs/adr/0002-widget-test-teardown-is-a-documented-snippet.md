---
status: accepted
date: 2026-09-11
ticket: https://github.com/KoTTi97/flutter_query/issues/36
---

# The widget-test teardown is a documented snippet, not an export

`query_kit_flutter` listed `flutter_test` as a regular dependency so that
`lib/testing.dart` could export `queryWidgetTest`. That made the README's "no
dependency beyond Flutter itself" false, put `test_api`, `matcher` and
`leak_tracker_*` into the regular graph of every consuming app, and — because
`flutter_test` imports `dart:io` — would have had pub.dev tag the binding as
not Web/WASM-compatible, for a helper with exactly one caller in the
repository (its own test). Research ([test-helper-packaging](../research/test-helper-packaging.md))
found the widest-reach packages either keep helpers on `test_api` alone
(impossible here: `testWidgets` and `WidgetTester` *are* the helper) or export
nothing and document a snippet. We take the snippet: `flutter_test` moves to
`dev_dependencies`, `lib/testing.dart` is removed, and the three-step teardown
(`pumpWidget(SizedBox())`, `pumpAndSettle()`, `client.clear()`) is the first
thing on the testing page and in the binding README, compiled in
`examples/doc_snippets` so it cannot rot. The binding's own tests and both
examples use one harness of that shape.

## Considered options

1. **A companion `query_kit_flutter_test` package.** The honest place for a
   `flutter_test` dependency, but a permanent pub.dev name, a third publish
   stage with its own wait, a third tag glob and a third leg in every CI job,
   for two functions of forty lines. Available if a real helper ever grows
   (the name was free on 2026-09-11).
2. **This** — a snippet. Nothing to publish, the README claim stays true, the
   package page shows Web and WASM; matches provider, go_router and dio.
3. **Keep the regular dependency.** No points lost on pub.dev and no
   resolution failure, but a visible contradiction between what the package
   says and what its page shows, and a floor bump every time `flutter_test`
   changes its API.

## Consequences

- The "it is API, not a snippet" stance in `CLAUDE.md` is reversed on the
  evidence of one caller; the snippet must stay the first thing a reader of
  the testing page sees, because a first widget test fails without it.
- The API-shape ticket's C22 (what `testing.dart` exports) is moot.
- The deeper harness C45 asks for (accept a client, wire the provider, fake
  the lifecycle source, tear down once) is the binding test suite's own
  concern now, not public API; the documented snippet shows the minimal form
  and, below it, the fuller harness both examples use.
