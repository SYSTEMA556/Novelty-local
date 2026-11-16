import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/local_library/meta_rules.dart';
import 'package:novelty/local_library/work_meta_detector.dart';

void main() {
  WorkMeta detect(String fileName, [String head = '']) =>
      WorkMetaDetector.detect(fileName: fileName, head: head);

  group('夜伽形式', () {
    const head = '''
<div class="info">
「架空の作品 第3話」
作者:テスト作者
投稿日時:20140101 1200
</div>


<div class="content">
本文です。
''';

    test('情報欄から作者と作品名を読み取る', () {
      expect(
        detect('00001_20140101_1200_架空の作品3話.txt', head),
        const WorkMeta(title: '架空の作品 第3話', author: 'テスト作者'),
      );
    });

    test('番号付きファイル名は、番号と日時を除いてから判定する', () {
      expect(
        detect('00002_20140101_1200_無題の話.txt', '本文だけ'),
        const WorkMeta(title: '無題の話'),
      );
    });

    test('全角コロンの作者行にも対応する', () {
      expect(
        detect('x.txt', '「題名」\n作者：山田\n'),
        const WorkMeta(title: '題名', author: '山田'),
      );
    });
  });

  group('青空文庫形式', () {
    test('作品名の次に「作者／訳者訳」が来る形', () {
      expect(
        detect('a.txt', '幸福について（上）\nアラン／宗左近訳\n\n\n目　次\n'),
        const WorkMeta(title: '幸福について（上）', author: 'アラン'),
      );
    });

    test('「作者／訳者訳」が先に来る形', () {
      expect(
        detect('b.txt', 'Ｅ・Ｓ・ガードナー／能島武文訳\n奇妙な花嫁\n\n\n\n登場人物\n'),
        const WorkMeta(title: '奇妙な花嫁', author: 'Ｅ・Ｓ・ガードナー'),
      );
    });

    test('区切り線の前の見出し：作品名・作者名', () {
      const head = '吾輩は猫である\n夏目漱石\n\n'
          '-------------------------------------------------------\n'
          '【テキスト中に現れる記号について】\n';
      expect(
        detect('c.txt', head),
        const WorkMeta(title: '吾輩は猫である', author: '夏目漱石'),
      );
    });

    test('区切り線の前の見出し：作品名・作者名・訳者名', () {
      const head = '変身\nフランツ・カフカ\n原田義人訳\n\n'
          '-------------------------------------------------------\n';
      expect(
        detect('d.txt', head),
        const WorkMeta(title: '変身', author: 'フランツ・カフカ'),
      );
    });
  });

  group('ファイル名', () {
    test('作者_作品', () {
      expect(
        detect('山田太郎_海辺の話.txt', '本文'),
        const WorkMeta(title: '海辺の話', author: '山田太郎'),
      );
    });

    test('作者-作品', () {
      expect(
        detect('山田太郎-海辺の話.txt', '本文'),
        const WorkMeta(title: '海辺の話', author: '山田太郎'),
      );
    });

    test('[作者] 作品 と 【作者】作品', () {
      expect(
        detect('[山田] 海辺.txt').author,
        '山田',
      );
      expect(
        detect('【山田】海辺.txt').author,
        '山田',
      );
    });

    test('区切りが無ければ作者不明', () {
      expect(detect('海辺の話.txt', '本文'), const WorkMeta(title: '海辺の話'));
    });

    test('本文の情報がファイル名より優先される', () {
      expect(
        detect('別人_題.txt', '「題」\n作者:本当の作者\n').author,
        '本当の作者',
      );
    });

    test('長すぎる作者名は誤判定とみなす', () {
      final longName = 'あ' * (WorkMetaDetector.maxAuthorLength + 1);
      expect(detect('${longName}_題.txt', '本文').author, isNull);
    });
  });

  group('authorKey', () {
    test('全角英数字と空白の違いを同一視する', () {
      expect(
        WorkMetaDetector.authorKey('Ｅ・Ｓ・ガードナー'),
        WorkMetaDetector.authorKey('E・S・ガードナー'),
      );
      expect(
        WorkMetaDetector.authorKey('夏目 漱石'),
        WorkMetaDetector.authorKey('夏目漱石'),
      );
    });
  });

  group('ルール設定', () {
    MetaRuleSet withRules(
      List<MetaRule> rules, {
      List<StripPattern>? strips,
    }) => MetaRuleSet(
      rules: rules,
      strips: strips ?? MetaRuleSet.defaults.strips,
    );

    test('無効にしたルールは使わない', () {
      final rules = withRules([
        const MetaRule.builtin(BuiltinRule.nameUnderscore, enabled: false),
        const MetaRule.builtin(BuiltinRule.nameDash),
      ]);
      expect(
        WorkMetaDetector.detect(
          fileName: 'A_B-C.txt',
          head: '',
          rules: rules,
        ),
        const WorkMeta(title: 'C', author: 'A_B'),
      );
    });

    test('上にあるルールが優先される', () {
      final rules = withRules([
        const MetaRule.builtin(BuiltinRule.nameDash),
        const MetaRule.builtin(BuiltinRule.nameUnderscore),
      ]);
      expect(
        WorkMetaDetector.detect(fileName: 'A_B-C.txt', head: '', rules: rules),
        const WorkMeta(title: 'C', author: 'A_B'),
      );
    });

    test('自作ルール（ファイル名）：名前付きグループで作者と作品名を取る', () {
      final rules = withRules([
        const MetaRule.custom(
          id: 'c1',
          name: '作品（作者）',
          target: RuleTarget.fileName,
          pattern: r'^(?<title>.+)（(?<author>.+)）$',
        ),
      ]);
      final result = WorkMetaDetector.detectDetailed(
        fileName: '海辺の話（山田）.txt',
        head: '',
        rules: rules,
      );
      expect(result.meta, const WorkMeta(title: '海辺の話', author: '山田'));
      expect(result.rule?.id, 'c1');
    });

    test('自作ルール（本文の冒頭）：行頭・行末を使える', () {
      final rules = withRules([
        const MetaRule.custom(
          id: 'c2',
          name: '著者行',
          target: RuleTarget.head,
          pattern: r'^著者[:：](?<author>.+)$',
        ),
      ]);
      expect(
        WorkMetaDetector.detect(
          fileName: '題.txt',
          head: '題\n著者：佐藤\n本文',
          rules: rules,
        ),
        const WorkMeta(title: '題', author: '佐藤'),
      );
    });

    test('正規表現が誤っている自作ルールは飛ばす', () {
      final rules = withRules([
        const MetaRule.custom(
          id: 'bad',
          name: '壊れたルール',
          target: RuleTarget.fileName,
          pattern: '(?<author>',
        ),
        const MetaRule.builtin(BuiltinRule.nameUnderscore),
      ]);
      expect(
        WorkMetaDetector.detect(fileName: '山田_題.txt', head: '', rules: rules),
        const WorkMeta(title: '題', author: '山田'),
      );
    });

    test('除去パターンを追加・無効化できる', () {
      final stripped = withRules(
        [const MetaRule.builtin(BuiltinRule.nameUnderscore)],
        strips: [
          const StripPattern(
            id: 's1',
            name: '末尾の日付',
            pattern: r'\s*\(\d{2}-\d{2}-\d{2}\)$',
          ),
        ],
      );
      expect(
        WorkMetaDetector.detect(
          fileName: '山田_題 (09-06-07).txt',
          head: '',
          rules: stripped,
        ),
        const WorkMeta(title: '題', author: '山田'),
      );

      final noStrip = withRules(
        [const MetaRule.builtin(BuiltinRule.nameUnderscore)],
        strips: [StripPattern.yotogiPrefix.copyWith(enabled: false)],
      );
      expect(
        WorkMetaDetector.detect(
          fileName: '00001_20140101_1200_題.txt',
          head: '',
          rules: noStrip,
        ).author,
        '00001',
      );
    });

    test('どのルールにも当てはまらなければ作者不明・採用ルールなし', () {
      final result = WorkMetaDetector.detectDetailed(
        fileName: '題.txt',
        head: '本文',
      );
      expect(result.meta, const WorkMeta(title: '題'));
      expect(result.rule, isNull);
    });
  });

  group('MetaRuleSet', () {
    test('JSONに保存して読み戻せる', () {
      final rules = MetaRuleSet.defaults.copyWith(
        rules: [
          const MetaRule.custom(
            id: 'c1',
            name: '自作',
            target: RuleTarget.head,
            pattern: '(?<author>x)',
            enabled: false,
          ),
          ...MetaRuleSet.defaults.rules,
        ],
      );
      expect(MetaRuleSet.fromJson(rules.toJson()), rules);
    });

    test('保存に無い組み込みルールは末尾に補う', () {
      final restored = MetaRuleSet.fromJson(const {'rules': [], 'strips': []});
      expect(restored, MetaRuleSet.defaults);
    });

    test('validatePattern は誤りを日本語で返す', () {
      expect(validatePattern(r'^(?<author>.+)$'), isNull);
      expect(validatePattern(''), isNotNull);
      expect(validatePattern('(abc'), isNotNull);
    });
  });
}
