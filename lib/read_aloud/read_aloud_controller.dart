import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:novelty/read_aloud/speech_direction.dart';
import 'package:novelty/read_aloud/speech_document.dart';
import 'package:novelty/read_aloud/voicevox_engine.dart';

/// 読み上げエンジン（端末の音声合成）の抽象。
///
/// テストで差し替えられるよう、使う機能だけを切り出している。
abstract class SpeechEngine {
  /// 次に読む文の速さ・高さ・音量・声を設定する。
  ///
  /// [voice] は声の名前（null なら端末の標準の声）。
  /// [direction] は演出（演技を切っているときは null）。声の種類を選ぶのに使う。
  Future<void> apply(
    SpeechProsody prosody, {
    String? voice,
    SpeechDirection? direction,
  });

  /// [ahead] 文先の声を先に作っておく（作る必要のないエンジンでは何もしない）。
  Future<void> prefetch(
    String text,
    SpeechProsody prosody, {
    String? voice,
    SpeechDirection? direction,
    int ahead = 1,
  });

  /// [text] を読み上げ、読み終わる（または止められる）まで待つ。
  Future<void> speak(String text);

  /// 読み上げを止める。
  Future<void> stop();

  /// 後始末をする。
  Future<void> dispose();
}

/// 端末の音声合成の声。
@immutable
class TtsVoice {
  /// コンストラクタ。
  const TtsVoice({required this.name, required this.locale});

  /// 声の名前（エンジンごとの識別子）。
  final String name;

  /// 言語（ja-JP など）。
  final String locale;

  /// ネットにつないで作る声か（Google の音声エンジンでは名前に network が付く）。
  bool get needsNetwork => name.contains('network');

  @override
  bool operator ==(Object other) =>
      other is TtsVoice && other.name == name && other.locale == locale;

  @override
  int get hashCode => Object.hash(name, locale);
}

// 端末の音声合成はアプリで1つを使い回す。
// FlutterTts を複数作ると、読み終わりの知らせを受け取る先が後から作ったものに
// 置き換わり、読み上げが止まらなくなる・進まなくなることがあるため。
final FlutterTts _sharedTts = FlutterTts();

/// 端末にある日本語の声の一覧（端末の中だけで作る声を先に並べる）。
Future<List<TtsVoice>> availableJapaneseVoices() async {
  try {
    final raw = await _sharedTts.getVoices;
    final voices = <TtsVoice>[
      if (raw is List)
        for (final v in raw)
          if (v is Map &&
              v['name'] is String &&
              '${v['locale']}'.toLowerCase().startsWith('ja'))
            TtsVoice(name: v['name'] as String, locale: '${v['locale']}'),
    ]..sort((a, b) {
        if (a.needsNetwork != b.needsNetwork) return a.needsNetwork ? 1 : -1;
        return a.name.compareTo(b.name);
      });
    return voices;
  } on Object catch (e) {
    debugPrint('声の一覧を取得できませんでした: $e');
    return const [];
  }
}

/// 端末の音声合成（flutter_tts）を使うエンジン。
///
/// 同じ値を何度も送らないよう、最後に設定した値を覚えておく。
class FlutterTtsEngine implements SpeechEngine {
  final FlutterTts _tts = _sharedTts;
  bool _initialized = false;
  SpeechProsody? _lastProsody;
  // 前の読み上げが別の声を残していることがあるため、最初の1回は必ず設定する
  bool _voiceApplied = false;
  String? _lastVoice;
  Map<String, String>? _defaultVoice;
  Map<String, String> _voiceLocales = const {};

  Future<void> _init() async {
    if (_initialized) return;
    _initialized = true;
    // speak() が読み終わりまで待つようにする（文ごとに順番に読むため）
    await _tts.awaitSpeakCompletion(true);
    await _tts.setLanguage('ja-JP');
    try {
      final def = await _tts.getDefaultVoice;
      if (def is Map && def['name'] != null) {
        _defaultVoice = {
          'name': '${def['name']}',
          'locale': '${def['locale']}',
        };
      }
      _voiceLocales = {
        for (final v in await availableJapaneseVoices()) v.name: v.locale,
      };
    } on Object catch (e) {
      debugPrint('標準の声を取得できませんでした: $e');
    }
  }

  @override
  Future<void> prefetch(
    String text,
    SpeechProsody prosody, {
    String? voice,
    SpeechDirection? direction,
    int ahead = 1,
  }) async {}

  @override
  Future<void> apply(
    SpeechProsody prosody, {
    String? voice,
    SpeechDirection? direction,
  }) async {
    await _init();
    if (!_voiceApplied || voice != _lastVoice) {
      _voiceApplied = true;
      _lastVoice = voice;
      final locale = voice == null ? null : _voiceLocales[voice];
      final target = voice != null && locale != null
          ? {'name': voice, 'locale': locale}
          : _defaultVoice;
      if (target != null) await _tts.setVoice(target);
    }
    final last = _lastProsody;
    if (last?.rate != prosody.rate) await _tts.setSpeechRate(prosody.rate);
    if (last?.pitch != prosody.pitch) await _tts.setPitch(prosody.pitch);
    if (last?.volume != prosody.volume) await _tts.setVolume(prosody.volume);
    _lastProsody = prosody;
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
    this.onCompleted,
    this.mediaTitle,
    this.mediaSubtitle,
    String? announcement,
  }) : _engine = engine ?? CompositeSpeechEngine(),
       _announcement = announcement;

  /// 読み上げを始めたときに呼ばれる（通知・車のボタンとつなぐのに使う）。
  ///
  /// [mediaTitle] のある読み上げだけが対象。アプリの起動時に設定する。
  static void Function(ReadAloudController controller)? onStartedPlaying;

  /// 後始末のときに呼ばれる（通知・車のボタンとの接続を外すのに使う）。
  static void Function(ReadAloudController controller)? onDisposed;

  /// 通知・ロック画面・車の画面に出す題名（null なら出さない）。
  final String? mediaTitle;

  /// 通知などで題名の下に出す文（作者・話の番号など）。
  final String? mediaSubtitle;

  // 最初の文の前に読む案内（「次は、〇〇」など）。読んだら消す
  String? _announcement;

  /// 読み上げる本文。
  final SpeechDocument document;

  /// 読む文が変わったとき・止めたときに呼ばれる（読み上げ位置の保存用）。
  final void Function(SpeechSegment segment)? onPositionChanged;

  /// 最後の文まで読み終えたときに呼ばれる（次の話へ進むのに使う）。
  /// 止めた・一時停止した場合は呼ばれない。
  final VoidCallback? onCompleted;

  final SpeechEngine _engine;

  ReadAloudStatus _status = ReadAloudStatus.stopped;
  int _index = 0;
  bool _finished = false;

  // 読み上げループの世代。止める・位置を変えるたびに進め、古いループを終わらせる
  int _generation = 0;

  double _rate = 0.5;
  double _pitch = 1;
  double _acting = 0;
  String? _narrationVoice;
  String? _dialogueVoice;
  int _prefetchAhead = 1;

  /// 文ごとの演出（役割・感情・間）。初めて使うときに読み取る。
  late final List<SpeechDirection> directions = SpeechDirector.direct(
    document,
  );

  /// 今の文の演出（文が無ければ null）。
  SpeechDirection? get currentDirection =>
      document.segments.isEmpty ? null : directions[_index];

  /// 演技の強さ（0.0〜1.0）。
  double get acting => _acting;

  SpeechProsody _prosodyOf(SpeechDirection direction) => direction.prosody(
    baseRate: _rate,
    basePitch: _pitch,
    acting: _acting,
  );

  String? _voiceOf(SpeechDirection direction) =>
      direction.role == SpeechRole.narration
      ? _narrationVoice
      : _dialogueVoice ?? _narrationVoice;

  /// 現在の状態。
  ReadAloudStatus get status => _status;

  /// 読み上げ中か。
  bool get isPlaying => _status == ReadAloudStatus.playing;

  /// 読み上げ中または一時停止中か（読んでいる箇所を示すべきか）。
  bool get isActive => _status != ReadAloudStatus.stopped;

  /// 今の文の番号。
  int get index => _index;

  /// 最後の文まで読み終えたか（止めた・一時停止した場合は false）。
  bool get finished => _finished;

  /// 今の文（文が無ければ null）。
  SpeechSegment? get currentSegment =>
      document.segments.isEmpty ? null : document.segments[_index];

  /// 速さ・高さ・演技の強さ・声を変える（次の文から反映）。
  ///
  /// [acting] は 0.0〜1.0（0 なら感情を付けず、間も置かない）。
  /// [narrationVoice]・[dialogueVoice] は声の名前（null なら端末の標準の声）。
  void setVoice({
    required double rate,
    required double pitch,
    double acting = 0,
    String? narrationVoice,
    String? dialogueVoice,
    int prefetchAhead = 1,
  }) {
    _prefetchAhead = prefetchAhead.clamp(1, 8);
    _rate = rate;
    _pitch = pitch;
    _acting = acting.clamp(0.0, 1.0);
    _narrationVoice = narrationVoice;
    _dialogueVoice = dialogueVoice;
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

  /// 今の速さでおよそ [seconds] 秒ぶん進む（負なら戻る）。
  ///
  /// 文の途中には入れないため、文の頭に合わせる。
  Future<void> seekBySeconds(double seconds) => _jump(
    indexAfterSeconds(
      document,
      from: _index,
      seconds: seconds,
      charsPerSecond: charsPerSecondAt(_rate),
    ),
  );

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
    _finished = false;
    if (mediaTitle != null) onStartedPlaying?.call(this);
    notifyListeners();
    await _engine.stop();
    if (generation != _generation) return;
    await _loop(generation);
  }

  Future<void> _loop(int generation) async {
    while (generation == _generation && _index < document.segments.length) {
      _reportPosition();
      notifyListeners();
      final direction = directions[_index];
      try {
        // 話・作品の切り替わりでは、最初に題名などを読んで知らせる
        if (_announcement case final announcement?) {
          _announcement = null;
          await _engine.apply(
            SpeechProsody(rate: _rate, pitch: _pitch, volume: 1),
            voice: _narrationVoice,
          );
          if (generation != _generation) return;
          await _engine.speak(announcement);
          if (generation != _generation) return;
          await Future<void>.delayed(const Duration(milliseconds: 600));
          if (generation != _generation) return;
        }
        await _engine.apply(
          _prosodyOf(direction),
          voice: _voiceOf(direction),
          direction: _acting > 0 ? direction : null,
        );
        if (generation != _generation) return;
        // 声を作るエンジンでは、読んでいる間に先の文の声を作っておく
        for (var ahead = 1; ahead <= _prefetchAhead; ahead++) {
          final nextIndex = _index + ahead;
          if (nextIndex >= document.segments.length) break;
          final next = directions[nextIndex];
          unawaited(
            _engine.prefetch(
              document.segments[nextIndex].text,
              _prosodyOf(next),
              voice: _voiceOf(next),
              direction: _acting > 0 ? next : null,
              ahead: ahead,
            ),
          );
        }
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
        _finished = true;
        notifyListeners();
        onCompleted?.call();
        return;
      }
      // 場面の切り替わりや「……」のあとに間を置く
      final pause = direction.pause(acting: _acting);
      if (pause > Duration.zero) {
        await Future<void>.delayed(pause);
        if (generation != _generation) return;
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
    onDisposed?.call(this);
    _generation++;
    unawaited(_engine.dispose());
    super.dispose();
  }
}

/// 速さ [rate]（0.5 が標準）で1秒に読むおよその文字数。
///
/// 日本語の読み上げは標準の速さで1秒に8文字ほど。
double charsPerSecondAt(double rate) => 8 * (rate <= 0 ? 0.5 : rate) / 0.5;

/// [from] 番目の文から、およそ [seconds] 秒ぶん進んだ（負なら戻った）文の番号。
///
/// 文の長さを [charsPerSecond] で秒に直して数える。
int indexAfterSeconds(
  SpeechDocument document, {
  required int from,
  required double seconds,
  required double charsPerSecond,
}) {
  final segments = document.segments;
  if (segments.isEmpty) return 0;
  var index = from.clamp(0, segments.length - 1);
  final target = seconds.abs() * charsPerSecond;
  var passed = 0;
  if (seconds >= 0) {
    while (index < segments.length - 1 && passed < target) {
      passed += segments[index].text.length;
      index++;
    }
  } else {
    while (index > 0 && passed < target) {
      index--;
      passed += segments[index].text.length;
    }
  }
  return index;
}
