import 'package:flutter_test/flutter_test.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/read_aloud/speech_direction.dart';
import 'package:novelty/read_aloud/speech_document.dart';

void main() {
  List<SpeechDirection> direct(List<NovelContentElement> elements) =>
      SpeechDirector.direct(SpeechDocument.fromElements(elements));

  group('役割', () {
    test('台詞・心の声・地の文を見分ける', () {
      final d = direct([
        PlainText('朝が来た。'),
        NewLine(),
        PlainText('「おはよう」'),
        NewLine(),
        PlainText('（眠い……）'),
      ]);
      expect(d.map((x) => x.role), [
        SpeechRole.narration,
        SpeechRole.dialogue,
        SpeechRole.thought,
      ]);
    });

    test('長い台詞が文に分かれても、閉じるまでは台詞', () {
      final d = direct([PlainText('「一つ目。二つ目。」そう言った。')]);
      expect(d.map((x) => x.role), [
        SpeechRole.dialogue,
        SpeechRole.dialogue,
        SpeechRole.narration,
      ]);
    });
  });

  group('感情', () {
    test('後ろの「と叫んだ」「と囁いた」から読み取る', () {
      final shout = direct([PlainText('「待て」と彼は叫んだ。')]);
      expect(shout.first.emotion, SpeechEmotion.shout);
      final whisper = direct([PlainText('「待って」と小さく囁いた。')]);
      expect(whisper.first.emotion, SpeechEmotion.whisper);
    });

    test('台詞の中の記号と言葉から読み取る', () {
      expect(
        direct([PlainText('「えっ、本当に！？」')]).first.emotion,
        SpeechEmotion.surprise,
      );
      expect(
        direct([PlainText('「ふふ、ありがとう」')]).first.emotion,
        SpeechEmotion.joy,
      );
      expect(
        direct([PlainText('「助けて、来ないで」')]).first.emotion,
        SpeechEmotion.fear,
      );
    });

    test('手がかりがなければ普通に読む', () {
      final d = direct([PlainText('「今日は火曜日です」')]);
      expect(d.first.emotion, SpeechEmotion.neutral);
      expect(d.first.intensity, 0);
    });

    test('悲しい場面の空気は、続く台詞にも少し残る', () {
      final d = direct([
        PlainText('彼女は涙をこぼし、肩を落とした。'),
        NewLine(),
        PlainText('「そうだね」'),
      ]);
      expect(d.last.emotion, SpeechEmotion.sadness);
    });
  });

  group('間', () {
    test('空行のあとは長く、段落の終わりは短く間を置く', () {
      final d = direct([
        PlainText('一段落目。'),
        NewLine(),
        PlainText('二段落目。'),
        NewLine(),
        NewLine(),
        PlainText('次の場面。'),
      ]);
      expect(d[0].pauseAfter, const Duration(milliseconds: 300));
      expect(d[1].pauseAfter, const Duration(milliseconds: 900));
      expect(d[2].pauseAfter, Duration.zero);
    });
  });

  group('声の値', () {
    const angry = SpeechDirection(
      role: SpeechRole.dialogue,
      emotion: SpeechEmotion.whisper,
      intensity: 1,
    );

    test('演技 0 なら基準のまま', () {
      expect(
        angry.prosody(baseRate: 0.5, basePitch: 1, acting: 0),
        const SpeechProsody(rate: 0.5, pitch: 1, volume: 1),
      );
    });

    test('ささやきは小さくゆっくり', () {
      final p = angry.prosody(baseRate: 0.5, basePitch: 1, acting: 1);
      expect(p.volume, lessThan(0.6));
      expect(p.rate, lessThan(0.5));
    });

    test('範囲からはみ出さない', () {
      const surprise = SpeechDirection(
        emotion: SpeechEmotion.surprise,
        intensity: 1,
      );
      final p = surprise.prosody(baseRate: 1, basePitch: 2, acting: 1);
      expect(p.rate, 1);
      expect(p.pitch, 2);
    });
  });
}
