/// 一覧の並び順と、右端のインデックス（#・A〜Z・あ〜わ・漢）を決める。
///
/// - 全角英数字は半角に、カタカナはひらがなに揃えてから比べる
///   （「カ」と「か」が同じ行に並ぶ）
/// - 濁音・半濁音・小書き文字は元の行に入れる（「が」は「か」行）
/// - 漢字は呼び出し側で読み仮名に直してから渡す（読めなかったものは「漢」）
class KanaIndex {
  KanaIndex._();

  /// 数字・記号など。
  static const otherLabel = '#';

  /// 漢字で始まるもの。
  static const kanjiLabel = '漢';

  /// 作者不明。
  static const unknownLabel = '？';

  /// かなの行。
  static const kanaRows = ['あ', 'か', 'さ', 'た', 'な', 'は', 'ま', 'や', 'ら', 'わ'];

  static const _rowMembers = {
    'あ': 'ぁあぃいぅうぇえぉおゔ',
    'か': 'かがきぎくぐけげこごゕゖ',
    'さ': 'さざしじすずせぜそぞ',
    'た': 'ただちぢっつづてでとど',
    'な': 'なにぬねの',
    'は': 'はばぱひびぴふぶぷへべぺほぼぽ',
    'ま': 'まみむめも',
    'や': 'ゃやゅゆょよ',
    'ら': 'らりるれろ',
    'わ': 'ゎわゐゑをん',
  };

  static final Map<int, String> _rowOf = {
    for (final entry in _rowMembers.entries)
      for (final rune in entry.value.runes) rune: entry.key,
  };

  /// 比較用のキー（全角→半角、小文字化、空白除去、カタカナ→ひらがな）。
  static String sortKey(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune == 0x20 || rune == 0x3000) continue;
      if (rune >= 0xFF01 && rune <= 0xFF5E) {
        buffer.writeCharCode(rune - 0xFEE0);
      } else if (rune >= 0x30A1 && rune <= 0x30F6) {
        // カタカナ → ひらがな
        buffer.writeCharCode(rune - 0x60);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString().toLowerCase();
  }

  /// 先頭文字から、インデックスの見出しを決める。
  static String labelOf(String text) {
    final key = sortKey(text);
    if (key.isEmpty) return otherLabel;
    final first = key.runes.first;
    if (first >= 0x61 && first <= 0x7A) {
      return String.fromCharCode(first - 0x20);
    }
    final row = _rowOf[first];
    if (row != null) return row;
    if (_isKanji(first)) return kanjiLabel;
    return otherLabel;
  }

  /// 見出しの並び順（# → A〜Z → あ〜わ → 漢 → ？）。
  static int orderOf(String label) {
    if (label == otherLabel) return 0;
    if (label.length == 1) {
      final c = label.codeUnitAt(0);
      if (c >= 0x41 && c <= 0x5A) return 1 + (c - 0x41);
    }
    final row = kanaRows.indexOf(label);
    if (row >= 0) return 27 + row;
    if (label == kanjiLabel) return 37;
    return 38;
  }

  /// 見出しの順、同じ見出しの中ではキーの順で比べる。
  static int compare(String a, String b) {
    final byLabel = orderOf(labelOf(a)).compareTo(orderOf(labelOf(b)));
    if (byLabel != 0) return byLabel;
    return sortKey(a).compareTo(sortKey(b));
  }

  static bool _isKanji(int c) =>
      (c >= 0x4E00 && c <= 0x9FFF) ||
      (c >= 0x3400 && c <= 0x4DBF) ||
      (c >= 0xF900 && c <= 0xFAFF) ||
      (c >= 0x20000 && c <= 0x2FFFF) ||
      c == 0x3005;
}
