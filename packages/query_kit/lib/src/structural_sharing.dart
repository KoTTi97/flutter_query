/// Port of `replaceEqualDeep` from `query-core/src/utils.ts` at upstream
/// `50680b98c`.
library;

import 'dart:typed_data';

// A cycle (infinite_query → query → here), which Dart allows; the
// alternative is a public sharing interface, which nobody has asked for.
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
    for (var i = 0; i < nextLength; i++) {
      final nextItem = next[i];
      if (i < previousLength) {
        final previousItem = previous[i];
        final shared =
            replaceEqualDeep<Object?>(previousItem, nextItem, depth + 1);
        // The copy has `next`'s element type and `shared` may be `previous`'s
        // element: `<int>[1]` against `<double>[1.0]` finds `1 == 1.0` and
        // would store an `int` in a `List<double>`. A part that does not fit
        // stays `next`'s, and does not count as equal.
        try {
          copy[i] = shared;
        } on TypeError {
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
// A set of structurally equal lists is exactly the case that reaches here —
// a set of value-equal members has no duplicates to miscount.
bool _setsEqualDeep(Set<Object?> a, Set<Object?> b, int depth) {
  if (a.length != b.length) {
    return false;
  }
  final unmatched = List<Object?>.of(a);
  for (final element in b) {
    final partner =
        unmatched.indexWhere((other) => _equalDeep(other, element, depth + 1));
    if (partner < 0) {
      return false;
    }
    unmatched.removeAt(partner);
  }
  return true;
}
