import 'package:flutter/foundation.dart';
import 'package:narou_parser/narou_parser.dart';

/// 読み上げる1文。
///
/// [start]・[end] は本文中の位置（下記「本文位置」）で、
/// 読んでいる箇所の色付けや、読み上げ位置の保存に使う。
///
/// 本文位置：本文要素を先頭から数えた文字位置。
/// 地の文は文字数、ルビ・傍点は親文字の文字数、改行は1として数える。
/// 縦書き・横書きのどちらの表示とも対応づけられるよう、表示に依らない数え方にしている。
@immutable
class SpeechSegment {
  /// コンストラクタ。
  const SpeechSegment({
    required this.start,
    required this.end,
    required this.text,
  });

  /// 開始位置（本文位置、含む）。
  final int start;

  /// 終了位置（本文位置、含まない）。
  final int end;

  /// 読み上げる文字列（ルビは読み仮名に置き換え済み）。
  final String text;

  @override
  bool operator ==(Object other) =>
      other is SpeechSegment &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);

  @override
  String toString() => 'SpeechSegment($start-$end: $text)';
}

/// 本文を、読み上げ用の文の並びに変換したもの。
@immutable
class SpeechDocument {
  const SpeechDocument._(this.segments, this.length);

  /// 本文要素から作る。
  ///
  /// - 句点・感嘆符・疑問符（直後の閉じ括弧も含む）と改行で文を区切る
  /// - 台詞（「」『』）と心の声（（））は、地の文と別の文にする
  ///   （声色を変えて演じ分けるため）
  /// - ルビは読み仮名で読む（「漢字《かんじ》」は「かんじ」）
  /// - 長すぎる文は読点で区切る（読み上げエンジンの上限対策）
  /// - 読む文字が無い文（空行・記号だけ・HTMLタグだけの行）は飛ばす
  factory SpeechDocument.fromElements(List<NovelContentElement> elements) {
    final builder = _SegmentBuilder();
    var offset = 0;
    for (final element in elements) {
      switch (element) {
        case PlainText(:final text):
          for (var i = 0; i < text.length; i++) {
            final ch = text[i];
            if (ch == '\n') {
              builder.breakAt(offset + i);
              continue;
            }
            builder.add(ch, offset + i, offset + i + 1);
            if (_sentenceEnds.contains(ch)) builder.markSentenceEnd();
          }
          offset += text.length;
        case RubyText(:final base, :final ruby):
          builder.add(ruby, offset, offset + base.length);
          offset += base.length;
        case Kenten(:final base):
          builder.add(base, offset, offset + base.length);
          offset += base.length;
        case NewLine():
          builder.breakAt(offset);
          offset += 1;
      }
    }
    builder.breakAt(offset);
    return SpeechDocument._(List.unmodifiable(builder.segments), offset);
  }

  /// 文の並び。
  final List<SpeechSegment> segments;

  /// 本文全体の長さ（本文位置）。
  final int length;

  /// 本文位置 [offset] を含む（無ければ直後の）文の番号。
  ///
  /// 本文の終わりより後なら最後の文の番号を返す。文が無ければ 0。
  int segmentIndexAt(int offset) {
    if (segments.isEmpty) return 0;
    var low = 0;
    var high = segments.length - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (segments[mid].end <= offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// 読み進めた割合（0.0〜1.0）に相当する文の番号。
  int segmentIndexAtProgress(double progress) {
    final clamped = progress.isNaN ? 0.0 : progress.clamp(0.0, 1.0);
    return segmentIndexAt((length * clamped).floor());
  }

  // 「…」「‥」は文の途中（「彼は……黙った」）にもよく出るため、文末にしない
  static const _sentenceEnds = {'。', '！', '？', '!', '?'};
}

class _SegmentBuilder {
  final segments = <SpeechSegment>[];
  final _text = StringBuffer();
  int? _start;
  int _end = 0;
  bool _ended = false;

  /// 1文の最大文字数。超えたら読点で区切る。
  static const _maxLength = 200;

  static const _closings = {'」', '』', '）', ')', '】', '〉', '》', '”', '’'};
  static const _endMarks = {'。', '！', '？', '!', '?'};
  static const _quoteOpenings = {'「', '『', '（', '('};
  static const _quoteClosings = {'」', '』', '）', ')'};

  // 地の文の途中でも区切る開き括弧（『』は書名、（）は読み仮名や注釈にも
  // 使われるため、文の頭にあるときだけ台詞・心の声として扱う）
  static const _splitOpenings = {'「'};

  // 文の頭が開き括弧だったときの括弧の深さ（頭が括弧でなければ null）
  int? _quoteDepth;
  static final _speakable = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final _tagOnly = RegExp(r'^\s*</?[a-zA-Z][^>]*>\s*$');

  void add(String text, int start, int end) {
    // 文末の後に閉じ括弧や文末の記号（！！・！？）が続く場合は同じ文に含める
    if (_ended &&
        !(text.length == 1 &&
            (_closings.contains(text) || _endMarks.contains(text)))) {
      _flush();
    }
    final isOpening = text.length == 1 && _quoteOpenings.contains(text);
    // 地の文の途中から台詞が始まるときは、その手前で区切る
    if (_splitOpenings.contains(text) &&
        _quoteDepth == null &&
        _speakable.hasMatch(_text.toString())) {
      _flush();
    }
    if (_start == null) {
      _start = start;
      _quoteDepth = isOpening ? 0 : null;
    }
    _text.write(text);
    _end = end;
    final depth = _quoteDepth;
    if (depth != null && text.length == 1) {
      if (_quoteOpenings.contains(text)) {
        _quoteDepth = depth + 1;
      } else if (_quoteClosings.contains(text)) {
        _quoteDepth = depth - 1;
        // 台詞が閉じたら、続く地の文（「〜と言った」）は別の文にする
        if (depth - 1 <= 0) _ended = true;
      }
    }
    if (_text.length >= _maxLength && (text == '、' || text == '，')) {
      _flush();
    }
  }

  void markSentenceEnd() => _ended = true;

  void breakAt(int offset) => _flush();

  void _flush() {
    _ended = false;
    _quoteDepth = null;
    final start = _start;
    final text = _text.toString();
    _text.clear();
    _start = null;
    if (start == null) return;
    if (!_speakable.hasMatch(text) || _tagOnly.hasMatch(text)) return;
    segments.add(SpeechSegment(start: start, end: _end, text: text.trim()));
  }
}
