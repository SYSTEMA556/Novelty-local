import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/sites/novel_source.dart';
import 'package:novelty/utils/web_reading_positions.dart';

void main() {
  group('webEpisodeKey', () {
    test('サイト・作品・話ごとに別のキーになる', () {
      final a = webEpisodeKey(NovelSource.values.first, 'n1234ab', 1);
      final b = webEpisodeKey(NovelSource.values.first, 'n1234ab', 2);
      expect(a, isNot(b));
      expect(a, contains('n1234ab'));
    });
  });

  group('WebEpisodePosition', () {
    test('JSON に変換して戻せる', () {
      final position = WebEpisodePosition(
        offsets: const {'h': 120.5, 'vp': 3},
        updatedAt: DateTime.utc(2026, 11, 17),
      );
      final restored = WebEpisodePosition.fromJson(position.toJson());
      expect(restored.offsets, {'h': 120.5, 'vp': 3.0});
      expect(restored.updatedAt, DateTime.utc(2026, 11, 17));
    });
  });

  group('pruneWebPositions', () {
    test('上限を超えたら最後に読んだのが古いものから消す', () {
      WebEpisodePosition at(int day) => WebEpisodePosition(
        offsets: const {},
        updatedAt: DateTime.utc(2026, 1, day),
      );
      final pruned = pruneWebPositions({
        'old': at(1),
        'new': at(3),
        'mid': at(2),
      }, limit: 2);
      expect(pruned.keys.toSet(), {'new', 'mid'});
    });

    test('上限以内ならそのまま', () {
      final positions = {
        'a': WebEpisodePosition(offsets: const {}, updatedAt: DateTime(2026)),
      };
      expect(pruneWebPositions(positions, limit: 2), same(positions));
    });
  });
}
