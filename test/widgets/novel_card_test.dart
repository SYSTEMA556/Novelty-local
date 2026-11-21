import 'package:flutter_test/flutter_test.dart';
import 'package:novelty/widgets/novel_card.dart';

void main() {
  test('同じジャンルは同じ色、違うジャンルは違う色になりやすい', () {
    expect(novelCardColor('narou:201'), novelCardColor('narou:201'));
    expect(novelCardColor('narou:201'), isNot(novelCardColor('narou:102')));
  });

  test('ひとことは、あらすじの最初の一文', () {
    expect(novelCardBlurb('  旅に出る。\n仲間ができる。'), '旅に出る。');
    expect(novelCardBlurb('句点のない文'), '句点のない文');
    expect(novelCardBlurb(''), isNull);
    expect(novelCardBlurb(null), isNull);
  });

  test('長い一文は切って「…」を付ける', () {
    final blurb = novelCardBlurb('あ' * 100, maxLength: 10);
    expect(blurb, '${'あ' * 10}…');
  });
}
