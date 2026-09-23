---
title: Structural sharing
description: A refetch that brings back equal data keeps the cached instances — what is shared, why a model needs ==, StructurallyShareable, and turning it off.
---

{/* demo: select-and-sharing */}

# Structural sharing

On by default, and it is what makes `select` and `buildWhen` worth having: if
a refetch brings back data equal to what is cached, the *same instances* are
kept, so `==` downstream stays true and nothing rebuilds unnecessarily.

Lists are shared element by element; maps and sets are kept whole when deeply
equal; everything else is compared with `==`. **A typed model therefore needs
`==` and `hashCode`** — without them every fetch produces a new value.

## A class of your own

**A class of your own is a leaf, including what is inside it.** A wrapper
around a list — `TaskList(items)`, the shape freezed suggests — is compared
with `==` and kept or replaced *whole*: when one task changes, all of them get
new instances. Nothing looks wrong, because `==` still holds; `identical` and
everything built on it is what goes. Hold the list itself in the cache, or let
the class take part by implementing `StructurallyShareable`:

```dart snippet="guides/structural-sharing.md#structurally-shareable"
@immutable
class TaskList implements StructurallyShareable<TaskList> {
  const TaskList(this.items);

  final List<Task> items;

  // Asked only when the two are not equal: keep every Task instance the
  // cache already holds, and replace the ones that changed.
  @override
  TaskList shareWith(TaskList previous) =>
      TaskList(replaceEqualDeep(previous.items, items));

  @override
  bool operator ==(Object other) =>
      other is TaskList && listEquals(other.items, items);

  @override
  int get hashCode => Object.hashAll(items);
}
```

Returning `previous` itself is right exactly when nothing changed. A class
without value equality is never `==` to its predecessor, even with the same
content, so the walk asks on every refetch, and handing `previous` back is the
only way it keeps its instance:

```dart snippet="guides/structural-sharing.md#share-with-previous"
// No value equality: two TaskFeeds are never ==, so the walk always asks.
class TaskFeed implements StructurallyShareable<TaskFeed> {
  TaskFeed(this.items);

  final List<Task> items;

  @override
  TaskFeed shareWith(TaskFeed previous) {
    final shared = replaceEqualDeep(previous.items, items);
    return identical(shared, previous.items) ? previous : TaskFeed(shared);
  }
}
```

Nothing checks the contract, in debug builds or release: for a class whose
`==` is not deep, the walk cannot tell a correct `previous` from a mistaken
one. So there are two ways to get `shareWith` wrong, both silent. Returning
`previous` — or anything not equal in content to `this` — when something did
change puts stale data in the cache. Returning an equal value that shares
nothing — a plain copy — is correct and useless: the saving is gone without a
sound. Measure it once: after a refetch that changed one element, the others
should be `identical` to what was there before, and after one that changed
nothing, the whole value should be. (A hook that throws is ignored, and the
incoming value kept.)

It is found wherever the walk goes — at the top, in a list, in an
`InfiniteData` page — so one implementation replaces a `structuralSharing`
hook on every query that holds the type.

## Maps, sealed lists and sets

"Kept whole" cuts both ways: a `Map<Id, Dto>` in which one entry changed is
replaced whole, and every entry's instance with it — Dart cannot rebuild a map
of your key and value types from inside the walk, as it can a list. If you
cache normalised by id and rely on instance identity, cache a list, or share
the map yourself in a `structuralSharing` hook.

A rebuilt list is growable only if the one that came in was. A list that
cannot grow — fixed-length or unmodifiable — is rebuilt as a **fixed-length**
list when a cached instance is swapped into it: keeping those instances is the
point of sharing, and Dart cannot build an unmodifiable list of your element
type from inside the walk. `add` and `remove` throw on it; `list[i] = x` does
not. When nothing is swapped in, your sealed list is stored as it came. If the
cache must hold a sealed list in every case, seal it in your own
`structuralSharing` hook, where the element type is known.

A set is compared by its members' `==` and `hashCode`, never by the
comparator or `equals:` it was built with, so a case-insensitive set still
reports `'Alpha'` becoming `'alpha'`. That costs about a millisecond and a half
a write for 10 000 members and roughly a frame for 100 000; for a set that
large, `noStructuralSharing()` skips the comparison.

## Turning it off

To turn it off — `structuralSharing: false` in TanStack Query:

```dart snippet="guides/structural-sharing.md#structural-sharing"
structuralSharing: noStructuralSharing(), // `false` in TanStack Query
```

That turns sharing off everywhere: for the cache write, for placeholder data
and for what `select` produces, so a selector that returns a fresh list every
time then counts as a change on every fetch.

A function of your own, `(previous, next) => …`, replaces the default for the
cache write and placeholder data only. It cannot be handed a selection —
it is typed for the query's data, and a selection can be another type — so
what `select` produces is still shared by the default comparison. That is
also true of `(_, next) => next`: it keeps every write, but it is not the
opt-out, and a selection over it stays shared. Use `noStructuralSharing()`
when you mean off.
