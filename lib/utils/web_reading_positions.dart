import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Web小説の1話ごとの読書位置（話の途中のどこまで読んだか）。
class WebEpisodePosition {
  /// コンストラクタ。
  const WebEpisodePosition({required this.offsets, required this.updatedAt});

  /// JSON から復元する。
  factory WebEpisodePosition.fromJson(Map<String, dynamic> json) {
    final raw = json['offsets'] as Map<String, dynamic>? ?? const {};
    return WebEpisodePosition(
      offsets: {
        for (final entry in raw.entries)
          entry.key: (entry.value as num).toDouble(),
      },
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// 表示モードごとのスクロール位置。
  final Map<String, double> offsets;

  /// 最後に読んだ日時。
  final DateTime updatedAt;

  /// JSON に変換する。
  Map<String, dynamic> toJson() => {
    'offsets': offsets,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

/// 読書位置の保存キー（サイト・作品・話ごと）。
String webEpisodeKey(NovelSource source, String workId, int episode) =>
    '${source.name}:$workId:$episode';

/// 保存しておく話数の上限。超えたら古いものから消す。
const int maxWebEpisodePositions = 3000;

/// 上限を超えた分を、最後に読んだのが古い順に取り除く。
Map<String, WebEpisodePosition> pruneWebPositions(
  Map<String, WebEpisodePosition> positions, {
  int limit = maxWebEpisodePositions,
}) {
  if (positions.length <= limit) return positions;
  final entries = positions.entries.toList()
    ..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));
  return Map.fromEntries(entries.take(limit));
}

/// Web小説の読書位置。
final webReadingPositionsProvider =
    AsyncNotifierProvider<
      WebReadingPositionsNotifier,
      Map<String, WebEpisodePosition>
    >(WebReadingPositionsNotifier.new);

/// Web小説の読書位置を管理する。
///
/// スクロールのたびに書き込むと負荷が高いため、
/// 状態へはすぐ反映し、ファイル保存は少し待ってまとめて行う。
class WebReadingPositionsNotifier
    extends AsyncNotifier<Map<String, WebEpisodePosition>> {
  Timer? _saveTimer;

  Future<File> _file() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, 'reader', 'web_positions.json'));
  }

  @override
  Future<Map<String, WebEpisodePosition>> build() async {
    ref.onDispose(() => _saveTimer?.cancel());
    try {
      final file = await _file();
      if (!file.existsSync()) return {};
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return {
        for (final entry in json.entries)
          entry.key: WebEpisodePosition.fromJson(
            entry.value as Map<String, dynamic>,
          ),
      };
    } on Object {
      // 読めない・壊れているときは読書位置なしで始める
      return {};
    }
  }

  /// [key] の話の、表示モード [mode] でのスクロール位置を記録する。
  void record(String key, {required String mode, required double offset}) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      pruneWebPositions({
        ...current,
        key: WebEpisodePosition(
          offsets: {...?current[key]?.offsets, mode: offset},
          updatedAt: DateTime.now(),
        ),
      }),
    );
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () => unawaited(flush()));
  }

  /// 保留中の読書位置をすぐに保存する。
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final current = state.value;
    if (current == null) return;
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(
        jsonEncode({
          for (final entry in current.entries)
            entry.key: entry.value.toJson(),
        }),
        flush: true,
      );
      await tmp.rename(file.path);
    } on Object {
      // 保存できなくても読書は続けられるので、次の機会に任せる
    }
  }
}
