import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'package:tategaki/src/layout/column.dart';

/// 要素の範囲に付ける背景色（読み上げ中の文など）
@immutable
class TategakiHighlight {
  /// コンストラクタ
  const TategakiHighlight({
    required this.start,
    required this.end,
    required this.color,
  });

  /// 開始位置（要素リストの位置、含む）
  final int start;

  /// 終了位置（要素リストの位置、含まない）
  final int end;

  /// 背景色
  final Color color;

  /// [index] 番目の要素が範囲に含まれるか
  bool contains(int index) => index >= start && index < end;

  /// 列に範囲内の要素が含まれるか
  bool overlapsColumn(TategakiColumn column) {
    final first = column.firstElementIndex;
    final last = column.lastElementIndex;
    if (first == null || last == null) return false;
    return first < end && last >= start;
  }

  /// 列 [column] の範囲内の要素の背景を描く（[origin] は列の左上）
  void paintColumn(Canvas canvas, TategakiColumn column, Offset origin) {
    if (!overlapsColumn(column)) return;
    final paint = Paint()..color = color;
    for (final placed in column.placedItems) {
      if (!contains(placed.elementIndex)) continue;
      canvas.drawRect(
        Rect.fromLTWH(
          origin.dx,
          origin.dy + placed.inlineOffset,
          column.width,
          placed.item.advance,
        ),
        paint,
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TategakiHighlight &&
      other.start == start &&
      other.end == end &&
      other.color == color;

  @override
  int get hashCode => Object.hash(start, end, color);
}
