/// 読み方の辞書（フォークで追加）。
///
/// 読み上げで読み間違える言葉（人名・造語など）に、正しい読みを登録する。
/// 置き換えるのは音声エンジンに渡す文字列だけで、画面の本文や
/// 文の位置（しおり・読書位置）は変えない。
///
/// - 範囲は「すべての作品」（[ReadingRule.globalScope]）か「この作品だけ」。
///   同じ表記が両方にあれば、作品の登録を優先する。
/// - 置き換えは長い表記から順に、1回だけ行う（置き換えた読みを、さらに
///   別の登録で置き換えることはない）。
/// - 保存先は `<documents>/reader/reading_dictionary.json`。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 読み方の登録1件。
@immutable
class ReadingRule {
  /// コンストラクタ。
  const ReadingRule({
    required this.surface,
    required this.reading,
    this.scope = globalScope,
  });

  /// JSONから生成する。
  factory ReadingRule.fromJson(Map<String, dynamic> json) => ReadingRule(
    surface: json['surface'] as String,
    reading: json['reading'] as String,
    scope: json['scope'] as String? ?? globalScope,
  );

  /// 「すべての作品」を表す範囲。
  static const globalScope = '*';

  /// 本文での書き方（例：「天音」）。
  final String surface;

  /// 読ませたい読み（例：「あまね」）。
  final String reading;

  /// 範囲。[globalScope] か、作品ごとの鍵（[ReadingDictionary.localScope] など）。
  final String scope;

  /// すべての作品に効く登録か。
  bool get isGlobal => scope == globalScope;

  /// JSONに変換する。
  Map<String, dynamic> toJson() => {
    'surface': surface,
    'reading': reading,
    'scope': scope,
  };

  @override
  bool operator ==(Object other) =>
      other is ReadingRule &&
      other.surface == surface &&
      other.reading == reading &&
      other.scope == scope;

  @override
  int get hashCode => Object.hash(surface, reading, scope);
}

/// 読み方の辞書。
class ReadingDictionary {
  /// コンストラクタ。[rules] は最初の登録。
  ReadingDictionary([List<ReadingRule> rules = const []])
    : _rules = List.of(rules);

  /// アプリ全体で使う辞書（起動時に [loadShared] で読み込む）。
  static final shared = ReadingDictionary();

  /// ローカル本棚の作品の範囲。
  static String localScope(String workId) => 'local:$workId';

  /// Web 小説の作品の範囲。
  static String webScope(String source, String workId) => 'web:$source:$workId';

  List<ReadingRule> _rules;
  File? _file;

  // 範囲ごとの置き換え用の正規表現（登録が変わったら作り直す）
  final _cache = <String, (RegExp, Map<String, String>)?>{};

  /// 登録の一覧（変更できない）。
  List<ReadingRule> get rules => List.unmodifiable(_rules);

  /// [scope] の作品で使われる登録（作品の登録と、すべての作品の登録）。
  List<ReadingRule> rulesFor(String? scope) => [
    for (final r in _rules)
      if (r.isGlobal || r.scope == scope) r,
  ];

  /// [text] の中の登録された表記を、読みに置き換える。
  ///
  /// [scope] は作品の範囲。null なら「すべての作品」の登録だけを使う。
  String apply(String text, {String? scope}) {
    if (_rules.isEmpty || text.isEmpty) return text;
    final key = scope ?? ReadingRule.globalScope;
    final compiled = _cache.putIfAbsent(key, () => _compile(scope));
    if (compiled == null) return text;
    final (pattern, readings) = compiled;
    return text.replaceAllMapped(pattern, (m) => readings[m[0]] ?? m[0]!);
  }

  (RegExp, Map<String, String>)? _compile(String? scope) {
    final readings = <String, String>{};
    // すべての作品の登録を先に入れ、作品の登録で上書きする
    for (final r in _rules.where((r) => r.isGlobal)) {
      readings[r.surface] = r.reading;
    }
    for (final r in _rules.where((r) => !r.isGlobal && r.scope == scope)) {
      readings[r.surface] = r.reading;
    }
    readings.removeWhere((surface, _) => surface.isEmpty);
    if (readings.isEmpty) return null;
    // 長い表記を先に試す（「天音川」と「天音」なら「天音川」）
    final surfaces = readings.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final pattern = RegExp(surfaces.map(RegExp.escape).join('|'));
    return (pattern, readings);
  }

  /// 登録する。同じ範囲・同じ表記があれば読みを置き換える。
  Future<void> put(ReadingRule rule) async {
    _rules = [
      for (final r in _rules)
        if (!(r.surface == rule.surface && r.scope == rule.scope)) r,
      rule,
    ];
    await _changed();
  }

  /// 登録を消す。
  Future<void> remove(ReadingRule rule) async {
    _rules = [..._rules]..remove(rule);
    await _changed();
  }

  Future<void> _changed() async {
    _cache.clear();
    await _save();
  }

  /// 保存先のファイルから読み込む（[shared] 用）。失敗したら空のまま。
  Future<void> loadShared() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      await loadFrom(
        File(p.join(docs.path, 'reader', 'reading_dictionary.json')),
      );
    } on Object catch (e) {
      debugPrint('読み方の辞書を読み込めませんでした: $e');
    }
  }

  /// [file] から読み込み、以後の変更を [file] に保存する。
  Future<void> loadFrom(File file) async {
    _file = file;
    if (!file.existsSync()) return;
    try {
      final list = jsonDecode(await file.readAsString()) as List;
      _rules = [
        for (final item in list)
          ReadingRule.fromJson(item as Map<String, dynamic>),
      ];
    } on FormatException {
      _rules = [];
    }
    _cache.clear();
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final r in _rules) r.toJson()]));
    await tmp.rename(file.path);
  }
}
