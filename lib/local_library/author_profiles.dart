/// 作者ごとの表示名の付け替えと読み仮名（フォークで追加）。
///
/// 作者は [WorkMetaDetector.authorKey]（空白などを除いた正規化済みの名前）で
/// 同一視する。本文から推定した名前は変えず、表示のときだけ付け替える。
library;

import 'package:flutter/foundation.dart';
import 'package:novelty/local_library/work_meta_detector.dart';

/// 作者ごとの表示名の変更と読み仮名。
///
/// 自動判定の結果（作品の author）には手を入れず、表示時に置き換える。
/// そのため再判定しても名前の変更は失われない。
/// 変更後の名前が他の作者と同じなら、一覧では1人にまとまる。
@immutable
class AuthorProfiles {
  /// コンストラクタ。
  const AuthorProfiles({this.renames = const {}, this.readings = const {}});

  /// JSONから生成する。
  factory AuthorProfiles.fromJson(Map<String, dynamic> json) {
    Map<String, String> read(String key) => {
      for (final e in (json[key] as Map<String, dynamic>? ?? const {}).entries)
        e.key: e.value as String,
    };
    return AuthorProfiles(renames: read('renames'), readings: read('readings'));
  }

  /// 何も設定していない状態。
  static const empty = AuthorProfiles();

  /// 元の作者キー → 表示名。
  final Map<String, String> renames;

  /// 表示名の作者キー → 読み仮名。
  final Map<String, String> readings;

  /// 名前の変更を反映した作者名（作者不明なら null）。
  String? effectiveName(String? author) {
    if (author == null) return null;
    return renames[WorkMetaDetector.authorKey(author)] ?? author;
  }

  /// 表示名に付けた読み仮名。
  String? readingOf(String name) => readings[WorkMetaDetector.authorKey(name)];

  /// 作者の名前・読み仮名を変更したコピーを返す。
  ///
  /// [originalAuthors] はその作者に属する作品の、判定された作者名。
  /// [reading] が空なら読み仮名を消す。
  AuthorProfiles edit({
    required Iterable<String> originalAuthors,
    required String newName,
    required String? reading,
  }) {
    final name = newName.trim();
    final nextRenames = {...renames};
    for (final original in originalAuthors) {
      final key = WorkMetaDetector.authorKey(original);
      if (original == name) {
        nextRenames.remove(key);
      } else {
        nextRenames[key] = name;
      }
    }
    final nextReadings = {...readings};
    final nameKey = WorkMetaDetector.authorKey(name);
    final trimmed = reading?.trim() ?? '';
    if (trimmed.isEmpty) {
      nextReadings.remove(nameKey);
    } else {
      nextReadings[nameKey] = trimmed;
    }
    return AuthorProfiles(renames: nextRenames, readings: nextReadings);
  }

  /// JSONに変換する。
  Map<String, dynamic> toJson() => {'renames': renames, 'readings': readings};

  @override
  bool operator ==(Object other) =>
      other is AuthorProfiles &&
      mapEquals(other.renames, renames) &&
      mapEquals(other.readings, readings);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(renames.entries.map((e) => '${e.key}=${e.value}')),
    Object.hashAllUnordered(readings.entries.map((e) => '${e.key}=${e.value}')),
  );
}
