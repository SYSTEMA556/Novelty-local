import 'package:flutter_test/flutter_test.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/read_aloud/speech_document.dart';

void main() {
  SpeechDocument doc(List<NovelContentElement> elements) =>
      SpeechDocument.fromElements(elements);

  group('文の区切り', () {
    test('句点で区切り、位置は本文位置で持つ', () {
      final d = doc([PlainText('晴れた。雨が降る。')]);
      expect(d.segments, const [
        SpeechSegment(start: 0, end: 4, text: '晴れた。'),
        SpeechSegment(start: 4, end: 9, text: '雨が降る。'),
      ]);
      expect(d.length, 9);
    });

    test('文末の直後の閉じ括弧は同じ文に含める', () {
      final d = doc([PlainText('「行こう。」と言った。')]);
      expect(d.segments.map((s) => s.text), ['「行こう。」', 'と言った。']);
    });

    test('改行でも区切り、空行は飛ばす', () {
      final d = doc([
        PlainText('一行目'),
        NewLine(),
        NewLine(),
        PlainText('二行目'),
      ]);
      expect(d.segments, const [
        SpeechSegment(start: 0, end: 3, text: '一行目'),
        SpeechSegment(start: 5, end: 8, text: '二行目'),
      ]);
    });

    test('記号だけ・HTMLタグだけの行は読まない', () {
      final d = doc([
        PlainText('<div class="content">'),
        NewLine(),
        PlainText('◇◇◇'),
        NewLine(),
        PlainText('本文'),
      ]);
      expect(d.segments.map((s) => s.text), ['本文']);
    });

    test('長すぎる文は読点で区切る', () {
      final long = '${'あ' * 210}、続き。';
      final d = doc([PlainText(long)]);
      expect(d.segments.length, 2);
      expect(d.segments.first.text.endsWith('、'), isTrue);
    });
  });

  group('ルビと傍点', () {
    test('ルビは読み仮名で読み、位置は親文字の長さで数える', () {
      final d = doc([
        PlainText('彼は'),
        RubyText('魔法使い', 'ウィザード'),
        PlainText('だ。'),
      ]);
      expect(d.segments.single.text, '彼はウィザードだ。');
      expect(d.segments.single.end, 2 + 4 + 2);
    });

    test('傍点は親文字を読む', () {
      final d = doc([Kenten('重要', '﹅'), PlainText('です。')]);
      expect(d.segments.single.text, '重要です。');
    });
  });

  group('位置からの検索', () {
    final d = doc([PlainText('一文目。二文目。三文目。')]);

    test('本文位置を含む文の番号', () {
      expect(d.segmentIndexAt(0), 0);
      expect(d.segmentIndexAt(4), 1);
      expect(d.segmentIndexAt(11), 2);
      expect(d.segmentIndexAt(999), 2);
    });

    test('読み進めた割合から文の番号', () {
      expect(d.segmentIndexAtProgress(0), 0);
      expect(d.segmentIndexAtProgress(0.5), 1);
      expect(d.segmentIndexAtProgress(1), 2);
    });

    test('文が無い本文でも落ちない', () {
      expect(doc(const []).segmentIndexAt(5), 0);
    });
  });

  group('台詞と地の文を分ける', () {
    test('台詞の後ろの地の文は別の文にする', () {
      final d = doc([PlainText('「はい」と答えた。')]);
      expect(d.segments.map((s) => s.text), ['「はい」', 'と答えた。']);
    });

    test('地の文の途中から始まる台詞は手前で区切る', () {
      final d = doc([PlainText('彼は言った「待て」')]);
      expect(d.segments.map((s) => s.text), ['彼は言った', '「待て」']);
    });

    test('地の文の中の（）や『』では区切らない', () {
      final d = doc([PlainText('東京（とうきょう）で『坊っちゃん』を読んだ。')]);
      expect(d.segments, hasLength(1));
    });
  });
}
