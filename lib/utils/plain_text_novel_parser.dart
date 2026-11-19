import 'dart:convert';
import 'dart:typed_data';

import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/utils/japanese_legacy_codecs.dart';
import 'package:novelty/utils/text_width.dart';

/// テキストファイルの文字コードを判別できなかったときに投げる例外。
class UnsupportedTextEncodingException implements Exception {
  /// コンストラクタ。
  const UnsupportedTextEncodingException();

  @override
  String toString() =>
      'このファイルの文字コードを判別できませんでした。'
      'UTF-8 で保存し直してから開いてください。';
}

/// ローカルのテキストファイル（.txt）を本文要素に変換するパーサー。
///
/// なろう・カクヨム互換のルビ／傍点記法に対応する。
/// - `｜親文字《るび》` / `|親文字《るび》`
/// - `漢字《かんじ》`（縦棒なし。直前の連続した漢字を親文字とみなす）
/// - `《《傍点》》`
/// - `｜《` は `《` をそのまま表示する（エスケープ）
class PlainTextNovelParser {
  PlainTextNovelParser._();

  /// ルビとして認める最大文字数（誤検出防止）。
  static const int maxRubyLength = 20;

  /// 縦棒指定時に親文字として認める最大文字数（誤検出防止）。
  static const int maxBaseLength = 20;

  /// バイト列を文字列にデコードする。
  ///
  /// BOM付きUTF-8 / UTF-16（LE・BE）/ BOMなしUTF-8 に対応する。
  /// UTF-8 として読めなければ Shift_JIS・EUC-JP として読み、
  /// 読めない所の少ないほうを選ぶ（フォークで追加）。
  /// どれでもほとんど読めない場合は [UnsupportedTextEncodingException] を投げる。
  static String decode(Uint8List bytes) => decodeDetailed(bytes).text;

  /// [decode] と同じく読み、どの文字コードとして読んだかも返す。
  ///
  /// errors は読めずに「�」にしたバイトの数（UTF-8・UTF-16 なら 0）。
  static ({String text, String encoding, int errors}) decodeDetailed(
    Uint8List bytes,
  ) {
    final hasUtf16Bom =
        bytes.length >= 2 &&
        ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
            (bytes[0] == 0xFE && bytes[1] == 0xFF));
    // 0 のバイトは UTF-8 の文章には出てこないので、先に BOM の無い UTF-16 を見る
    final bomless = hasUtf16Bom ? null : _decodeBomlessUtf16(bytes);
    if (bomless != null) {
      return (text: bomless, encoding: 'UTF-16', errors: 0);
    }
    try {
      return (
        text: _decodeUnicode(bytes),
        encoding: hasUtf16Bom ? 'UTF-16' : 'UTF-8',
        errors: 0,
      );
    } on UnsupportedTextEncodingException {
      // 下で UTF-8 以外を試す
    }
    final sjis = decodeShiftJis(bytes);
    final euc = decodeEucJp(bytes);
    final best = euc.penalty < sjis.penalty ? euc : sjis;
    // 読めない所が多すぎるなら、どちらでもない（画像などの別物）
    if (best.errors > 16 && best.errors * 50 > bytes.length) {
      throw const UnsupportedTextEncodingException();
    }
    return (
      text: best.text,
      encoding: identical(best, euc) ? 'EUC-JP' : 'Shift_JIS',
      errors: best.errors,
    );
  }

  // BOM の無い UTF-16（半角が多い文章では、1バイトおきに 0 が並ぶ）
  static String? _decodeBomlessUtf16(Uint8List bytes) {
    if (bytes.length < 16) return null;
    final sample = bytes.length < 4096 ? bytes.length : 4096;
    var evenZeros = 0;
    var oddZeros = 0;
    for (var i = 0; i + 1 < sample; i += 2) {
      if (bytes[i] == 0) evenZeros++;
      if (bytes[i + 1] == 0) oddZeros++;
    }
    final pairs = sample ~/ 2;
    if (oddZeros * 3 > pairs && evenZeros * 20 < pairs) {
      return _decodeUtf16(bytes, littleEndian: true);
    }
    if (evenZeros * 3 > pairs && oddZeros * 20 < pairs) {
      return _decodeUtf16(bytes, littleEndian: false);
    }
    return null;
  }

  static String _decodeUnicode(Uint8List bytes) {
    // UTF-8 BOM
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return _decodeUtf8(bytes.sublist(3));
    }
    // UTF-16 LE BOM
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: true);
    }
    // UTF-16 BE BOM
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: false);
    }
    return _decodeUtf8(bytes);
  }

  static String _decodeUtf8(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const UnsupportedTextEncodingException();
    }
  }

  static String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(
        littleEndian
            ? bytes[i] | (bytes[i + 1] << 8)
            : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    return String.fromCharCodes(units);
  }

  static final _htmlComment = RegExp(r'<!--[\s\S]*?-->');
  static final _htmlBreak = RegExp(r'<br\s*/?>', caseSensitive: false);
  static final _htmlTag = RegExp(r'</?[a-zA-Z][a-zA-Z0-9]*(?:\s[^<>]*)?/?>');
  static final _htmlDeclaration = RegExp('<![^<>]*>');
  static final _aozoraNote = RegExp('［＃[^］\n]*］');
  static final _separator = RegExp(r'^\s*[-－―─]{10,}\s*$');
  static final _numericEntity = RegExp('&#([xX]?)([0-9a-fA-F]+);');
  static const _namedEntities = {
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&apos;': "'",
    '&nbsp;': ' ',
    '&amp;': '&',
  };

  /// 青空文庫の「テキスト中に現れる記号について」の説明の見出し。
  static const aozoraNoticeHeading = '【テキスト中に現れる記号について】';

  /// 本文に混ざった HTML のタグや青空文庫の注記を取り除く。
  ///
  /// - HTML のタグ・コメントは消し、`<br>` は改行にする。`&amp;` などは文字に戻す
  /// - 青空文庫の注記（`［＃改ページ］` など）と、冒頭の記号の説明は消す
  /// - タグや注記だけでできていた行は、行ごと消す
  static String cleanMarkup(String text) {
    final normalized = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(_htmlComment, '')
        .replaceAll(_htmlBreak, '\n');
    final lines = _removeAozoraNotice(normalized.split('\n'));
    final out = <String>[];
    for (final line in lines) {
      final cleaned = cleanLine(line);
      if (cleaned.trim().isEmpty && line.trim().isNotEmpty) continue;
      out.add(cleaned);
    }
    return out.join('\n');
  }

  /// 1行から HTML のタグと青空文庫の注記を取り除く。
  static String cleanLine(String line) {
    final stripped = line
        .replaceAll(_htmlTag, '')
        .replaceAll(_htmlDeclaration, '')
        .replaceAll(_aozoraNote, '');
    if (!stripped.contains('&')) return stripped;
    final named = _namedEntities.entries.fold(
      stripped,
      (text, entry) => text.replaceAll(entry.key, entry.value),
    );
    return named.replaceAllMapped(_numericEntity, (match) {
      final code = int.tryParse(
        match.group(2)!,
        radix: match.group(1)!.isEmpty ? 10 : 16,
      );
      if (code == null || code <= 0 || code > 0x10FFFF) return match.group(0)!;
      return String.fromCharCode(code);
    });
  }

  // 冒頭の区切り線で挟まれた「記号について」の説明を取り除く
  static List<String> _removeAozoraNotice(List<String> lines) {
    final searchEnd = lines.length < 80 ? lines.length : 80;
    for (var start = 0; start < searchEnd; start++) {
      if (!_separator.hasMatch(lines[start])) continue;
      final limit = start + 60 < lines.length ? start + 60 : lines.length;
      for (var end = start + 1; end < limit; end++) {
        if (!_separator.hasMatch(lines[end])) continue;
        final block = lines.sublist(start, end);
        if (block.any((line) => line.contains(aozoraNoticeHeading))) {
          return [...lines.sublist(0, start), ...lines.sublist(end + 1)];
        }
        break;
      }
    }
    return lines;
  }

  /// テキストを本文要素のリストに変換する。
  ///
  /// [clean] なら、先に [cleanMarkup] で HTML のタグや青空文庫の注記を取り除く。
  /// [unifyWidth] なら、全角英数字を半角に、半角カナを全角にそろえる
  /// （[unifyTextWidth]）。
  static List<NovelContentElement> parse(
    String text, {
    bool clean = true,
    bool unifyWidth = false,
  }) {
    final widened = unifyWidth ? unifyTextWidth(text) : text;
    final normalized = clean
        ? cleanMarkup(widened)
        : widened.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    // 末尾の改行による空行は表示しない
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }

    final elements = <NovelContentElement>[];
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) elements.add(NovelContentElement.newLine());
      _parseLine(lines[i], elements);
    }
    return elements;
  }

  /// 1行分を解析して [out] に追加する。
  static void _parseLine(String line, List<NovelContentElement> out) {
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isNotEmpty) {
        out.add(NovelContentElement.plainText(buffer.toString()));
        buffer.clear();
      }
    }

    var i = 0;
    while (i < line.length) {
      final ch = line[i];

      // 傍点: 《《...》》
      if (line.startsWith('《《', i)) {
        final end = line.indexOf('》》', i + 2);
        if (end > i + 2) {
          flush();
          out.add(
            NovelContentElement.kenten(line.substring(i + 2, end), '﹅'),
          );
          i = end + 2;
          continue;
        }
      }

      // 縦棒による明示ルビ: ｜親文字《るび》
      if (ch == '｜' || ch == '|') {
        // エスケープ: ｜《 は 《 をそのまま表示
        if (i + 1 < line.length && line[i + 1] == '《') {
          buffer.write('《');
          i += 2;
          continue;
        }
        final open = line.indexOf('《', i + 1);
        if (open > i + 1 && open - (i + 1) <= maxBaseLength) {
          final close = line.indexOf('》', open + 1);
          final rubyLength = close - (open + 1);
          if (close > open + 1 && rubyLength <= maxRubyLength) {
            flush();
            out.add(
              NovelContentElement.rubyText(
                line.substring(i + 1, open),
                line.substring(open + 1, close),
              ),
            );
            i = close + 1;
            continue;
          }
        }
        // 記法として成立しなければ縦棒は文字として扱う
        buffer.write(ch);
        i++;
        continue;
      }

      // 縦棒なしルビ: 漢字《かんじ》
      if (ch == '《') {
        final close = line.indexOf('》', i + 1);
        final rubyLength = close - (i + 1);
        if (close > i + 1 && rubyLength <= maxRubyLength) {
          final pending = buffer.toString();
          var start = pending.length;
          while (start > 0 && _isKanji(pending.codeUnitAt(start - 1))) {
            start--;
          }
          if (start < pending.length) {
            buffer
              ..clear()
              ..write(pending.substring(0, start));
            flush();
            out.add(
              NovelContentElement.rubyText(
                pending.substring(start),
                line.substring(i + 1, close),
              ),
            );
            i = close + 1;
            continue;
          }
        }
      }

      buffer.write(ch);
      i++;
    }
    flush();
  }

  /// 縦棒なしルビの親文字になり得る文字（漢字・々・〆・ヶ など）か判定する。
  static bool _isKanji(int c) {
    return (c >= 0x4E00 && c <= 0x9FFF) || // CJK統合漢字
        (c >= 0x3400 && c <= 0x4DBF) || // CJK統合漢字拡張A
        (c >= 0xF900 && c <= 0xFAFF) || // CJK互換漢字
        c == 0x3005 || // 々
        c == 0x3006 || // 〆
        c == 0x30F6 || // ヶ
        c == 0x30F5; // ヵ
  }
}
