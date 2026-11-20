/// 作者の読み取りルールの定義（フォークで追加）。
///
/// 組み込みルール（[BuiltinRule]）と、ユーザーが足す正規表現ルール（[MetaRule]）、
/// ファイル名から取り除く文字列（StripPattern）をまとめて [MetaRuleSet] とする。
/// 正規表現は保存時に検証し、壊れたものは読み込み時に無視する。
library;

import 'package:flutter/foundation.dart';

/// 組み込みの作者読み取りルール。
enum BuiltinRule {
  /// 夜伽形式：冒頭の `作者:〇〇` 行（作品名は `「〇〇」` 行）。
  yotogi('夜伽形式', '本文冒頭の「作者:〇〇」行'),

  /// 青空文庫形式：`作者／訳者訳` 行、または区切り線の前の見出し。
  aozora('青空文庫形式', '「作者／訳者訳」行・区切り線の前の見出し'),

  /// ファイル名：`[作者] 作品` / `【作者】作品`。
  nameBracket('ファイル名：[作者] 作品', '[作者] や【作者】で始まる名前'),

  /// ファイル名：`作者_作品`。
  nameUnderscore('ファイル名：作者_作品', '最初の _ より前を作者とする'),

  /// ファイル名：`作者-作品`。
  nameDash('ファイル名：作者-作品', '最初の - より前を作者とする');

  const BuiltinRule(this.label, this.description);

  /// 表示名。
  final String label;

  /// 説明。
  final String description;
}

/// 自作ルールの適用先。
enum RuleTarget {
  /// 拡張子と除去パターンを取り除いたファイル名。
  fileName('ファイル名'),

  /// 本文の冒頭（空行・タグだけの行を除く）。
  head('本文の冒頭');

  const RuleTarget(this.label);

  /// 表示名。
  final String label;
}

/// 作者・作品名を読み取るルール（組み込み、または自作の正規表現）。
@immutable
class MetaRule {
  /// 組み込みルール。
  const MetaRule.builtin(BuiltinRule this.builtin, {this.enabled = true})
    : _customId = null,
      name = '',
      target = RuleTarget.fileName,
      pattern = '';

  /// 自作ルール。
  ///
  /// [pattern] には名前付きグループ `(?<author>...)` と
  /// `(?<title>...)` を書く（どちらか一方でもよい）。
  const MetaRule.custom({
    required String id,
    required this.name,
    required this.target,
    required this.pattern,
    this.enabled = true,
  }) : builtin = null,
       _customId = id;

  /// JSONから生成する。
  factory MetaRule.fromJson(Map<String, dynamic> json) {
    final enabled = json['enabled'] as bool? ?? true;
    final builtinName = json['builtin'] as String?;
    if (builtinName != null) {
      return MetaRule.builtin(
        BuiltinRule.values.byName(builtinName),
        enabled: enabled,
      );
    }
    return MetaRule.custom(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      target: RuleTarget.values.byName(json['target'] as String),
      pattern: json['pattern'] as String? ?? '',
      enabled: enabled,
    );
  }

  // 自作ルールの識別子（組み込みは種類から決まるため null）
  final String? _customId;

  /// 識別子。
  String get id => _customId ?? 'builtin:${builtin!.name}';

  /// 組み込みルールの種類（自作なら null）。
  final BuiltinRule? builtin;

  /// 自作ルールの名前。
  final String name;

  /// 自作ルールの適用先。
  final RuleTarget target;

  /// 自作ルールの正規表現。
  final String pattern;

  /// 有効か。
  final bool enabled;

  /// 自作ルールか。
  bool get isCustom => builtin == null;

  /// 表示名。
  String get label {
    final b = builtin;
    if (b != null) return b.label;
    return name.isEmpty ? '自作ルール' : name;
  }

  /// 説明。
  String get description {
    final b = builtin;
    if (b != null) return b.description;
    return '${target.label}：$pattern';
  }

  /// 有効／無効を切り替えたコピー。
  MetaRule copyWith({bool? enabled}) {
    final b = builtin;
    if (b != null) return MetaRule.builtin(b, enabled: enabled ?? this.enabled);
    return MetaRule.custom(
      id: id,
      name: name,
      target: target,
      pattern: pattern,
      enabled: enabled ?? this.enabled,
    );
  }

  /// JSONに変換する。
  Map<String, dynamic> toJson() {
    final b = builtin;
    if (b != null) return {'builtin': b.name, 'enabled': enabled};
    return {
      'id': id,
      'name': name,
      'target': target.name,
      'pattern': pattern,
      'enabled': enabled,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is MetaRule &&
      other.id == id &&
      other.builtin == builtin &&
      other.name == name &&
      other.target == target &&
      other.pattern == pattern &&
      other.enabled == enabled;

  @override
  int get hashCode =>
      Object.hash(id, builtin, name, target, pattern, enabled);
}

/// ファイル名から取り除く部分（夜伽の番号・日時など）。
@immutable
class StripPattern {
  /// コンストラクタ。
  const StripPattern({
    required this.id,
    required this.name,
    required this.pattern,
    this.enabled = true,
    this.isBuiltin = false,
  });

  /// JSONから生成する。
  factory StripPattern.fromJson(Map<String, dynamic> json) => StripPattern(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    pattern: json['pattern'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? true,
    isBuiltin: json['builtin'] as bool? ?? false,
  );

  /// 夜伽のファイル名の先頭「番号_YYYYMMDD_HHMM_」。
  static const yotogiPrefix = StripPattern(
    id: 'builtin:yotogiPrefix',
    name: '夜伽の番号・日時',
    pattern: r'^\d+_\d{8}_\d{4}_',
    isBuiltin: true,
  );

  /// 識別子。
  final String id;

  /// 表示名。
  final String name;

  /// 取り除く部分の正規表現。
  final String pattern;

  /// 有効か。
  final bool enabled;

  /// 組み込みか（組み込みは編集・削除できない）。
  final bool isBuiltin;

  /// 有効／無効を切り替えたコピー。
  StripPattern copyWith({bool? enabled}) => StripPattern(
    id: id,
    name: name,
    pattern: pattern,
    enabled: enabled ?? this.enabled,
    isBuiltin: isBuiltin,
  );

  /// JSONに変換する。
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'pattern': pattern,
    'enabled': enabled,
    'builtin': isBuiltin,
  };

  @override
  bool operator ==(Object other) =>
      other is StripPattern &&
      other.id == id &&
      other.name == name &&
      other.pattern == pattern &&
      other.enabled == enabled &&
      other.isBuiltin == isBuiltin;

  @override
  int get hashCode => Object.hash(id, name, pattern, enabled, isBuiltin);
}

/// 作者読み取りの設定一式。
///
/// [rules] は上から順に試し、最初に作者か作品名を返したものを採用する。
@immutable
class MetaRuleSet {
  /// コンストラクタ。
  const MetaRuleSet({required this.rules, required this.strips});

  /// JSONから生成する。
  ///
  /// 保存後に追加された組み込みルールは末尾に足す。
  factory MetaRuleSet.fromJson(Map<String, dynamic> json) {
    final rules = [
      for (final r in json['rules'] as List<dynamic>? ?? const [])
        MetaRule.fromJson(r as Map<String, dynamic>),
    ];
    for (final b in BuiltinRule.values) {
      if (!rules.any((r) => r.builtin == b)) rules.add(MetaRule.builtin(b));
    }
    final strips = [
      for (final s in json['strips'] as List<dynamic>? ?? const [])
        StripPattern.fromJson(s as Map<String, dynamic>),
    ];
    if (!strips.any((s) => s.id == StripPattern.yotogiPrefix.id)) {
      strips.insert(0, StripPattern.yotogiPrefix);
    }
    return MetaRuleSet(rules: rules, strips: strips);
  }

  /// 初期設定。
  static const defaults = MetaRuleSet(
    rules: [
      MetaRule.builtin(BuiltinRule.yotogi),
      MetaRule.builtin(BuiltinRule.aozora),
      MetaRule.builtin(BuiltinRule.nameBracket),
      MetaRule.builtin(BuiltinRule.nameUnderscore),
      MetaRule.builtin(BuiltinRule.nameDash),
    ],
    strips: [StripPattern.yotogiPrefix],
  );

  /// 読み取りルール（適用順）。
  final List<MetaRule> rules;

  /// ファイル名の除去パターン。
  final List<StripPattern> strips;

  /// 一部を差し替えたコピー。
  MetaRuleSet copyWith({List<MetaRule>? rules, List<StripPattern>? strips}) =>
      MetaRuleSet(rules: rules ?? this.rules, strips: strips ?? this.strips);

  /// JSONに変換する。
  Map<String, dynamic> toJson() => {
    'rules': [for (final r in rules) r.toJson()],
    'strips': [for (final s in strips) s.toJson()],
  };

  @override
  bool operator ==(Object other) =>
      other is MetaRuleSet &&
      listEquals(other.rules, rules) &&
      listEquals(other.strips, strips);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(rules), Object.hashAll(strips));
}

/// 正規表現として正しいか検査し、誤りがあればその内容を返す。
String? validatePattern(String pattern) {
  if (pattern.isEmpty) return '正規表現を入力してください';
  try {
    RegExp(pattern);
    return null;
  } on FormatException catch (e) {
    return '正規表現が正しくありません: ${e.message}';
  }
}
