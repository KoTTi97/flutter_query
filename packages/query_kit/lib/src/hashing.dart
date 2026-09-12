/// Hash spreading shared by the key and the sharing walk. Not exported.
library;

import 'package:meta/meta.dart';

/// [hash] with its high bits folded into its low ones.
///
/// Dart's composite hashes (`Object.hash`, `Object.hashAll`,
/// `Object.hashAllUnordered`) combine through a 29-bit mask, and a hash map
/// spreads its keys by their low bits, so a hash whose variation sits in its
/// high bits collapses in both. A fractional `double` on the VM is one: `0.5`
/// hashes to `0x3fe000003fe00000`, and 10 000 keys `['price', i + 0.5]` shared
/// 396 hash codes — every `setQueryData` and lookup on such a key scanned a
/// long chain, 1.7 s for 50 000 of them (round-3 reviews, R3-1 and its nested
/// follow-up). The shifts do not align with a value's two 32-bit halves, so
/// the halves cannot cancel. A function of [hash] alone: two values with equal
/// hash codes still spread to equal results, which is all `==` needs.
@internal
int spreadHash(int hash) =>
    (hash ^ (hash >> 7) ^ (hash >> 17) ^ (hash >> 37)) & 0x3fffffff;
