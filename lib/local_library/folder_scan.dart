/// フォルダの再スキャンと、元ファイルの読み込み（フォークで追加）。
///
/// このファイルの関数はすべて同期・純粋に近く、`Isolate.run` の中で呼ぶ前提。
/// - 変更の判定は「大きさ:更新日時(ms)」の署名（[fileSignature]）だけで行い、
///   中身のハッシュは取らない（数千ファイルでも速くするため）。
/// - [planScan] は I/O を持たない純粋関数で、追加・更新・変化なし・消失に仕分ける。
/// - [readSourceText] は文字コードを判別し、指定があれば元ファイルを UTF-8 に
///   書き直す。読めないバイトが1つでもあれば書き直さない（不可逆な損失を防ぐ）。
library;

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

/// 元のファイルを読んだ結果。
typedef SourceText = ({String text, bool nonUtf8, bool converted});

/// 元のファイルを読む（UTF-8 以外の文字コードも読む）。
///
/// [convertSource] なら、UTF-8 以外のファイルを UTF-8 で書き直す
/// （読めない文字が1つでもあるときは、元の中身を失わないよう書き直さない。
/// 書き込めない場所のファイルもそのまま）。
SourceText readSourceText(String path, {bool convertSource = false}) {
  final decoded = PlainTextNovelParser.decodeDetailed(
    File(path).readAsBytesSync(),
  );
  final nonUtf8 = decoded.encoding != 'UTF-8';
  var converted = false;
  if (nonUtf8 && convertSource && decoded.errors == 0) {
    final tmp = File('$path.utf8tmp');
    try {
      tmp
        ..writeAsStringSync(decoded.text, flush: true)
        ..renameSync(path);
      converted = true;
    } on Object {
      if (tmp.existsSync()) tmp.deleteSync();
    }
  }
  return (text: decoded.text, nonUtf8: nonUtf8, converted: converted);
}

/// [updateTexts] の結果。
typedef UpdateTextsResult = ({
  List<UpdatedText> updated,
  List<String> failed,
  int nonUtf8,
  int converted,
});

/// 中身が変わったファイルを読み直して本文を書き換える（Isolate から呼ぶ）。
///
/// 読めなかったファイルは failed にファイル名を入れて返す。
UpdateTextsResult updateTexts(
  List<ScannedFile> files,
  String textsDirPath,
  MetaRuleSet rules, {
  bool convertSource = false,
}) {
  final results = <UpdatedText>[];
  final failed = <String>[];
  var nonUtf8 = 0;
  var converted = 0;
  for (final file in files) {
    final fileName = p.basename(file.path);
    try {
      final source = readSourceText(file.path, convertSource: convertSource);
      final text = source.text;
      if (source.nonUtf8) nonUtf8++;
      if (source.converted) converted++;
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
  return (
    updated: results,
    failed: failed,
    nonUtf8: nonUtf8,
    converted: converted,
  );
}

/// [convertFolderToUtf8] の結果。
typedef ConvertFolderResult = ({
  int converted,
  int nonUtf8,
  Map<String, String> signatures,
});

/// フォルダの中の UTF-8 以外の .txt を UTF-8 で書き直す（Isolate から呼ぶ）。
///
/// 結果の signatures には、書き直したファイルの新しい目印（大きさ・日時）を入れる。
/// 読めない文字があるファイルは書き直さない（[readSourceText]）。
ConvertFolderResult convertFolderToUtf8(String dirPath) {
  var converted = 0;
  var nonUtf8 = 0;
  final signatures = <String, String>{};
  for (final file in listFolder(dirPath)) {
    try {
      final result = readSourceText(file.path, convertSource: true);
      if (result.nonUtf8) nonUtf8++;
      if (!result.converted) continue;
      converted++;
      signatures[file.id] = fileSignature(File(file.path).statSync());
    } on Object {
      // 読めないファイルはそのまま
    }
  }
  return (converted: converted, nonUtf8: nonUtf8, signatures: signatures);
}
