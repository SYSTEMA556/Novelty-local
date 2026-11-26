import 'package:flutter_test/flutter_test.dart';
import 'package:narou_parser/narou_parser.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/read_aloud/speech_document.dart';
import 'package:novelty/widgets/pinned_bookmarks_sheet.dart';

void main() {
  final document = SpeechDocument.fromElements([
    const PlainText('一つ目の文。'),
    const NewLine(),
    const PlainText('二つ目の文はとても長くて、しおりの目印としては三十文字を超えてしまう文です。'),
  ]);

  test('しおりは文の頭の位置と、冒頭30文字ほどの目印を持つ', () {
    final pin = pinnedBookmarkAt(document, 1, now: DateTime(2026));
    expect(pin.offset, document.segments[1].start);
    expect(pin.fraction, closeTo(pin.offset / document.length, 1e-9));
    expect(pin.snippet.endsWith('…'), isTrue);
    expect(pin.snippet.length, pinnedSnippetLength + 1);
  });

  test('短い文は、続く文までつないで目印にする', () {
    final pin = pinnedBookmarkAt(document, 0, now: DateTime(2026));
    expect(pin.snippet.startsWith('一つ目の文。二つ目の文'), isTrue);
  });

  test('しおりは保存して読み戻せ、前の版の読書位置も読める', () {
    final position = ReadingPosition(
      offsets: const {'v': 1},
      progress: 0.5,
      updatedAt: DateTime(2026),
    ).withPins([pinnedBookmarkAt(document, 1, now: DateTime(2026))]);
    final restored = ReadingPosition.fromJson(position.toJson());
    expect(restored.pins, hasLength(1));
    expect(restored.pins.single.snippet, position.pins.single.snippet);

    final old = ReadingPosition.fromJson({
      'offsets': <String, dynamic>{},
      'progress': 0.1,
      'updatedAt': 0,
    });
    expect(old.pins, isEmpty);
  });
}
