import 'package:flutter/material.dart';

/// 縦書きモード時のホームジェスチャー誤爆を防ぐための透明シールド
///
/// 画面下部のシステムジェスチャー領域に配置し、垂直スワイプを
/// 消費することでホームジェスチャーとの競合を回避します。
class GestureShield extends StatelessWidget {
  /// コンストラクタ
  const GestureShield({super.key});

  /// シールドの追加高さ（システムジェスチャー領域に加える余裕）
  static const double _kExtraHeight = 40;

  @override
  Widget build(BuildContext context) {
    final systemGestureInsets = MediaQuery.of(context).systemGestureInsets;
    final shieldHeight = systemGestureInsets.bottom + _kExtraHeight;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: shieldHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) {},
        onVerticalDragUpdate: (_) {},
        onVerticalDragEnd: (_) {},
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// 読書画面の下の「触っても何も起きない帯」（フォークで追加）。
///
/// Android の戻る・ホームのボタンやジェスチャーを使うときに、指が
/// ページ送りやシークバーに触れないよう、タップとスワイプをすべて吸い込む。
/// [Stack] の中に置く。
class ReaderBottomGuard extends StatelessWidget {
  /// コンストラクタ。
  const ReaderBottomGuard({required this.height, super.key});

  /// 帯の高さ（[heightOf] で求める）。
  final double height;

  /// 画面の下に空けておく帯の高さ。
  ///
  /// 画面の高さの [percent]% と、システムのボタン・ジェスチャーの領域の
  /// 大きいほう。[percent] が 0 ならシステムの領域だけ。
  static double heightOf(BuildContext context, int percent) {
    final media = MediaQuery.of(context);
    final system = media.viewPadding.bottom;
    if (percent <= 0) return system;
    final guard = media.size.height * percent.clamp(0, 25) / 100;
    return guard > system ? guard : system;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        onVerticalDragStart: (_) {},
        onVerticalDragUpdate: (_) {},
        onVerticalDragEnd: (_) {},
        onHorizontalDragStart: (_) {},
        onHorizontalDragUpdate: (_) {},
        onHorizontalDragEnd: (_) {},
        child: const SizedBox.expand(),
      ),
    );
  }
}
