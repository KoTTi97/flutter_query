/// The cache's identity type, [QueryKey].
library;

import 'package:meta/meta.dart';

import 'hashing.dart';

/// An immutable, structurally compared cache key: what identifies a query
/// in the cache.
///
/// Two options objects with equal keys address the same cache entry, so a
/// key must describe everything the query function's result depends on —
/// a list key and a detail key per id, a filter object as part of the key.
///
/// ```dart
/// QueryKey(['tasks']);
/// QueryKey(['tasks', id]);
/// QueryKey(['tasks', {'status': 'active', 'project': 'website'}]);
///
/// final tasks = QueryKey(['tasks']);
/// final task = tasks.append([id]);          // QueryKey(['tasks', id])
/// task.matches(tasks);                      // true: a prefix matches
/// client.invalidateQueries(filters: QueryFilters(queryKey: tasks));
/// ```
///
/// Filters such as `QueryFilters.queryKey` match by prefix ([matches]), so a
/// hierarchical key — the most general part first — lets one call
/// invalidate a whole family of queries.
///
/// Unlike TanStack Query, which hashes keys to a JSON string because
/// JavaScript has no structural equality, a key here is a value type with
/// `==` and `hashCode`, and the cache is keyed by it directly.
///
/// Parts are deep-copied into unmodifiable collections at construction, so a
/// list or map you keep a reference to cannot later corrupt the cache.
///
/// Every part must have value equality: primitives, [String], [DateTime],
/// [Duration], enums, collections of those, and user types that implement
/// `==`/`hashCode` (freezed, Equatable, or written by hand). A debug-only
/// assertion rejects parts that use identity equality, because such a key can
/// never match a second, equal key.
/// User objects are retained, not cloned: their equality and hash values must
/// remain immutable for the key's lifetime. Collection graphs must be acyclic;
/// cyclic input is unsupported. Map keys must also have stable value equality.
///
/// Parts compare with `==`, and `1 == 1.0` holds in Dart on every platform,
/// so `QueryKey([1])` and `QueryKey([1.0])` are the same key — not a web
/// quirk.
///
/// Two [DateTime] parts compare by instant: a UTC and a local `DateTime` of
/// the same moment are one key, as they are in TanStack Query, whose JSON
/// hash writes both as the same ISO string (Dart's own `DateTime.==` also
/// compares the time zone flag). The parts keep what was passed; the entry
/// keeps the key it was created with. This holds only for parts — a
/// `DateTime` used as a *map key* inside a part is looked up with its own
/// `==`.
///
/// **What the debug assertion cannot see.** It looks at `hashCode`, so it
/// passes two kinds of part that never match a second, equal-looking key:
///
/// * A record is a leaf, compared with the record's own `==`, and that
///   compares each field with *its* `==` — a `List`, `Set` or `Map` field by
///   identity. `QueryKey([(id, [1, 2])])` is therefore never equal to another
///   key built the same way: every lookup misses and every build creates a
///   new entry. Dart cannot walk a record's fields generically, so this is
///   not checked. Keep collections out of records in keys — put them as parts
///   of their own, or in a map part: `QueryKey([id, {'channels': [1, 2]}])`.
/// * A class that overrides `hashCode` but not `==`.
///
/// A map part's keys must have value equality too, and are held to the same
/// test as a part, with one addition: a collection as a map key is refused,
/// because a map part is compared by looking its keys up, and a collection
/// key hashes by identity.
///
/// {@category Queries}
@immutable
final class QueryKey {
  /// A key of [parts], each list, set and map in them deep-copied into an
  /// unmodifiable one. In debug builds, asserts that every part has value
  /// equality.
  QueryKey(List<Object?> parts)
      : parts = List<Object?>.unmodifiable(parts.map<Object?>(_freeze)) {
    assert(
      _debugCheckParts(this.parts),
      'A QueryKey part uses identity equality, or a map in it has a collection '
      'as a key, so this key can never match an equal key: $this. Give the '
      'type value equality (freezed, Equatable, or a hand-written '
      '==/hashCode), put a primitive in the key instead, or key the map by a '
      'value rather than a collection.',
    );
  }

  /// The key's parts, with nested collections copied into unmodifiable ones.
  /// User objects remain responsible for their own immutability.
  final List<Object?> parts;

  /// A key with [more] appended — the idiom for deriving a detail key from a
  /// list key.
  QueryKey append(List<Object?> more) => QueryKey(<Object?>[...parts, ...more]);

  /// Whether [filter] matches this key.
  ///
  /// With `exact: false` (the default) the filter is a prefix, and any map
  /// inside it needs only the entries it names (TanStack Query's
  /// `partialMatchKey`). `QueryKey(['tasks'])` matches
  /// `QueryKey(['tasks', 3])`, and
  /// `QueryKey(['tasks', {'project': 'website'}])` matches a key whose map
  /// also carries a `'status'` entry.
  bool matches(QueryKey filter, {bool exact = false}) =>
      exact ? this == filter : _partialMatch(parts, filter.parts);

  /// A canonical rendering with map keys sorted, for logs and debugging
  /// (the same shape as TanStack Query's `hashKey`). Not the key's identity:
  /// equality is structural, see the class doc.
  String get debugString => _describe(parts);

  @override
  String toString() => 'QueryKey($debugString)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryKey && _partsEqual(parts, other.parts);

  @override
  late final int hashCode = _hashPart(parts);
}

Object? _freeze(Object? part) {
  if (part is List) {
    return List<Object?>.unmodifiable(part.map<Object?>(_freeze));
  }
  if (part is Set) {
    return Set<Object?>.unmodifiable(part.map<Object?>(_freeze));
  }
  if (part is Map) {
    return Map<Object?, Object?>.unmodifiable(<Object?, Object?>{
      for (final entry in part.entries) entry.key: _freeze(entry.value),
    });
  }
  return part;
}

bool _partsEqual(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!_partsEqual(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  if (a is Set && b is Set) {
    if (a.length != b.length) {
      return false;
    }
    // The set's own equality first, in O(n): `==` implies parts-equal, and a
    // set holds no duplicates under its own equality, so the multisets below
    // agree whenever this does. A set of ids never goes further; counting
    // partners pairwise cost 120 ms for a 2 000-element part.
    if (a.containsAll(b)) {
      return true;
    }
    // As multisets, not "every element has *a* match": a frozen set holds
    // structurally equal lists as distinct members, so `{[1], [1], [2]}` and
    // `{[1], [2], [2]}` both pass the any-match test while hashing
    // differently. Consuming each partner once keeps `==` and `hashCode`
    // telling the same story, and bucketing by `_hashPart` — which is what
    // `hashCode` ties to `_partsEqual` — keeps it linear.
    final unmatched = <int, List<Object?>>{};
    for (final element in a) {
      (unmatched[_hashPart(element)] ??= <Object?>[]).add(element);
    }
    for (final element in b) {
      final bucket = unmatched[_hashPart(element)];
      if (bucket == null) {
        return false;
      }
      final partner = bucket.indexWhere((other) => _partsEqual(other, element));
      if (partner < 0) {
        return false;
      }
      bucket.removeAt(partner);
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key) ||
          !_partsEqual(entry.value, b[entry.key])) {
        return false;
      }
    }
    return true;
  }
  // By instant, as upstream's JSON hash compares an ISO string; `==` also
  // compares the zone flag. `DateTime.hashCode` already ignores the flag.
  if (a is DateTime && b is DateTime) {
    return a.isAtSameMomentAs(b);
  }
  return a == b;
}

int _hashPart(Object? part) {
  if (part is List) {
    return Object.hashAll(part.map<Object?>(_hashPart));
  }
  if (part is Set) {
    return Object.hashAllUnordered(part.map<Object?>(_hashPart));
  }
  if (part is Map) {
    return Object.hashAllUnordered(<Object?>[
      for (final entry in part.entries)
        Object.hash(spreadHash(entry.key.hashCode), _hashPart(entry.value)),
    ]);
  }
  return spreadHash(part.hashCode);
}

/// TanStack Query's `partialMatchKey`: every element of [filter] must
/// partially match the element at the same position (or under the same map
/// key) in [key].
bool _partialMatch(Object? key, Object? filter) {
  if (identical(key, filter)) {
    return true;
  }
  if (key is List && filter is List) {
    if (filter.length > key.length) {
      return false;
    }
    for (var i = 0; i < filter.length; i++) {
      if (!_partialMatch(key[i], filter[i])) {
        return false;
      }
    }
    return true;
  }
  if (key is Map && filter is Map) {
    for (final entry in filter.entries) {
      if (!key.containsKey(entry.key) ||
          !_partialMatch(key[entry.key], entry.value)) {
        return false;
      }
    }
    return true;
  }
  return _partsEqual(key, filter);
}

String _describe(Object? part) {
  if (part is List) {
    return '[${part.map(_describe).join(',')}]';
  }
  if (part is Set) {
    final described = part.map(_describe).toList()..sort();
    return '{${described.join(',')}}';
  }
  if (part is Map) {
    final entries = part.entries
        .map((e) => '${_describe(e.key)}:${_describe(e.value)}')
        .toList()
      ..sort();
    return '{${entries.join(',')}}';
  }
  if (part is String) {
    return '"$part"';
  }
  return '$part';
}

bool _debugCheckParts(Object? part) {
  if (part == null || part is num || part is String || part is bool) {
    return true;
  }
  if (part is List) {
    return part.every(_debugCheckParts);
  }
  if (part is Set) {
    return part.every(_debugCheckParts);
  }
  if (part is Map) {
    // A map is compared entry by entry through `b[key]`, which is a hash
    // lookup: a key that is itself a collection would never be found again.
    // Upstream cannot hit this — JSON object keys are strings. Any other map
    // key is held to the test a part is: a record or a value class keys a
    // map as well as a string does.
    return part.entries.every(
      (entry) =>
          entry.key is! List &&
          entry.key is! Set &&
          entry.key is! Map &&
          _debugCheckParts(entry.key) &&
          _debugCheckParts(entry.value),
    );
  }
  if (part is DateTime ||
      part is Duration ||
      part is Enum ||
      part is Type ||
      part is Record) {
    return true;
  }
  // Anything left that hashes by identity can never match an equal-but-distinct
  // instance, which is always a bug in a cache key.
  return part.hashCode != identityHashCode(part);
}
