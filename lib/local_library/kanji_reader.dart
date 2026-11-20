/// 漢字の読み仮名の辞書（フォークで追加）。
///
/// `assets/dict/readings.tsv.gz`（JMdict から
/// tool/build_reading_dictionary.py で作成、CC BY-SA 4.0）を Isolate で展開し、
/// ソート済みの行を二分探索して最長一致で読む。
/// ソートキーを作るためだけの用途で、表示する読みではない。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 読み仮名の辞書（アプリに同梱）。
///
/// 1行に「漢字を含む語・タブ・ひらがなの読み」。語の順に並べて gzip 圧縮する。
/// 作り方は tool/build_reading_dictionary.py を参照。
const readingDictionaryAsset = 'assets/dict/readings.tsv.gz';

/// 漢字の読みを辞書から推測する。
///
/// 作品名や作者名を「あいうえお順」に並べるために使う。
/// 文の頭から、辞書にある一番長い語を当てはめていく（最長一致）。
/// 辞書にない文字はそのまま残す。並べ替えに効くのは頭の数文字なので、
/// 人名などで多少外れても、順番が大きく狂うことは少ない。
class KanjiReader {
  KanjiReader._(this._data, this._lineStarts);

  /// 辞書の本文（TSV）から作る。
  ///
  /// 行は UTF-16 の並び順に並んでいる前提で、各行の先頭位置だけを覚える。
  /// 語ごとの表（Map）は作らず、本文の上で直接二分探索する
  /// （計算は少し増えるが、メモリは本文と行の位置の分だけで済む）。
  factory KanjiReader.fromTsv(String data) {
    final starts = <int>[];
    var pos = 0;
    while (pos < data.length) {
      final end = data.indexOf('\n', pos);
      final lineEnd = end < 0 ? data.length : end;
      final tab = data.indexOf('\t', pos);
      if (tab > pos && tab < lineEnd) starts.add(pos);
      pos = lineEnd + 1;
    }
    return KanjiReader._(data, Int32List.fromList(starts));
  }

  final String _data;

  // 各行の先頭位置（行は語の UTF-16 順）
  final Int32List _lineStarts;

  // 読み終えた文の結果（作品名・作者名の数だけ。多すぎたら捨てる）
  final Map<String, String> _cache = {};

  static const int _maxCache = 50000;

  static const int _tab = 0x09;

  /// 読みを推測する文字数の上限（並べ替えには頭だけで足りる）。
  static const int maxReadLength = 40;

  // 行 [line] の語の [depth] 文字目（語がそこで終わっていればタブ）
  int _charAt(int line, int depth) =>
      _data.codeUnitAt(_lineStarts[line] + depth);

  // [lo, hi) のうち、[depth] 文字目が [c] 以上（[upper] なら c より大きい）
  // になる最初の行
  int _bound(int lo, int hi, int depth, int c, {required bool upper}) {
    var low = lo;
    var high = hi;
    while (low < high) {
      final mid = (low + high) >> 1;
      final v = _charAt(mid, depth);
      if (upper ? v <= c : v < c) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  String _readingOfLine(int line, int keyLength) {
    final start = _lineStarts[line] + keyLength + 1;
    final next = line + 1 < _lineStarts.length
        ? _lineStarts[line + 1] - 1
        : _data.length;
    var end = next;
    while (end > start && _data.codeUnitAt(end - 1) == 0x0A) {
      end--;
    }
    return _data.substring(start, end);
  }

  /// [text] の [from] から始まる一番長い語の（長さ, 読み）。なければ null。
  ///
  /// 1文字進むごとに「その文字で始まる語の範囲」を二分探索で狭めていく。
  (int, String)? _longestMatch(String text, int from, int limit) {
    var lo = 0;
    var hi = _lineStarts.length;
    (int, String)? best;
    for (var depth = 0; from + depth < limit; depth++) {
      final c = text.codeUnitAt(from + depth);
      lo = _bound(lo, hi, depth, c, upper: false);
      hi = _bound(lo, hi, depth, c, upper: true);
      if (lo >= hi) break;
      // 範囲の先頭は、ちょうどこの長さで終わる語（タブが一番小さいため）
      if (_charAt(lo, depth + 1) == _tab) {
        best = (depth + 1, _readingOfLine(lo, depth + 1));
      }
    }
    return best;
  }

  /// [word] そのものの読み（辞書になければ null）。
  String? lookup(String word) {
    if (word.isEmpty) return null;
    final match = _longestMatch(word, 0, word.length);
    return match != null && match.$1 == word.length ? match.$2 : null;
  }

  /// [text] の漢字を読み仮名に置き換えた文字列を返す。
  ///
  /// かな・英数字・記号はそのまま残す。
  String read(String text) {
    final cached = _cache[text];
    if (cached != null) return cached;
    final limit = text.length < maxReadLength ? text.length : maxReadLength;
    final buffer = StringBuffer();
    var i = 0;
    while (i < limit) {
      final head = text.codeUnitAt(i);
      // 英字・数字から始まる語（「Ｘ線」など）はかなに直さず、A〜Z・# に残す
      final match = _isLatinOrDigit(head)
          ? null
          : _longestMatch(text, i, limit);
      if (match == null) {
        buffer.writeCharCode(head);
        i++;
      } else {
        buffer.write(match.$2);
        i += match.$1;
      }
    }
    if (limit < text.length) buffer.write(text.substring(limit));
    if (_cache.length >= _maxCache) _cache.clear();
    return _cache[text] = buffer.toString();
  }
}

bool _isLatinOrDigit(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0xFF10 && c <= 0xFF19) ||
    (c >= 0xFF21 && c <= 0xFF3A) ||
    (c >= 0xFF41 && c <= 0xFF5A);

/// gzip 圧縮された辞書を展開して [KanjiReader] を作る。
KanjiReader parseKanjiReadings(List<int> compressed) =>
    KanjiReader.fromTsv(utf8.decode(gzip.decode(compressed)));

// Isolateへ渡すクロージャが呼び出し元の状態を巻き込まないよう、
// 引数だけを受け取るトップレベル関数を経由する。
Future<KanjiReader> _parseInBackground(Uint8List bytes) =>
    Isolate.run(() => parseKanjiReadings(bytes));

/// 読み仮名の辞書。読み込めなければ null（漢字は「漢」にまとめる）。
final kanjiReaderProvider = FutureProvider<KanjiReader?>((ref) async {
  try {
    final data = await rootBundle.load(readingDictionaryAsset);
    return await _parseInBackground(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  } on Object catch (e) {
    debugPrint('読み仮名の辞書を読み込めませんでした: $e');
    return null;
  }
});

/// 辞書の出典とライセンスを、アプリの「ライセンス」画面に載せる。
void registerReadingDictionaryLicense() {
  LicenseRegistry.addLicense(
    () => Stream.value(
      const LicenseEntryWithLineBreaks(
        ['読み仮名の辞書 (JMdict / JMnedict / KANJIDIC2)'],
        'ローカル作品の並べ替えに使う読み仮名の辞書は、'
        'Electronic Dictionary Research and Development Group (EDRDG) の '
        'JMdict・JMnedict・KANJIDIC2 をもとに作成しています。\n\n'
        'These files are the property of the Electronic Dictionary Research '
        'and Development Group, and are used in conformance with the '
        "Group's licence.\n"
        'https://www.edrdg.org/edrdg/licence.html\n\n'
        'Licensed under the Creative Commons Attribution-ShareAlike 4.0 '
        'International License (CC BY-SA 4.0).\n'
        'https://creativecommons.org/licenses/by-sa/4.0/',
      ),
    ),
  );
}
