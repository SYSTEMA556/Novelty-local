import 'package:flutter/painting.dart';

import 'package:tategaki/src/layout/tategaki_measurer.dart';
import 'package:tategaki/src/painting/paintable.dart';

/// 列内に配置された要素（計測結果＋インライン位置）
class TategakiPlacedItem {
  /// コンストラクタ
  const TategakiPlacedItem({
    required this.item,
    required this.inlineOffset,
    required this.blockOffset,
    this.elementIndex = -1,
  });

  /// 計測済みの要素
  final TategakiMeasuredItem item;

  /// インライン方向（縦）の開始位置
  final double inlineOffset;

  /// ブロック方向（横）の開始位置
  final double blockOffset;

  /// 元の要素リストでの位置（ハイライト・追従に使う。不明なら -1）
  final int elementIndex;

  /// 計測結果を複製して位置を差し替えたものを返す
  TategakiPlacedItem copyWith({double? inlineOffset, double? blockOffset}) {
    return TategakiPlacedItem(
      item: item,
      inlineOffset: inlineOffset ?? this.inlineOffset,
      blockOffset: blockOffset ?? this.blockOffset,
      elementIndex: elementIndex,
    );
  }
}

/// 縦書きの1列を表すクラス
class TategakiColumn {
  /// コンストラクタ
  TategakiColumn({
    required this.placedItems,
    required this.width,
    required this.baseWidth,
  });

  /// 配置済みの要素
  final List<TategakiPlacedItem> placedItems;

  /// 列の総幅（ルビなどのオーバーハングを含む）
  final double width;

  /// ベーステキストの基準幅（行送り）
  final double baseWidth;

  /// 描画要素のリスト（配置順）
  List<Paintable> get items =>
      [for (final p in placedItems) p.item.paintable];

  /// 内容が空かどうか
  bool get isEmpty => placedItems.isEmpty;

  /// 列に含まれる最初の要素の位置（空の列は null）
  int? get firstElementIndex =>
      placedItems.isEmpty ? null : placedItems.first.elementIndex;

  /// 列に含まれる最後の要素の位置（空の列は null）
  int? get lastElementIndex =>
      placedItems.isEmpty ? null : placedItems.last.elementIndex;
}

/// レイアウト計算結果のメトリクス
class TategakiMetrics {
  /// コンストラクタ
  const TategakiMetrics({
    required this.columns,
    required this.size,
  });

  /// 列のリスト
  final List<TategakiColumn> columns;

  /// 全体のサイズ
  final Size size;
}
