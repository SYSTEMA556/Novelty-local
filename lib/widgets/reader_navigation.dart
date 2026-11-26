/// 読書画面の位置の取得と移動をまとめる（フォークで追加）。
///
/// 縦書き/横書き・スクロール/ページめくりの4通りの表示で、
/// 「全体のどこにいるか（0〜1）」と「そこへ飛ぶ」を同じ API で扱う。
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
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

  /// 1ページ（スクロール表示では画面1枚分）進む（[direction] が 1）か戻る（-1）。
  ///
  /// 動けたら true、すでに端にいて動けなければ false を返す
  /// （Web小説では false のとき前後の話へ移る）。
  bool move(
    int direction, {
    required bool isVertical,
    required bool isPageFlip,
  }) {
    if (isVertical && isPageFlip) {
      if (!pageController.hasClients) return false;
      final target = currentPage.value + direction;
      if (target < 0 || (pageCount.value > 0 && target >= pageCount.value)) {
        return false;
      }
      unawaited(
        pageController.animateToPage(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
      return true;
    }
    if (isVertical) return tategakiController.scrollByPage(direction);

    if (!horizontalController.hasClients) return false;
    final position = horizontalController.position;
    final target = (position.pixels +
            position.viewportDimension * 0.9 * direction)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 1) return false;
    unawaited(
      horizontalController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
    );
    return true;
  }

  /// 今見ている位置を全体の割合（0.0〜1.0）で返す。
  double currentFraction({required bool isVertical, required bool isPageFlip}) {
    if (isVertical && isPageFlip) {
      final count = pageCount.value;
      return count > 1 ? currentPage.value / (count - 1) : 0;
    }
    return progress.value;
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

  /// 本文の組み立てが済むのを待ってから、全体の [fraction] の位置へ移る
  /// （しおりから開いたとき。フォークで追加）。
  ///
  /// 開いた直後は、縦書きの組版やスクロールの準備ができていないため、
  /// 準備ができるまで1フレームずつ待つ（最大でおよそ5秒）。
  Future<void> seekWhenReady(
    double fraction, {
    required bool isVertical,
    required bool isPageFlip,
  }) async {
    for (var frame = 0; frame < 300; frame++) {
      await SchedulerBinding.instance.endOfFrame;
      if (isVertical && isPageFlip) {
        final count = pageCount.value;
        if (count > 1 && pageController.hasClients) {
          jumpToPage((fraction.clamp(0.0, 1.0) * (count - 1)).round());
          return;
        }
      } else if (isVertical) {
        if (tategakiElementCount > 0) {
          seek(fraction, isVertical: true);
          return;
        }
      } else if (horizontalController.hasClients &&
          horizontalController.position.maxScrollExtent > 0) {
        seek(fraction, isVertical: false);
        return;
      }
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
