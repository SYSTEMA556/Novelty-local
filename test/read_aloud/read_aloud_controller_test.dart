import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/read_aloud/read_aloud_controller.dart';
import 'package:novelty/read_aloud/speech_document.dart';

/// 読み上げを手動で進めるテスト用エンジン。
class FakeEngine implements SpeechEngine {
  final spoken = <String>[];
  Completer<void>? _current;
  int stopCount = 0;

  /// 今読んでいる文を読み終えたことにする。
  Future<void> finish() async {
    _current?.complete();
    _current = null;
    await pumpEventQueue();
  }

  @override
  Future<void> configure({required double rate, required double pitch}) async {}

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    _current = Completer<void>();
    return _current!.future;
  }

  @override
  Future<void> stop() async {
    stopCount++;
    // 実エンジンと同じく、止めると読み上げ中の speak も終わる
    _current?.complete();
    _current = null;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  late FakeEngine engine;
  late List<int> reported;
  late ReadAloudController controller;

  setUp(() {
    engine = FakeEngine();
    reported = [];
    controller = ReadAloudController(
      document: SpeechDocument.fromElements([
        const PlainText('一文目。二文目。三文目。'),
      ]),
      engine: engine,
      onPositionChanged: (s) => reported.add(s.start),
    );
  });

  tearDown(() => controller.dispose());

  test('指定した文から順に最後まで読み、最後で停止する', () async {
    unawaited(controller.playFrom(1));
    await pumpEventQueue();
    expect(controller.status, ReadAloudStatus.playing);
    expect(engine.spoken, ['二文目。']);

    await engine.finish();
    expect(engine.spoken, ['二文目。', '三文目。']);
    expect(controller.index, 2);

    await engine.finish();
    expect(controller.status, ReadAloudStatus.stopped);
    expect(reported, [4, 8]);
  });

  test('一時停止して再開すると同じ文の頭から読む', () async {
    unawaited(controller.playFrom(0));
    await pumpEventQueue();
    await engine.finish();
    expect(controller.index, 1);

    await controller.pause();
    expect(controller.status, ReadAloudStatus.paused);
    // 止めたことで終わった speak の後に、次の文へ進んではいけない
    await pumpEventQueue();
    expect(controller.index, 1);

    unawaited(controller.resume());
    await pumpEventQueue();
    expect(engine.spoken.last, '二文目。');
    expect(controller.status, ReadAloudStatus.playing);
  });

  test('読み上げ中に次の文へ飛ばせる', () async {
    unawaited(controller.playFrom(0));
    await pumpEventQueue();

    unawaited(controller.next());
    await pumpEventQueue();

    expect(controller.index, 1);
    expect(engine.spoken.last, '二文目。');
  });

  test('停止中の前後移動は位置だけ動かす', () async {
    await controller.next();
    await controller.next();
    await controller.next();
    expect(controller.index, 2);
    await controller.previous();
    expect(controller.index, 1);
    expect(engine.spoken, isEmpty);
  });

  test('停止すると状態が戻り、位置を知らせる', () async {
    unawaited(controller.playFrom(2));
    await pumpEventQueue();
    await controller.stop();
    expect(controller.status, ReadAloudStatus.stopped);
    expect(reported.last, 8);
  });
}
