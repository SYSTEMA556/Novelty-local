import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:novelty/widgets/reader_navigation.dart';

/// 本文の下に出す、今のページ（位置）とシークバー。
class ReaderPositionBar extends HookWidget {
  /// コンストラクタ。
  const ReaderPositionBar({
    required this.navigation,
    required this.isVertical,
    required this.isPageFlip,
    this.textColor,
    super.key,
  });

  /// バーの高さ。
  static const double height = 48;

  /// 位置の情報と移動。
  final ReaderNavigation navigation;

  /// 縦書きか。
  final bool isVertical;

  /// ページ送りか。
  final bool isPageFlip;

  /// 色調の文字色（端末に合わせる場合は null）。
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final paged = isVertical && isPageFlip;
    final page = useValueListenable(navigation.currentPage);
    final pageCount = useValueListenable(navigation.pageCount);
    final progress = useValueListenable(navigation.progress);
    // 指で動かしている間の値（離したときに移動する）
    final dragging = useState<double?>(null);

    final double max;
    final double value;
    final String label;
    if (paged) {
      max = pageCount > 1 ? (pageCount - 1).toDouble() : 1;
      final current = (dragging.value ?? page.toDouble()).clamp(0.0, max);
      value = current;
      label = pageCount == 0
          ? ''
          : '${current.round() + 1} / $pageCount';
    } else {
      max = 1;
      value = (dragging.value ?? progress).clamp(0.0, 1.0);
      label = '${(value * 100).round()}%';
    }
    final enabled = !paged || pageCount > 1;

    return SizedBox(
      height: height,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(
            // 縦書きは右から左へ読み進めるため、シークバーも右から左にする
            child: Directionality(
              textDirection: isVertical ? TextDirection.rtl : TextDirection.ltr,
              child: Slider(
                value: value,
                max: max,
                divisions: paged && pageCount > 1 ? pageCount - 1 : null,
                label: label,
                onChanged: enabled ? (v) => dragging.value = v : null,
                onChangeEnd: enabled
                    ? (v) {
                        dragging.value = null;
                        if (paged) {
                          navigation.jumpToPage(v.round());
                        } else {
                          navigation.seek(v, isVertical: isVertical);
                        }
                      }
                    : null,
              ),
            ),
          ),
          SizedBox(
            width: 88,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}
