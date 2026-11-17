import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/read_aloud/speech_direction.dart';
import 'package:novelty/read_aloud/voicevox_engine.dart';

void main() {
  final metan = voicevoxCharacters.first;

  group('声の種類の選び方（四国めたん）', () {
    SpeechDirection d(
      SpeechEmotion e, {
      SpeechRole role = SpeechRole.dialogue,
    }) => SpeechDirection(role: role, emotion: e, intensity: 1);

    test('演技を切っているときはノーマル', () {
      expect(metan.styleFor(null), 2);
    });

    test('感情に合わせて声の種類を変える', () {
      expect(metan.styleFor(d(SpeechEmotion.neutral)), 2);
      expect(metan.styleFor(d(SpeechEmotion.joy)), 0);
      expect(metan.styleFor(d(SpeechEmotion.anger)), 6);
      expect(metan.styleFor(d(SpeechEmotion.shout)), 6);
      expect(metan.styleFor(d(SpeechEmotion.whisper)), 36);
      // 専用の声が無い感情はノーマル（高さ・速さ・抑揚で演じる）
      expect(metan.styleFor(d(SpeechEmotion.sadness)), 2);
    });

    test('心の声はヒソヒソ', () {
      expect(
        metan.styleFor(
          d(SpeechEmotion.neutral, role: SpeechRole.thought),
        ),
        37,
      );
    });
  });

  test('ずんだもんの悲しみはなみだめ、きりたんは常にノーマル', () {
    final zundamon = voicevoxCharacterOf('voicevox:zundamon')!;
    const sad = SpeechDirection(
      role: SpeechRole.dialogue,
      emotion: SpeechEmotion.sadness,
      intensity: 1,
    );
    expect(zundamon.styleFor(sad), 76);
    final kiritan = voicevoxCharacterOf('voicevox:kiritan')!;
    expect(kiritan.styleFor(sad), 108);
    expect(kiritan.credit, 'VOICEVOX:東北きりたん');
  });

  test('4人の声を同梱している', () {
    expect(
      voicevoxCharacters.map((c) => c.name),
      ['四国めたん', 'ずんだもん', '九州そら', '東北きりたん'],
    );
  });

  test('声の設定の名前からキャラクターを引ける', () {
    expect(voicevoxCharacterOf('voicevox:metan')?.name, '四国めたん');
    expect(voicevoxCharacterOf('ja-jp-x-htm-local'), isNull);
    expect(voicevoxCharacterOf(null), isNull);
    expect(metan.credit, 'VOICEVOX:四国めたん');
  });

  test('端末の音声合成の値を VOICEVOX の値に直す', () {
    final r = VoicevoxRequest.of(
      'こんにちは',
      const SpeechProsody(rate: 0.5, pitch: 1, volume: 1),
      metan,
      null,
    );
    expect(r.speed, 1.0);
    expect(r.pitch, 0.0);
    expect(r.intonation, 1.0);
    expect(r.styleId, 2);

    final fast = VoicevoxRequest.of(
      'こんにちは',
      const SpeechProsody(rate: 1, pitch: 2, volume: 1, intonation: 3),
      metan,
      null,
    );
    expect(fast.speed, 2.0);
    expect(fast.pitch, 0.15);
    expect(fast.intonation, 2.0);
  });
}
