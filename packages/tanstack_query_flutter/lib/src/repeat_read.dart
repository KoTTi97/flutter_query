/// The debug check `context.query` and `QueryMixin` share for one identity
/// read twice in one build.
library;

import 'package:flutter/foundation.dart';
import 'package:tanstack_query_core/tanstack_query_core.dart';

/// One widget reading one identity twice in one build with options that
/// produce different results — two `select`s of the same output type on one
/// key, without `id` — would flip the observer between them on every build,
/// and each flip notifies, so the widget rebuilds forever. Caught where it
/// happens: the same observer cannot yield two results in one synchronous
/// build unless its options changed between the reads.
///
/// With one exception, which is why the comparison masks `isStale`: it is
/// read from the clock, and two reads a millisecond apart can straddle the
/// moment the data goes stale. That flip notifies nobody (the observer's own
/// stale timer does), so it is no loop, and must not be reported as one
/// (fourth review, 2026-09-09).
///
/// [who] names the reader in the message: "This widget", "This State".
void debugCheckRepeatRead(
  bool repeat,
  QueryResult<Object?>? before,
  QueryResult<Object?> after,
  Object identity,
  String who,
) {
  assert(() {
    if (repeat && before != null && !_sameButForStaleness(before, after)) {
      throw FlutterError(
        '$who read the query $identity twice in one build with options that '
        'produce different results — most likely two different `select`s of '
        'the same output type. Give each read its own `id:` so they get '
        'observers of their own.',
      );
    }
    return true;
  }());
}

/// `QueryResult ==` without `isStale`. Field by field because the result has
/// no `copyWith`; a field added to the result later is simply not compared
/// here, which errs on the side of not throwing.
bool _sameButForStaleness(QueryResult<Object?> a, QueryResult<Object?> b) =>
    identical(a, b) ||
    a.runtimeType == b.runtimeType &&
        a.fetchStatus == b.fetchStatus &&
        a.dataUpdatedAt == b.dataUpdatedAt &&
        a.errorUpdatedAt == b.errorUpdatedAt &&
        a.failureCount == b.failureCount &&
        a.failureReason == b.failureReason &&
        a.errorUpdateCount == b.errorUpdateCount &&
        a.isEnabled == b.isEnabled &&
        a.isFetched == b.isFetched &&
        a.isFetchedAfterMount == b.isFetchedAfterMount &&
        a.isPlaceholderData == b.isPlaceholderData &&
        a.dataOrNull == b.dataOrNull &&
        a.errorOrNull == b.errorOrNull;
