---
status: accepted
date: 2026-09-12
---

# Core operations own their state through callbacks and settlement

The pre-release core review found state corruption at asynchronous settlement
and synchronous public callbacks. An old query could overwrite a successor;
same-scope mutations could overlap; observer callbacks could install newer
ownership which an older stack frame then overwrote. Green ported tests did
not exercise those sequences. This decision records the contract enforced by
the additional `release_*_regressions_test.dart` suites.

## Ownership rules

- A query fetch owns its cache writes through its operation identity. Reset
  revokes that identity even if the transport already resolved. Cancellation,
  initialization and structural-sharing callbacks cannot authorize an older
  stack frame to write over a successor or start a removed entry's transport.
  A discarded transport result may still complete its original caller; it
  does not commit data or fire a successful cache-write hook.
- Query signal consumption belongs to the active fetch token. A canceled
  function accessing its old context later cannot change the next fetch's
  unsubscribe behavior.
- A mutation scope has an explicit owner through transport and completion
  callbacks. Cache insertion order alone is insufficient. Removing an active
  owner does not release the scope until its run settles; removing an
  unstarted restored queue head releases its waiters once that removal has
  completed (the next microtask), and only the head's removal does. Removing
  entries — one, a filtered loop, or `clear()` — never starts a mutation
  function while the removal is under way.
- Every mutation call has an invocation identity. Reentrant newer calls or
  resets retain ownership of the observer and its per-call callbacks. An
  older invocation may still execute its own mutation without taking the
  observer back. Re-executing one already-running Mutation instance joins
  that run; distinct mutation calls create distinct entries.
- Each subscription has its own registration token. Unsubscribe and clear
  invalidate that token, including during dispatch; old handles cannot
  remove new registrations of an equal callback.
- State observers deliver synchronously. A newer nested state notification
  supersedes the remaining delivery of an older snapshot. Cache events are
  discrete events and retain their event-by-event dispatch semantics.
- Result value equality does not imply callback ownership equality. A
  collection key replacement/reordering updates its callable targets even
  when the data is equal.
- Committed and optimistic selection memo/error state are separate. Repeated
  previews can reuse their own input/selector memo without contaminating a
  committed placeholder or its error recovery.

## Options and API lifetime decisions

| Setting or operation | Contract |
| --- | --- |
| Query options | Last installed defaulted options, with the retry exception below. |
| Imperative query with no explicit/client/key-default retry | One transport attempt; retain the entry's existing retry policy for later refetches. Explicit retry replaces that policy. |
| Retry policy, retry delay, network mode | Snapshot when each retryer is created. Dynamic callbacks can still read external state at invocation time. |
| Mutation function and completion hooks | Function read per attempt; hooks read when invoked, with that run's variables/context. |
| Mutation scope | Fixed for the entire run, through completion hooks. |
| Resume selection | Uses the existing retryer's network mode; a restored mutation without a retryer uses the impending run's start rule. |
| Query/Mutation re-add after removal | Removed objects are terminal; reject with StateError. Build a fresh entry instead. Duplicate add of an already cached Mutation is a no-op. |
| Restored states | Cache build, direct constructors and query setState validate the same payload/presence invariants before installation. Genuine nullable-null payloads remain valid. |
| Reentrant initial data | Preserve the canonical cache entry created during the callback. Removal before fetch startup prevents detached transport work. |
| Infinite optimistic result | Preview data does not commit paging actions/options. Page flags and methods continue to describe the committed query until options are applied. |
| Placeholder sharing | Custom raw-data hook applies to unselected placeholders. Selected output uses replaceEqualDeep; selected data is never cast back into raw input. |
| Collection equality | Default sharing assumes standard equality. Custom comparator/equality collections require a custom sharing policy when those semantics matter. |

Query keys require acyclic collection graphs and stable equality/hash values
for user objects. Generic cloning of mutable application objects, support for
cyclic keys, and preservation of arbitrary custom collection semantics are
not added to this release. These are explicit input boundaries, not runtime
bugs silently treated as fixed.

## Relationship to the pinned upstream

Compared with `query/` at `50680b98c`, and directly reproduced upstream for
the most consequential sequences:

- Superseded query cancellation and nested MutationAdded callback corruption
  also occur upstream. Copying the original does not repair those guarantees.
- Upstream's unconditional await during mutation initialization masks the
  ordinary nested-scope trigger which Dart's intentional synchronous
  optimistic path exposes. An earlier-built mutation executed after a later
  transport starts also breaks upstream's first-pending rule. An actual owner
  fixes both without adding artificial delay to optimistic callbacks.
- Retry-callback teardown and throwing query lifecycle policies retain
  upstream weaknesses. Dart already promises stronger timer cleanup/error
  isolation, so these fixes complete that policy.
- Collection callback target retention, invocation/snapshot bookkeeping and
  generic placeholder type safety require Dart-specific treatment.

The upstream pin and ported assertions remain unchanged. The alternative of
restoring upstream lines verbatim was rejected because it preserves observed
defects. A general new scheduling framework or public state-machine API was
also rejected; the identities above remain internal implementation details.

## Release acceptance

Each behavioral change has a failing-before/passing-after reproduction.
Original assertions were preserved. Core VM/browser tests, supported SDK
checks, consumer compatibility tests, analyzer, formatter, API docs and
publish dry-run are required. Fresh reviewers independently probe the final
contracts, and their unresolved concrete defects block acceptance.

Review artifacts are local under `docs/reviews/2026-09-12-core/`; the permanent
tests and this decision carry the essential contract without that gitignored
directory. A core acceptance does not certify the Flutter binding or publish
either package.
