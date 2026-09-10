# Contributing

Issues and pull requests are welcome. The repository has one unusual rule and
a few ordinary ones; the unusual one is first because everything else follows
from it.

## The unusual rule: fidelity is proven, not asserted

This is a port. Its claim is that it behaves the way TanStack Query behaves,
and the evidence is that upstream's own test suite runs against it, case for
case. So:

- **When a ported test fails, the assumption is that the port is wrong, not
  the test.** Change an assertion only when a design decision genuinely makes
  upstream's expectation inapplicable — and write down why, in
  [`packages/query_kit/test/PORTING_NOTES.md`](packages/query_kit/test/PORTING_NOTES.md).
- **When you port a test, port it — don't rewrite it.** Keep the upstream name
  so the two files diff against each other. One Dart test file maps to one
  upstream file; port-only behaviour goes in `smoke_test.dart`.
- **Every divergence and every omission is recorded** in PORTING_NOTES, with
  its reason. That file is the audit, and it is the first thing to read before
  touching a ported suite.
- **A bug report is reproduced before anything is changed.** Several confident
  reports have turned out not to reproduce; the ones that did not are written
  down too, because an unreproduced report is worth knowing about.

Working on the port needs the upstream checkout, pinned — test counts and line
references drift otherwise:

```bash
git clone https://github.com/TanStack/query.git query
```

```bash
git -C query checkout 50680b98c
```

It is gitignored, and every ported test names the upstream file it came from.

## The gate

Everything in one commit: the change, its tests, the analyzer, the formatter,
and a PORTING_NOTES entry if it touches ported behaviour.

```bash
flutter pub get
```

```bash
cd packages/query_kit && dart test
```

```bash
cd packages/query_kit_flutter && flutter test
```

```bash
cd examples/showcase && flutter test
```

```bash
cd examples/sensor_demo && flutter test
```

```bash
dart analyze --fatal-infos packages examples tool && dart format --set-exit-if-changed packages examples/showcase/lib examples/showcase/test examples/doc_snippets/lib tool
```

CI runs the same gates plus `dart doc`, both publish dry-runs, a web build of
each example, the documentation site, the two Playwright end-to-end suites and
the whole suite again on the declared Flutter floor. The examples' READMEs say
how to run their backends and their browser suites locally.

## Conventions that are load-bearing

These are not style preferences; breaking them breaks the tests or the
semantics.

- **Time goes through `package:clock`** (`clock.now()`), never
  `DateTime.now()`, and delays through plain `Timer` / `Future.delayed`.
  `fake_async` intercepts both at the zone level; a stray `DateTime.now()`
  silently desynchronizes from virtual time.
- **Every internally-held future gets an explicit `.ignore()`** where nobody
  awaits it. A retryer's future rejects whether or not anyone is listening,
  and an unhandled async error fails the whole test file.
- **Tests use `testFakeAsync` from `test/test_utils.dart`**, not bare
  `fakeAsync`: `FakeAsync.elapse` cannot be called re-entrantly.
- **Null means "unset" on every options field**, so merging defaults is a
  plain `??` per field. An option with a real "off" value says so with a
  sealed value type (`StaleTime`, `GcTime`, `Enabled`, `RetryPolicy`,
  `RefetchOn`, `RefetchInterval`) rather than a magic number or string.
- **No third-party package may be required by either published package.**
  Not for state management, not for connectivity. Integrations belong in
  separate opt-in packages. This was the maintainer's explicit ruling and it
  holds for anything built on top.
- **The documentation names no default call style.** The four ways to read a
  query are presented as equal alternatives.
- **A Dart sample on the website appears in `examples/doc_snippets/` too**,
  under a comment naming its page, so the analyzer sees it. A sample nothing
  compiles is a sample that rots.
- Comments explain *why*, not what.

## Where the plan lives

Decisions are tracked as a wayfinder map on
[issue #1](https://github.com/KoTTi97/flutter_query/issues/1); each fork in the
road is a sub-issue closed with the options, the answer, and why it beat the
alternatives. The research behind them is under [`docs/`](docs/). If you are
proposing something that changes the shape of the API, open an issue first —
the map is where that conversation belongs.

## Pull requests

- One concern per pull request; a green gate before you open it.
- Say what you changed and how you know it works. If a review finding prompted
  it, say whether you reproduced it and how.
- The package name is a codename (see
  [`docs/releasing.md`](docs/releasing.md)); don't hard-code it in prose you
  could phrase around, and never edit `tool/rename_packages.dart`'s frozen
  list without a reason.

## Licence

By contributing you agree that your contribution is licensed under the MIT
licence, the same as the rest of the repository.
