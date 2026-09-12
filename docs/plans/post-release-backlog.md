# Post-release backlog for `query_kit`

What the pre-release deep-dive review of 2026-09-12 found and **deliberately did
not fix before 0.1.0**, with the reason each one waits. Everything a user could
lose data or time to was fixed; the evidence is in
[PORTING_NOTES](../../packages/query_kit/test/PORTING_NOTES.md), sections
"Pre-release deep-dive review" and "Final review of the pre-release branch".

This list exists so the next review does not rediscover these as new findings.
**An item here is known, triaged and waiting — not a finding.** A reviewer who
reports one should be pointed at this file; a reviewer who finds something
*not* on this list, or shows an item is worse than rated, has found something.

## Why the review stopped where it did

Every fresh pass over a round of fixes found defects those fixes had
introduced: six after the first round (one P1), three after the second, one
after the third. The fourth pass found no defect in the fix it reviewed, only
an older hashing collapse one level deeper, which was fixed and measured on
three platforms. Findings shrank each round, from silent stale data to a
quadratic cost for one data shape. The items below are what remains below the
line: P3, contract questions and nits, none of them wrong data, a crash or a
realistic-path slowdown.

## Contract questions — decide before 1.0, all breaking to change later

| ID | Question | Current state |
|---|---|---|
| API-07 | The four `*Error` types implement `Exception`; three are programming or configuration errors, which Dart spells `Error` | Kept for 0.1.0 |
| API-06 | Method names that follow JavaScript rather than Dart idiom: `getDefaultOptions()`/`setDefaultOptions()`, `isFocused()`, `isOnline()`, `isFetching()`/`isMutating()` returning `int` | Kept: upstream familiarity is the migration story |
| API-05 | `.when` / `.dynamic` / `.compute` are three names for "computed per query" across the option value types | Kept: each name says what its callback receives |
| DC-12 | "`null` means not configured" leaves no per-call way to *clear* a key or client default for `meta`, `scope`, `queryFn`, `structuralSharing` | Undocumented limitation; document or add an explicit unset |
| F4 | A sealed `StructuralSharing` type instead of the `noStructuralSharing()` sentinel would match the repository's own convention for option unions | Sentinel shipped; the sealed type touches about a dozen call sites and a site fence |
| FI-11 | Maps are shared whole: a JSON-shaped `Map<String, Object?>` with one changed leaf shares nothing below it, so `==`-based rebuilds over sub-maps fire for every sibling | Recorded cost; a `Map<String, Object?>` special case is the candidate |

## Robustness (P3)

| ID | Finding | Why it waits |
|---|---|---|
| OB-02 | `getOptimisticResult` for other options overwrites the result the stale timer reads; a preview not followed by `setOptions` can stop the committed result flipping stale | Upstream-identical; whether the binding reaches it is unmeasured |
| OB-03 | `refetch()`, and silently the poll timer, throw `QueryDataTypeError` on a key/type collision although `QueryRefetch` promises errors in the result | A programming error; the contract question is whether to surface it as data |
| OB-04 | `client.clear()` during a fetch leaves a subscribed observer at `fetchStatus: fetching` until its next update | Upstream-identical; self-heals |
| OB-05 | `QueriesObserver.setQueries` re-entered from a cache listener writes destroyed observers' options onto the shared query | Requires re-entrant misuse |
| R3-2 | A set of maps with a custom key equality compares "not equal" though the walk calls the maps equal: lost sharing, one extra rebuild | Hashing only values would make sets of rows differing only in keys quadratic |
| AR-08 | Hot collections are lists: 5 000 observers on one query cost 60 ms to subscribe; `MutationCache` scans get slower with many live mutations | Measured; not user-visible at realistic sizes |
| API-11, API-12, API-15, API-16 | Unexported supertypes hoisted in dartdoc; uneven `toString`; two undocumented constructors; `*ObserverRef` implementable despite "unsupported" | Documentation and polish; pana is 160/160 |
| F7 | `Query.setState` does not normalise a restored `fetchStatus`, `QueryCache.build` does | Deliberate: `setState` is the merge half of a restore, as upstream's hydration |

## Structure (next wayfinder map)

| ID | Finding |
|---|---|
| AR-06 | Run ownership is spread across several identities in `Query` (`_fetchGeneration`, `_operation`, `_retryer`) and `Mutation`, checked with different idioms; four observers repeat the result-revision guard. One run token per entity would replace them |
| AR-10 | 15 of 29 `lib/src` modules form one import cycle with `query_client` at its centre |
| AR-13–18 | Duplicated helpers, `toString` gaps on `Defaulted*Options`, per-success future allocation in `MutationCache`, a 0 ms periodic timer from `RefetchInterval.every` below 1 ms |

## Upstream-identical, recorded, no action

IN-03, IN-04, IN-05, MU-04, MU-05, MU-06, AR-11 (one timer per retained
mutation), MU-07 and DC-16 (both in the divergence table), R3-3 and R3-4
(Dart's own `num` behaviour at 2^53 and for `NaN`).

## Not the core

The task manager's end-to-end test "shared data stays consistent through
rename, rollback and network recovery" (`examples/task_manager/e2e/tests/tasks.spec.ts:315`)
is flaky on `main` and on the review branch alike — two and three of seven
full-suite runs failed, never when run alone. It fails in a Tab/Shift+Tab focus
workaround on Flutter web's hidden text input, which never touches `query_kit`.
The fix belongs in the test: redo the click and focus steps inside the wait.
