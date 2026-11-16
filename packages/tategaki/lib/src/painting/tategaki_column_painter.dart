import 'package:flutter/rendering.dart';

import 'package:tategaki/src/highlight.dart';
import 'package:tategaki/src/layout/column.dart';

/// 縦書きの1列を描画する CustomPainter
///
/// 列ごとに独立した Canvas（幅 = column.width、高さ = maxHeight）に、
/// 配置済みアイテムを座標どおりに描画する。
class TategakiColumnPainter extends CustomPainter {
  /// コンストラクタ
  const TategakiColumnPainter({
    required this.column,
    this.highlight,
  });

  /// 描画対象の列
  final TategakiColumn column;

  /// 背景色を付ける範囲（なければ null）
  final TategakiHighlight? highlight;

  @override
  void paint(Canvas canvas, Size size) {
    highlight?.paintColumn(canvas, column, Offset.zero);
    for (final placed in column.placedItems) {
      placed.item.paintable.paint(
        canvas,
        Offset(placed.blockOffset, placed.inlineOffset),
      );
    }
  }

  @override
  bool shouldRepaint(covariant TategakiColumnPainter oldDelegate) {
    return oldDelegate.column != column || oldDelegate.highlight != highlight;
  }
}
