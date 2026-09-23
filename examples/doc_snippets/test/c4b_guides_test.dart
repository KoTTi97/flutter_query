import 'dart:async';

import 'package:doc_snippets/c4b_guides.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reachability: a probe that answers after the link dropped is ignored',
      () async {
    final link = StreamController<bool>();
    final answers = <Completer<bool>>[];
    Future<bool> probe() {
      final answer = Completer<bool>();
      answers.add(answer);
      return answer.future;
    }

    final seen = <bool>[];
    final subscription = reachability(link.stream, probe).listen(seen.add);

    link.add(true);
    await pumpEventQueue();
    expect(answers, hasLength(1), reason: 'the link came up: one probe');

    link.add(false);
    await pumpEventQueue();
    expect(seen, [false]);

    answers.single.complete(true);
    await pumpEventQueue();
    expect(seen, [false], reason: 'the old probe must not report online');

    await subscription.cancel();
    await link.close();
  });

  test('reachability: online once the link is up and the probe answers',
      () async {
    final link = StreamController<bool>();
    final seen = <bool>[];
    final subscription =
        reachability(link.stream, () async => true).listen(seen.add);

    link.add(true);
    await pumpEventQueue();
    expect(seen, [true]);

    await subscription.cancel();
    await link.close();
  });
}
