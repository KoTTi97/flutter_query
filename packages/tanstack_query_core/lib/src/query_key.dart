/// The cache's identity type.
///
/// Ports the *semantics* of `hashKey` and `partialMatchKey` from
/// `query-core/src/utils.ts` at upstream `50680b98c`, but not their mechanism:
/// upstream hashes keys to a JSON string because JavaScript has no structural
/// equality, whereas here the key is a value type and the cache is keyed by it
/// directly. See https://github.com/KoTTi97/flutter_query/issues/8.
library;

import 'package:meta/meta.dart';

/// An immutable, structurally compared cache key.
///
/// ```dart
/// QueryKey(['sensors']);
/// QueryKey(['sensors', id]);
/// QueryKey(['sensors', {'status': 'active', 'room': 'kitchen'}]);
/// ```
///
/// Parts are deep-copied into unmodifiable collections at construction, so a
/// list or map you keep a reference to cannot later corrupt the cache.
///
/// Every part must have value equality: primitives, [String], [DateTime],
/// [Duration], enums, collections of those, and user types that implement
/// `==`/`hashCode` (freezed, Equatable, or written by hand). A debug-only
/// assertion rejects parts that use identity equality, because such a key can
/// never match a second, equal key.
@immutable
final class QueryKey {
  QueryKey(List<Object?> parts)
      : parts = List<Object?>.unmodifiable(parts.map<Object?>(_freeze)) {
    assert(
      _debugCheckParts(this.parts),
      'A QueryKey part uses identity equality, so this key can never match an '
      'equal key: $this. Give the type value equality (freezed, Equatable, or '
      'a hand-written ==/hashCode), or put a primitive in the key instead.',
    );
  }

  /// The key's parts, deeply unmodifiable.
  final List<Object?> parts;

  /// A key with [more] appended — the idiom for deriving a detail key from a
  /// list key.
  QueryKey append(List<Object?> more) => QueryKey(<Object?>[...parts, ...more]);

  /// Whether [filter] matches this key.
  ///
  /// With `exact: false` (the default) this is upstream's `partialMatchKey`:
  /// the filter is a prefix, and any map inside it needs only the entries it
  /// names. `QueryKey(['sensors'])` matches `QueryKey(['sensors', 3])`, and
  /// `QueryKey(['sensors', {'room': 'kitchen'}])` matches a key whose map also
  /// carries a `'status'` entry.
  bool matches(QueryKey filter, {bool exact = false}) =>
      exact ? this == filter : _partialMatch(parts, filter.parts);

  /// A canonical rendering with map keys sorted — upstream's `hashKey` output,
  /// kept as a debugging view rather than as the key's identity.
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
    return a.every((element) => b.any((other) => _partsEqual(element, other)));
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
        Object.hash(entry.key, _hashPart(entry.value)),
    ]);
  }
  return part.hashCode;
}

/// Upstream `partialMatchKey`: every element of [filter] must partially match
/// the element at the same position (or under the same map key) in [key].
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
    return part.entries.every(
      (entry) => _debugCheckParts(entry.key) && _debugCheckParts(entry.value),
    );
  }
  if (part is DateTime || part is Duration || part is Enum || part is Type) {
    return true;
  }
  // Anything left that hashes by identity can never match an equal-but-distinct
  // instance, which is always a bug in a cache key.
  return part.hashCode != identityHashCode(part);
}
