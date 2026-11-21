import 'package:flutter/material.dart';

/// 縦書きモード時のホームジェスチャー誤爆を防ぐための透明シールド
///
/// 画面下部のシステムジェスチャー領域に配置し、垂直スワイプを
/// 消費することでホームジェスチャーとの競合を回避します。
class GestureShield extends StatelessWidget {
  /// コンストラクタ
  ///
  /// [height] を渡すと、その高さの帯にし、タップや横のスワイプも吸い込む
  /// （読書画面の下の「触っても何も起きない帯」。フォークで追加）。
  const GestureShield({this.height, super.key});

  /// 帯の高さ。null ならシステムのジェスチャー領域＋余裕。
  final double? height;

  /// 画面の下に空けておく帯の高さ（フォークで追加）。
  ///
  /// 画面の高さの [percent]% と、システムのボタン・ジェスチャーの領域の
  /// 大きいほう。[percent] が 0 ならシステムの領域だけ。
  static double guardHeightOf(BuildContext context, int percent) {
    final media = MediaQuery.of(context);
    final system = media.viewPadding.bottom;
    if (percent <= 0) return system;
    final guard = media.size.height * percent.clamp(0, 25) / 100;
    return guard > system ? guard : system;
  }

  /// シールドの追加高さ（システムジェスチャー領域に加える余裕）
  static const double _kExtraHeight = 40;

  @override
  Widget build(BuildContext context) {
    final systemGestureInsets = MediaQuery.of(context).systemGestureInsets;
    final shieldHeight = height ?? systemGestureInsets.bottom + _kExtraHeight;
    final absorbAll = height != null;

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
        // 下の帯として使うときは、タップと横のスワイプも吸い込む
        onTap: absorbAll ? () {} : null,
        onHorizontalDragStart: absorbAll ? (_) {} : null,
        onHorizontalDragUpdate: absorbAll ? (_) {} : null,
        onHorizontalDragEnd: absorbAll ? (_) {} : null,
        child: const SizedBox.expand(),
      ),
    );
  }
}
