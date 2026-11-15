import 'dart:convert';
import 'dart:typed_data';

import 'package:narou_parser/narou_parser.dart';

/// テキストファイルの文字コードを判別できなかったときに投げる例外。
class UnsupportedTextEncodingException implements Exception {
  /// コンストラクタ。
  const UnsupportedTextEncodingException();

  @override
  String toString() =>
      'このファイルの文字コードには対応していません。'
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
  /// いずれにも当てはまらない場合は [UnsupportedTextEncodingException] を投げる。
  static String decode(Uint8List bytes) {
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

  /// テキストを本文要素のリストに変換する。
  static List<NovelContentElement> parse(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
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
