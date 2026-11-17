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
          _ => null,
        } ??
        normal;
  }
}

/// このアプリに同梱している VOICEVOX の声。
///
/// 番号は公式の音声モデル（0.vvm・5.vvm）の中身で確かめたもの。
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

  /// 声を作り、WAV ファイルの場所を返す。
  static Future<String> synthesize(VoicevoxRequest request) async =>
      (await _channel.invokeMethod<String>('synthesize', request.toMap()))!;

  /// 次に読む文の声を先に作っておく（待たない）。
  static Future<void> prefetch(VoicevoxRequest request) =>
      _channel.invokeMethod<void>('prefetch', request.toMap());

  /// WAV を鳴らし、鳴り終わる（または止められる）まで待つ。
  static Future<void> play(String path) =>
      _channel.invokeMethod<void>('play', {'path': path});

  /// 鳴らしている声を止める。
  static Future<void> stop() => _channel.invokeMethod<void>('stop');
}

/// VOICEVOX で声を作って読むエンジン。
class VoicevoxEngine implements SpeechEngine {
  VoicevoxRequest? _next;
  bool _stopped = false;

  static Future<void>? _prepared;

  /// 声の部品を準備する（失敗したら次にやり直す）。
  static Future<void> ensurePrepared() async {
    final future = _prepared ??= VoicevoxBridge.prepare();
    try {
      await future;
    } on Object {
      if (identical(_prepared, future)) _prepared = null;
      rethrow;
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
    // 文は speak で受け取るので、ここでは値だけ覚えておく
    _next = VoicevoxRequest.of('', prosody, _characterOf(voice), direction);
  }

  @override
  Future<void> prefetch(
    String text,
    SpeechProsody prosody, {
    String? voice,
    SpeechDirection? direction,
  }) async {
    try {
      await VoicevoxBridge.prefetch(
        VoicevoxRequest.of(text, prosody, _characterOf(voice), direction),
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
    final path = await VoicevoxBridge.synthesize(
      VoicevoxRequest(
        text: text,
        styleId: base.styleId,
        speed: base.speed,
        pitch: base.pitch,
        intonation: base.intonation,
        volume: base.volume,
      ),
    );
    // 声を作っている間に止められていたら鳴らさない
    if (_stopped) return;
    await VoicevoxBridge.play(path);
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    try {
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

  Future<bool> _useVoicevox(String? voice) async =>
      voicevoxCharacterOf(voice) != null && await VoicevoxBridge.isAvailable();

  @override
  Future<void> apply(
    SpeechProsody prosody, {
    String? voice,
    SpeechDirection? direction,
  }) async {
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
  }) async {
    if (await _useVoicevox(voice)) {
      await _voicevox.prefetch(
        text,
        prosody,
        voice: voice,
        direction: direction,
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
        _current = _system;
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
        '読み上げの声に VOICEVOX を使っています。\n'
        '${voicevoxCharacters.map((c) => c.credit).join('\n')}\n\n'
        'VOICEVOX 音声モデル・VOICEVOX ONNX Runtime 利用規約より：'
        '商用・非商用問わず利用でき、アプリケーションに組み込んで再配布できます。'
        '作成された音声を利用する際は各音声ライブラリの規約に従ってください。'
        '利用の際は VOICEVOX を利用したことがわかるクレジット表記が必要です。\n'
        '四国めたんの音声ライブラリの規約：https://zunko.jp/con_ongen_kiyaku.html\n'
        'https://voicevox.hiroshiba.jp/',
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
      const LicenseEntryWithLineBreaks(
        ['Open JTalk / open_jtalk_dic'],
        'Open JTalk の辞書（mecab-naist-jdic を基にしたもの）を使っています。'
        '修正 BSD ライセンス。\nhttps://open-jtalk.sourceforge.net/',
      ),
    ]),
  );
}
