import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/read_aloud/speech_direction.dart';
import 'package:novelty/read_aloud/voicevox_engine.dart';
import 'package:novelty/read_aloud/voicevox_models.dart';

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

  test('使える声の一覧', () {
    expect(
      voicevoxCharacters.map((c) => c.name),
      [
        '四国めたん',
        'ずんだもん',
        '春日部つむぎ',
        'ナースロボ＿タイプＴ',
        '中部つるぎ',
        '暁記ミタマ',
        '里石ユカ',
        '九州そら',
        '東北きりたん',
      ],
    );
  });

  test('どの声にも、入っているモデルが分かっている', () {
    for (final c in voicevoxCharacters) {
      expect(c.model, isNotNull, reason: c.name);
      for (final id in [
        c.amaama,
        c.tsuntsun,
        c.sasayaki,
        c.hisohiso,
        c.namidame,
      ].whereType<int>()) {
        expect(voicevoxModelOfStyle[id], isNotNull, reason: '${c.name} $id');
      }
    }
  });

  test('同梱は めたん・つむぎ・ナースロボ（0.vvm と 11.vvm）', () {
    expect(voicevoxCharacterOf('voicevox:metan')?.model, '0.vvm');
    expect(voicevoxCharacterOf('voicevox:tsumugi')?.model, '0.vvm');
    expect(voicevoxCharacterOf('voicevox:nurserobo')?.model, '11.vvm');
    expect(voicevoxCharacterOf('voicevox:tsurugi')?.model, '18.vvm');
    expect(voicevoxCharacterOf('voicevox:yuka')?.model, '24.vvm');
    expect(
      voicevoxCharacterOf('voicevox:yuka')?.credit,
      'VOICEVOX:里石ユカ（つぼみ）',
    );
    // 追加できるモデルに同梱分は入れない
    expect(
      voicevoxModelPacks.map((p) => p.file),
      isNot(anyOf(contains('0.vvm'), contains('11.vvm'))),
    );
  });

  test('演技用のモデルが入っていなければノーマルで読む', () {
    const whisper = SpeechDirection(
      role: SpeechRole.dialogue,
      emotion: SpeechEmotion.whisper,
      intensity: 1,
    );
    expect(metan.styleFor(whisper, installed: {'0.vvm'}), 2);
    expect(metan.styleFor(whisper, installed: {'0.vvm', '5.vvm'}), 36);
    final nurse = voicevoxCharacterOf('voicevox:nurserobo')!;
    expect(nurse.styleFor(whisper, installed: {'0.vvm', '11.vvm'}), 50);
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

  group('長い文を分ける', () {
    test('短い文はそのまま', () {
      expect(splitForVoicevox('こんにちは。'), ['こんにちは。']);
    });

    test('上限を超える文は読点の後ろで分ける', () {
      final text = '${'あ' * 30}、${'い' * 30}、${'う' * 30}。';
      final chunks = splitForVoicevox(text, maxLength: 40);
      expect(chunks.join(), text);
      expect(chunks.every((c) => c.length <= 40), isTrue);
      expect(chunks.first, '${'あ' * 30}、');
    });

    test('切れ目が無ければ上限で切る', () {
      final text = 'あ' * 100;
      final chunks = splitForVoicevox(text, maxLength: 40);
      expect(chunks.map((c) => c.length), [40, 40, 20]);
    });
  });
}
