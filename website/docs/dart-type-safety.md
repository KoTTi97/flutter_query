---
title: Type safety in Dart
description: Sealed results, one key one exact type, two options shapes, and the analyzer setting that catches the one literal inference cannot type.
---

{/* depth: todo */}
{/* demo: diagnostics */}

# Type safety in Dart

The port follows TanStack Query's behaviour, not its TypeScript tricks. Dart's
type system is sound and has sealed classes, and the API leans on both. What
you feel at the call site:

## The result is sealed

A query result is one of `QueryPending`, `QuerySuccess` or `QueryError`. A
`switch` over it is exhaustive, so the compiler tells you when a state is not
handled, and the data is a non-nullable field of `QuerySuccess` — no `data!`.
`QueryError` carries `staleData`, the last good value, for a refetch that
failed with data already on screen. See [queries](guides/queries.md).

A mutation result is sealed the same way: `MutationIdle`, `MutationPending`,
`MutationSuccess`, `MutationError`.

## Two type parameters, not five

- `Query<TQueryData>` at the cache layer, `QueryObserver<TQueryData, TData>`
  where a `select` needs a second.
- There is no `TError`: errors are an `Object` plus a `StackTrace`, as
  everywhere in Dart.
- There is no `TQueryKey`: a `QueryKey` is a value type, deep-frozen and
  compared by value. See [query keys](guides/query-keys.md).

## Two options shapes

Observer options come in two shapes: `QueryObserverOptions<TData>`, with no
`select` and one type argument, and `QuerySelectOptions<TQueryData, TData>`,
with `select` required. The required `select` is what anchors the second type,
so neither shape has a type argument inference cannot fill. See [describing a
query once](guides/query-options.md).

## The one literal inference cannot type

A key-only options literal — neither a `queryFn` nor a type argument, relying
on a cached entry or a [default query function](guides/default-query-function.md)
— has nothing to infer its data type from, and Dart would silently make it
`dynamic`. Two things catch it:

- the binding's controllers refuse it in debug builds, with a message naming
  the cure;
- the analyzer reports it at the literal once `analysis_options.yaml` asks
  for strict inference. Recommended:

```yaml
analyzer:
  language:
    strict-inference: true
```

The cure is an explicit type argument: `QueryObserverOptions<Task>(queryKey:
…)`.

## One key, one exact type

A key is bound to the data type it was first used with, and reading it as any
other type throws `QueryDataTypeError` — **related types included**. `int` and
`int?` are two types. So are `List<Task>` and `List<Object?>`.

TanStack Query casts blindly, and TypeScript cannot tell. Here
`getQueryData<T>`, `getQueriesData<T>` and an observer's `TQueryData` all have
to agree with the key's first use. It is the single most likely thing to catch
you out when porting JavaScript, and it is catching a real bug.

A **write** is the one place a related type is welcome. `setQueryData` infers
its type from the value (and so do `updateQueryData` and `updateQueriesData`
from the updater), so an entry that already exists takes any value its own
type can hold — a `String` into a `String?` query, a sealed type's variant
into a query of the sealed type — and keeps its type. Name the type when the
write *creates* the entry, as when seeding a key before its query exists:
`setQueryData<List<Task>>(key, [])`.

When one key prefix spans entries of different types, give each type its own
key, or store a wrapper type that says what the entry is. See
[troubleshooting](reference/troubleshooting.md#querydatatypeerror-for-a-list-that-is-the-right-type).

## Sealed values instead of magic numbers

`null` means "not configured" on every option field. An option with modes is
a sealed value type — `StaleTime`, `GcTime`, `Enabled`, `RetryPolicy`,
`RetryDelay`, `RefetchOn`, `RefetchInterval` — never a magic number, string
or boolean. `staleTime: 0`, `staleTime: Infinity` and `staleTime: 'static'`
are three ideas JavaScript squeezes into one field; here they are three
constructors of one sealed class, and a `switch` over them is exhaustive. See
[describing a query once](guides/query-options.md#two-rules) for the
computed forms.

## Cancellation and time

- **Cancellation is `QueryCancelToken.onCancel`**, because Dart has no
  ecosystem-wide cancellation primitive. See [query
  cancellation](guides/query-cancellation.md).
- **Time goes through `package:clock`**, so fake time in tests controls
  staleness and garbage collection completely. See
  [testing](guides/testing.md).
