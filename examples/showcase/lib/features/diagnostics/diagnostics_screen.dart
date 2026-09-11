/// Port-specific: what the library throws, and when. Two errors upstream
/// does not have, because they guard what TypeScript checks at compile time
/// and JavaScript lets slide at run time:
///
/// * [QueryDataTypeError] — one key, one exact type. A read or write that
///   names a type other than the one the entry holds throws *synchronously*,
///   from the call itself — `getQueryData`, `setQueryData`, `getQueriesData`,
///   an observer's `setOptions` — rather than handing back a value that is
///   not what the caller asked for
///   (https://github.com/KoTTi97/flutter_query/issues/7). The error names
///   the key, the type asked for and the type held.
/// * [MissingMutationFunctionError] — a mutation run with no `mutationFn` and
///   no default registered for its key fails with it, as its error state, the
///   way upstream's "No mutationFn found" rejects. The message names the cure:
///   `QueryClient.setMutationDefaults`, and the same button here registers
///   one and the next run succeeds.
///
/// The counter (`GET /api/counter`) is the entry the typed reads are made
/// against, read through a `QueryBuilder<int>`; the function-less mutation is
/// a `context.mutation`.
///
/// Proofs (widget tests in `test/features/diagnostics_test.dart`, end-to-end
/// in `e2e/tests/diagnostics.spec.ts`): a read as `int` answers the cached
/// value and a read as `String` throws `QueryDataTypeError` naming `String`
/// and `int`; a write of a `String` throws the same and leaves the entry as it
/// was, `updates=1`; a mutation without a function ends in `status=error`
/// with `MissingMutationFunctionError` and sends nothing; and once a default
/// `mutationFn` is registered for its key the same mutation succeeds with
/// `data=1`, one `POST`.
library;

import 'package:flutter/material.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import '../../shared/api.dart';
import '../../shared/debug_strip.dart';
import '../../shared/feature.dart';
import '../../shared/feature_scaffold.dart';
import '../../shared/scope.dart';
import '../../shared/theme.dart';

const Feature diagnosticsFeature = Feature(
  id: 'diagnostics',
  title: 'Diagnostics',
  summary: 'What the library throws, and when: the wrong type, the missing '
      'function.',
);

/// The entry the typed reads are made against. This screen's own key.
QueryKey get diagnosticsCounterKey =>
    QueryKey(const <Object?>['diagnostics', 'counter']);

/// The function-less mutation's key — what `setMutationDefaults` addresses.
QueryKey get noFunctionKey =>
    QueryKey(const <Object?>['diagnostics', 'no-function']);

/// The counter, as an `int`: the one exact type the entry holds from then on.
QueryObserverOptions<int> counterQuery(ShowcaseApi api) =>
    QueryObserverOptions<int>(
      queryKey: diagnosticsCounterKey,
      queryFn: (context) => api.counter(signal: context.signal),
    );

/// A mutation with a key and no function. `retry: never` is a mutation's
/// default anyway, and the library forces it while the function is missing.
MutationOptions<int, int, void> noFunctionMutation() =>
    MutationOptions.simple<int, int>(mutationKey: noFunctionKey);

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  String _read = 'none';
  String _write = 'none';
  String _expected = 'none';
  String _actual = 'none';
  bool _defaultRegistered = false;

  /// A read that names the entry's own type: the value, or null if nothing
  /// is cached yet.
  void _readAsInt() {
    final value = QueryClientProvider.of(context)
        .getQueryData<int>(diagnosticsCounterKey);
    setState(() => _read = 'int $value');
  }

  /// A read that names another type. It throws before any future exists —
  /// from the call — so a plain `try` is where it is caught.
  void _readAsString() {
    final client = QueryClientProvider.of(context);
    try {
      final value = client.getQueryData<String>(diagnosticsCounterKey);
      setState(() => _read = 'String $value');
    } on QueryDataTypeError catch (error) {
      setState(() {
        _read = 'QueryDataTypeError';
        _expected = '${error.expected}';
        _actual = '${error.actual}';
      });
    }
  }

  /// A write of another type: refused the same way, and the entry is left
  /// exactly as it was.
  void _writeString() {
    final client = QueryClientProvider.of(context);
    try {
      client.setQueryData<String>(diagnosticsCounterKey, 'not a number');
      setState(() => _write = 'String written');
    } on QueryDataTypeError catch (error) {
      setState(() {
        _write = 'QueryDataTypeError';
        _expected = '${error.expected}';
        _actual = '${error.actual}';
      });
    }
  }

  /// The cure the error message names: a default for every mutation under
  /// the key. The observer re-applies its options on the rebuild, and the
  /// default fills the function in.
  void _registerDefault() {
    final api = ShowcaseScope.apiOf(context);
    QueryClientProvider.of(context).setMutationDefaults(
      noFunctionKey,
      MutationDefaults(
        mutationFn: (variables) => api.increment(by: variables! as int),
      ),
    );
    setState(() => _defaultRegistered = true);
  }

  @override
  Widget build(BuildContext context) {
    final api = ShowcaseScope.apiOf(context);
    return FeatureScaffold(
      feature: diagnosticsFeature,
      children: <Widget>[
        SectionCard(
          title: 'One key, one type',
          trailing: QueryBuilder<int>(
            options: counterQuery(api),
            builder: (context, counter) => Text(
              switch (counter) {
                QueryPending() => 'counter=…',
                QueryError(staleData: null) => 'counter=error',
                QuerySuccess(:final data) ||
                QueryError(staleData: final data!) =>
                  'counter=$data',
              },
              style: _mono,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'The entry holds an int, fetched by the builder up here. A '
                'read or write that names another type throws '
                'QueryDataTypeError from the call itself — synchronously, '
                'before any future exists — instead of handing back '
                'something that is not what was asked for. The error names '
                'the key, the type asked for and the type held.',
              ),
              const SizedBox(height: 12),
              _Toolbar(
                children: <Widget>[
                  _Action(label: 'Read as int', onPressed: _readAsInt),
                  _Action(label: 'Read as String', onPressed: _readAsString),
                  _Action(label: 'Write a String', onPressed: _writeString),
                ],
              ),
              const SizedBox(height: 8),
              _Facts(
                <String>[
                  'read=$_read',
                  'write=$_write',
                  'expected=$_expected',
                  'actual=$_actual',
                ],
                label: 'typed',
              ),
            ],
          ),
        ),
        QueryDebugStrip(queryKey: diagnosticsCounterKey, label: 'counter'),
        SectionCard(
          title: 'A mutation without a function',
          child: _NoFunctionCard(
            defaultRegistered: _defaultRegistered,
            onRegisterDefault: _registerDefault,
          ),
        ),
      ],
    );
  }
}

const TextStyle _mono = TextStyle(fontFamily: 'monospace', fontSize: 13);

/// The error's name by an `is` check, not `runtimeType`: a web build
/// minifies type names, and the fact is read as an exact text.
String _nameOf(Object error) => switch (error) {
      MissingMutationFunctionError() => 'MissingMutationFunctionError',
      QueryDataTypeError() => 'QueryDataTypeError',
      _ => 'other',
    };

/// Its own widget so `context.mutation` re-applies its options on the
/// rebuild that follows the default being registered — which is when the
/// default fills the function in.
class _NoFunctionCard extends StatelessWidget {
  const _NoFunctionCard({
    required this.defaultRegistered,
    required this.onRegisterDefault,
  });

  final bool defaultRegistered;
  final VoidCallback onRegisterDefault;

  @override
  Widget build(BuildContext context) {
    final mutation = context.mutation(noFunctionMutation());
    final result = mutation.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'MutationOptions.simple(mutationKey: …) and nothing else: no '
          'mutationFn, and no default registered for the key. Running it '
          'fails with MissingMutationFunctionError as the mutation\'s error '
          'state — nothing is sent — and the message names the cure. '
          'Register a default mutationFn for the key, and the same mutation '
          'runs it.',
        ),
        const SizedBox(height: 12),
        _Toolbar(
          children: <Widget>[
            _Action(
              label: 'Mutate without a function',
              filled: true,
              onPressed: () => mutation.mutate(1),
            ),
            _Action(
              label: 'Register a default mutationFn',
              onPressed: defaultRegistered ? null : onRegisterDefault,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _Facts(
          <String>[
            'status=${result.status.name}',
            if (result case MutationError(:final error))
              'error=${_nameOf(error)}',
            if (result case MutationSuccess(:final data)) 'data=$data',
            'default=${defaultRegistered ? 'registered' : 'none'}',
          ],
          label: 'no-function',
        ),
        if (result case MutationError(:final error)) ...<Widget>[
          const SizedBox(height: 8),
          Notice('$error', error: true),
        ],
      ],
    );
  }
}

/// A row of buttons, each its own semantics node.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        explicitChildNodes: true,
        child: Wrap(spacing: 8, runSpacing: 8, children: children),
      );
}

/// A button named by its label; the tooltip stays out of the semantics tree.
class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: filled
            ? FilledButton.tonal(onPressed: onPressed, child: Text(label))
            : OutlinedButton(onPressed: onPressed, child: Text(label)),
      );
}

/// `key=value` texts, one node each, in a group a test can address — the
/// strip says `status=success` about the query, these about the calls.
class _Facts extends StatelessWidget {
  const _Facts(this.facts, {required this.label});

  final List<String> facts;

  /// The semantics group is `facts <label>`, the widget key `facts-<label>`.
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'facts $label',
        child: Wrap(
          key: ValueKey<String>('facts-$label'),
          spacing: 12,
          runSpacing: 4,
          children: <Widget>[
            for (final fact in facts) Text(fact, style: _mono),
          ],
        ),
      );
}
