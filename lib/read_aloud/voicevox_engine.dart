import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:novelty/read_aloud/read_aloud_controller.dart';
import 'package:novelty/read_aloud/speech_direction.dart';

/// VOICEVOX の声を表す名前の頭（声の設定に「voicevox:metan」のように入れる）。
const voicevoxVoicePrefix = 'voicevox:';

/// VOICEVOX のキャラクター（このアプリに同梱している声）。
@immutable
class VoicevoxCharacter {
  /// コンストラクタ。
  const VoicevoxCharacter({
    required this.id,
    required this.name,
    required this.normal,
    this.amaama,
    this.tsuntsun,
    this.sasayaki,
    this.hisohiso,
    this.namidame,
  });

  /// 設定に保存する名前（voicevox: の後ろ）。
  final String id;

  /// 表示名（クレジット表記にも使う）。
  final String name;

  /// 声の種類の番号（スタイル ID）。
  final int normal;

  /// あまあま（喜びに使う）。
  final int? amaama;

  /// ツンツン（怒り・叫びに使う）。
  final int? tsuntsun;

  /// ささやき（ささやきに使う）。
  final int? sasayaki;

  /// ヒソヒソ（心の声に使う）。
  final int? hisohiso;

  /// なみだめ（悲しみに使う）。
  final int? namidame;

  /// 声の設定に入れる値。
  String get voice => '$voicevoxVoicePrefix$id';

  /// クレジット表記（各音声ライブラリの規約で必要）。
  String get credit => 'VOICEVOX:$name';

  /// 演出から声の種類を選ぶ（演技を切っているときは [direction] が null）。
  int styleFor(SpeechDirection? direction) {
    if (direction == null) return normal;
    if (direction.role == SpeechRole.thought && hisohiso != null) {
      return hisohiso!;
    }
    return switch (direction.emotion) {
          SpeechEmotion.whisper => sasayaki,
          SpeechEmotion.joy => amaama,
          SpeechEmotion.anger || SpeechEmotion.shout => tsuntsun,
          SpeechEmotion.sadness => namidame,
          _ => null,
        } ??
        normal;
  }
}

/// このアプリに同梱している VOICEVOX の声。
///
/// 番号は公式の音声モデル（0.vvm・2.vvm・5.vvm・15.vvm・21.vvm）の中身で
/// 確かめたもの。
const voicevoxCharacters = [
  VoicevoxCharacter(
    id: 'metan',
    name: '四国めたん',
    normal: 2,
    amaama: 0,
    tsuntsun: 6,
    sasayaki: 36,
    hisohiso: 37,
  ),
  VoicevoxCharacter(
    id: 'zundamon',
    name: 'ずんだもん',
    normal: 3,
    amaama: 1,
    tsuntsun: 7,
    sasayaki: 22,
    hisohiso: 38,
    namidame: 76,
  ),
  VoicevoxCharacter(
    id: 'sora',
    name: '九州そら',
    normal: 16,
    amaama: 15,
    tsuntsun: 18,
    sasayaki: 19,
  ),
  // 東北きりたんは今のところノーマルだけ（高さ・速さ・抑揚・間で演じる）
  VoicevoxCharacter(id: 'kiritan', name: '東北きりたん', normal: 108),
];

/// [voice] が VOICEVOX の声なら、そのキャラクター（違えば null）。
VoicevoxCharacter? voicevoxCharacterOf(String? voice) {
  if (voice == null || !voice.startsWith(voicevoxVoicePrefix)) return null;
  final id = voice.substring(voicevoxVoicePrefix.length);
  for (final c in voicevoxCharacters) {
    if (c.id == id) return c;
  }
  return null;
}

/// 声を作るときの値。
@immutable
class VoicevoxRequest {
  /// コンストラクタ。
  const VoicevoxRequest({
    required this.text,
    required this.styleId,
    required this.speed,
    required this.pitch,
    required this.intonation,
    required this.volume,
  });

  /// 読む文と値から作る。
  ///
  /// 端末の音声合成の値（速さ 0.5 が標準、高さ 1.0 が標準）を
  /// VOICEVOX の値（速さ 1.0 が標準、高さ 0.0 が標準で ±0.15 程度）に直す。
  factory VoicevoxRequest.of(
    String text,
    SpeechProsody prosody,
    VoicevoxCharacter character,
    SpeechDirection? direction,
  ) {
    double round(double v) => (v * 1000).roundToDouble() / 1000;
    return VoicevoxRequest(
      text: text,
      styleId: character.styleFor(direction),
      speed: round((prosody.rate * 2).clamp(0.5, 2.0)),
      pitch: round(((prosody.pitch - 1) * 0.3).clamp(-0.15, 0.15)),
      intonation: round(prosody.intonation.clamp(0.0, 2.0)),
      volume: round((prosody.volume * 1.2).clamp(0.1, 2.0)),
    );
  }

  /// 読む文。
  final String text;

  /// 声の種類の番号。
  final int styleId;

  /// 話す速さ（1.0 が標準）。
  final double speed;

  /// 声の高さ（0.0 が標準）。
  final double pitch;

  /// 抑揚（1.0 が標準）。
  final double intonation;

  /// 音量（1.0 が標準）。
  final double volume;

  /// プラットフォームへ渡す形。
  Map<String, Object> toMap() => {
    'text': text,
    'styleId': styleId,
    'speed': speed,
    'pitch': pitch,
    'intonation': intonation,
    'volume': volume,
  };
}

/// VOICEVOX に一度に渡す文の長さの上限。
///
/// 声を作るときのメモリは文の長さに比例して増えるため、句読点の少ない長い段落を
/// まるごと渡すと、メモリが足りずにアプリが落ちることがあった。
const voicevoxMaxChunk = 80;

/// 長い文を、読点や括弧の切れ目でなるべく自然に [maxLength] 文字以内に分ける。
List<String> splitForVoicevox(String text, {int maxLength = voicevoxMaxChunk}) {
  if (text.length <= maxLength) return [text];
  const breaks = '、，。！？!?」』）) 　';
  final chunks = <String>[];
  var rest = text;
  while (rest.length > maxLength) {
    var cut = -1;
    // 上限の手前で、いちばん後ろの切れ目を探す（短すぎる切れ目は使わない）
    for (var i = maxLength; i >= maxLength ~/ 3; i--) {
      if (breaks.contains(rest[i - 1])) {
        cut = i;
        break;
      }
    }
    if (cut < 0) cut = maxLength;
    chunks.add(rest.substring(0, cut));
    rest = rest.substring(cut);
  }
  if (rest.trim().isNotEmpty) chunks.add(rest);
  return chunks;
}

/// Android 側（VoicevoxBridge.kt）とのやりとり。
class VoicevoxBridge {
  VoicevoxBridge._();

  static const _channel = MethodChannel('novelty/voicevox');

  static Future<bool>? _available;

  /// この APK に VOICEVOX の部品が入っているか（結果は覚えておく）。
  static Future<bool> isAvailable() => _available ??= () async {
    try {
      final status = await _channel.invokeMapMethod<String, Object?>(
        'status',
      );
      return status?['available'] == true;
    } on Object {
      // Android 以外・部品が無い・テスト環境
      return false;
    }
  }();

  /// 声の部品を展開して読み込む（初回は時間がかかる）。
  static Future<void> prepare() => _channel.invokeMethod<void>('prepare');

  /// 声を作り、WAV ファイルの場所を返す（取り消されたら null）。
  ///
  /// [fresh] なら取っておいた声を使わずに作り直す（診断で速さを測るため）。
  static Future<String?> synthesize(
    VoicevoxRequest request, {
    bool fresh = false,
  }) => _channel.invokeMethod<String>('synthesize', {
    ...request.toMap(),
    'fresh': fresh,
  });

  /// [ahead] 文先の声を先に作っておく（待たない）。
  ///
  /// どこまで先を作るかは、パフォーマンスモードに合わせて Android 側が決める。
  static Future<void> prefetch(VoicevoxRequest request, {int ahead = 1}) =>
      _channel.invokeMethod<void>('prefetch', {
        ...request.toMap(),
        'ahead': ahead,
      });

  /// パフォーマンスモードを伝える（0: 標準、1: 全力、2: 充電中だけ全力）。
  static Future<void> configure({required int performance}) async {
    if (!await isAvailable()) return;
    try {
      await _channel.invokeMethod<void>('configure', {
        'performance': performance,
      });
    } on Object catch (e) {
      debugPrint('VOICEVOX の設定を変えられませんでした: $e');
    }
  }

  /// WAV を鳴らし、鳴り終わる（または止められる）まで待つ。
  static Future<void> play(String path) =>
      _channel.invokeMethod<void>('play', {'path': path});

  /// 鳴らしている声を止める。
  static Future<void> stop() => _channel.invokeMethod<void>('stop');

  /// 並んでいるだけでまだ始まっていない先読みを取り消す（移動・停止のとき）。
  static Future<void> cancelPending() =>
      _channel.invokeMethod<void>('cancelPending');

  /// 最後に作った声の処理時間（合成にかかった時間・待った時間・声の長さ、ミリ秒）。
  ///
  /// あわせて、ネイティブ側のメモリ使用量（MB）・上限・解放した回数も返す。
  static Future<
    ({
      int synthesisMs,
      int waitMs,
      int audioMs,
      int nativeMb,
      int limitMb,
      int refreshes,
    })
  >
  lastTiming() async {
    final m = await _channel.invokeMapMethod<String, Object?>('lastTiming');
    int read(String key) => (m?[key] as num?)?.toInt() ?? 0;
    return (
      synthesisMs: read('synthesisMs'),
      waitMs: read('waitMs'),
      audioMs: read('audioMs'),
      nativeMb: read('nativeMb'),
      limitMb: read('limitMb'),
      refreshes: read('refreshes'),
    );
  }
}

/// VOICEVOX の失敗を、人が読める文にする（どの段階で何が起きたか）。
String describeVoicevoxError(Object error) {
  if (error is PlatformException) {
    final details = error.details;
    return [
      error.message ?? error.code,
      if (details is String && details.isNotEmpty) details,
    ].join('\n');
  }
  return error.toString();
}

/// VOICEVOX で声を作って読むエンジン。
class VoicevoxEngine implements SpeechEngine {
  VoicevoxRequest? _next;
  bool _stopped = false;

  // 今読む文の「声を作って」を Android へ送ったら完了する。
  // 先読みはこれを待ってから送る（先読みが先に始まって今読む文を待たせないため）。
  Completer<void>? _dispatched;

  static Future<void>? _prepared;

  /// 最後に起きた VOICEVOX の失敗（無ければ null）。画面に出して原因を伝える。
  static final ValueNotifier<String?> lastError = ValueNotifier(null);

  /// 声の部品を準備する（失敗したら次にやり直す）。
  static Future<void> ensurePrepared() async {
    final future = _prepared ??= VoicevoxBridge.prepare();
    try {
      await future;
      lastError.value = null;
    } on Object catch (e) {
      if (identical(_prepared, future)) _prepared = null;
      lastError.value = describeVoicevoxError(e);
      rethrow;
    }
  }

  /// 準備して文を1つ作ってみる（設定画面の診断用）。
  ///
  /// 成功なら、準備の時間と「声1秒を作るのにかかる時間」を返す。
  /// 声の長さより作る時間の方が短ければ（1倍速より速ければ）、途切れずに読める。
  static Future<({bool ok, String message})> diagnose() async {
    try {
      final watch = Stopwatch()..start();
      await ensurePrepared();
      final prepared = watch.elapsedMilliseconds;
      String? last;
      // 1回目は慣らし（初回だけ遅いことがある）、2回目を測る
      const samples = [
        'テストです。',
        '吾輩は猫である。名前はまだ無い。どこで生まれたかとんと見当がつかぬ。',
      ];
      for (final text in samples) {
        last = await VoicevoxBridge.synthesize(
          VoicevoxRequest(
            text: text,
            styleId: voicevoxCharacters.first.normal,
            speed: 1,
            pitch: 0,
            intonation: 1,
            volume: 1,
          ),
          fresh: true,
        );
      }
      final timing = await VoicevoxBridge.lastTiming();
      lastError.value = null;
      final audio = timing.audioMs / 1000;
      final synth = timing.synthesisMs / 1000;
      final speed = synth == 0 ? 0 : audio / synth;
      return (
        ok: last != null,
        message: [
          '準備できました（準備 ${(prepared / 1000).toStringAsFixed(1)} 秒）',
          [
            '声 ${audio.toStringAsFixed(1)} 秒を',
            ' ${synth.toStringAsFixed(1)} 秒で作成',
            '（${speed.toStringAsFixed(2)} 倍速）',
          ].join(),
          if (speed >= 1) '1倍速より速いので、先読みが効けば途切れずに読めます',
          if (speed > 0 && speed < 1) '1倍速より遅いため、文と文の間に待ちが出ます',
          [
            'メモリ ${timing.nativeMb} MB（上限 ${timing.limitMb} MB',
            '・これまでに ${timing.refreshes} 回解放）',
          ].join(),
        ].join('\n'),
      );
    } on Object catch (e) {
      final message = describeVoicevoxError(e);
      lastError.value = message;
      return (ok: false, message: '失敗しました：\n$message');
    }
  }

  VoicevoxCharacter _characterOf(String? voice) =>
      voicevoxCharacterOf(voice) ?? voicevoxCharacters.first;

  @override
  Future<void> apply(
    SpeechProsody prosody, {
    String? voice,
    SpeechDirection? direction,
  }) async {
    _stopped = false;
    _dispatched = Completer<void>();
    // 文は speak で受け取るので、ここでは値だけ覚えておく
    _next = VoicevoxRequest.of('', prosody, _characterOf(voice), direction);
  }

  @override
  Future<void> prefetch(
    String text,
    SpeechProsody prosody, {
    String? voice,
    SpeechDirection? direction,
    int ahead = 1,
  }) async {
    try {
      // 今読む文を先に送る。来なくても少し待ったら先読みを始める
      await _dispatched?.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
      // 長い文は分けて作るので、先読みも最初の一切れだけ作っておく
      await VoicevoxBridge.prefetch(
        VoicevoxRequest.of(
          splitForVoicevox(text).first,
          prosody,
          _characterOf(voice),
          direction,
        ),
        ahead: ahead,
      );
    } on Object catch (e) {
      debugPrint('VOICEVOX の先読みに失敗しました: $e');
    }
  }

  @override
  Future<void> speak(String text) async {
    final base = _next;
    if (base == null) return;
    await ensurePrepared();
    VoicevoxRequest requestOf(String chunk) => VoicevoxRequest(
      text: chunk,
      styleId: base.styleId,
      speed: base.speed,
      pitch: base.pitch,
      intonation: base.intonation,
      volume: base.volume,
    );
    // 長い文は切れ目で分け、一切れずつ作って鳴らす（次の一切れは鳴らしている間に作る）
    final chunks = splitForVoicevox(text);
    for (var i = 0; i < chunks.length; i++) {
      final String? path;
      try {
        final pending = VoicevoxBridge.synthesize(requestOf(chunks[i]));
        final dispatched = _dispatched;
        if (dispatched != null && !dispatched.isCompleted) {
          dispatched.complete();
        }
        if (i + 1 < chunks.length) {
          unawaited(
            VoicevoxBridge.prefetch(requestOf(chunks[i + 1])).catchError(
              (Object e) => debugPrint('VOICEVOX の先読みに失敗しました: $e'),
            ),
          );
        }
        path = await pending;
      } on Object catch (e) {
        lastError.value = describeVoicevoxError(e);
        rethrow;
      }
      // 声を作っている間に止められた・取り消されたら鳴らさない
      if (_stopped || path == null) return;
      await VoicevoxBridge.play(path);
      if (_stopped) return;
    }
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    try {
      // 移動・停止したら、古い先読みはもう要らない
      await VoicevoxBridge.cancelPending();
      await VoicevoxBridge.stop();
    } on Object catch (e) {
      debugPrint('VOICEVOX を止められませんでした: $e');
    }
  }

  @override
  Future<void> dispose() => stop();
}

/// 声の設定に応じて、端末の音声合成と VOICEVOX を切り替えるエンジン。
///
/// 地の文は端末の声、台詞は VOICEVOX、のように混ぜることもできる。
/// VOICEVOX が使えない（部品が無い・準備に失敗した）ときは端末の声で読む。
class CompositeSpeechEngine implements SpeechEngine {
  /// コンストラクタ。
  CompositeSpeechEngine({SpeechEngine? system, SpeechEngine? voicevox})
    : _system = system ?? FlutterTtsEngine(),
      _voicevox = voicevox ?? VoicevoxEngine();

  final SpeechEngine _system;
  final SpeechEngine _voicevox;
  late SpeechEngine _current = _system;

  // 一度失敗したら、この読み上げの間は VOICEVOX を使わない
  // （毎文やり直して一瞬で読み飛ばすのを防ぐ）
  bool _voicevoxBroken = false;

  // 端末の声へ切り替えるときに設定し直すため、最後の値を覚えておく
  SpeechProsody? _lastProsody;
  SpeechDirection? _lastDirection;

  Future<bool> _useVoicevox(String? voice) async =>
      !_voicevoxBroken &&
      voicevoxCharacterOf(voice) != null &&
      await VoicevoxBridge.isAvailable();

  @override
  Future<void> apply(
    SpeechProsody prosody, {
    String? voice,
    SpeechDirection? direction,
  }) async {
    _lastProsody = prosody;
    _lastDirection = direction;
    final next = await _useVoicevox(voice) ? _voicevox : _system;
    if (!identical(next, _current)) await _current.stop();
    _current = next;
    await next.apply(
      prosody,
      voice: identical(next, _system) && voicevoxCharacterOf(voice) != null
          ? null
          : voice,
      direction: direction,
    );
  }

  @override
  Future<void> prefetch(
    String text,
    SpeechProsody prosody, {
    String? voice,
    SpeechDirection? direction,
    int ahead = 1,
  }) async {
    if (await _useVoicevox(voice)) {
      await _voicevox.prefetch(
        text,
        prosody,
        voice: voice,
        direction: direction,
        ahead: ahead,
      );
    }
  }

  @override
  Future<void> speak(String text) async {
    if (identical(_current, _voicevox)) {
      try {
        await _voicevox.speak(text);
        return;
      } on Object catch (e) {
        // 準備に失敗したなどで VOICEVOX が使えないときは端末の声で読む
        debugPrint('VOICEVOX で読めなかったため端末の声で読みます: $e');
        _voicevoxBroken = true;
        _current = _system;
        // 端末の声の準備（読み終わりまで待つ設定など）をしてから読む
        final prosody = _lastProsody;
        if (prosody != null) {
          await _system.apply(prosody, direction: _lastDirection);
        }
      }
    }
    await _system.speak(text);
  }

  @override
  Future<void> stop() async {
    await Future.wait([_system.stop(), _voicevox.stop()]);
  }

  @override
  Future<void> dispose() async {
    await Future.wait([_system.dispose(), _voicevox.dispose()]);
  }
}

/// VOICEVOX のライセンスとクレジットを、アプリの「ライセンス」画面に載せる。
void registerVoicevoxLicenses() {
  LicenseRegistry.addLicense(
    () => Stream.fromIterable([
      LicenseEntryWithLineBreaks(
        ['VOICEVOX（読み上げの声）'],
        [
          '読み上げの声に VOICEVOX を使っています。',
          ...voicevoxCharacters.map((c) => c.credit),
          '',
          'VOICEVOX 音声モデル・VOICEVOX ONNX Runtime 利用規約より：',
          '商用・非商用問わず利用でき、アプリケーションに組み込んで再配布できます。',
          '作成された音声を利用する際は各音声ライブラリの規約に従ってください。',
          '利用の際は VOICEVOX を利用したことがわかるクレジット表記が必要です。',
          '四国めたん・ずんだもん・九州そら・東北きりたんの音声ライブラリの規約：',
          'https://zunko.jp/con_ongen_kiyaku.html',
          'https://voicevox.hiroshiba.jp/',
        ].join('\n'),
      ),
      const LicenseEntryWithLineBreaks(
        ['VOICEVOX CORE'],
        'MIT License\n\nCopyright (c) 2021 Hiroshiba Kazuyuki\n\n'
        'Permission is hereby granted, free of charge, to any person obtaining '
        'a copy of this software and associated documentation files (the '
        '"Software"), to deal in the Software without restriction, including '
        'without limitation the rights to use, copy, modify, merge, publish, '
        'distribute, sublicense, and/or sell copies of the Software, and to '
        'permit persons to whom the Software is furnished to do so, subject to '
        'the following conditions:\n\nThe above copyright notice and this '
        'permission notice shall be included in all copies or substantial '
        'portions of the Software.\n\nTHE SOFTWARE IS PROVIDED "AS IS", '
        'WITHOUT WARRANTY OF ANY KIND.',
      ),
      LicenseEntryWithLineBreaks(
        ['Open JTalk / open_jtalk_dic'],
        [
          'Open JTalk の辞書（mecab-naist-jdic を基にしたもの）を使っています。',
          '修正 BSD ライセンス。',
          'https://open-jtalk.sourceforge.net/',
        ].join('\n'),
      ),
    ]),
  );
}
