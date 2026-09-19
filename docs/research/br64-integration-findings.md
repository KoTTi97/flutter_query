# Findings from the first real integration (BR64, 2026-09-19)

`query_kit` and `query_kit_flutter` were integrated, unmodified, into Eltako
Connect: BR64 sensors, actuators and controllers with list, detail, writes,
polling and teach-in. The integration reported fourteen findings. This is the
triage: each one checked against the code and against upstream at the pin
(`50680b98c`) **before** anything was changed, as every review here is.

Verdicts: **defect** (the port is wrong), **docs** (the behaviour is right and
under-explained), **faithful** (upstream does the same; changing it is a
feature decision), **beyond upstream** (a request upstream does not have
either), **not reproduced**.

| # | Finding | Verdict | What happened |
|---|---|---|---|
| 1 | Structural sharing returns an unmodifiable list as a growable one | **defect**, reproduced | Fixed: PORTING_NOTES "First real integration", I1. Decided twice: the first fix (never copy a sealed list) cost sealed lists their element sharing and regressed infinite-query pages; the reporter objected with a measurement, and the kept fix returns a fixed-length shared copy, or the sealed list itself when nothing was swapped in |
| 2 | `removeQueries` with observers still mounted re-creates the entry on the next `setOptions`/poll | faithful | Upstream's `removeQueries` does exactly this; an observer owns a key, not an entry. The request — close a prefix so nothing new is built under it — is beyond upstream. Seed for the next map |
| 3 | No `MutationFunctionContext` | recorded divergence ([#14](https://github.com/KoTTi97/flutter_query/issues/14)) — and the request is **beyond upstream** | Upstream's context is `{client, meta, mutationKey}`. It carries neither the `onMutate` result nor a signal, so porting it would not have prevented the rename bug. `mutationFn` runs *after* `onMutate` by design; the pre-patch value belongs in the variables, which is what the app did. Seed: is `onMutateResult` in the function's context worth a divergence? |
| 4 | No heterogeneous `combine` | recorded divergence (table: "`useQueries` with a heterogeneous tuple") | Confirmed in use as the most-missed piece. Seed: a record-typed combine in the binding |
| 5 | Mutations cannot be cancelled | faithful | Upstream has no `mutation.cancel()` and no signal on mutations. Beyond upstream; seed, together with 3 |
| 6 | No consecutive-error counter | faithful, confirmed by reading | `fetchFailureCount` resets per fetch, `errorUpdateCount` never (`query.dart`, the reducer). Upstream has the same two. The app's workaround (retry with the poll interval as delay) is the upstream idiom. Seed |
| 7 | No stream adapter | recorded omission (`streamedQuery`, experimental upstream) | Seed |
| 8 | No devtools | out of scope since map #1 | `queryCache.findAll()` plus the cache's event stream is the intended base; a package is a seed |
| 9 | `RefetchInterval.dynamic` / `Enabled.when` do not see external state | faithful, **docs** | Upstream evaluates both on query events only. The pattern that works — `setOptions` with a value — is the documented one upstream too. A `Listenable` trigger is a Flutter-side idea worth a ticket in the binding. Seed; first entry of the troubleshooting page |
| 10 | A `MutationController` observes its latest run only; per-call callbacks are dropped when superseded | faithful | Upstream's `MutationObserver` is identical, and its docs say so. Troubleshooting entry written |
| 11 | `MutationStateController.select` is untyped | faithful, confirmed | Upstream's `useMutationState` select receives `Mutation<unknown, …>` too. A typed filter is a Dart-side improvement; seed |
| 12 | Nested `mutateAsync` in the same `MutationScope` deadlocks | faithful (by reading, as reported) | Same upstream. A debug assertion needs the running mutation to be known at `mutate` time (a zone value); seed |
| 13a | `QueryListener` needs a `QueryController` | confirmed | By design it listens to a controller somebody owns; the other styles have no handle to give. Seed: a key-based listener |
| 13b | `setMutationDefaults` cannot be removed | faithful | Upstream has no removal either. Seed |
| 13c | Mutations default to `networkMode: online` while queries follow the client default | **not reproduced** | Both resolve `options ?? client default ?? online` (`query_client.dart`, the two defaulting functions). Queries and mutations have *separate* client defaults, as upstream: set `defaultOptions.mutations.networkMode` as well as the queries' one |
| 13d | One key, one exact type; no list covariance | by design ([ADR-0001](../adr/0001-one-type-slot-for-plain-queries.md)) | **docs**: troubleshooting entry written |
| 14 | Not consumable outside the workspace | **docs**, fixed | The path-plus-`dependency_overrides` recipe is now in the installation page and the binding README |

## What this says about the library

One defect in fourteen findings, in a corner (list modifiability) that has no
upstream counterpart and therefore no ported test — the same shape as every
earlier review's finds. Nothing behavioural that upstream's suite covers was
reported wrong.

The rest is a consistent picture: the app wanted **more than upstream** around
mutations (context, cancellation, a typed state selector, scope diagnostics)
and around reacting to state outside the cache (finding 9). Those are feature
decisions, not repairs, so by this repository's rules they are charted, not
patched in: they are the seeds for the map after
[#70](https://github.com/KoTTi97/flutter_query/issues/70). By the reporter's
own priority the order is 4 (combine), 3+5 (mutation context and
cancellation, one design), 9 (a re-evaluation trigger), then 6, 2, 11, 12.

**Finding 9 ranks first among the traps**, whatever upstream does: it is the
only one where the library's behaviour stopped the app — polling paused for a
write never resumed. Verified in `query_observer.dart`: `setOptions` compares
`enabled.resolve(query)` of the old and the new options at the same instant,
so a predicate over outside state never reads as changed. It opens the site's
[troubleshooting page](../../website/docs/reference/troubleshooting.md),
which this integration started: 9, 2, 10, 13d, 12 and 13c, symptom first, its
two samples compiled as twins. [#78](https://github.com/KoTTi97/flutter_query/issues/78)
adds its own eight entries to the same page.
