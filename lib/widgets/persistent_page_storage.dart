/// PageStorage の読み書きを、ファイルへの保存に流す（フォークで追加）。
///
/// Flutter のスクロール位置の復元（PageStorage）をそのまま使い、
/// 書き込みだけを横取りして読書位置として保存する。
library;

import 'package:flutter/widgets.dart';

/// 表示モードを読書位置の保存キーに変換する。
///
/// スクロール位置の意味がモードごとに異なるため、別々に保存する。
String readingModeKey({required bool isVertical, required bool isPageFlip}) {
  if (!isVertical) return 'h';
  return isPageFlip ? 'vp' : 'vs';
}

/// 読み書きを1つのキー（表示モード）に集約する [PageStorageBucket]。
///
/// 読書画面にはスクロール領域が1つしかないため、
/// 識別子は使わず表示モードごとに値を保持する。
class PersistentPageStorageBucket extends PageStorageBucket {
  /// コンストラクタ。
  PersistentPageStorageBucket({
    required Map<String, double> initialValues,
    required this.currentKey,
    required this.onWrite,
  }) : _values = initialValues;

  final Map<String, double> _values;

  /// 現在の表示モードのキーを返す。
  final String Function() currentKey;

  /// 位置が書き込まれたときに呼ばれる。
  final void Function(String key, double value) onWrite;

  @override
  Object? readState(BuildContext context, {Object? identifier}) {
    return _values[currentKey()];
  }

  @override
  void writeState(BuildContext context, Object? data, {Object? identifier}) {
    if (data is! double) return;
    final key = currentKey();
    if (_values[key] == data) return;
    _values[key] = data;
    onWrite(key, data);
  }
}
