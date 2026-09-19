/// `MutationController.cancel` (#83): the run fails with a `CancelledError`
/// and the controller shows it. Disposing alone does not cancel.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:query_kit_flutter/query_kit_flutter.dart';

import 'harness.dart';

void main() {
  queryWidgetTest('cancel fails the write and the listener sees it',
      (tester, client) async {
    var aborted = false;
    final reply = Completer<String>();
    final controller =
        MutationController<String, String, void>(client, MutationOptions(
      mutationFnWithContext: (name, context) {
        context.signal.onCancel(() => aborted = true);
        return reply.future;
      },
    ));
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(
        client,
        ValueListenableBuilder(
          valueListenable: controller,
          builder: (context, state, _) => Text(switch (state) {
            MutationError(:final error) => 'failed: ${error.runtimeType}',
            MutationPending() => 'writing',
            _ => 'idle',
          }),
        )));
    controller.mutate('BR64');
    await tester.pump();
    expect(find.text('writing'), findsOneWidget);

    controller.cancel();
    expect(aborted, isTrue);
    // The error callbacks run over a few microtasks before the state settles.
    await tester.pump();
    await tester.pump();
    expect(find.text('failed: CancelledError'), findsOneWidget);

    reply.complete('late');
    await tester.pump();
    expect(find.text('failed: CancelledError'), findsOneWidget);
  });
}
