import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/widgets/kenten_text_widget.dart';
import 'package:novelty/widgets/ruby_text_widget.dart';

/// 小説のコンテンツを表示するウィジェット。
class NovelContentView extends HookWidget {
  /// コンストラクタ。
  const NovelContentView({
    required this.elements,
    this.isRubyEnabled = true,
    this.highlightStart,
    this.highlightEnd,
    this.highlightColor,
    super.key,
  });

  /// 小説のコンテンツ要素のリスト。
  final List<NovelContentElement> elements;

  /// ルビの表示設定。
  final bool isRubyEnabled;

  /// 背景色を付ける範囲の開始（本文位置。読み上げ中の文など）
  final int? highlightStart;

  /// 背景色を付ける範囲の終了（本文位置、含まない）
  final int? highlightEnd;

  /// 背景色。
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    // 色を付けた範囲の先頭に置く目印（自動スクロールの基準）
    final anchorKey = useMemoized(GlobalKey.new);

    // 範囲が画面外に出たら、画面の上寄りに来るようスクロールする
    useEffect(() {
      if (highlightStart == null) return null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _revealAnchor(anchorKey);
      });
      return null;
    }, [highlightStart]);

    final defaultStyle = DefaultTextStyle.of(context).style;

    // ルビの高さを考慮して、行の高さを少し多めに確保する
    // ルビ無効時は StrutStyle を使わず、lineHeight をそのまま反映
    // スタイル計算をメモ化してパフォーマンスを向上
    final strutStyle = useMemoized(
      () => isRubyEnabled
          ? StrutStyle(
              fontSize: defaultStyle.fontSize,
              height: 1.8, // 行間の倍率
              forceStrutHeight: true,
            )
          : null,
      [defaultStyle.fontSize, isRubyEnabled],
    );

    // span生成処理をメモ化してelementsが変更された時のみ再計算
    final spans = useMemoized(
      () => buildSpans(
        elements,
        defaultStyle,
        isRubyEnabled: isRubyEnabled,
        highlightStart: highlightStart,
        highlightEnd: highlightEnd,
        highlightColor: highlightColor,
        anchorKey: anchorKey,
      ),
      [
        elements,
        defaultStyle,
        isRubyEnabled,
        highlightStart,
        highlightEnd,
        highlightColor,
      ],
    );

    return RichText(
      strutStyle: strutStyle,
      text: TextSpan(
        style: defaultStyle,
        children: spans,
      ),
    );
  }

  /// 目印が画面外なら、画面の上から2割の位置に来るようスクロールする。
  static void _revealAnchor(GlobalKey anchorKey) {
    final anchorContext = anchorKey.currentContext;
    if (anchorContext == null) return;
    final box = anchorContext.findRenderObject();
    if (box is! RenderBox || !box.attached) return;
    final scrollable = Scrollable.maybeOf(anchorContext);
    if (scrollable == null) return;
    final position = scrollable.position;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;

    // 目印を画面の上端に置くときのスクロール位置
    final top = viewport.getOffsetToReveal(box, 0).offset;
    final visibleStart = position.pixels;
    final visibleEnd = visibleStart + position.viewportDimension * 0.85;
    if (top >= visibleStart && top <= visibleEnd) return;

    final target = (top - position.viewportDimension * 0.2).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    unawaited(
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      ),
    );
  }

  /// 小説のコンテンツ要素から`InlineSpan`のリストを生成するヘルパーメソッド。
  ///
  /// [highlightStart]〜[highlightEnd]（本文位置）を指定すると、その範囲に
  /// [highlightColor] の背景色を付け、範囲の先頭に [anchorKey] の目印を置く。
  static List<InlineSpan> buildSpans(
    List<NovelContentElement> elements,
    TextStyle style, {
    bool isRubyEnabled = true,
    int? highlightStart,
    int? highlightEnd,
    Color? highlightColor,
    Key? anchorKey,
  }) {
    final hasHighlight =
        highlightStart != null &&
        highlightEnd != null &&
        highlightColor != null;
    // hasHighlight が false のときは使われない
    final hlStart = highlightStart ?? 0;
    final hlEnd = highlightEnd ?? 0;
    final highlightStyle = hasHighlight
        ? style.copyWith(backgroundColor: highlightColor)
        : style;

    final spans = <InlineSpan>[];
    var offset = 0;

    // 範囲の先頭がこの要素内なら目印を置く
    void addAnchorIfStartsIn(int from, int to) {
      if (!hasHighlight || anchorKey == null) return;
      if (hlStart >= from && hlStart < to) {
        spans.add(
          WidgetSpan(child: SizedBox.shrink(key: anchorKey)),
        );
      }
    }

    bool overlaps(int from, int to) =>
        hasHighlight && from < hlEnd && to > hlStart;

    for (final element in elements) {
      switch (element) {
        case PlainText():
          final text = element.text;
          final end = offset + text.length;
          if (!overlaps(offset, end)) {
            spans.add(TextSpan(text: text, style: style));
          } else {
            // 範囲の前・中・後に分けて、中だけ色を付ける
            final from = (hlStart - offset).clamp(0, text.length);
            final to = (hlEnd - offset).clamp(0, text.length);
            if (from > 0) {
              spans.add(TextSpan(text: text.substring(0, from), style: style));
            }
            addAnchorIfStartsIn(offset, end);
            spans.add(
              TextSpan(text: text.substring(from, to), style: highlightStyle),
            );
            if (to < text.length) {
              spans.add(TextSpan(text: text.substring(to), style: style));
            }
          }
          offset = end;
        case RubyText():
          final end = offset + element.base.length;
          addAnchorIfStartsIn(offset, end);
          final rubyStyle = overlaps(offset, end) ? highlightStyle : style;
          offset = end;
          if (isRubyEnabled) {
            // ルビ有効時: WidgetSpanを使用してルビを表示
            spans.add(
              WidgetSpan(
                child: _highlightBox(
                  highlighted: rubyStyle != style,
                  color: highlightColor,
                  child: RubySpan(
                    base: element.base,
                    ruby: element.ruby,
                    style: style,
                  ),
                ),
              ),
            );
          } else {
            // ルビ無効時: ベーステキストのみ表示
            spans.add(TextSpan(text: element.base, style: rubyStyle));
          }
        case Kenten():
          final end = offset + element.base.length;
          addAnchorIfStartsIn(offset, end);
          final highlighted = overlaps(offset, end);
          offset = end;
          // 横書きでは各文字の上に点を表示する
          spans.add(
            WidgetSpan(
              child: _highlightBox(
                highlighted: highlighted,
                color: highlightColor,
                child: KentenSpan(
                  base: element.base,
                  mark: element.mark,
                  style: style,
                ),
              ),
            ),
          );
        case NewLine():
          addAnchorIfStartsIn(offset, offset + 1);
          offset += 1;
          spans.add(const TextSpan(text: '\n'));
      }
    }
    return spans;
  }

  static Widget _highlightBox({
    required bool highlighted,
    required Color? color,
    required Widget child,
  }) {
    if (!highlighted || color == null) return child;
    return DecoratedBox(
      decoration: BoxDecoration(color: color),
      child: child,
    );
  }
}
