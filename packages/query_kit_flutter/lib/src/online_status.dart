/// The connectivity a `QueryClientProvider` brings, as one value
/// (https://github.com/KoTTi97/flutter_query/issues/60).
library;

import 'package:flutter/foundation.dart';

/// What the client should believe about the network, and where later changes
/// come from.
///
/// Connectivity is opt-in: nothing is installed by default, no connectivity
/// package is a dependency of this one, and a client with no [OnlineStatus]
/// assumes it is online — which is what upstream does with no listener.
///
/// Two modes, and both of them answer "what is true *now*":
///
/// * [OnlineStatus.fixed] — this is the state, and it stays that way until a
///   rebuild says otherwise or something calls `onlineManager.setOnline`.
///   For a client that has no connectivity source: a test, a desktop build, a
///   developer's offline switch.
/// * [OnlineStatus.stream] — [OnlineStatusStream.changes] reports every later
///   change, and [OnlineStatusStream.initial] is what to assume until the
///   first event arrives. `initial` is required because a `Stream` has no
///   current value: a provider that only listens starts out believing the
///   default — online — however long the first event takes, and an app
///   launched in airplane mode then fetches once against a network that is
///   not there. Most connectivity packages answer the question directly
///   (`connectivity_plus`'s `checkConnectivity()`).
///
/// This is the shape every option with more than one mode has in this port —
/// a sealed value type rather than a pair of half-answers
/// (https://github.com/KoTTi97/flutter_query/issues/10), and `null` on the
/// option itself is the only way to say "bring nothing".
@immutable
sealed class OnlineStatus {
  const OnlineStatus();

  /// The client is [online], with no source of later changes.
  const factory OnlineStatus.fixed(bool online) = OnlineStatusFixed;

  /// The client follows [changes], and assumes [initial] until the first
  /// event arrives.
  const factory OnlineStatus.stream(
    Stream<bool> changes, {
    required bool initial,
  }) = OnlineStatusStream;

  /// What a client is told the moment it is given this status: the whole
  /// story for [OnlineStatus.fixed], the starting assumption for
  /// [OnlineStatus.stream].
  bool get initial;

  /// Later changes, or `null` when this status has no source of them.
  Stream<bool>? get changes;
}

/// The [OnlineStatus.fixed] variant: one value, no stream.
final class OnlineStatusFixed extends OnlineStatus {
  /// The client is [online].
  const OnlineStatusFixed(this.online);

  /// Whether the network counts as reachable.
  final bool online;

  @override
  bool get initial => online;

  @override
  Stream<bool>? get changes => null;

  @override
  bool operator ==(Object other) =>
      other is OnlineStatusFixed && other.online == online;
  @override
  int get hashCode => Object.hash(OnlineStatusFixed, online);
  @override
  String toString() => 'OnlineStatus.fixed($online)';
}

/// The [OnlineStatus.stream] variant: a starting assumption and a stream of
/// changes.
final class OnlineStatusStream extends OnlineStatus {
  /// Follows [changes] from [initial].
  const OnlineStatusStream(this.changes, {required this.initial});

  /// Every later change. Any `Stream<bool>` will do, single-subscription
  /// included: the provider subscribes once per stream object.
  @override
  final Stream<bool> changes;

  /// What to assume until [changes] has said anything.
  @override
  final bool initial;

  @override
  bool operator ==(Object other) =>
      other is OnlineStatusStream &&
      other.changes == changes &&
      other.initial == initial;
  @override
  int get hashCode => Object.hash(OnlineStatusStream, changes, initial);
  @override
  String toString() => 'OnlineStatus.stream($changes, initial: $initial)';
}
