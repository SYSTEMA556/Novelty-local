import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:tategaki/src/element/tategaki_element.dart';
import 'package:tategaki/src/highlight.dart';
import 'package:tategaki/src/layout/tategaki_column_engine.dart';
import 'package:tategaki/src/layout/tategaki_layout.dart';
import 'package:tategaki/src/painting/tategaki_column_painter.dart';
import 'package:tategaki/src/tategaki_text_controller.dart';

/// 縦書きテキストを表示するウィジェット（横スクロール）
///
/// エピソード全体をレイアウトするのではなく、列単位の**遅延レンダリング**
/// を行う。横スクロールは [ListView.builder] で実装し、可視領域に近づいた
/// 列だけを [TategakiColumnEngine] で計算・描画する（列はバッチ単位で
/// 追加計算され、スクロール位置が末尾に近づくと拡張される）。
///
/// レイアウト結果は State が保持するため、入力（要素リスト・高さ・
/// スタイル）が変わらない限り再計算されない。同内容の要素リストは
/// 同じインスタンスを渡すこと（呼び出し側でメモ化する）。
class TategakiText extends StatefulWidget {
  /// コンストラクタ
  const TategakiText(
    this.elements, {
    required this.height,
    this.highlight,
    this.followHighlight = true,
    this.controller,
    this.onVisibleElementChanged,
    super.key,
  });

  /// 表示する要素のリスト
  final List<TategakiElement> elements;

  /// 列の高さ（必須）
  final double height;

  /// 背景色を付ける範囲（読み上げ中の文など）
  final TategakiHighlight? highlight;

  /// [highlight] が画面外に出たら自動でスクロールするか
  final bool followHighlight;

  /// 外から位置を移動するためのコントローラー
  final TategakiTextController? controller;

  /// スクロールが止まったとき、画面の読み始め側にある要素の位置を知らせる
  /// （全体のどこを読んでいるかの表示に使う）
  final ValueChanged<int>? onVisibleElementChanged;

  @override
  State<TategakiText> createState() => _TategakiTextState();
}

class _TategakiTextState extends State<TategakiText> {
  /// 列エンジン（入力が変わらない限り再利用）
  TategakiColumnEngine? _engine;

  /// 最後にレイアウト計算した入力値（再計算が必要かの判定用）
  List<TategakiElement>? _cachedElements;
  double? _cachedHeight;
  TextStyle? _cachedStyle;

  /// ListView に渡す itemCount（= 計算済みの列数）
  int _computedCount = 0;

  /// 追加計算のスケジュール済みフラグ
  bool _extendScheduled = false;

  /// 追加計算する列数（1画面分 + 余裕）
  static const int _extendBatch = 60;

  /// スクロール末尾からこの距離に近づいたら追加計算する
  static const double _extendThreshold = 800;

  /// ハイライトへの追従に使うスクロールコントローラー
  /// （位置の保存・復元は従来どおり PageStorage が行う）
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerRequest);
    widget.controller?.attachPageHandler(_scrollByPage);
    // 復元されたスクロール位置を、最初の描画後に知らせる
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reportVisibleElement();
    });
  }

  void _onControllerRequest() {
    final element = widget.controller?.takePendingElement();
    if (element != null) _revealElement(element, jump: true);
  }

  /// 画面1枚分（少し重ねて）スクロールする。端で動けなければ false
  bool _scrollByPage(int direction) {
    if (!_scrollController.hasClients) return false;
    final position = _scrollController.position;
    // 読み進める先の列を計算しておく（遅延計算のため）
    if (direction > 0) {
      _extendColumns(_currentEngine, notify: true);
    }
    final step = position.viewportDimension * 0.9;
    final target = (position.pixels + step * direction).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 1) return false;
    unawaited(
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
    );
    return true;
  }

  /// 画面の読み始め側にある要素の位置を知らせる
  void _reportVisibleElement() {
    final callback = widget.onVisibleElementChanged;
    if (callback == null || !_scrollController.hasClients) return;
    final engine = _currentEngine;
    final pixels = _scrollController.position.pixels;
    var start = 0.0;
    for (var i = 0; i < engine.computedColumnCount; i++) {
      final column = engine.columnAt(i);
      final end = start + column.width + TategakiLayout.columnSpacing;
      final first = column.firstElementIndex;
      if (end > pixels && first != null) {
        callback(first);
        return;
      }
      start = end;
    }
  }

  @override
  void didUpdateWidget(covariant TategakiText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerRequest);
      oldWidget.controller?.attachPageHandler(null);
      widget.controller?.addListener(_onControllerRequest);
      widget.controller?.attachPageHandler(_scrollByPage);
    }
    final highlight = widget.highlight;
    if (widget.followHighlight &&
        highlight != null &&
        highlight != oldWidget.highlight) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealElement(highlight.start);
      });
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerRequest);
    widget.controller?.attachPageHandler(null);
    _scrollController.dispose();
    super.dispose();
  }

  /// 要素 [elementIndex] を含む列が見えていなければ、見える位置へ動かす
  ///
  /// [jump] が true なら、見えていても列を読み始め側の端に置き、
  /// アニメーションせずに移動する（シークバーでの移動用）。
  void _revealElement(int elementIndex, {bool jump = false}) {
    if (!_scrollController.hasClients) {
      return;
    }
    final engine = _currentEngine;
    final columnIndex = engine.columnIndexOfElement(elementIndex);
    if (columnIndex == null) {
      return;
    }
    // その列の開始位置（列幅と列間の合計）
    var start = 0.0;
    for (var i = 0; i < columnIndex; i++) {
      start += engine.columnAt(i).width + TategakiLayout.columnSpacing;
    }
    final columnWidth = engine.columnAt(columnIndex).width;

    // ListView が列を表示できるよう、計算済みの列数を増やしておく
    if (engine.computedColumnCount != _computedCount) {
      setState(() => _computedCount = engine.computedColumnCount);
    }

    final position = _scrollController.position;
    final visibleStart = position.pixels;
    final visibleEnd = visibleStart + position.viewportDimension;
    if (!jump && start >= visibleStart && start + columnWidth <= visibleEnd) {
      return; // すでに見えている
    }
    // 読み進める方向に余裕を持たせ、画面の手前寄りに置く
    final target = jump
        ? start
        : (start - position.viewportDimension * 0.1).clamp(
            0.0,
            double.infinity,
          );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target > max ? max : target);
        _reportVisibleElement();
        return;
      }
      unawaited(
        _scrollController.animateTo(
          target > max ? max : target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        ),
      );
    });
  }

  /// 現在の入力に対応する列エンジンを返す
  TategakiColumnEngine get _currentEngine {
    final style = DefaultTextStyle.of(context).style;
    if (_engine == null ||
        !identical(_cachedElements, widget.elements) ||
        _cachedHeight != widget.height ||
        _cachedStyle != style) {
      _engine = TategakiColumnEngine(
        elements: widget.elements,
        maxHeight: widget.height,
        textStyle: style,
      );
      _cachedElements = widget.elements;
      _cachedHeight = widget.height;
      _cachedStyle = style;
      _computedCount = 0;
      _extendScheduled = false;
    }
    return _engine!;
  }

  /// 列を [_extendBatch] 個だけ追加計算して _computedCount を更新する
  void _extendColumns(TategakiColumnEngine engine, {required bool notify}) {
    var count = 0;
    while (count < _extendBatch) {
      if (engine.computeNextColumn() == null) {
        break; // 列の終端に到達
      }
      count++;
    }
    final newCount = engine.computedColumnCount;
    if (newCount != _computedCount) {
      _computedCount = newCount;
      if (notify && mounted) {
        setState(() {});
      }
    }
  }

  /// 追加計算を次フレーム以降にスケジュールする
  void _scheduleExtend() {
    if (_extendScheduled) {
      return;
    }
    _extendScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _extendScheduled = false;
      if (!mounted) {
        return;
      }
      _extendColumns(_currentEngine, notify: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.elements.isEmpty) {
      return const SizedBox.shrink();
    }

    final engine = _currentEngine;

    // 初回はビルド中に最初のバッチを計算して itemCount を確保する
    if (_computedCount == 0) {
      _extendColumns(engine, notify: false);
    }

    final scrollPositionKey = PageStorageKey<Object>(widget.key ?? this);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // スクロール位置が末尾に近づいたら列を追加計算する
        if (notification.metrics.axis == Axis.horizontal &&
            notification.metrics.extentAfter < _extendThreshold) {
          _scheduleExtend();
        }
        return false;
      },
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (_) {
          _reportVisibleElement();
          return false;
        },
        child: ListView.separated(
        // PageStorageKey でスクロール位置を保持する
        key: scrollPositionKey,
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        itemCount: _computedCount,
        // 列間のスペース（旧実装の columnSpacing に相当）
        separatorBuilder: (context, index) =>
            const SizedBox(width: TategakiLayout.columnSpacing),
        itemBuilder: (context, index) {
          // 末尾の列をビルドしたら追加計算を予約する
          if (index >= _computedCount - 1) {
            _scheduleExtend();
          }
          final column = engine.columnAt(index);
          final highlight = widget.highlight;
          return CustomPaint(
            size: Size(column.width, widget.height),
            painter: TategakiColumnPainter(
              column: column,
              // 範囲外の列には渡さず、無駄な再描画を避ける
              highlight: highlight != null && highlight.overlapsColumn(column)
                  ? highlight
                  : null,
            ),
          );
        },
        ),
      ),
    );
  }
}
