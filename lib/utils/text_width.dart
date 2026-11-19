/// 文字の幅（全角・半角）の表記ゆれをそろえる（フォークで追加）。
///
/// - 全角の英数字（Ａ・ｂ・１）は半角（A・b・1）に
/// - 半角カナ（ｶﾞ）は全角（ガ）に。濁点・半濁点は前の字とくっつける
///
/// 「！」「？」「（」や全角スペースなどの記号は変えない。
/// 日本語の文章では全角のまま使うのが普通で、縦書きの見た目も崩れるため。
String unifyTextWidth(String text) {
  final out = StringBuffer();
  final units = text.runes.toList();
  for (var i = 0; i < units.length; i++) {
    final c = units[i];
    // 全角英数字
    if ((c >= 0xFF10 && c <= 0xFF19) ||
        (c >= 0xFF21 && c <= 0xFF3A) ||
        (c >= 0xFF41 && c <= 0xFF5A)) {
      out.writeCharCode(c - 0xFEE0);
      continue;
    }
    if (c >= 0xFF61 && c <= 0xFF9F) {
      final next = i + 1 < units.length ? units[i + 1] : 0;
      final base = _halfKana[c - 0xFF61];
      if (next == 0xFF9E && _dakuten.containsKey(base)) {
        out.write(_dakuten[base]);
        i++;
      } else if (next == 0xFF9F && _handakuten.containsKey(base)) {
        out.write(_handakuten[base]);
        i++;
      } else {
        out.write(base);
      }
      continue;
    }
    out.writeCharCode(c);
  }
  return out.toString();
}

// U+FF61〜U+FF9F の半角カナに対応する全角の字
const _halfKana = [
  '。', '「', '」', '、', '・', 'ヲ', 'ァ', 'ィ', 'ゥ', 'ェ', 'ォ', 'ャ', //
  'ュ', 'ョ', 'ッ', 'ー', 'ア', 'イ', 'ウ', 'エ', 'オ', 'カ', 'キ', 'ク', //
  'ケ', 'コ', 'サ', 'シ', 'ス', 'セ', 'ソ', 'タ', 'チ', 'ツ', 'テ', 'ト', //
  'ナ', 'ニ', 'ヌ', 'ネ', 'ノ', 'ハ', 'ヒ', 'フ', 'ヘ', 'ホ', 'マ', 'ミ', //
  'ム', 'メ', 'モ', 'ヤ', 'ユ', 'ヨ', 'ラ', 'リ', 'ル', 'レ', 'ロ', 'ワ', //
  'ン', '゛', '゜',
];

const _dakuten = {
  'カ': 'ガ', 'キ': 'ギ', 'ク': 'グ', 'ケ': 'ゲ', 'コ': 'ゴ', //
  'サ': 'ザ', 'シ': 'ジ', 'ス': 'ズ', 'セ': 'ゼ', 'ソ': 'ゾ', //
  'タ': 'ダ', 'チ': 'ヂ', 'ツ': 'ヅ', 'テ': 'デ', 'ト': 'ド', //
  'ハ': 'バ', 'ヒ': 'ビ', 'フ': 'ブ', 'ヘ': 'ベ', 'ホ': 'ボ', //
  'ウ': 'ヴ',
};

const _handakuten = {
  'ハ': 'パ', 'ヒ': 'ピ', 'フ': 'プ', 'ヘ': 'ペ', 'ホ': 'ポ', //
};
