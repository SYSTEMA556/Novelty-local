import 'package:flutter/widgets.dart';
import 'package:tategaki/tategaki.dart';

/// 読書画面の「全体のどこにいるか」の表示と、シークバーでの移動をまとめる。
///
/// 表示モードごとに位置の測り方が違うため、それぞれを吸収する。
/// - 縦書きページ送り：ページ番号（[currentPage] / [pageCount]）
/// - 縦書きスクロール：何番目の要素を読んでいるか（[progress]）
/// - 横書き：スクロール量の割合（[progress]）
class ReaderNavigation {
  /// コンストラクタ。
  ReaderNavigation() {
    pageController.addListener(_onPageScroll);
    horizontalController.addListener(_onHorizontalScroll);
  }

  /// 縦書きページ送り用。
  final PageController pageController = PageController();

  /// 縦書きスクロール用。
  final TategakiTextController tategakiController = TategakiTextController();

  /// 横書き用。
  final ScrollController horizontalController = ScrollController();

  /// 今のページ（0始まり。ページ送りのときだけ使う）。
  final ValueNotifier<int> currentPage = ValueNotifier(0);

  /// 総ページ数（ページ送りのときだけ使う。分割前は 0）。
  final ValueNotifier<int> pageCount = ValueNotifier(0);

  /// 読み進めた割合（0.0〜1.0。スクロール表示のときに使う）。
  final ValueNotifier<double> progress = ValueNotifier(0);

  /// 縦書き要素の総数（縦書きスクロールの割合の計算に使う）。
  int tategakiElementCount = 0;

  void _onPageScroll() {
    if (!pageController.hasClients) return;
    final page = pageController.page;
    if (page != null) currentPage.value = page.round();
  }

  void _onHorizontalScroll() {
    if (!horizontalController.hasClients) return;
    final position = horizontalController.position;
    final max = position.maxScrollExtent;
    progress.value = max <= 0 ? 1 : (position.pixels / max).clamp(0, 1);
  }

  /// 縦書きスクロールで、画面の読み始め側の要素が変わったときに呼ぶ。
  void onVisibleTategakiElement(int elementIndex) {
    final total = tategakiElementCount;
    progress.value = total <= 1
        ? 0
        : (elementIndex / (total - 1)).clamp(0, 1).toDouble();
  }

  /// ページ [page] へ移る。
  void jumpToPage(int page) {
    if (!pageController.hasClients) return;
    pageController.jumpToPage(page);
  }

  /// 全体の [fraction]（0.0〜1.0）の位置へ移る（スクロール表示）。
  void seek(double fraction, {required bool isVertical}) {
    final f = fraction.clamp(0.0, 1.0);
    if (isVertical) {
      final total = tategakiElementCount;
      if (total == 0) return;
      tategakiController.jumpToElement((f * (total - 1)).round());
      progress.value = f;
    } else if (horizontalController.hasClients) {
      final max = horizontalController.position.maxScrollExtent;
      horizontalController.jumpTo(f * max);
    }
  }

  /// 後始末をする。
  void dispose() {
    pageController.dispose();
    tategakiController.dispose();
    horizontalController.dispose();
    currentPage.dispose();
    pageCount.dispose();
    progress.dispose();
  }
}
