import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Identifies a cache entry.
///
/// Upstream hashes keys to a string with `JSON.stringify` and sorted object
/// keys. Dart needs no such indirection: [QueryKey] has deep value equality, so
/// it works directly as a `Map` key. Map parts compare order-insensitively,
/// matching the sorted-key hash upstream produces.
///
/// Parts must be values with stable equality — primitives, [List]s and [Map]s
/// of those, or types with a correct `==`/`hashCode`. A part whose equality is
/// identity-based (most model classes without an `==` override) silently
/// produces a key that never matches an equal-looking one.
@immutable
final class QueryKey {
  const QueryKey(this.parts);

  /// The key's segments, ordered from most general to most specific.
  final List<Object?> parts;

  static const DeepCollectionEquality _equality = DeepCollectionEquality();

  /// Whether this key is a prefix of [other] — the port of upstream's
  /// `partialMatchKey`, and what makes `invalidateQueries(['sensors'])` reach
  /// every key beginning with `'sensors'`.
  ///
  /// A [Map] part matches when every entry it declares matches the
  /// corresponding entry in [other]; extra entries on [other]'s side are
  /// ignored. That is what lets a filter object match partially.
  bool isPrefixOf(QueryKey other) => _isPartialMatch(other.parts, parts);

  /// Whether [candidate] (from the query being tested) satisfies every
  /// constraint declared by [filter].
  static bool _isPartialMatch(Object? candidate, Object? filter) {
    if (_equality.equals(candidate, filter)) {
      return true;
    }

    if (candidate is List && filter is List) {
      if (filter.length > candidate.length) {
        return false;
      }
      for (var i = 0; i < filter.length; i++) {
        if (!_isPartialMatch(candidate[i], filter[i])) {
          return false;
        }
      }
      return true;
    }

    if (candidate is Map && filter is Map) {
      for (final entry in filter.entries) {
        if (!candidate.containsKey(entry.key)) {
          return false;
        }
        if (!_isPartialMatch(candidate[entry.key], entry.value)) {
          return false;
        }
      }
      return true;
    }

    return false;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryKey && _equality.equals(parts, other.parts);

  @override
  int get hashCode => _equality.hash(parts);

  @override
  String toString() => 'QueryKey$parts';
}
