import 'package:flutter/material.dart';

/// 本文の色調（背景色と文字色の組み合わせ）。
enum ReaderColorTheme {
  /// 端末のライト／ダーク設定に合わせる。
  system('端末に合わせる', null, null),

  /// 白地に黒文字。
  white('白', Color(0xFFFFFFFF), Color(0xFF212121)),

  /// 生成り（紙の本に近い黄味）。
  sepia('生成り', Color(0xFFF4ECD8), Color(0xFF4A3B2A)),

  /// 薄いグレー。
  gray('グレー', Color(0xFFE3E3E3), Color(0xFF2E2E2E)),

  /// 暗い灰色に明るい文字。
  dark('ダーク', Color(0xFF2B2B2B), Color(0xFFD8D8D8)),

  /// 真っ黒（有機ELで省電力）。
  black('黒', Color(0xFF000000), Color(0xFFC4C4C4));

  const ReaderColorTheme(this.label, this.background, this.text);

  /// 表示名。
  final String label;

  /// 背景色（[system] は null）。
  final Color? background;

  /// 文字色（[system] は null）。
  final Color? text;

  /// 保存値から復元する（不明な値は [system]）。
  static ReaderColorTheme fromName(String? name) =>
      ReaderColorTheme.values.firstWhere(
        (t) => t.name == name,
        orElse: () => ReaderColorTheme.system,
      );
}

/// ページボタン（画面のタップ領域）の配置。
enum TapZoneLayout {
  /// 左右の帯（中央はメニュー）。
  sides('左右'),

  /// 上下の帯（中央はメニュー）。
  topBottom('上下'),

  /// 左右の帯に加え、下の帯も「次へ」。
  lShape('L字（下も次へ）');

  const TapZoneLayout(this.label);

  /// 表示名。
  final String label;

  /// 保存値から復元する（不明な値は [sides]）。
  static TapZoneLayout fromName(String? name) => TapZoneLayout.values
      .firstWhere((l) => l.name == name, orElse: () => TapZoneLayout.sides);
}

/// タップした場所に割り当てられた動作。
enum TapAction {
  /// 次のページへ。
  next,

  /// 前のページへ。
  previous,

  /// メニュー（バーの表示切り替え）。
  menu,
}

/// ページボタンの設定。
@immutable
class TapZoneConfig {
  /// コンストラクタ。
  const TapZoneConfig({
    required this.layout,
    required this.sizePercent,
    this.reversed = false,
    this.disablePrevious = false,
  });

  /// 配置。
  final TapZoneLayout layout;

  /// 帯の太さ（画面の幅・高さに対する割合、%）。
  final int sizePercent;

  /// 次へ／前への位置を入れ替えるか。
  final bool reversed;

  /// 「前へ」を無効にする（その場所はメニューになる）か。
  final bool disablePrevious;

  /// 「次へ」が左側か。
  ///
  /// 縦書きは右から左へ読み進めるため、標準では左が「次へ」。
  /// 横書きは標準で右が「次へ」。[reversed] で入れ替わる。
  bool nextOnLeft({required bool isVertical}) => isVertical != reversed;

  /// [size] の画面で [position] をタップしたときの動作。
  TapAction actionAt(
    Offset position,
    Size size, {
    required bool isVertical,
  }) {
    final f = sizePercent.clamp(10, 45) / 100;
    final leftNext = nextOnLeft(isVertical: isVertical);

    TapAction sideAction({required bool isLeft}) =>
        isLeft == leftNext ? TapAction.next : TapAction.previous;

    TapAction action;
    switch (layout) {
      case TapZoneLayout.sides:
        if (position.dx < size.width * f) {
          action = sideAction(isLeft: true);
        } else if (position.dx > size.width * (1 - f)) {
          action = sideAction(isLeft: false);
        } else {
          action = TapAction.menu;
        }
      case TapZoneLayout.topBottom:
        // 上が「前へ」、下が「次へ」（反転で入れ替え）
        if (position.dy < size.height * f) {
          action = reversed ? TapAction.next : TapAction.previous;
        } else if (position.dy > size.height * (1 - f)) {
          action = reversed ? TapAction.previous : TapAction.next;
        } else {
          action = TapAction.menu;
        }
      case TapZoneLayout.lShape:
        if (position.dy > size.height * (1 - f)) {
          action = TapAction.next;
        } else if (position.dx < size.width * f) {
          action = sideAction(isLeft: true);
        } else if (position.dx > size.width * (1 - f)) {
          action = sideAction(isLeft: false);
        } else {
          action = TapAction.menu;
        }
    }
    if (disablePrevious && action == TapAction.previous) {
      return TapAction.menu;
    }
    return action;
  }
}
