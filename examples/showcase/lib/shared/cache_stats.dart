/// Counts what the cache does, from the moment the app starts.
///
/// A screen's debug strip cannot count fetches itself: it is built *after*
/// the query it watches was started by the same build, so the first fetch
/// action is gone before the strip subscribes. This listener is created with
/// the client, before any screen exists, and the strips read it.
library;

import 'package:flutter/foundation.dart';
import 'package:tanstack_query_flutter/tanstack_query_flutter.dart';

class CacheStats extends ChangeNotifier {
  CacheStats(this.client) {
    _unsubscribe = client.queryCache.subscribe(_onEvent);
  }

  final QueryClient client;
  late final void Function() _unsubscribe;
  final Map<QueryKey, int> _fetches = <QueryKey, int>{};

  /// How many fetches the entry under [key] has started since the app began —
  /// refetches, retries after a cancel, page fetches alike.
  int fetchesOf(QueryKey key) => _fetches[key] ?? 0;

  void _onEvent(QueryCacheEvent event) {
    if (event is QueryUpdated && event.action is QueryFetchAction) {
      _fetches.update(event.query.queryKey, (count) => count + 1,
          ifAbsent: () => 1);
    }
    // Every event, not only the counted ones: a strip rebuilds on any of
    // them and reads the rest of its facts live from the cache.
    notifyListeners();
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }
}
