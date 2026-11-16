import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/utils/line_length.dart';

void main() {
  group('lineExtentLimit', () {
    test('0 以下なら制限なし', () {
      expect(lineExtentLimit(maxChars: 0, fontSize: 16), isNull);
      expect(lineExtentLimit(maxChars: -1, fontSize: 16), isNull);
    });

    test('文字数 × フォントサイズ（＋端数の余裕）', () {
      expect(lineExtentLimit(maxChars: 40, fontSize: 16), 641);
    });
  });

  group('clampLineExtent', () {
    test('上限が無ければそのまま', () {
      expect(clampLineExtent(800, null), 800);
    });

    test('使える長さと上限の小さいほう', () {
      expect(clampLineExtent(800, 641), 641);
      expect(clampLineExtent(500, 641), 500);
    });
  });
}
