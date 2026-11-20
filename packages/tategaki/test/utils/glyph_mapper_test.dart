import 'package:flutter_test/flutter_test.dart';
import 'package:tategaki/src/utils/glyph_mapper.dart';

void main() {
  group('GlyphMapper', () {
    group('句読点', () {
      test('。を︒に変換する', () {
        expect(GlyphMapper.map('。'), '︒');
      });

      test('、を︑に変換する', () {
        expect(GlyphMapper.map('、'), '︑');
      });
    });

    group('欧文句読点', () {
      test('.を﹒に変換する', () {
        expect(GlyphMapper.map('.'), '﹒');
      });

      test('!を︕に変換する', () {
        expect(GlyphMapper.map('!'), '︕');
      });

      test('?を︖に変換する', () {
        expect(GlyphMapper.map('?'), '︖');
      });
    });

    group('長音・ダッシュ', () {
      test('ーを丨に変換する', () {
        expect(GlyphMapper.map('ー'), '丨');
      });

      test('—を丨に変換する', () {
        expect(GlyphMapper.map('—'), '丨');
      });

      test('―を丨に変換する', () {
        expect(GlyphMapper.map('―'), '丨');
      });

      test('–を丨に変換する', () {
        expect(GlyphMapper.map('–'), '丨');
      });

      test('ダッシュ代わりの罫線・記号も縦にする', () {
        for (final c in ['─', '‒', '⁃', '⎯', '⸺', '⸻', '﹘', '﹣']) {
          expect(GlyphMapper.map(c), '丨', reason: c);
        }
      });

      test('横の罫線は、太さ・破線の種類が同じ縦の罫線にする', () {
        expect(GlyphMapper.map('━'), '┃');
        expect(GlyphMapper.map('┄'), '┆');
        expect(GlyphMapper.map('═'), '║');
        expect(GlyphMapper.map('╌'), '╎');
      });

      test('‐を丨に変換する', () {
        expect(GlyphMapper.map('‐'), '丨');
      });
    });

    group('中点', () {
      test('・を｜に変換する', () {
        expect(GlyphMapper.map('・'), '｜');
      });

      test('･を｜に変換する', () {
        expect(GlyphMapper.map('･'), '｜');
      });
    });

    group('二重山括弧', () {
      test('《を︽に変換する', () {
        expect(GlyphMapper.map('《'), '︽');
      });

      test('》を︾に変換する', () {
        expect(GlyphMapper.map('》'), '︾');
      });
    });

    group('括弧', () {
      test('「を﹁に変換する', () {
        expect(GlyphMapper.map('「'), '﹁');
      });

      test('」を﹂に変換する', () {
        expect(GlyphMapper.map('」'), '﹂');
      });

      test('（を︵に変換する', () {
        expect(GlyphMapper.map('（'), '︵');
      });

      test('）を︶に変換する', () {
        expect(GlyphMapper.map('）'), '︶');
      });
    });

    group('変換不要な文字', () {
      test('ひらがなはそのまま', () {
        expect(GlyphMapper.map('あ'), 'あ');
      });

      test('カタカナはそのまま', () {
        expect(GlyphMapper.map('ア'), 'ア');
      });

      test('漢字はそのまま', () {
        expect(GlyphMapper.map('猫'), '猫');
      });
    });
  });
}
