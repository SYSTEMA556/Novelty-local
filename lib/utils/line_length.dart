import 'dart:math' as math;

/// 1行の長さの上限（論理ピクセル）を返す。
///
/// [maxChars] が 0 以下なら制限なしとして null を返す。
/// 和文は1文字の送り幅がほぼフォントサイズと等しいため、
/// 文字数 × フォントサイズを上限とする（端数での折り返しを防ぐため 1px 足す）。
double? lineExtentLimit({required int maxChars, required double fontSize}) {
  if (maxChars <= 0) return null;
  return maxChars * fontSize + 1;
}

/// 使える長さ [available] に上限 [limit] を当てはめた長さを返す。
double clampLineExtent(double available, double? limit) {
  if (limit == null) return available;
  return math.min(available, limit);
}
