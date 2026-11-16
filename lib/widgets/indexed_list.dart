import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

/// 右端にインデックス（#・A〜Z・あ〜わ など）を表示するリスト。
///
/// 見出しをタップ、または指でなぞると、その見出しの先頭の項目へ飛ぶ。
/// なぞっている間は画面中央に見出しを大きく表示する。
class IndexedList extends HookWidget {
  /// コンストラクタ。
  const IndexedList({
    required this.itemCount,
    required this.itemBuilder,
    required this.labelOf,
    this.showIndex = true,
    super.key,
  });

  /// 項目数。
  final int itemCount;

  /// 項目を作る。
  final IndexedWidgetBuilder itemBuilder;

  /// 項目の見出し（並び順どおりに並んでいる前提）。
  final String Function(int index) labelOf;

  /// インデックスを表示するか（並び順が見出しと関係ないときは false）。
  final bool showIndex;

  /// インデックスの幅。
  static const double barWidth = 28;

  @override
  Widget build(BuildContext context) {
    final controller = useMemoized(ItemScrollController.new);

    // 見出し → その見出しの最初の項目の位置
    final firstIndex = useMemoized(() {
      final map = <String, int>{};
      for (var i = 0; i < itemCount; i++) {
        map.putIfAbsent(labelOf(i), () => i);
      }
      return map;
    }, [itemCount, labelOf]);
    final labels = firstIndex.keys.toList();
    final hasIndex = showIndex && labels.length > 1;
    final active = useState<String?>(null);

    void jumpTo(String label) {
      if (active.value == label) return;
      active.value = label;
      final index = firstIndex[label];
      if (index != null && controller.isAttached) {
        controller.jumpTo(index: index);
        _selectionHaptic();
      }
    }

    return Stack(
      children: [
        ScrollablePositionedList.builder(
          itemCount: itemCount,
          itemBuilder: itemBuilder,
          itemScrollController: controller,
          // インデックスと項目が重ならないよう右側を空ける
          padding: EdgeInsets.only(right: hasIndex ? barWidth : 0),
        ),
        if (hasIndex)
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: barWidth,
            child: _IndexBar(
              labels: labels,
              active: active.value,
              onSelect: jumpTo,
              onEnd: () => active.value = null,
            ),
          ),
        if (active.value != null)
          IgnorePointer(
            child: Center(child: _Bubble(label: active.value!)),
          ),
      ],
    );
  }
}

/// 見出しが切り替わったことを指先に伝える。
void _selectionHaptic() {
  // 振動の完了を待つ必要はないため、戻り値の Future は待たない
  HapticFeedback.selectionClick().ignore();
}

/// 右端の見出しの列。
class _IndexBar extends StatelessWidget {
  const _IndexBar({
    required this.labels,
    required this.active,
    required this.onSelect,
    required this.onEnd,
  });

  final List<String> labels;
  final String? active;
  final ValueChanged<String> onSelect;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // 見出しが多くて入りきらない場合は文字を小さくする
        final slot = constraints.maxHeight / labels.length;
        final fontSize = slot.clamp(6, 13).toDouble();

        void select(double dy) {
          final i = (dy / slot).floor().clamp(0, labels.length - 1);
          onSelect(labels[i]);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => select(d.localPosition.dy),
          onTapUp: (_) => onEnd(),
          onTapCancel: onEnd,
          onVerticalDragStart: (d) => select(d.localPosition.dy),
          onVerticalDragUpdate: (d) => select(d.localPosition.dy),
          onVerticalDragEnd: (_) => onEnd(),
          onVerticalDragCancel: onEnd,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: active == null
                  ? Colors.transparent
                  : theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.8,
                    ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                for (final label in labels)
                  SizedBox(
                    height: slot,
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: label == active
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// なぞっている間、中央に出す大きな見出し。
class _Bubble extends StatelessWidget {
  const _Bubble({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 72,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 36, color: scheme.onPrimaryContainer),
      ),
    );
  }
}
