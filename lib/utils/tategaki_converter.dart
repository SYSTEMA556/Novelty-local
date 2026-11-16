import 'package:narou_parser/narou_parser.dart';
import 'package:tategaki/tategaki.dart';

/// NovelContentElementからTategakiElementへの変換ユーティリティ
class TategakiConverter {
  TategakiConverter._();

  /// NovelContentElementのリストをTategakiElementのリストに変換する
  static List<TategakiElement> convert(
    List<NovelContentElement> elements, {
    bool isRubyEnabled = true,
  }) {
    final result = <TategakiElement>[];

    for (final element in elements) {
      switch (element) {
        case PlainText(:final text):
          // PlainTextはTategakiParserでパースして縦中横などを適用
          result.addAll(TategakiParser.parse(text));
        case RubyText(:final base, :final ruby):
          if (isRubyEnabled) {
            // ルビ有効時: TategakiElement.rubyとして変換
            result.add(TategakiElement.ruby(base: base, ruby: ruby));
          } else {
            // ルビ無効時: ベーステキストのみをパース
            result.addAll(TategakiParser.parse(base));
          }
        case Kenten(:final base, :final mark):
          result.add(TategakiElement.kenten(base: base, mark: mark));
        case NewLine():
          result.add(const TategakiElement.newLine());
      }
    }

    return result;
  }

  /// 変換し、各縦書き要素が本文のどこから始まるかも返す。
  ///
  /// 位置は [SpeechDocument] と同じ「本文位置」（地の文は文字数、
  /// ルビ・傍点は親文字の文字数、改行は1）で数える。
  /// 読み上げ中の文を縦書き表示の要素に対応づけるために使う。
  static TategakiConversion convertWithOffsets(
    List<NovelContentElement> elements, {
    bool isRubyEnabled = true,
  }) {
    final result = <TategakiElement>[];
    final offsets = <int>[];
    var offset = 0;

    void addParsed(String text) {
      var local = 0;
      for (final element in TategakiParser.parse(text)) {
        result.add(element);
        offsets.add(offset + local);
        local += _sourceLength(element);
      }
    }

    for (final element in elements) {
      switch (element) {
        case PlainText(:final text):
          addParsed(text);
          offset += text.length;
        case RubyText(:final base, :final ruby):
          if (isRubyEnabled) {
            result.add(TategakiElement.ruby(base: base, ruby: ruby));
            offsets.add(offset);
          } else {
            addParsed(base);
          }
          offset += base.length;
        case Kenten(:final base, :final mark):
          result.add(TategakiElement.kenten(base: base, mark: mark));
          offsets.add(offset);
          offset += base.length;
        case NewLine():
          result.add(const TategakiElement.newLine());
          offsets.add(offset);
          offset += 1;
      }
    }
    return TategakiConversion(elements: result, offsets: offsets);
  }

  /// パーサーが作った要素が、元の文字列の何文字分にあたるか。
  static int _sourceLength(TategakiElement element) {
    return switch (element) {
      TategakiChar(:final char) => char.length,
      TategakiTcy(:final text) => text.length,
      TategakiRotated(:final text) => text.length,
      TategakiNewLine() => 1,
      TategakiRuby(:final base) => base.length,
      TategakiKenten(:final base) => base.length,
    };
  }
}

/// 縦書き要素と、各要素の本文位置。
class TategakiConversion {
  /// コンストラクタ。
  const TategakiConversion({required this.elements, required this.offsets});

  /// 縦書き要素。
  final List<TategakiElement> elements;

  /// 各要素の開始位置（本文位置）。[elements] と同じ長さ。
  final List<int> offsets;

  /// 本文位置の範囲 [start, end) にかかる要素の範囲を返す。
  ({int start, int end}) elementRange(int start, int end) {
    return (start: _firstAtOrAfter(start), end: _firstAtOrAfter(end));
  }

  // 開始位置が [offset] 以上になる最初の要素の番号
  int _firstAtOrAfter(int offset) {
    var low = 0;
    var high = offsets.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (offsets[mid] < offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}
