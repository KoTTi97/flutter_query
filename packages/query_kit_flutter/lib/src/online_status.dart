/// The connectivity a `QueryClientProvider` brings, as one value. See
/// [OnlineStatus].
library;

import 'package:flutter/foundation.dart';

/// What the client should believe about the network, and where later changes
/// come from. Passed as `QueryClientProvider.onlineStatus`.
///
/// Connectivity is opt-in: nothing is installed by default, no connectivity
/// package is a dependency of this one, and a client with no [OnlineStatus]
/// assumes it is online. While the client believes it is offline, queries
/// and mutations with the default network mode pause instead of failing,
/// and continue when it is back online.
///
/// Two modes, and both of them answer "what is true *now*":
///
/// * [OnlineStatus.fixed] — this is the state, and it stays that way until a
///   rebuild says otherwise or something calls `onlineManager.setOnline`.
///   For a client that has no connectivity source: a test, a desktop build, a
///   developer's offline switch.
/// * [OnlineStatus.stream] — [OnlineStatusStream.changes] reports every later
///   change, and [OnlineStatusStream.initial] is what to assume until the
///   first event arrives — not applied at all when that event arrives while
///   the provider listens, as a synchronous controller's `onListen` can
///   deliver it. `initial` is required because a `Stream` has no
///   current value: a provider that only listens starts out believing the
///   default — online — however long the first event takes, and an app
///   launched in airplane mode then fetches once against a network that is
///   not there. Most connectivity packages answer the question directly.
///
/// An example with the `connectivity_plus` package. It is *not* a dependency
/// of this package — add it to your own app to use this:
///
/// ```dart
/// // Requires `connectivity_plus` in your app's pubspec.
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   final connectivity = Connectivity();
///   bool isOnline(List<ConnectivityResult> results) =>
///       !results.contains(ConnectivityResult.none);
///
///   // Built once, outside `build`: a new stream on every rebuild would be
///   // listened to again each time.
///   final changes = connectivity.onConnectivityChanged.map(isOnline);
///   final online = isOnline(await connectivity.checkConnectivity());
///
///   runApp(
///     QueryClientProvider.create(
///       create: QueryClient.new,
///       onlineStatus: OnlineStatus.stream(changes, initial: online),
///       child: const MyApp(),
///     ),
///   );
/// }
/// ```
///
/// A link is not reachability: a phone on a captive-portal wifi reports
/// "connected". Any `Stream<bool>` works — your own reachability check
/// included.
///
/// Passing `null` as the provider's `onlineStatus` is the way to say "bring
/// nothing".
///
/// {@category Connectivity & lifecycle}
@immutable
sealed class OnlineStatus {
  const OnlineStatus();

  /// The client is [online], with no source of later changes.
  ///
  /// ```dart
  /// // A developer's offline switch, applied on every rebuild:
  /// QueryClientProvider(
  ///   client: client,
  ///   onlineStatus: OnlineStatus.fixed(!simulateOffline),
  ///   child: const MyApp(),
  /// );
  /// ```
  const factory OnlineStatus.fixed(bool online) = OnlineStatusFixed;

  /// The client follows [changes], and assumes [initial] until the first
  /// event arrives. See the class doc for an example.
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
///
/// Usually written as `OnlineStatus.fixed(online)`; the class is public so a
/// `switch` over an [OnlineStatus] can name it.
///
/// {@category Connectivity & lifecycle}
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
///
/// Usually written as `OnlineStatus.stream(changes, initial: …)`; the class
/// is public so a `switch` over an [OnlineStatus] can name it.
///
/// {@category Connectivity & lifecycle}
final class OnlineStatusStream extends OnlineStatus {
  /// Follows [changes] from [initial].
  const OnlineStatusStream(this.changes, {required this.initial});

  /// Every later change. A broadcast stream always works. A
  /// single-subscription one works as long as exactly one provider listens
  /// to it exactly once: a provider keeps its one subscription across
  /// rebuilds and client switches, but a provider remounted with the same
  /// status, two providers given it, or one switched away from it and back
  /// each listen again — and a second `listen` fails with a `FlutterError`
  /// that says so. When in doubt, pass `stream.asBroadcastStream()`.
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
