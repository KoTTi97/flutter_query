/// Port of `replaceEqualDeep` from `query-core/src/utils.ts` at upstream
/// `50680b98c`.
library;

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

  if (previous is List && next is List) {
    final previousLength = previous.length;
    final nextLength = next.length;
    // `toList` on the incoming list keeps its runtime element type, which a
    // `List<Object?>` built here would not.
    final copy = next.toList();
    var equalItems = 0;
    for (var i = 0; i < nextLength; i++) {
      final nextItem = next[i];
      if (i < previousLength) {
        final previousItem = previous[i];
        final shared =
            replaceEqualDeep<Object?>(previousItem, nextItem, depth + 1);
        copy[i] = shared;
        if (identical(shared, previousItem)) {
          equalItems++;
        }
      }
    }
    if (previousLength == nextLength && equalItems == previousLength) {
      return previous as T;
    }
    return copy as T;
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

bool _equalDeep(Object? a, Object? b, int depth) =>
    identical(replaceEqualDeep<Object?>(a, b, depth + 1), a);

bool _mapsEqualDeep(
    Map<Object?, Object?> a, Map<Object?, Object?> b, int depth) {
  if (a.length != b.length) {
    return false;
  }
  for (final entry in b.entries) {
    if (!a.containsKey(entry.key) ||
        !_equalDeep(a[entry.key], entry.value, depth)) {
      return false;
    }
  }
  return true;
}

bool _setsEqualDeep(Set<Object?> a, Set<Object?> b, int depth) {
  if (a.length != b.length) {
    return false;
  }
  for (final element in b) {
    if (!a.any((other) => _equalDeep(other, element, depth))) {
      return false;
    }
  }
  return true;
}
