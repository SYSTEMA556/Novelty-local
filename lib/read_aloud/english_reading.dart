/// 英単語をカタカナの読みに直す（VOICEVOX で読むとき用・フォークで追加）。
///
/// VOICEVOX は英語を読めず、アルファベットを1文字ずつ読んでしまう。
/// そこで声を作る前に、文の中の英単語を次の順でカタカナに置き換える。
///
/// 1. 利用者の「読みの辞書」（読み上げの前に済んでいる。いちばん強い）
/// 2. このファイルの辞書（the・of・you など、推測が外れやすい短い言葉）
/// 3. 大文字だけの略語（AI・NPC など）は1文字ずつ（エーアイ・エヌピーシー）
/// 4. それ以外は kanalizer（VOICEVOX 製の、つづりから読みを推測するモデル）
/// 5. 推測できなかったら1文字ずつ
///
/// たとえるなら、まず手元の単語帳を引き、載っていなければ
/// 「英語っぽいつづりの読み方」に慣れた人に聞く、という順番。
library;

/// 英単語（全角も含む）。it's・don't のような短縮形もひとまとまりにする。
final _wordPattern = RegExp(
  "[A-Za-zＡ-Ｚａ-ｚ]+(?:['’][A-Za-zＡ-Ｚａ-ｚ]+)?",
);

/// 全角のアルファベットと ’ を半角に直す。
String _toAscii(String word) {
  final buffer = StringBuffer();
  for (final rune in word.runes) {
    if ((rune >= 0xFF21 && rune <= 0xFF3A) ||
        (rune >= 0xFF41 && rune <= 0xFF5A)) {
      buffer.writeCharCode(rune - 0xFEE0);
    } else if (rune == 0x2019) {
      buffer.write("'");
    } else {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// アルファベット1文字の読み。
const _letters = {
  'a': 'エー',
  'b': 'ビー',
  'c': 'シー',
  'd': 'ディー',
  'e': 'イー',
  'f': 'エフ',
  'g': 'ジー',
  'h': 'エイチ',
  'i': 'アイ',
  'j': 'ジェー',
  'k': 'ケー',
  'l': 'エル',
  'm': 'エム',
  'n': 'エヌ',
  'o': 'オー',
  'p': 'ピー',
  'q': 'キュー',
  'r': 'アール',
  's': 'エス',
  't': 'ティー',
  'u': 'ユー',
  'v': 'ブイ',
  'w': 'ダブリュー',
  'x': 'エックス',
  'y': 'ワイ',
  'z': 'ゼット',
};

/// 1文字ずつ読む（AI → エーアイ）。
String spellEnglish(String word) => [
  for (final c in _toAscii(word).toLowerCase().split('')) _letters[c] ?? '',
].join();

/// 推測が外れやすい言葉の辞書（小文字で引く）。
///
/// 機能語（the・of など）は短すぎてつづりから推測しにくく、kanalizer だと
/// 「the → セ」のようになるため、ここで決めておく。
/// 小説によく出る言葉で、試して外れたもの（hello・status など）も入れている。
const englishReadingDictionary = {
  // 冠詞・代名詞
  'a': 'ア',
  'an': 'アン',
  'the': 'ザ',
  'i': 'アイ',
  'me': 'ミー',
  'my': 'マイ',
  'mine': 'マイン',
  'you': 'ユー',
  'your': 'ユア',
  'yours': 'ユアーズ',
  'he': 'ヒー',
  'him': 'ヒム',
  'his': 'ヒズ',
  'she': 'シー',
  'her': 'ハー',
  'it': 'イット',
  'its': 'イッツ',
  'we': 'ウィー',
  'us': 'アス',
  'our': 'アワー',
  'they': 'ゼイ',
  'them': 'ゼム',
  'their': 'ゼア',
  'this': 'ディス',
  'that': 'ザット',
  'these': 'ディーズ',
  'those': 'ゾーズ',
  'who': 'フー',
  'what': 'ホワット',
  'which': 'ウィッチ',
  'where': 'ホエア',
  'when': 'ホエン',
  'why': 'ホワイ',
  'how': 'ハウ',
  // 前置詞・接続詞
  'of': 'オブ',
  'to': 'トゥー',
  'in': 'イン',
  'on': 'オン',
  'at': 'アット',
  'by': 'バイ',
  'for': 'フォー',
  'from': 'フロム',
  'with': 'ウィズ',
  'without': 'ウィズアウト',
  'into': 'イントゥー',
  'over': 'オーバー',
  'under': 'アンダー',
  'about': 'アバウト',
  'and': 'アンド',
  'or': 'オア',
  'but': 'バット',
  'if': 'イフ',
  'so': 'ソー',
  'as': 'アズ',
  'than': 'ザン',
  'then': 'ゼン',
  'not': 'ノット',
  'no': 'ノー',
  'yes': 'イエス',
  'all': 'オール',
  'up': 'アップ',
  'out': 'アウト',
  'off': 'オフ',
  // 動詞
  'is': 'イズ',
  'am': 'アム',
  'are': 'アー',
  'was': 'ワズ',
  'were': 'ワー',
  'be': 'ビー',
  'been': 'ビーン',
  'do': 'ドゥー',
  'does': 'ダズ',
  'did': 'ディド',
  'have': 'ハブ',
  'has': 'ハズ',
  'had': 'ハド',
  'will': 'ウィル',
  'would': 'ウッド',
  'can': 'キャン',
  'could': 'クッド',
  'shall': 'シャル',
  'should': 'シュッド',
  'may': 'メイ',
  'might': 'マイト',
  'must': 'マスト',
  'go': 'ゴー',
  'come': 'カム',
  'get': 'ゲット',
  'let': 'レット',
  'make': 'メイク',
  'take': 'テイク',
  'give': 'ギブ',
  'know': 'ノウ',
  'see': 'シー',
  'say': 'セイ',
  'love': 'ラブ',
  'live': 'リブ',
  'like': 'ライク',
  'want': 'ウォント',
  // 短縮形
  "i'm": 'アイム',
  "i'll": 'アイル',
  "i've": 'アイブ',
  "you're": 'ユーアー',
  "it's": 'イッツ',
  "that's": 'ザッツ',
  "let's": 'レッツ',
  "don't": 'ドント',
  "doesn't": 'ダズント',
  "didn't": 'ディドント',
  "can't": 'キャント',
  "won't": 'ウォント',
  "isn't": 'イズント',
  "aren't": 'アーント',
  "wasn't": 'ワズント',
  "what's": 'ホワッツ',
  // あいさつ・よく出る言葉
  'hello': 'ハロー',
  'hi': 'ハイ',
  'bye': 'バイ',
  'goodbye': 'グッバイ',
  'thank': 'サンク',
  'thanks': 'サンクス',
  'please': 'プリーズ',
  'sorry': 'ソーリー',
  'ok': 'オーケー',
  'okay': 'オーケー',
  'oh': 'オー',
  'mr': 'ミスター',
  'mrs': 'ミセス',
  'ms': 'ミズ',
  'dr': 'ドクター',
  'vs': 'バーサス',
  'etc': 'エトセトラ',
  'one': 'ワン',
  'two': 'ツー',
  'three': 'スリー',
  'four': 'フォー',
  'five': 'ファイブ',
  'six': 'シックス',
  'seven': 'セブン',
  'eight': 'エイト',
  'nine': 'ナイン',
  'ten': 'テン',
  // 小説（ゲーム・異世界もの）に多い言葉
  'status': 'ステータス',
  'skill': 'スキル',
  'skills': 'スキルズ',
  'level': 'レベル',
  'lv': 'レベル',
  'hp': 'エイチピー',
  'mp': 'エムピー',
  'exp': 'イーエックスピー',
  'str': 'エスティーアール',
  'vit': 'ブイアイティー',
  'agi': 'エージーアイ',
  'int': 'アイエヌティー',
  'dex': 'デックス',
  'luk': 'ラック',
  'max': 'マックス',
  'game': 'ゲーム',
  'unknown': 'アンノウン',
  'error': 'エラー',
  'system': 'システム',
  'quest': 'クエスト',
  'guild': 'ギルド',
  'rank': 'ランク',
  'party': 'パーティー',
  'online': 'オンライン',
  'login': 'ログイン',
  'logout': 'ログアウト',
  'vrmmo': 'ブイアールエムエムオー',
  'vrmmorpg': 'ブイアールエムエムオーアールピージー',
  'rpg': 'アールピージー',
  'npc': 'エヌピーシー',
  'pk': 'ピーケー',
  'pvp': 'ピーブイピー',
  'boss': 'ボス',
  'ex': 'イーエックス',
  'sss': 'トリプルエス',
  'ss': 'ダブルエス',
  'lucky': 'ラッキー',
  'sir': 'サー',
  'lady': 'レディ',
  'king': 'キング',
  'queen': 'クイーン',
  'god': 'ゴッド',
  'heart': 'ハート',
  'world': 'ワールド',
  'end': 'エンド',
  'new': 'ニュー',
  'night': 'ナイト',
  'day': 'デイ',
  'dark': 'ダーク',
  'black': 'ブラック',
  'white': 'ホワイト',
  'red': 'レッド',
  'blue': 'ブルー',
  'happy': 'ハッピー',
  'good': 'グッド',
  'bad': 'バッド',
  'very': 'ベリー',
  'nice': 'ナイス',
  'cool': 'クール',
  'perfect': 'パーフェクト',
  'win': 'ウィン',
  'lose': 'ルーズ',
  'start': 'スタート',
  'stop': 'ストップ',
};

/// 文の中の英単語を読みに直す。
///
/// [infer] は辞書に無い単語をまとめて推測する関数（kanalizer）。
/// 空文字が返った単語は1文字ずつ読む。
Future<String> readEnglishAsKana(
  String text, {
  required Future<List<String>> Function(List<String> words) infer,
}) async {
  final matches = _wordPattern.allMatches(text).toList();
  if (matches.isEmpty) return text;
  final readings = <String, String>{};
  final unknown = <String>{};
  for (final m in matches) {
    final word = _toAscii(m[0]!);
    if (readings.containsKey(word)) continue;
    final reading = readEnglishWithoutModel(word);
    if (reading != null) {
      readings[word] = reading;
    } else {
      final cached = _cache[word.toLowerCase()];
      if (cached != null) {
        readings[word] = cached;
      } else {
        unknown.add(word.toLowerCase());
      }
    }
  }
  if (unknown.isNotEmpty) {
    final words = unknown.toList();
    // 推測には a〜z だけを渡す（Alice's は Alice を推測して「ズ」を足す）
    final queries = [for (final w in words) _queryOf(w)];
    var results = const <String>[];
    try {
      results = await infer(queries.map((q) => q.base).toList());
    } on Object {
      // 推測できないときは1文字ずつ読む
    }
    for (var i = 0; i < words.length; i++) {
      final kana = i < results.length ? results[i] : '';
      _remember(
        words[i],
        kana.isEmpty ? spellEnglish(words[i]) : '$kana${queries[i].suffix}',
      );
    }
  }
  return text.replaceAllMapped(_wordPattern, (m) {
    final word = _toAscii(m[0]!);
    return readings[word] ?? _cache[word.toLowerCase()] ?? spellEnglish(word);
  });
}

/// 辞書と決まりだけで読めれば、その読み（推測が要るなら null）。
String? readEnglishWithoutModel(String word) {
  final ascii = _toAscii(word);
  final lower = ascii.toLowerCase();
  // 大文字1文字は文字の名前（A → エー）。ただし I は「私」
  if (ascii.length == 1 && ascii != lower && lower != 'i') {
    return spellEnglish(ascii);
  }
  final known = englishReadingDictionary[lower];
  if (known != null) return known;
  // 大文字だけの略語（AI・NPC・HP など）は1文字ずつ
  if (ascii.length <= 5 && ascii == ascii.toUpperCase() && ascii != lower) {
    return spellEnglish(ascii);
  }
  // 母音の無いつづり（hmm・pst など）は推測しにくいので1文字ずつ
  if (!RegExp('[aeiouy]').hasMatch(lower)) {
    return lower.length <= 3 ? spellEnglish(lower) : null;
  }
  // 所有の 's（Alice's → アリス＋ズ）
  if (lower.endsWith("'s")) {
    final base = englishReadingDictionary[lower.substring(0, lower.length - 2)];
    if (base != null) return '$baseズ';
  }
  return null;
}

({String base, String suffix}) _queryOf(String lower) {
  if (lower.endsWith("'s")) {
    return (base: lower.substring(0, lower.length - 2), suffix: 'ズ');
  }
  return (base: lower.replaceAll("'", ''), suffix: '');
}

// 推測した読み（同じ単語を何度も推測しないよう覚えておく）
final Map<String, String> _cache = {};

void _remember(String word, String kana) {
  if (_cache.length >= 5000) _cache.remove(_cache.keys.first);
  _cache[word] = kana;
}
