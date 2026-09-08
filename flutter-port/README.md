# flutter-port

The Dart/Flutter port of TanStack Query's `query-core`. A pub workspace.

- [DESIGN.md](DESIGN.md) — design doc of record; decisions **D1–D13**, cited
  throughout the source, plus the amendments implementation has made to them.
- [PLAN.md](PLAN.md) — approved milestone plan and module map, with current
  status.
- [packages/query_core/test/PORTING_NOTES.md](packages/query_core/test/PORTING_NOTES.md)
  — fidelity audit: what is ported from where, every omission with a reason.

## Layout

```
flutter-port/
  pubspec.yaml            workspace root (Dart SDK ^3.11.0)
  analysis_options.yaml   package:lints/recommended + strict-casts/inference/raw-types
  packages/
    query_core/           pure Dart. Zero Flutter imports.       ← complete for the MVP
    flutter_query/        the widget binding                     ← M7, not started
  apps/
    sensor_demo/          the Flutter sensor demo                ← M8, not started
```

Only `packages/query_core` is active in the workspace today; the other two are
commented out in `pubspec.yaml` and get uncommented when their milestone starts.

## query_core

Pure Dart — it has no Flutter dependency and runs under plain `dart test`, which
is why the whole state machine can be tested against virtual time.

| File | Upstream counterpart |
|---|---|
| `query_key.dart` | `utils.ts` (`hashKey`, `partialMatchKey`) |
| `option_values.dart` | the union-typed options in `types.ts` |
| `query_options.dart` | `types.ts` (query options + defaulting) |
| `query_state.dart`, `query.dart` | `query.ts` |
| `query_cache.dart` | `queryCache.ts` |
| `query_observer.dart`, `query_result.dart` | `queryObserver.ts` |
| `query_client.dart` | `queryClient.ts` |
| `mutation_options.dart`, `mutation_state.dart`, `mutation.dart` | `mutation.ts` |
| `mutation_cache.dart` | `mutationCache.ts` |
| `mutation_observer.dart`, `mutation_result.dart` | `mutationObserver.ts` |
| `filters.dart` | `utils.ts` (`QueryFilters`, `MutationFilters`) |
| `retryer.dart`, `cancel_token.dart` | `retryer.ts` |
| `notify_manager.dart` | `notifyManager.ts` (redesigned — D8) |
| `focus_manager.dart`, `online_manager.dart` | same names, event sources removed (D10) |
| `subscribable.dart`, `removable.dart` | same names |

Dropped entirely: `timeoutManager`, `environmentManager` (D10), `hydration`
(D12), `infiniteQueryBehavior`, `infiniteQueryObserver`, `queriesObserver`,
`streamedQuery`.

### Running it

```bash
cd packages/query_core && dart test
```

```bash
cd packages/query_core && dart analyze --fatal-infos && dart format --set-exit-if-changed .
```

Both, plus green tests, are the gate for calling a milestone done.

### Test layout

One Dart test file per upstream test file, so the two diff against each other:

| Dart | Upstream | Cases |
|---|---:|---:|
| `query_test.dart` | `query.test.tsx` | 44 / 50 |
| `query_cache_test.dart` | `queryCache.test.tsx` | 14 / 16 |
| `query_observer_test.dart` | `queryObserver.test.tsx` | 52 / 73 |
| `query_client_test.dart` | `queryClient.test.tsx` | 110 / 156 |
| `mutation_test.dart` | `mutation.test.tsx` | 27 / 28 |
| `mutation_cache_test.dart` | `mutationCache.test.tsx` | 16 / 16 |
| `mutation_observer_test.dart` | `mutationObserver.test.tsx` | 16 / 16 |

Plus files with no single upstream counterpart: `query_key_test.dart`,
`query_options_test.dart`, `managers_test.dart`, `notify_manager_test.dart`,
`removable_test.dart`, `retryer_test.dart` (upstream has no retryer suite),
`test_utils_test.dart`, and `port_specifics_test.dart` for behavior the port
introduces.

**372 tests total.** Every unported upstream case is listed with a reason in
PORTING_NOTES.md — the invariant worth preserving is that there are no silent
omissions.
