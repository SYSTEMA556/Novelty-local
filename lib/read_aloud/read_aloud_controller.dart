import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:novelty/read_aloud/speech_document.dart';

/// 読み上げエンジン（端末の音声合成）の抽象。
///
/// テストで差し替えられるよう、使う機能だけを切り出している。
abstract class SpeechEngine {
  /// 言語・速さ・高さを設定する。
  Future<void> configure({required double rate, required double pitch});

  /// [text] を読み上げ、読み終わる（または止められる）まで待つ。
  Future<void> speak(String text);

  /// 読み上げを止める。
  Future<void> stop();

  /// 後始末をする。
  Future<void> dispose();
}

/// 端末の音声合成（flutter_tts）を使うエンジン。
class FlutterTtsEngine implements SpeechEngine {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  @override
  Future<void> configure({required double rate, required double pitch}) async {
    if (!_initialized) {
      // speak() が読み終わりまで待つようにする（文ごとに順番に読むため）
      await _tts.awaitSpeakCompletion(true);
      await _tts.setLanguage('ja-JP');
      _initialized = true;
    }
    await _tts.setSpeechRate(rate);
    await _tts.setPitch(pitch);
  }

  @override
  Future<void> speak(String text) => _tts.speak(text);

  @override
  Future<void> stop() => _tts.stop();

  @override
  Future<void> dispose() => _tts.stop();
}

/// 読み上げの状態。
enum ReadAloudStatus {
  /// 停止中（読み上げていない）。
  stopped,

  /// 読み上げ中。
  playing,

  /// 一時停止中（再開すると同じ文の頭から読む）。
  paused,
}

/// 本文を1文ずつ読み上げる。
///
/// 一時停止は「止めて、今の文を覚えておく」方式。再開すると
/// その文の頭から読み直す（端末によって一時停止に対応しないため）。
class ReadAloudController extends ChangeNotifier {
  /// コンストラクタ。
  ReadAloudController({
    required this.document,
    SpeechEngine? engine,
    this.onPositionChanged,
  }) : _engine = engine ?? FlutterTtsEngine();

  /// 読み上げる本文。
  final SpeechDocument document;

  /// 読む文が変わったとき・止めたときに呼ばれる（読み上げ位置の保存用）。
  final void Function(SpeechSegment segment)? onPositionChanged;

  final SpeechEngine _engine;

  ReadAloudStatus _status = ReadAloudStatus.stopped;
  int _index = 0;

  // 読み上げループの世代。止める・位置を変えるたびに進め、古いループを終わらせる
  int _generation = 0;

  double _rate = 0.5;
  double _pitch = 1;

  /// 現在の状態。
  ReadAloudStatus get status => _status;

  /// 読み上げ中か。
  bool get isPlaying => _status == ReadAloudStatus.playing;

  /// 読み上げ中または一時停止中か（読んでいる箇所を示すべきか）。
  bool get isActive => _status != ReadAloudStatus.stopped;

  /// 今の文の番号。
  int get index => _index;

  /// 今の文（文が無ければ null）。
  SpeechSegment? get currentSegment =>
      document.segments.isEmpty ? null : document.segments[_index];

  /// 速さ・高さを変える（次の文から反映）。
  void setVoice({required double rate, required double pitch}) {
    _rate = rate;
    _pitch = pitch;
  }

  /// [segmentIndex] 番目の文から読み始める。
  Future<void> playFrom(int segmentIndex) async {
    if (document.segments.isEmpty) return;
    _index = segmentIndex.clamp(0, document.segments.length - 1);
    await _restart();
  }

  /// 一時停止した位置から再開する（停止中なら今の文から）。
  Future<void> resume() => _restart();

  /// 一時停止する。
  Future<void> pause() async {
    if (_status != ReadAloudStatus.playing) return;
    _generation++;
    _status = ReadAloudStatus.paused;
    _reportPosition();
    notifyListeners();
    await _engine.stop();
  }

  /// 止める。
  Future<void> stop() async {
    if (_status == ReadAloudStatus.stopped) return;
    _generation++;
    _status = ReadAloudStatus.stopped;
    _reportPosition();
    notifyListeners();
    await _engine.stop();
  }

  /// 次の文へ進む。
  Future<void> next() => _jump(_index + 1);

  /// 前の文へ戻る。
  Future<void> previous() => _jump(_index - 1);

  Future<void> _jump(int target) async {
    if (document.segments.isEmpty) return;
    final clamped = target.clamp(0, document.segments.length - 1);
    if (_status == ReadAloudStatus.playing) {
      _index = clamped;
      await _restart();
    } else {
      _index = clamped;
      _reportPosition();
      notifyListeners();
    }
  }

  Future<void> _restart() async {
    if (document.segments.isEmpty) return;
    final generation = ++_generation;
    _status = ReadAloudStatus.playing;
    notifyListeners();
    await _engine.stop();
    if (generation != _generation) return;
    await _engine.configure(rate: _rate, pitch: _pitch);
    await _loop(generation);
  }

  Future<void> _loop(int generation) async {
    while (generation == _generation && _index < document.segments.length) {
      _reportPosition();
      notifyListeners();
      try {
        await _engine.speak(document.segments[_index].text);
      } on Object catch (e) {
        debugPrint('Read aloud failed: $e');
        if (generation == _generation) {
          _status = ReadAloudStatus.stopped;
          notifyListeners();
        }
        return;
      }
      // 止められた・位置を変えられた場合は、このループは終わる
      if (generation != _generation) return;
      if (_index >= document.segments.length - 1) {
        // 最後まで読んだ
        _status = ReadAloudStatus.stopped;
        notifyListeners();
        return;
      }
      _index++;
    }
  }

  void _reportPosition() {
    final segment = currentSegment;
    if (segment != null) onPositionChanged?.call(segment);
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_engine.dispose());
    super.dispose();
  }
}
