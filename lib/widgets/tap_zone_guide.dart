import 'package:flutter/material.dart';
import 'package:novelty/utils/reader_appearance.dart';

/// ページボタンの領域を色分けして描く（本文の上の薄い表示や、設定画面の見本）。
class TapZoneGuide extends StatelessWidget {
  /// コンストラクタ。
  const TapZoneGuide({
    required this.config,
    required this.isVertical,
    this.opacity = 1,
    this.showLabels = true,
    super.key,
  });

  /// ページボタンの設定。
  final TapZoneConfig config;

  /// 縦書きか（「次へ」の向きが変わる）。
  final bool isVertical;

  /// 濃さ（0.0〜1.0）。
  final double opacity;

  /// 「次へ」「前へ」の文字を出すか。
  final bool showLabels;

  /// 「次へ」の色。
  static const nextColor = Color(0xFFA0607A);

  /// 「前へ」の色。
  static const previousColor = Color(0xFF6078A8);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final f = config.sizePercent.clamp(10, 45) / 100;
        final w = size.width;
        final h = size.height;

        // 配置ごとの帯（L字は下の帯と重ならないよう左右を短くする）
        final rects = switch (config.layout) {
          TapZoneLayout.sides => [
            Rect.fromLTWH(0, 0, w * f, h),
            Rect.fromLTWH(w * (1 - f), 0, w * f, h),
          ],
          TapZoneLayout.topBottom => [
            Rect.fromLTWH(0, 0, w, h * f),
            Rect.fromLTWH(0, h * (1 - f), w, h * f),
          ],
          TapZoneLayout.lShape => [
            Rect.fromLTWH(0, 0, w * f, h * (1 - f)),
            Rect.fromLTWH(w * (1 - f), 0, w * f, h * (1 - f)),
            Rect.fromLTWH(0, h * (1 - f), w, h * f),
          ],
        };

        return Stack(
          children: [
            for (final rect in rects)
              _zone(
                rect,
                config.actionAt(rect.center, size, isVertical: isVertical),
              ),
          ],
        );
      },
    );
  }

  Widget _zone(Rect rect, TapAction action) {
    final Color color;
    final String label;
    switch (action) {
      case TapAction.next:
        color = nextColor;
        label = '次へ';
      case TapAction.previous:
        color = previousColor;
        label = '前へ';
      case TapAction.menu:
        return const SizedBox.shrink();
    }
    return Positioned.fromRect(
      rect: rect,
      child: ColoredBox(
        color: color.withValues(alpha: opacity.clamp(0.0, 1.0)),
        child: showLabels
            ? Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(
                      alpha: (opacity * 1.5).clamp(0.0, 1.0),
                    ),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
