/// Web 小説（なろう・カクヨム）の、長押しで挟むしおり（フォークで追加）。
///
/// ローカルの本棚のしおり（`PinnedBookmark`）と同じく1作品に3つまで。
/// Web 小説は話ごとに本文が分かれているので、話の番号と、その話の中の
/// 文字位置・割合で場所を持つ。
/// 保存先は `<documents>/reader/web_pins.json`。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Web 小説のしおり。
@immutable
class WebPin {
  /// コンストラクタ。
  const WebPin({
    required this.source,
    required this.workId,
    required this.title,
    required this.episode,
    required this.offset,
    required this.fraction,
    required this.snippet,
    required this.createdAt,
  });

  /// JSONから生成する。読めないサイトのものは null。
  static WebPin? fromJson(Map<String, dynamic> json) {
    final source = NovelSource.values
        .where((s) => s.name == json['source'])
        .firstOrNull;
    if (source == null) return null;
    return WebPin(
      source: source,
      workId: json['workId'] as String,
      title: json['title'] as String? ?? '',
      episode: json['episode'] as int,
      offset: json['offset'] as int,
      fraction: (json['fraction'] as num).toDouble(),
      snippet: json['snippet'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
    );
  }

  /// 1作品に挟めるしおりの数。
  static const maxPerWork = 3;

  /// サイト。
  final NovelSource source;

  /// サイトでの作品 ID。
  final String workId;

  /// 作品名（一覧に出す）。
  final String title;

  /// 話の番号。
  final int episode;

  /// その話の本文の文字位置（文の頭）。
  final int offset;

  /// その話の中のどこか（0.0〜1.0）。
  final double fraction;

  /// その場所の冒頭の文字。
  final String snippet;

  /// 挟んだ日時。
  final DateTime createdAt;

  /// 同じ作品か。
  bool sameWork(NovelSource source, String workId) =>
      this.source == source && this.workId == workId;

  /// JSONに変換する。
  Map<String, dynamic> toJson() => {
    'source': source.name,
    'workId': workId,
    'title': title,
    'episode': episode,
    'offset': offset,
    'fraction': fraction,
    'snippet': snippet,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };
}

/// Web 小説のしおりの一覧（挟んだ順）。
final webPinsProvider = AsyncNotifierProvider<WebPinsNotifier, List<WebPin>>(
  WebPinsNotifier.new,
);

/// Web 小説のしおりを管理する。変えるたびにファイルへ保存する。
class WebPinsNotifier extends AsyncNotifier<List<WebPin>> {
  /// 保存先（テストでは差し替える）。
  @visibleForTesting
  static Future<File> Function() fileOf = () async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, 'reader', 'web_pins.json'));
  };

  @override
  Future<List<WebPin>> build() async {
    try {
      final file = await fileOf();
      if (!file.existsSync()) return const [];
      final list = jsonDecode(await file.readAsString()) as List;
      return [
        for (final item in list)
          ?WebPin.fromJson(item as Map<String, dynamic>),
      ];
    } on Object catch (e) {
      debugPrint('Web 小説のしおりを読めませんでした: $e');
      return const [];
    }
  }

  /// 作品のしおり（話・場所の順）。
  List<WebPin> pinsOf(NovelSource source, String workId) =>
      [
        for (final pin in state.value ?? const <WebPin>[])
          if (pin.sameWork(source, workId)) pin,
      ]..sort((a, b) {
        final byEpisode = a.episode.compareTo(b.episode);
        return byEpisode != 0 ? byEpisode : a.offset.compareTo(b.offset);
      });

  /// しおりを挟む。作品のしおりが埋まっていたら [replace]（指定が無ければ
  /// いちばん古いもの）と入れ替える。
  Future<void> add(WebPin pin, {WebPin? replace}) async {
    final all = [...await future];
    final mine = [
      for (final p in all)
        if (p.sameWork(pin.source, pin.workId)) p,
    ];
    if (mine.length >= WebPin.maxPerWork) {
      final oldest = mine.reduce(
        (a, b) => a.createdAt.isBefore(b.createdAt) ? a : b,
      );
      all.remove(replace ?? oldest);
    }
    all.add(pin);
    await _save(all);
  }

  /// しおりを外す。
  Future<void> remove(WebPin pin) async {
    await _save([...await future]..remove(pin));
  }

  Future<void> _save(List<WebPin> pins) async {
    state = AsyncData(List.unmodifiable(pins));
    try {
      final file = await fileOf();
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode([for (final p in pins) p.toJson()]));
      await tmp.rename(file.path);
    } on Object catch (e) {
      debugPrint('Web 小説のしおりを保存できませんでした: $e');
    }
  }
}
