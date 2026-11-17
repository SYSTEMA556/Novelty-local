import 'package:flutter/painting.dart';

import 'package:tategaki/src/element/tategaki_element.dart';
import 'package:tategaki/src/layout/column.dart';
import 'package:tategaki/src/layout/tategaki_column_engine.dart';

/// 縦書きレイアウトを計算するクラス
class TategakiLayout {
  TategakiLayout._();

  /// 列間のスペース
  ///
  /// 行送り（fontSize × lineHeight）が列幅に含まれるため、追加の列間
  /// スペースは 0 とする（Q23: 軸の取り違えを修正）。
  static const double columnSpacing = 0;

  /// 列リストの合計幅を計算する
  ///
  /// N列の場合、totalWidth = Σ(column.width) + columnSpacing × (N-1)
  static double calculateTotalWidth(List<TategakiColumn> columns) {
    if (columns.isEmpty) return 0;
    final columnsWidth = columns.fold<double>(0, (sum, c) => sum + c.width);
    final spacingWidth = columnSpacing * (columns.length - 1);
    return columnsWidth + spacingWidth;
  }

  /// 要素リストからレイアウトを計算する
  ///
  /// [TategakiColumnEngine] に委譲し、列単位の遅延生成・メモ化を利用する。
  static TategakiMetrics calculate({
    required List<TategakiElement> elements,
    required double maxHeight,
    required TextStyle textStyle,
  }) {
    if (elements.isEmpty) {
      return const TategakiMetrics(
        columns: [],
        size: Size.zero,
      );
    }

    final engine = TategakiColumnEngine(
      elements: elements,
      maxHeight: maxHeight,
      textStyle: textStyle,
    );
    final columns = engine.computeAll();

    return TategakiMetrics(
      columns: columns,
      size: Size(calculateTotalWidth(columns), maxHeight),
    );
  }

  /// 列リストを指定された幅に収まるようにページ分割する
  static List<TategakiMetrics> partition({
    required List<TategakiColumn> columns,
    required double maxWidth,
    required double height,
  }) {
    final pages = <TategakiMetrics>[];
    var currentPageColumns = <TategakiColumn>[];
    var currentWidth = 0.0;

    void flushPage() {
      if (currentPageColumns.isNotEmpty) {
        pages.add(
          TategakiMetrics(
            columns: currentPageColumns,
            size: Size(currentWidth, height),
          ),
        );
      }
    }

    for (final column in columns) {
      // この列を追加した場合の幅を計算
      // 最初の列ならスペースなし、それ以降はスペースあり
      final spacing = currentPageColumns.isEmpty ? 0.0 : columnSpacing;
      final columnWidth = column.width;

      // 1列だけで幅を超えている場合は強制的に追加（無限ループ防止）
      // または、現在のページに収まるなら追加
      if (currentPageColumns.isEmpty ||
          (currentWidth + spacing + columnWidth <= maxWidth)) {
        currentPageColumns.add(column);
        currentWidth += spacing + columnWidth;
      } else {
        // 次のページへ
        flushPage();
        currentPageColumns = [column];
        currentWidth = columnWidth; // 新しいページの最初の列なのでスペースなし
      }
    }

    flushPage();

    return pages;
  }

  /// 列を1つずつ計算しながらページの区切りだけを求める
  ///
  /// [partition] と同じ規則で区切るが、列そのものは保持しない。
  /// 長い本文でも、ページの数に比例する小さなメモリで済む
  /// （ページの中身は表示するときに [TategakiPageBoundary.start] から作り直す）。
  static List<TategakiPageBoundary> paginate({
    required TategakiColumnEngine engine,
    required double maxWidth,
  }) {
    final pages = <TategakiPageBoundary>[];
    var start = engine.state;
    var count = 0;
    var width = 0.0;
    int? first;
    int? last;

    void flushPage() {
      if (count == 0) return;
      pages.add(
        TategakiPageBoundary(
          start: start,
          columnCount: count,
          width: width,
          firstElementIndex: first,
          lastElementIndex: last,
        ),
      );
    }

    while (true) {
      final before = engine.state;
      final column = engine.computeNextColumn();
      if (column == null) break;
      // 区切りを求めるだけなので、計算した列はすぐ捨てる
      engine.discardComputedColumns();

      final spacing = count == 0 ? 0.0 : columnSpacing;
      if (count == 0 || width + spacing + column.width <= maxWidth) {
        if (count == 0) start = before;
        count++;
        width += spacing + column.width;
      } else {
        flushPage();
        start = before;
        count = 1;
        width = column.width;
        first = null;
        last = null;
      }
      first ??= column.firstElementIndex;
      last = column.lastElementIndex ?? last;
    }
    flushPage();
    return pages;
  }
}

/// ページの区切り（中身は持たず、作り直すための位置だけを持つ）
class TategakiPageBoundary {
  /// コンストラクタ
  const TategakiPageBoundary({
    required this.start,
    required this.columnCount,
    required this.width,
    this.firstElementIndex,
    this.lastElementIndex,
  });

  /// ページ先頭の列を計算し始める位置
  final TategakiEngineState start;

  /// ページの列数
  final int columnCount;

  /// ページの幅
  final double width;

  /// ページに含まれる最初の要素の位置（空のページは null）
  final int? firstElementIndex;

  /// ページに含まれる最後の要素の位置（空のページは null）
  final int? lastElementIndex;

  /// 要素の範囲 [start]〜[end]（end は含まない）と重なるか
  bool overlaps(int start, int end) {
    final f = firstElementIndex;
    final l = lastElementIndex;
    if (f == null || l == null) return false;
    return f < end && l >= start;
  }
}
