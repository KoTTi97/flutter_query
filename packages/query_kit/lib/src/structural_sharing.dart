/// Port of `replaceEqualDeep` from `query-core/src/utils.ts` at upstream
/// `50680b98c`.
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

// A cycle (infinite_query → query → here), which Dart allows; the
// alternative is a public sharing interface, which nobody has asked for.
import 'hashing.dart';
import 'infinite_query.dart';

/// Returns [previous] when [next] is deep-equal to it, and otherwise [next]
/// with every deep-equal part swapped for the instance [previous] already
/// held — upstream's default structural sharing, and the reason a refetch
/// that brings back the same data does not rebuild anything.
///
/// Upstream walks plain objects and arrays and compares everything else by
/// identity. Here a `List` is walked element by element, and a `Map` or `Set`
/// is shared as a whole when it is deep-equal; everything else is compared
/// with `==`, so a typed model takes part exactly as far as its own equality
/// goes: a class with value equality is shared, a class without one is
/// replaced. Maps are not rebuilt entry by entry because Dart cannot construct
/// a map of the same runtime type from inside a generic function, and a copy
/// typed `Map<Object?, Object?>` would not be the caller's `Map<String, int>`.
/// A list can be copied with `toList()`, which keeps its element type.
///
/// A set is compared as a multiset under this walk's own relation — never
/// under the set's equality policy, so a `SplayTreeSet` with a
/// case-insensitive comparator reports a member that changed case
/// (pre-release review, 2026-09-12, F1). The comparison asks the two sets for
/// nothing but their length and their members: no `lookup`, `contains` or
/// `containsAll`, whose answers are the set's policy and, for a `Set` a user
/// wrote, whatever that implementation does (pre-release review, round 3,
/// R2-1, R2-2, R2-4). Members are bucketed by a hash consistent with the walk,
/// so a set of 10 000 ids costs about 1.5 ms a write (review AR-01).
///
/// A map is still looked up by its own keys, so a map with a custom key
/// equality is compared under that policy: two maps whose keys differ only in
/// a way their own comparator ignores are shared, and the older key
/// representation is kept. Give such a map a custom `structuralSharing` hook
/// (or the opt-out `noStructuralSharing`) when the key representation
/// matters.
///
/// A [TypedData] list — `Uint8List`, `Float32List` and the rest — is a leaf,
/// as a `Uint8Array` is for upstream: compared with `==` (identity, for
/// those), never walked. `Uint8List.toList()` is a plain `List<int>`, so a
/// walked copy could not be handed back as the caller's type, and a
/// byte-by-byte walk of an image would cost more than the rebuild it saves
/// (fifth review, 2026-09-09).
///
/// Sharing is best effort and never a type error: a `previous` that is not a
/// [T] — `<num>[]` where a `List<double>` was asked for — is not returned as
/// one, and a shared element that does not fit the incoming list's element
/// type stays `next`'s.
///
/// An [InfiniteData] is walked like upstream's `{ pages, pageParams }` object:
/// each list is shared on its own, and the whole is `previous` when both come
/// back unchanged. Its `==` alone could not do that, because a page is
/// usually a `List` — equal only to itself (fourth review, 2026-09-09).
///
/// Decided on https://github.com/KoTTi97/flutter_query/issues/12 and revised
/// after the third review (2026-09-09): a `select` that returns a fresh list
/// every time used to notify — and rebuild — on every call.
T replaceEqualDeep<T>(Object? previous, T next, [int depth = 0]) {
  if (identical(previous, next)) {
    return next;
  }
  if (depth > 500) {
    return next;
  }

  if (previous is TypedData || next is TypedData) {
    return previous is T && previous == next ? previous : next;
  }

  if (previous is List && next is List) {
    final previousLength = previous.length;
    final nextLength = next.length;
    // `toList` on the incoming list keeps its runtime element type, which a
    // `List<Object?>` built here would not. Always a copy when not every
    // element is shared, as upstream's is; the ported suite pins that.
    final copy = next.toList();
    var equalItems = 0;
    Set<Type>? refused;
    for (var i = 0; i < nextLength; i++) {
      final nextItem = next[i];
      if (i < previousLength) {
        final previousItem = previous[i];
        final shared =
            replaceEqualDeep<Object?>(previousItem, nextItem, depth + 1);
        if (identical(shared, nextItem)) {
          // Nothing to store: the copy already holds `next`'s element. It is
          // still an equal one when both sides held the very same instance.
          if (identical(nextItem, previousItem)) {
            equalItems++;
          }
          continue;
        }
        // The copy has `next`'s element type and `shared` may be `previous`'s
        // element: `<int>[1]` against `<double>[1.0]` finds `1 == 1.0` and
        // would store an `int` in a `List<double>`. A part that does not fit
        // stays `next`'s, and does not count as equal. Whether it fits is a
        // property of its runtime type alone, so a type the list refused once
        // is not tried again: `<int>` against `<double>` used to throw and
        // catch one `TypeError` per element, 2 µs apiece (review AR-09).
        final type = shared.runtimeType;
        if (refused != null && refused.contains(type)) {
          continue;
        }
        try {
          copy[i] = shared;
        } on TypeError {
          (refused ??= <Type>{}).add(type);
          continue;
        }
        if (identical(shared, previousItem)) {
          equalItems++;
        }
      }
    }
    if (previousLength == nextLength &&
        equalItems == previousLength &&
        previous is T) {
      return previous as T;
    }
    // `next` is a `T`; its `toList()` usually is too, but a `T` narrower
    // than a plain growable list (an unmodifiable view, say) is not.
    return copy is T ? copy as T : next;
  }

  if (previous is InfiniteData && next is InfiniteData) {
    // Same runtime type, or the shared lists could not be handed back into
    // `next`'s page types.
    if (previous.runtimeType != next.runtimeType) {
      return next;
    }
    final pages =
        replaceEqualDeep<List<Object?>>(previous.pages, next.pages, depth + 1);
    final pageParams = replaceEqualDeep<List<Object?>>(
        previous.pageParams, next.pageParams, depth + 1);
    if (identical(pages, previous.pages) &&
        identical(pageParams, previous.pageParams) &&
        previous is T) {
      return previous as T;
    }
    // Built on `previous`, whose `copyWith` keeps a list handed back
    // unchanged (identity included) and copies a changed one into an
    // unmodifiable list — the cache never holds a growable page list
    // (ninth review, 2026-09-10, C20).
    return previous.copyWith(pages: pages, pageParams: pageParams) as T;
  }

  if (previous is Map && next is Map) {
    return previous is T && _mapsEqualDeep(previous, next, depth)
        ? previous as T
        : next;
  }

  if (previous is Set && next is Set) {
    return previous is T && _setsEqualDeep(previous, next, depth)
        ? previous as T
        : next;
  }

  // `is T` and not just `==`: `1 == 1.0` holds in Dart, and an `int` handed
  // back where a `double` was asked for would not be the caller's type.
  return previous is T && previous == next ? previous : next;
}

/// The comparison half of [replaceEqualDeep], for the branches that share a
/// value whole or not at all. Same walk, same depth limit, same leaf rule —
/// but no copies: comparing a nested list through the sharing walk allocated
/// a copy of it for nothing (fifth review, 2026-09-09).
bool _equalDeep(Object? a, Object? b, int depth) {
  if (identical(a, b)) {
    return true;
  }
  if (depth > 500) {
    return false;
  }
  if (a is TypedData || b is TypedData) {
    return a == b;
  }
  if (a is List && b is List) {
    final length = a.length;
    if (length != b.length) {
      return false;
    }
    for (var i = 0; i < length; i++) {
      if (!_equalDeep(a[i], b[i], depth + 1)) {
        return false;
      }
    }
    return true;
  }
  if (a is InfiniteData && b is InfiniteData) {
    return a.runtimeType == b.runtimeType &&
        _equalDeep(a.pages, b.pages, depth + 1) &&
        _equalDeep(a.pageParams, b.pageParams, depth + 1);
  }
  if (a is Map && b is Map) {
    return _mapsEqualDeep(a, b, depth);
  }
  if (a is Set && b is Set) {
    return _setsEqualDeep(a, b, depth);
  }
  return a == b;
}

bool _mapsEqualDeep(
    Map<Object?, Object?> a, Map<Object?, Object?> b, int depth) {
  if (a.length != b.length) {
    return false;
  }
  for (final entry in b.entries) {
    if (!a.containsKey(entry.key) ||
        !_equalDeep(a[entry.key], entry.value, depth + 1)) {
      return false;
    }
  }
  return true;
}

// As multisets, the way `QueryKey` compares sets: "every element of `b` has
// *a* deep-equal partner in `a`" called `{[1], [1], [2]}` and `{[1], [2],
// [2]}` equal, and the cache kept the old value (fifth review, 2026-09-09).
//
// Only `length` and iteration are asked of either set, and only `==` and
// `hashCode` of their members, through `_equalDeep` and `_hashDeep` — the
// contract the rest of the walk relies on. Two shortcuts through the set's own
// methods were tried and both broke: `a.containsAll(b)` answered with `a`'s
// equality policy, so a case-insensitive set kept a stale member (F1); a
// `lookup` round trip trusted `lookup` to return the stored member and not to
// throw, but dart2js's default set returns its argument for numbers, which
// called `{0.0, 1.0, 3.0}` equal to `{-0.0, 0.0, 1.0}` on the web, and
// `package:collection`'s `MapKeySet.lookup` throws (R2-1, R2-2). Correctness
// by construction beats correctness by argument on a path that failed twice.
//
// Bucketed by a hash consistent with the walk, so a partner is looked for
// only among the members that can be one. The unbucketed walk this replaced
// cost 100 ms for 10 000 ints and 10 s for 100 000, on every cache write
// (review AR-01).
//
// Elements that break `==`'s own contract — not transitive, or equal without
// hashing alike — and sets nested past the depth limit get this walk's answer,
// which is greedy there; nothing better is defined (round 3, R2-5).
bool _setsEqualDeep(Set<Object?> a, Set<Object?> b, int depth) {
  if (a.length != b.length) {
    return false;
  }
  final unmatched = <int, List<Object?>>{};
  for (final element in a) {
    (unmatched[sharingBucketOf(element, depth + 1)] ??= <Object?>[])
        .add(element);
  }
  for (final element in b) {
    final bucket = unmatched[sharingBucketOf(element, depth + 1)];
    if (bucket == null) {
      return false;
    }
    final partner =
        bucket.indexWhere((other) => _equalDeep(other, element, depth + 1));
    if (partner < 0) {
      return false;
    }
    bucket.removeAt(partner);
  }
  return true;
}

/// The bucket a member of a compared set goes into: [_hashDeep], mixed.
/// Hidden from the barrel; visible to the suite, which pins its spread (R3-1).
///
/// The map the walk buckets into spreads its keys by their low bits, and a
/// raw hash does not always vary there — on the VM a fractional `double`
/// hashes to a value whose low bits barely change (`0.5` is
/// `0x3fe000003fe00000`), so 10 000 half-integers fell into a few dozen
/// buckets and the walk went quadratic: 40 ms where a `Set<int>` of the same
/// size took 1.5 ms (round-3 review, R3-1). Mixing moves which bucket a value
/// lands in and nothing else; a partner is still accepted only by
/// [_equalDeep], so the answer is the same whatever the mix.
@visibleForTesting
int sharingBucketOf(Object? value, int depth) =>
    spreadHash(_hashDeep(value, depth));

/// A hash consistent with [_equalDeep]: two values the walk calls equal hash
/// alike. Leaves hash as themselves, which Dart's `==` contract already ties
/// to equality (`1` and `1.0` hash the same); a list hashes in order, a map
/// or set unordered, an [InfiniteData] as its two lists — the shapes the walk
/// compares. Past the depth limit the walk says "not equal", so any value is
/// consistent there.
int _hashDeep(Object? value, int depth) {
  if (depth > 500) {
    return 0;
  }
  if (value is TypedData) {
    return spreadHash(value.hashCode);
  }
  if (value is List) {
    return Object.hashAll(
        <int>[for (final element in value) _hashDeep(element, depth + 1)]);
  }
  if (value is InfiniteData) {
    return Object.hash(
      value.runtimeType,
      _hashDeep(value.pages, depth + 1),
      _hashDeep(value.pageParams, depth + 1),
    );
  }
  if (value is Map) {
    return Object.hashAllUnordered(<int>[
      for (final entry in value.entries)
        Object.hash(
            spreadHash(entry.key.hashCode), _hashDeep(entry.value, depth + 1)),
    ]);
  }
  if (value is Set) {
    return Object.hashAllUnordered(
        <int>[for (final element in value) _hashDeep(element, depth + 1)]);
  }
  return spreadHash(value.hashCode);
}
