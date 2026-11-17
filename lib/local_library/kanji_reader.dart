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
  KanjiReader._(this._data, this._blocks);

  /// 辞書の本文（TSV）から作る。
  ///
  /// 行は語の順に並んでいる前提で、頭の文字ごとの範囲だけを覚えておく。
  /// 中身はその文字が初めて使われたときに読み込む（全部を展開すると重いため）。
  factory KanjiReader.fromTsv(String data) {
    final blocks = <int, (int, int, int)>{};
    var maxKeyLength = 1;
    int? current;
    var blockStart = 0;
    var pos = 0;
    while (pos < data.length) {
      var end = data.indexOf('\n', pos);
      if (end < 0) end = data.length;
      final tab = data.indexOf('\t', pos);
      if (tab > pos && tab < end) {
        final head = data.codeUnitAt(pos);
        if (head != current) {
          if (current != null) {
            blocks[current] = (blockStart, pos, maxKeyLength);
          }
          current = head;
          blockStart = pos;
          maxKeyLength = 1;
        }
        if (tab - pos > maxKeyLength) maxKeyLength = tab - pos;
      }
      pos = end + 1;
    }
    if (current != null) {
      blocks[current] = (blockStart, data.length, maxKeyLength);
    }
    return KanjiReader._(data, blocks);
  }

  final String _data;

  // 頭の文字（UTF-16 の1単位）→ 本文中の範囲と、その中で一番長い語の長さ
  final Map<int, (int, int, int)> _blocks;

  // 頭の文字ごとに展開した「語 → 読み」
  final Map<int, Map<String, String>> _parsed = {};

  // 読み終えた文の結果
  final Map<String, String> _cache = {};

  /// 読みを推測する文字数の上限（並べ替えには頭だけで足りる）。
  static const int maxReadLength = 40;

  Map<String, String>? _blockOf(int head) {
    final cached = _parsed[head];
    if (cached != null) return cached;
    final range = _blocks[head];
    if (range == null) return null;
    final map = <String, String>{};
    final (start, end, _) = range;
    for (final line in _data.substring(start, end).split('\n')) {
      final tab = line.indexOf('\t');
      if (tab <= 0) continue;
      map[line.substring(0, tab)] = line.substring(tab + 1);
    }
    return _parsed[head] = map;
  }

  /// [word] そのものの読み（辞書になければ null）。
  String? lookup(String word) {
    if (word.isEmpty) return null;
    return _blockOf(word.codeUnitAt(0))?[word];
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
      final block = _blockOf(head);
      var matched = 0;
      if (block != null) {
        final maxKey = _blocks[head]!.$3;
        final longest = limit - i < maxKey ? limit - i : maxKey;
        for (var length = longest; length >= 1; length--) {
          final reading = block[text.substring(i, i + length)];
          if (reading != null) {
            buffer.write(reading);
            matched = length;
            break;
          }
        }
      }
      if (matched == 0) {
        buffer.writeCharCode(text.codeUnitAt(i));
        matched = 1;
      }
      i += matched;
    }
    if (limit < text.length) buffer.write(text.substring(limit));
    return _cache[text] = buffer.toString();
  }
}

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
