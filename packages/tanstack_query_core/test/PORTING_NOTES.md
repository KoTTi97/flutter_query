# Porting notes

What this file is: the audit trail behind the port's central claim — *upstream's
behaviour, proven by upstream's own tests*. Every upstream case in a ported
suite is accounted for here as **ported**, **adapted** (with why), or
**omitted** (with which allowed category it falls in). A gap that is not listed
is a bug in this file.

- **Upstream revision:** `50680b98c` (`main`, 2026-09-08).
- **The policy that governs this file:**
  [#18](https://github.com/KoTTi97/flutter_query/issues/18).
- One Dart file per upstream file; upstream test names kept verbatim; a failing
  ported test means the port is wrong until proven otherwise.
- Port-only tests (no upstream counterpart) live in `smoke_test.dart` and, as
  the suite grows, `port_specifics_test.dart`.

## Status

| Upstream suite | Dart file | Cases | State |
|---|---|---|---|
| `subscribable.test.tsx` | `subscribable_test.dart` | 9 / 9 | done |
| `notifyManager.test.tsx` | `notify_manager_test.dart` | 6 / 7 | done |
| `focusManager.test.tsx` | `focus_manager_test.dart` | 6 / 9 | done |
| `onlineManager.test.tsx` | `online_manager_test.dart` | 6 / 11 | done |
| `removable.test.tsx` | `removable_test.dart` | 11 / 12 | done |
| `retryer.test.tsx` | `retryer_test.dart` | 13 / 13 | done |
| `query.test.tsx` | — | 0 / 51 | not started |
| `queryCache.test.tsx` | — | 0 / 16 | not started |
| `queryObserver.test.tsx` | — | 0 / 75 | not started |
| `queryClient.test.tsx` | — | 0 / 156 | not started |
| `mutation.test.tsx` | — | 0 / 28 | not started |
| `mutationCache.test.tsx` | — | 0 / 16 | not started |
| `mutationObserver.test.tsx` | — | 0 / 16 | not started |
| `infiniteQueryBehavior.test.tsx` | — | 0 / 9 | not started |
| `infiniteQueryObserver.test.tsx` | — | 0 / 7 | not started |
| `utils.test.tsx` | — | 0 / 78 | not started |

Suites not ported at all, each for one recorded reason:
`hydration.test.tsx` (hydration is out of v1 scope, #17),
`timeoutManager.test.tsx` (the module is not ported, #9),
`environmentManager.test.tsx` (no SSR),
`queriesObserver.test.tsx` (`useQueries` is fog, not v1),
`streamedQuery.test.tsx` (experimental upstream; the Dart `Stream` mapping is
fog).

## Omissions and adaptations, by suite

### `notifyManager.test.tsx`

- **omitted — type-level:** `typeDefs should catch proper signatures`.
  `expectTypeOf`/`assertType` have no Dart equivalent, and the inference it
  guards does not exist as a question here (#7, #18 §4).
- **adapted:** `should batch calls correctly`. Upstream's `batchCalls` is
  variadic; Dart has no variadics, so the two arguments travel as one record
  and the assertion is on the record. Same behaviour, one call shape.

### `focusManager.test.tsx`

- **omitted — browser environment (3):**
  `cleanup (removeEventListener) should not be called if window is not defined`,
  `... if window.addEventListener is not defined`, and the `addEventListener`
  spy half of `should call removeEventListener when last listener unsubscribes`.
  There is no `window` in Dart and no default DOM adapter to install; the
  Flutter binding's `AppLifecycleListener` adapter is covered by that package's
  own tests.
- **adapted:** `should return true for isFocused if document is undefined` —
  upstream deletes `globalThis.document` to show the manager defaults to
  focused. Pure Dart has nothing to ask in the first place, so the assertion is
  made against the default.
- **adapted:** `should call removeEventListener when last listener
  unsubscribes` — asserts the *installed adapter's cleanup* runs on the last
  unsubscribe, which is the behaviour the DOM spy was standing in for.

### `onlineManager.test.tsx`

- **omitted — browser environment (5):** the two `navigator.onLine` spies, the
  two `window`-undefined cleanup cases, and
  `should update online status from window online and offline events`. The
  Flutter binding's `connectivity_plus` adapter is tested in that package.
- **adapted:** `isOnline should return true if navigator is undefined` and
  `should call removeEventListener when last listener unsubscribes`, for the
  same reasons as the focus manager.

### `removable.test.tsx`

- **omitted — SSR:** `should default to Infinity on the server` (#9: no server
  environment).
- **adapted — all remaining cases:** upstream asserts against a mock
  `timeoutManager` provider (`setTimeout` called with `123`, `clearTimeout`
  called with that id). `timeoutManager` is not ported (#9), so each case
  asserts the *effect* under virtual time instead: that `optionalRemove` runs
  when the gc time elapses and not before, that no timer is scheduled for
  `GcTime.never`, and that rescheduling or clearing leaves the expected number
  of pending timers. This is a stronger test of the same behaviour — it would
  catch a provider that was called correctly but wired to nothing.

### `retryer.test.tsx`

- **adapted:** `should use the default exponential backoff capped at 30
  seconds`. Upstream reads the delay sequence off a `setTimeout` spy; here the
  delay is a pure function (`RetryDelay.resolve`), so the sequence
  `[1s, 2s, 4s, 8s, 16s, 30s]` is asserted directly *and* the retry loop is run
  to success, which proves the same schedule actually drives it.
- **adapted:** the module-level `focusManager`/`onlineManager` that upstream
  resets in `beforeEach` are per-test instances here (#19), so the suite needs
  no global reset and cannot leak into another test.
- **note:** `canFetch` is exported from `retryer.dart` exactly as upstream
  exports it, so `should reflect network availability in canFetch and canStart`
  ports unchanged apart from taking the manager as an argument.

## Deliberate divergences that will show up in later suites

These are decided, not accidental; each is listed here so a reader of a ported
suite does not have to go looking:

| Upstream behaviour | Here | Decided in |
|---|---|---|
| `data === undefined` runtime guard in `Query.fetch` | impossible: `Future<T>` with non-nullable `T` | [#7](https://github.com/KoTTi97/flutter_query/issues/7) |
| `hashKey` string identity, `queryKeyHashFn` | `QueryKey` is a value type; the string is a debug view | [#8](https://github.com/KoTTi97/flutter_query/issues/8) |
| `replaceEqualDeep` structural sharing | value equality plus an optional `structuralSharing` hook | [#12](https://github.com/KoTTi97/flutter_query/issues/12) |
| `trackResult`, `notifyOnChangeProps` | dropped; `select` plus the binding's `buildWhen` | [#15](https://github.com/KoTTi97/flutter_query/issues/15) |
| `throwOnError` | dropped; errors live in the sealed result | [#15](https://github.com/KoTTi97/flutter_query/issues/15) |
| `skipToken` | `Enabled.no` | [#17](https://github.com/KoTTi97/flutter_query/issues/17) |
| module-level managers | instances the `QueryClient` owns | [#19](https://github.com/KoTTi97/flutter_query/issues/19) |
| a blind cast in `getQueryData` | a type mismatch throws `QueryDataTypeError` | [#7](https://github.com/KoTTi97/flutter_query/issues/7) |
