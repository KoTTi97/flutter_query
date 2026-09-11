/// The Flutter binding for `query_kit`.
///
/// An independent community port: not affiliated with or endorsed by TanStack.
///
/// Four equal ways to reach a query, none of which needs a package beyond
/// Flutter (https://github.com/KoTTi97/flutter_query/issues/21):
///
/// * [QueryController] / [InfiniteQueryController] / [MutationController] — a
///   `ValueListenable`, the foundation the other three stand on, and what
///   makes signals, provider, riverpod and bloc integration free.
/// * [QueryBuilder] / [InfiniteQueryBuilder] / [MutationBuilder] — the
///   `StreamBuilder` shape.
/// * [QueryMixin] — `watchQuery(...)` straight in `build`.
/// * `context.query(...)` — the same, in a `StatelessWidget`, rebuilding only
///   the widgets that read that query.
///
/// The core's whole surface is re-exported, so one import is enough.
library;

export 'package:query_kit/query_kit.dart';

export 'src/mutation_state_controller.dart';
export 'src/queries_builder.dart';
export 'src/queries_controller.dart';
export 'src/query_builder.dart';
export 'src/query_client_provider.dart';
export 'src/query_context.dart' hide QueryScope, QueryScopeElement;
export 'src/query_controller.dart' hide ObservedState, observedStateOf;
export 'src/query_listener.dart';
export 'src/query_mixin.dart';
