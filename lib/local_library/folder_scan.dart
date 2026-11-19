import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:novelty/local_library/local_library_store.dart';
import 'package:novelty/local_library/meta_rules.dart';
import 'package:novelty/local_library/work_meta_detector.dart';
import 'package:novelty/utils/plain_text_novel_parser.dart';
import 'package:path/path.dart' as p;

/// 取り込んだフォルダ（再スキャンのために覚えておく）。
///
/// [files] は「作品ID → ファイルの目印（大きさと更新日時）」。
/// 目印が変わったファイルは、中身が書き換わったものとして取り込み直す。
@immutable
class FolderSource {
  /// コンストラクタ。
  const FolderSource({
    required this.path,
    this.files = const {},
    this.scannedAt,
  });

  /// JSON から復元する。
  factory FolderSource.fromJson(Map<String, dynamic> json) => FolderSource(
    path: json['path'] as String,
    files: {
      for (final e in (json['files'] as Map<String, dynamic>? ?? {}).entries)
        e.key: e.value as String,
    },
    scannedAt: DateTime.tryParse(json['scannedAt'] as String? ?? ''),
  );

  /// フォルダの場所。
  final String path;

  /// 作品ID → ファイルの目印。
  final Map<String, String> files;

  /// 最後にスキャンした日時。
  final DateTime? scannedAt;

  /// JSON に変換する。
  Map<String, dynamic> toJson() => {
    'path': path,
    'files': files,
    if (scannedAt != null) 'scannedAt': scannedAt!.toIso8601String(),
  };
}

/// フォルダの中で見つかった .txt ファイル。
@immutable
class ScannedFile {
  /// コンストラクタ。
  const ScannedFile({
    required this.path,
    required this.id,
    required this.signature,
  });

  /// ファイルの場所。
  final String path;

  /// 作品ID（ファイル名から決まる）。
  final String id;

  /// 目印（大きさ:更新日時）。
  final String signature;
}

/// ファイルの目印（大きさと更新日時）。中身が変わると、ふつうはどちらかが変わる。
String fileSignature(FileStat stat) =>
    '${stat.size}:${stat.modified.millisecondsSinceEpoch}';

/// フォルダ（サブフォルダ含む）の .txt を名前順に列挙する（Isolate から呼ぶ）。
///
/// 同じファイル名が複数あるときは、先に見つかった方だけを使う
/// （作品IDがファイル名から決まるため）。
List<ScannedFile> listFolder(String dirPath) {
  final entries = <(String, FileStat)>[];
  for (final entity in Directory(dirPath).listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is File && entity.path.toLowerCase().endsWith('.txt')) {
      entries.add((entity.path, entity.statSync()));
    }
  }
  entries.sort((a, b) => a.$1.compareTo(b.$1));
  final seen = <String>{};
  return [
    for (final (path, stat) in entries)
      if (seen.add(LocalLibraryStore.idForFileName(p.basename(path))))
        ScannedFile(
          path: path,
          id: LocalLibraryStore.idForFileName(p.basename(path)),
          signature: fileSignature(stat),
        ),
  ];
}

/// スキャンの段取り（何を追加し、何を取り込み直すか）。
@immutable
class ScanPlan {
  /// コンストラクタ。
  const ScanPlan({
    required this.toAdd,
    required this.toUpdate,
    required this.unchanged,
    required this.missingIds,
  });

  /// 本棚に無い新しいファイル。
  final List<ScannedFile> toAdd;

  /// 前回から中身が変わったファイル。
  final List<ScannedFile> toUpdate;

  /// 変わっていない（または目印を初めて記録する）ファイルの数。
  final int unchanged;

  /// 前回はこのフォルダにあったのに、見つからなくなった作品のID。
  final List<String> missingIds;
}

/// 見つかったファイルと前回の記録・本棚の中身を見比べて段取りを決める。
///
/// 本棚にあっても目印の記録が無いもの（再スキャン機能より前に取り込んだもの）は、
/// 取り込み直さずに目印だけを記録する（何千件も一度に取り込み直さないため）。
ScanPlan planScan(
  List<ScannedFile> files,
  Map<String, String> previous,
  Set<String> knownIds,
) {
  final toAdd = <ScannedFile>[];
  final toUpdate = <ScannedFile>[];
  var unchanged = 0;
  final present = <String>{};
  for (final file in files) {
    present.add(file.id);
    if (!knownIds.contains(file.id)) {
      toAdd.add(file);
    } else {
      final before = previous[file.id];
      if (before != null && before != file.signature) {
        toUpdate.add(file);
      } else {
        unchanged++;
      }
    }
  }
  return ScanPlan(
    toAdd: toAdd,
    toUpdate: toUpdate,
    unchanged: unchanged,
    missingIds: [
      for (final id in previous.keys)
        if (!present.contains(id) && knownIds.contains(id)) id,
    ],
  );
}

/// 取り込み直した1ファイルの結果。
@immutable
class UpdatedText {
  /// コンストラクタ。
  const UpdatedText({
    required this.id,
    required this.charCount,
    required this.meta,
  });

  /// 作品ID。
  final String id;

  /// 文字数。
  final int charCount;

  /// 読み取り直した作品名・作者。
  final WorkMeta meta;
}

/// 中身が変わったファイルを読み直して本文を書き換える（Isolate から呼ぶ）。
///
/// 読めなかったファイルは failed にファイル名を入れて返す。
({List<UpdatedText> updated, List<String> failed}) updateTexts(
  List<ScannedFile> files,
  String textsDirPath,
  MetaRuleSet rules,
) {
  final results = <UpdatedText>[];
  final failed = <String>[];
  for (final file in files) {
    final fileName = p.basename(file.path);
    try {
      final text = PlainTextNovelParser.decode(
        File(file.path).readAsBytesSync(),
      );
      File(p.join(textsDirPath, '${file.id}.txt')).writeAsStringSync(text);
      results.add(
        UpdatedText(
          id: file.id,
          charCount: text.length,
          meta: WorkMetaDetector.detect(
            fileName: fileName,
            head: text,
            rules: rules,
          ),
        ),
      );
    } on Object {
      failed.add(fileName);
    }
  }
  return (updated: results, failed: failed);
}
