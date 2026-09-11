// What the barrel hides, asserted rather than assumed: the ninth review's
// API decisions (C21, C23, C24) changed the list
// (https://github.com/KoTTi97/flutter_query/issues/43). Dart offers no
// runtime view of an export's combinators without `dart:mirrors`, which the
// Flutter-bundled SDK does not ship, so the source is read; the positive
// half — every name a consumer may write — is the import below compiling
// on every platform.
@TestOn('vm')
library;

import 'dart:io';

import 'package:query_kit/query_kit.dart';
import 'package:test/test.dart';

void main() {
  final barrel = File('lib/query_kit.dart').readAsStringSync();

  /// The `hide` list of the barrel's export of `src/<file>.dart`.
  Set<String> hidden(String file) {
    final export = RegExp("export 'src/$file.dart'(?:\\s+hide\\s+([^;]+))?;")
        .firstMatch(barrel);
    expect(export, isNotNull, reason: 'src/$file.dart is exported');
    final list = export!.group(1);
    return list == null
        ? const {}
        : list.split(',').map((name) => name.trim()).toSet();
  }

  test('C23.6 FetchBehavior and FetchContext are exported, the cache refs not',
      () {
    expect(hidden('query'), {'QueryCacheRef'});
    expect(hidden('mutation'), {'MutationCacheRef'});
    // Nameable through the barrel: the type of `QueryOptions.behavior`.
    expect(<Type>[FetchBehavior, FetchContext], hasLength(2));
  });

  test('C24 the observer-internal paging aliases are hidden', () {
    expect(hidden('infinite_query_observer'),
        {'hasNextPageOf', 'hasPreviousPageOf'});
  });

  test('the paging plumbing and the toString helper stay hidden', () {
    expect(hidden('infinite_query'), {
      'InfiniteQueryBehavior',
      'addToEnd',
      'addToStart',
      'hasNextPage',
      'hasPreviousPage',
      'nextPageParam',
      'previousPageParam',
    });
    expect(hidden('filters'), {'describeFilters'});
  });
}
