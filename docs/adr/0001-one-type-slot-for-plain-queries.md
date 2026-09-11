---
status: accepted
date: 2026-09-11
ticket: https://github.com/KoTTi97/flutter_query/issues/35
---

# One type slot for a plain query, two for a select, never an unanchored one

`QueryObserverOptions<TQueryData, TData>` carried `TData` only in its optional
`select`, so options written inline without a `select` inferred `TData` to
`dynamic` and put a `Query<dynamic>` in the cache; every typed reader of the
key afterwards threw. Research ([dynamic-inference-guards](../research/dynamic-inference-guards.md))
found that no library-side guard exists — the one analyzer diagnostic needs
`strict-inference` in the *consumer's* options, a bound on `TData` silences
it, an `assert` is compiled out — and that every comparable library anchors
the output type in a required parameter and makes `select` a separate entry
point. We do the same: the observer options split into two public shapes,
**`QueryObserverOptions<TData>`** (no `select`; the data type is the query's,
inferred from `queryFn`) and **`QuerySelectOptions<TQueryData, TData>`**
(`select` **required**), over a sealed base `QueryObserverOptionsBase<TQueryData, TData>`
that only the observer, the general `QueryController` constructor and the
client's defaulting accept. The infinite side mirrors it:
`InfiniteQueryObserverOptions<TPageData, TPageParam>` (data is
`InfiniteData<TPageData, TPageParam>`) and
`InfiniteQuerySelectOptions<TPageData, TPageParam, TData>` over
`InfiniteQueryObserverOptionsBase`. The four plain call styles take the
one-slot type, the four select styles the two-slot one; the infinite entry
points take the base and let inference read both slots off the options. A
debug-only backstop in the binding's controllers refuses a top-typed `TData`
(`dynamic`, `Object?`) with a message naming the cure, for the one residue no
shape removes — a key-only options object with neither `queryFn` nor a type
argument.

## Considered options

1. **This** — one slot plain, two slots with `select` required. The only
   variant whose failure mode is a compile error under every lint set; the
   split already existed in the widgets (`QueryBuilder` / `QuerySelectBuilder`)
   and on the mutation side (`MutationOptions.simple`); one `<Task, Task>`
   becomes `<Task>` everywhere.
2. **Two slots kept, a static `.simple<T>` factory.** The public constructor
   keeps the trap (`<int, dynamic>`), and a static cannot be `const`.
3. **Two slots kept, a runtime guard.** Detects in debug only, compiled out of
   release; misses `Object?`, which a future Dart may infer instead of
   `dynamic`. Kept only as the backstop above, not as the answer.
4. **Tolerate `Query<dynamic>` by casting on read.** Hides the erasure the
   typed cache was built to expose (map #1's generics decision). Rejected.

## Consequences

- Breaking for every options literal and every explicit `<X, X>` — done now,
  before anything is published; impossible after the 0.1.0 tag.
- A `select` that keeps the type (`List<Task>` → `List<Task>`) is still a
  select and goes through the select entry points.
- `SelectFn<TQueryData, TData>` is the typedef for `select`; the mutation
  callback typedefs are the API-shape ticket's.
- Recommend `analyzer: language: strict-inference: true` to consumers once in
  the docs; a package cannot enable it for its dependents.
