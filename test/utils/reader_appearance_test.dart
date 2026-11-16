import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/utils/reader_appearance.dart';

void main() {
  const size = Size(400, 800);

  group('TapZoneConfig: 左右', () {
    const config = TapZoneConfig(layout: TapZoneLayout.sides, sizePercent: 30);

    test('縦書きは左が次へ・右が前へ・中央がメニュー', () {
      expect(
        config.actionAt(const Offset(10, 400), size, isVertical: true),
        TapAction.next,
      );
      expect(
        config.actionAt(const Offset(390, 400), size, isVertical: true),
        TapAction.previous,
      );
      expect(
        config.actionAt(const Offset(200, 400), size, isVertical: true),
        TapAction.menu,
      );
    });

    test('横書きは右が次へ', () {
      expect(
        config.actionAt(const Offset(390, 400), size, isVertical: false),
        TapAction.next,
      );
    });

    test('反転すると入れ替わる', () {
      const reversed = TapZoneConfig(
        layout: TapZoneLayout.sides,
        sizePercent: 30,
        reversed: true,
      );
      expect(
        reversed.actionAt(const Offset(10, 400), size, isVertical: true),
        TapAction.previous,
      );
    });

    test('前へを無効にするとメニューになる', () {
      const noPrev = TapZoneConfig(
        layout: TapZoneLayout.sides,
        sizePercent: 30,
        disablePrevious: true,
      );
      expect(
        noPrev.actionAt(const Offset(390, 400), size, isVertical: true),
        TapAction.menu,
      );
    });
  });

  group('TapZoneConfig: 上下・L字', () {
    test('上下は上が前へ・下が次へ', () {
      const config = TapZoneConfig(
        layout: TapZoneLayout.topBottom,
        sizePercent: 25,
      );
      expect(
        config.actionAt(const Offset(200, 10), size, isVertical: true),
        TapAction.previous,
      );
      expect(
        config.actionAt(const Offset(200, 790), size, isVertical: true),
        TapAction.next,
      );
    });

    test('L字は下の帯も次へ', () {
      const config = TapZoneConfig(
        layout: TapZoneLayout.lShape,
        sizePercent: 25,
      );
      expect(
        config.actionAt(const Offset(390, 790), size, isVertical: true),
        TapAction.next,
      );
      expect(
        config.actionAt(const Offset(390, 300), size, isVertical: true),
        TapAction.previous,
      );
    });
  });

  test('保存値の復元：不明な値は既定値', () {
    expect(ReaderColorTheme.fromName('sepia'), ReaderColorTheme.sepia);
    expect(ReaderColorTheme.fromName('???'), ReaderColorTheme.system);
    expect(TapZoneLayout.fromName(null), TapZoneLayout.sides);
  });
}
