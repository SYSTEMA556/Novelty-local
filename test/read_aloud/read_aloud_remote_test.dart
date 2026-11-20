import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/read_aloud/read_aloud_controller.dart';
import 'package:novelty/read_aloud/read_aloud_remote.dart';
import 'package:novelty/read_aloud/reading_dictionary.dart';
import 'package:novelty/read_aloud/speech_direction.dart';
import 'package:novelty/read_aloud/speech_document.dart';

/// 読み上げを手動で進めるテスト用エンジン。
class _FakeEngine implements SpeechEngine {
  final spoken = <String>[];
  Completer<void>? _current;

  Future<void> finish() async {
    _current?.complete();
    _current = null;
    await pumpEventQueue();
  }

  @override
  Future<void> apply(
    SpeechProsody prosody, {
    String? voice,
    SpeechDirection? direction,
  }) async {}

  @override
  Future<void> prefetch(
    String text,
    SpeechProsody prosody, {
    String? voice,
    SpeechDirection? direction,
    int ahead = 1,
  }) async {}

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    _current = Completer<void>();
    return _current!.future;
  }

  @override
  Future<void> stop() async {
    _current?.complete();
    _current = null;
  }

  @override
  Future<void> dispose() async {}
}

SpeechDocument _doc(String text) =>
    SpeechDocument.fromElements([PlainText(text)]);

void main() {
  group('indexAfterSeconds', () {
    // 各文は4文字（「一二三。」）、1秒に4文字読む → 1文1秒
    final document = _doc('一二三。四五六。七八九。十一二。十三四。');

    test('進むときは、およそその秒数ぶん先の文の頭', () {
      expect(
        indexAfterSeconds(
          document,
          from: 0,
          seconds: 2,
          charsPerSecond: 4,
        ),
        2,
      );
    });

    test('戻るときは、およそその秒数ぶん前の文の頭', () {
      expect(
        indexAfterSeconds(
          document,
          from: 4,
          seconds: -3,
          charsPerSecond: 4,
        ),
        1,
      );
    });

    test('はじめと終わりを越えない', () {
      expect(
        indexAfterSeconds(
          document,
          from: 1,
          seconds: -30,
          charsPerSecond: 4,
        ),
        0,
      );
      expect(
        indexAfterSeconds(
          document,
          from: 3,
          seconds: 30,
          charsPerSecond: 4,
        ),
        4,
      );
    });

    test('標準の速さでは1秒に8文字、速くすると増える', () {
      expect(charsPerSecondAt(0.5), 8);
      expect(charsPerSecondAt(1), 16);
    });
  });

  group('ReadAloudController（運転中向けの追加）', () {
    test('案内を最初の文の前に1回だけ読む', () async {
      final engine = _FakeEngine();
      final controller = ReadAloudController(
        document: _doc('一文目。二文目。'),
        engine: engine,
        announcement: '第2話',
      );
      addTearDown(controller.dispose);
      unawaited(controller.playFrom(0));
      await pumpEventQueue();
      expect(engine.spoken, ['第2話']);
      await engine.finish();
      // 案内のあとの短い間
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(engine.spoken, ['第2話', '一文目。']);

      await controller.pause();
      unawaited(controller.resume());
      await pumpEventQueue();
      expect(engine.spoken, ['第2話', '一文目。', '一文目。']);
    });

    test('最後まで読むと finished、もう一度読み始めると戻る', () async {
      final engine = _FakeEngine();
      final controller = ReadAloudController(
        document: _doc('一文目。'),
        engine: engine,
      );
      addTearDown(controller.dispose);
      unawaited(controller.playFrom(0));
      await pumpEventQueue();
      expect(controller.finished, isFalse);
      await engine.finish();
      expect(controller.finished, isTrue);
      unawaited(controller.playFrom(0));
      await pumpEventQueue();
      expect(controller.finished, isFalse);
    });

    test('読み方の辞書は音声にだけ効き、文の位置は変えない', () async {
      final engine = _FakeEngine();
      final controller = ReadAloudController(
        document: _doc('天音は笑った。'),
        engine: engine,
        dictionaryScope: 'local:x',
        dictionary: ReadingDictionary([
          const ReadingRule(surface: '天音', reading: 'あまね', scope: 'local:x'),
        ]),
      );
      addTearDown(controller.dispose);
      unawaited(controller.playFrom(0));
      await pumpEventQueue();
      expect(engine.spoken, ['あまねは笑った。']);
      expect(controller.currentSegment?.text, '天音は笑った。');
    });

    test('題名のある読み上げだけ、始めたことを知らせる', () async {
      final started = <ReadAloudController>[];
      final disposed = <ReadAloudController>[];
      ReadAloudController.onStartedPlaying = started.add;
      ReadAloudController.onDisposed = disposed.add;
      addTearDown(() {
        ReadAloudController.onStartedPlaying = null;
        ReadAloudController.onDisposed = null;
      });
      final titled = ReadAloudController(
        document: _doc('一文目。'),
        engine: _FakeEngine(),
        mediaTitle: '作品',
      );
      final untitled = ReadAloudController(
        document: _doc('一文目。'),
        engine: _FakeEngine(),
      );
      unawaited(titled.playFrom(0));
      unawaited(untitled.playFrom(0));
      await pumpEventQueue();
      expect(started, [titled]);
      titled.dispose();
      untitled.dispose();
      expect(disposed, [titled, untitled]);
    });
  });

  group('ReadAloudRemote', () {
    late _FakeEngine engine;
    late ReadAloudController controller;
    late ReadAloudRemote remote;

    setUp(() {
      engine = _FakeEngine();
      controller = ReadAloudController(
        document: _doc('一文目。二文目。三文目。'),
        engine: engine,
      );
      remote = ReadAloudRemote()..attach(controller);
    });

    tearDown(() => controller.dispose());

    test('ボタンで再生・一時停止・次の文', () async {
      unawaited(remote.togglePlay());
      await pumpEventQueue();
      expect(controller.isPlaying, isTrue);
      unawaited(remote.next());
      await pumpEventQueue();
      expect(controller.index, 1);
      await remote.togglePlay();
      expect(controller.status, ReadAloudStatus.paused);
    });

    test('ナビの案内で止まり、終わると同じ文から続ける', () async {
      unawaited(remote.play());
      await pumpEventQueue();
      await remote.interruptionBegan(mayResume: true);
      expect(controller.status, ReadAloudStatus.paused);
      expect(remote.waitingForInterruption, isTrue);

      unawaited(remote.interruptionEnded());
      await pumpEventQueue();
      expect(controller.isPlaying, isTrue);
      expect(engine.spoken, ['一文目。', '一文目。']);
    });

    test('他のアプリに音を取られたときは、戻っても勝手に再開しない', () async {
      unawaited(remote.play());
      await pumpEventQueue();
      await remote.interruptionBegan(mayResume: false);
      await remote.interruptionEnded();
      expect(controller.status, ReadAloudStatus.paused);
    });

    test('自分で止めていたら、割り込みが終わっても再開しない', () async {
      await remote.interruptionBegan(mayResume: true);
      await remote.interruptionEnded();
      expect(controller.status, ReadAloudStatus.stopped);
    });

    test('割り込み中に自分で一時停止したら、終わっても再開しない', () async {
      unawaited(remote.play());
      await pumpEventQueue();
      await remote.interruptionBegan(mayResume: true);
      await remote.pause();
      await remote.interruptionEnded();
      expect(controller.status, ReadAloudStatus.paused);
    });

    test('Bluetooth が切れたら止める', () async {
      unawaited(remote.play());
      await pumpEventQueue();
      await remote.becameNoisy();
      expect(controller.status, ReadAloudStatus.paused);
    });

    test('外したあとの操作は何もしない', () async {
      expect(remote.detach(controller), isTrue);
      await remote.play();
      expect(controller.status, ReadAloudStatus.stopped);
    });
  });
}
