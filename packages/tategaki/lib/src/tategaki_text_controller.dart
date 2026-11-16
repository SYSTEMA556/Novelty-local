import 'package:flutter/foundation.dart';

/// `TategakiText` を外から操作するためのコントローラー
///
/// 縦書きスクロール表示は列を必要な分だけ計算するため、スクロール量では
/// 全体のどこにいるかがわからない。代わりに「何番目の要素へ移動するか」で
/// 操作する（シークバーでの移動などに使う）。
class TategakiTextController extends ChangeNotifier {
  int? _pendingElement;

  /// 要素 [elementIndex] を含む列が画面の右端（読み始め側）に来るよう移動する
  void jumpToElement(int elementIndex) {
    _pendingElement = elementIndex;
    notifyListeners();
  }

  /// 保留中の移動先を取り出す（`TategakiText` の内部で使う）
  int? takePendingElement() {
    final element = _pendingElement;
    _pendingElement = null;
    return element;
  }
}
