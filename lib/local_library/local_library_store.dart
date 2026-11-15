import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/utils/plain_text_novel_parser.dart';
import 'package:path/path.dart' as p;

/// ローカルライブラリの保存先を管理するストア。
///
/// 既存のデータベースとは独立して、次の構成でファイルに保存する。
/// - `index.json`: 作品一覧
/// - `positions.json`: 読書位置（しおり）
/// - `texts/<id>.txt`: 本文（UTF-8・BOMなしに正規化）
class LocalLibraryStore {
  /// コンストラクタ。
  LocalLibraryStore(this.rootDir);

  /// 保存先のルートディレクトリ。
  final Directory rootDir;

  File get _indexFile => File(p.join(rootDir.path, 'index.json'));

  File get _positionsFile => File(p.join(rootDir.path, 'positions.json'));

  /// 本文の保存先ディレクトリ。
  Directory get textsDir => Directory(p.join(rootDir.path, 'texts'));

  /// ファイル名から作品IDを算出する。
  ///
  /// 同じファイル名なら常に同じIDになるため、重複取り込みの判定に使う。
  static String idForFileName(String fileName) {
    final bytes = utf8.encode(fileName);
    // FNV-1a（32bit）を前方・後方の2方向で計算して連結する
    var forward = 0x811c9dc5;
    var backward = 0x811c9dc5;
    for (var i = 0; i < bytes.length; i++) {
      forward = ((forward ^ bytes[i]) * 0x01000193) & 0xFFFFFFFF;
      backward =
          ((backward ^ bytes[bytes.length - 1 - i]) * 0x01000193) & 0xFFFFFFFF;
    }
    return forward.toRadixString(16).padLeft(8, '0') +
        backward.toRadixString(16).padLeft(8, '0');
  }

  /// 作品一覧を読み込む。
  Future<List<LocalWork>> loadWorks() async {
    if (!_indexFile.existsSync()) return [];
    final raw = await _indexFile.readAsString();
    // 5000件規模でもUIが固まらないよう別Isolateで解析する
    return _decodeWorksInBackground(raw);
  }

  /// 作品一覧を保存する。
  Future<void> saveWorks(List<LocalWork> works) async {
    final data = [for (final w in works) w.toJson()];
    final raw = await _encodeInBackground(data);
    await _writeAtomically(_indexFile, raw);
  }

  /// 本文を読み込む。
  Future<String> readText(String id) {
    return File(p.join(textsDir.path, '$id.txt')).readAsString();
  }

  /// 作品を削除する（本文・一覧・読書位置）。
  Future<void> deleteWorks(Set<String> ids) async {
    final works = await loadWorks();
    works.removeWhere((w) => ids.contains(w.id));
    await saveWorks(works);

    final positions = await loadPositions();
    positions.removeWhere((id, _) => ids.contains(id));
    await savePositions(positions);

    for (final id in ids) {
      final file = File(p.join(textsDir.path, '$id.txt'));
      if (file.existsSync()) await file.delete();
    }
  }

  /// 読書位置を読み込む。
  Future<Map<String, ReadingPosition>> loadPositions() async {
    if (!_positionsFile.existsSync()) return {};
    final raw = await _positionsFile.readAsString();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return {
      for (final entry in json.entries)
        entry.key: ReadingPosition.fromJson(
          entry.value as Map<String, dynamic>,
        ),
    };
  }

  /// 読書位置を保存する。
  Future<void> savePositions(Map<String, ReadingPosition> positions) async {
    final raw = jsonEncode({
      for (final entry in positions.entries) entry.key: entry.value.toJson(),
    });
    await _writeAtomically(_positionsFile, raw);
  }

  /// テキストファイル群を取り込む。
  ///
  /// [batchSize] 件ずつ別Isolateで読み込み・コピーし、
  /// 1バッチ終わるごとに [onProgress] で進捗を通知する。
  /// 取り込み済み（同じファイル名）のものは飛ばす。
  Future<LocalImportResult> importFiles(
    List<String> paths, {
    void Function(int done, int total)? onProgress,
    int batchSize = 100,
  }) async {
    await textsDir.create(recursive: true);
    final works = await loadWorks();
    final knownIds = {for (final w in works) w.id};
    final textsPath = textsDir.path;

    var added = 0;
    var skipped = 0;
    final failed = <String>[];

    for (var start = 0; start < paths.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, paths.length);
      final batch = paths.sublist(start, end);
      final known = Set<String>.of(knownIds);
      final results = await _importBatchInBackground(batch, textsPath, known);

      for (final result in results) {
        final work = result.work;
        if (work != null) {
          works.add(work);
          knownIds.add(work.id);
          added++;
        } else if (result.failedFileName != null) {
          failed.add(result.failedFileName!);
        } else {
          skipped++;
        }
      }
      onProgress?.call(end, paths.length);
    }

    if (added > 0) await saveWorks(works);
    return LocalImportResult(
      added: added,
      skipped: skipped,
      failedFiles: failed,
    );
  }

  /// 一時ファイルに書いてから置き換え、書き込み途中で壊れないようにする。
  static Future<void> _writeAtomically(File file, String contents) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(contents, flush: true);
    await tmp.rename(file.path);
  }
}

// Isolateへ渡すクロージャが呼び出し元の状態を巻き込まないよう、
// 引数だけを受け取るトップレベル関数を経由する。
Future<List<LocalWork>> _decodeWorksInBackground(String raw) =>
    Isolate.run(() => decodeWorks(raw));

Future<String> _encodeInBackground(Object data) =>
    Isolate.run(() => jsonEncode(data));

Future<List<ImportItemResult>> _importBatchInBackground(
  List<String> paths,
  String textsDirPath,
  Set<String> knownIds,
) => Isolate.run(() => importBatch(paths, textsDirPath, knownIds));

/// 作品一覧のJSONを解析する（Isolateから呼び出す）。
@visibleForTesting
List<LocalWork> decodeWorks(String raw) {
  final list = jsonDecode(raw) as List<dynamic>;
  return [
    for (final item in list) LocalWork.fromJson(item as Map<String, dynamic>),
  ];
}

/// 1ファイル分の取り込み結果。
@immutable
class ImportItemResult {
  /// 追加できた場合。
  const ImportItemResult.added(LocalWork this.work) : failedFileName = null;

  /// 取り込み済みのため飛ばした場合。
  const ImportItemResult.skipped() : work = null, failedFileName = null;

  /// 読み込めなかった場合。
  const ImportItemResult.failed(String this.failedFileName) : work = null;

  /// 追加した作品。
  final LocalWork? work;

  /// 読み込めなかったファイル名。
  final String? failedFileName;
}

/// テキストファイル群を読み込み、本文を保存先へコピーする。
///
/// 別Isolateで実行するためトップレベル関数にしている。
/// [knownIds] は取り込み済みのID集合で、同一バッチ内の重複も防ぐ。
@visibleForTesting
List<ImportItemResult> importBatch(
  List<String> paths,
  String textsDirPath,
  Set<String> knownIds,
) {
  final now = DateTime.now();
  final results = <ImportItemResult>[];
  for (final path in paths) {
    final fileName = p.basename(path);
    final id = LocalLibraryStore.idForFileName(fileName);
    if (!knownIds.add(id)) {
      results.add(const ImportItemResult.skipped());
      continue;
    }
    try {
      final text = PlainTextNovelParser.decode(File(path).readAsBytesSync());
      File(p.join(textsDirPath, '$id.txt')).writeAsStringSync(text);
      results.add(
        ImportItemResult.added(
          LocalWork(
            id: id,
            title: p.basenameWithoutExtension(fileName),
            fileName: fileName,
            charCount: text.length,
            addedAt: now,
          ),
        ),
      );
    } on Object {
      knownIds.remove(id);
      results.add(ImportItemResult.failed(fileName));
    }
  }
  return results;
}
