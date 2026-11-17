import 'package:flutter/foundation.dart';
import 'package:novelty/read_aloud/speech_document.dart';

/// 文の役割（誰が・どう話しているか）。
enum SpeechRole {
  /// 地の文。
  narration('地の文'),

  /// 台詞（「」『』）。
  dialogue('台詞'),

  /// 心の声（（））。
  thought('心の声');

  const SpeechRole(this.label);

  /// 表示名。
  final String label;
}

/// 文の感情。
///
/// 声の高さ・速さ・音量の倍率を持つ（強さ 1・演技 100% のときの値）。
enum SpeechEmotion {
  /// 普通。
  neutral('普通', pitch: 1, rate: 1, volume: 1),

  /// 喜び・楽しさ。
  joy('喜び', pitch: 1.12, rate: 1.06, volume: 1),

  /// 怒り。低めで速く。
  anger('怒り', pitch: 0.93, rate: 1.1, volume: 1),

  /// 叫び。高めで速く。
  shout('叫び', pitch: 1.16, rate: 1.08, volume: 1),

  /// 悲しみ。低めでゆっくり、少し小さく。
  sadness('悲しみ', pitch: 0.9, rate: 0.84, volume: 0.85),

  /// 驚き。高く速く。
  surprise('驚き', pitch: 1.2, rate: 1.1, volume: 1),

  /// 怯え。少し高く速く、小さく。
  fear('怯え', pitch: 1.06, rate: 1.14, volume: 0.8),

  /// ささやき。ゆっくり、小さく。
  whisper('ささやき', pitch: 0.95, rate: 0.88, volume: 0.5);

  const SpeechEmotion(
    this.label, {
    required this.pitch,
    required this.rate,
    required this.volume,
  });

  /// 表示名。
  final String label;

  /// 声の高さの倍率。
  final double pitch;

  /// 速さの倍率。
  final double rate;

  /// 音量の倍率。
  final double volume;
}

/// 実際に音声合成へ渡す値。
@immutable
class SpeechProsody {
  /// コンストラクタ。
  const SpeechProsody({
    required this.rate,
    required this.pitch,
    required this.volume,
  });

  /// 速さ（0.1〜1.0。0.5 が標準）。
  final double rate;

  /// 声の高さ（0.5〜2.0。1.0 が標準）。
  final double pitch;

  /// 音量（0.0〜1.0）。
  final double volume;

  @override
  bool operator ==(Object other) =>
      other is SpeechProsody &&
      other.rate == rate &&
      other.pitch == pitch &&
      other.volume == volume;

  @override
  int get hashCode => Object.hash(rate, pitch, volume);

  @override
  String toString() => 'SpeechProsody(rate: $rate, pitch: $pitch, '
      'volume: $volume)';
}

/// 1文の「演出」（役割・感情・強さ・読んだあとの間）。
@immutable
class SpeechDirection {
  /// コンストラクタ。
  const SpeechDirection({
    this.role = SpeechRole.narration,
    this.emotion = SpeechEmotion.neutral,
    this.intensity = 0,
    this.pauseAfter = Duration.zero,
  });

  /// 役割。
  final SpeechRole role;

  /// 感情。
  final SpeechEmotion emotion;

  /// 感情の強さ（0.0〜1.0）。
  final double intensity;

  /// 読んだあとに置く間（演技 100% のときの長さ）。
  final Duration pauseAfter;

  /// 基準の速さ・高さと演技の強さ（0.0〜1.0）から、実際の値を求める。
  ///
  /// 演技が 0 なら、基準の値のまま（感情を付けない）読む。
  SpeechProsody prosody({
    required double baseRate,
    required double basePitch,
    required double acting,
  }) {
    double scale(double factor, double amount) =>
        1 + (factor - 1) * amount * acting;

    final roleRate = switch (role) {
      SpeechRole.narration => 1.0,
      SpeechRole.dialogue => 1.03,
      SpeechRole.thought => 0.94,
    };
    final rolePitch = switch (role) {
      SpeechRole.narration => 1.0,
      SpeechRole.dialogue => 1.06,
      SpeechRole.thought => 0.97,
    };
    final roleVolume = role == SpeechRole.thought ? 0.8 : 1.0;

    return SpeechProsody(
      rate: (baseRate *
              scale(roleRate, 1) *
              scale(emotion.rate, intensity))
          .clamp(0.1, 1.0),
      pitch: (basePitch *
              scale(rolePitch, 1) *
              scale(emotion.pitch, intensity))
          .clamp(0.5, 2.0),
      volume: (scale(roleVolume, 1) * scale(emotion.volume, intensity))
          .clamp(0.2, 1.0),
    );
  }

  /// 演技の強さに合わせた間。
  Duration pause({required double acting}) =>
      pauseAfter * acting.clamp(0.0, 1.0);

  @override
  bool operator ==(Object other) =>
      other is SpeechDirection &&
      other.role == role &&
      other.emotion == emotion &&
      other.intensity == intensity &&
      other.pauseAfter == pauseAfter;

  @override
  int get hashCode => Object.hash(role, emotion, intensity, pauseAfter);

  @override
  String toString() =>
      'SpeechDirection(${role.name}, ${emotion.name} '
      '${intensity.toStringAsFixed(2)}, pause ${pauseAfter.inMilliseconds}ms)';
}

/// 本文から、文ごとの演出を読み取る（端末の中だけで動く規則ベース）。
///
/// 手がかりは次のとおり。
/// 1. 台詞の直後の地の文（「〜と叫んだ」「〜と囁いた」など）。いちばん強い手がかり
/// 2. 台詞の中の記号（！の数、！？、…、ー）と言葉（「ふふ」「くそっ」「助けて」など）
/// 3. 地の文に出てくる感情の言葉から作る「場面の空気」（少しずつ薄れる）
///
/// 間は、段落の終わり・場面転換（空行）・…で終わる文・話し手の切り替わりで置く。
class SpeechDirector {
  SpeechDirector._();

  /// 感情とみなす最小の強さ（これ未満は普通として読む）。
  static const double threshold = 0.25;

  /// [document] の各文の演出を返す（[SpeechDocument.segments] と同じ並び）。
  static List<SpeechDirection> direct(SpeechDocument document) {
    final segments = document.segments;
    final roles = _roles(segments);
    final result = <SpeechDirection>[];
    // 場面の空気（地の文の感情の言葉から作り、少しずつ薄れる）
    final mood = <SpeechEmotion, double>{};

    for (var i = 0; i < segments.length; i++) {
      final text = segments[i].text;
      final role = roles[i];
      final scores = <SpeechEmotion, double>{};
      void add(SpeechEmotion emotion, double score) =>
          scores[emotion] = (scores[emotion] ?? 0) + score;

      // 場面の空気を薄める
      for (final key in mood.keys.toList()) {
        final next = mood[key]! * 0.75;
        if (next < 0.05) {
          mood.remove(key);
        } else {
          mood[key] = next;
        }
      }

      if (role == SpeechRole.narration) {
        // 地の文の言葉は場面の空気に足す（地の文そのものは控えめに演じる）
        _verbCues(text).forEach((emotion, score) {
          mood[emotion] = ((mood[emotion] ?? 0) + score * 0.6).clamp(0.0, 1.0);
        });
        mood.forEach((emotion, score) => add(emotion, score * 0.4));
      } else {
        _symbolCues(text).forEach(add);
        _wordCues(text).forEach(add);
        // 台詞のすぐ後ろの地の文（「〜と叫んだ」）
        final tag = _speechTag(segments, roles, i);
        if (tag != null) _verbCues(tag).forEach(add);
        mood.forEach((emotion, score) => add(emotion, score * 0.8));
      }

      var emotion = SpeechEmotion.neutral;
      var intensity = 0.0;
      scores.forEach((e, score) {
        if (score > intensity) {
          emotion = e;
          intensity = score;
        }
      });
      if (intensity < threshold) {
        emotion = SpeechEmotion.neutral;
        intensity = 0;
      }

      result.add(
        SpeechDirection(
          role: role,
          emotion: emotion,
          intensity: intensity.clamp(0.0, 1.0),
          pauseAfter: _pauseAfter(segments, roles, i),
        ),
      );
    }
    return result;
  }

  /// 各文の役割を決める（括弧の開き・閉じを文をまたいで追う）。
  static List<SpeechRole> _roles(List<SpeechSegment> segments) {
    final roles = <SpeechRole>[];
    final stack = <SpeechRole>[];
    for (final segment in segments) {
      final text = segment.text.trimLeft();
      final first = text.isEmpty ? '' : text[0];
      final opening = _openings[first];
      roles.add(
        opening ?? (stack.isNotEmpty ? stack.last : SpeechRole.narration),
      );
      for (final ch in text.split('')) {
        final role = _openings[ch];
        if (role != null) {
          stack.add(role);
        } else if (_closingChars.contains(ch) && stack.isNotEmpty) {
          stack.removeLast();
        }
      }
      // 閉じ忘れが続いても地の文に戻れるよう、深くなりすぎたら捨てる
      if (stack.length > 4) stack.clear();
    }
    return roles;
  }

  static const Map<String, SpeechRole> _openings = {
    '「': SpeechRole.dialogue,
    '『': SpeechRole.dialogue,
    '（': SpeechRole.thought,
    '(': SpeechRole.thought,
  };
  static const _closingChars = {'」', '』', '）', ')'};

  /// 台詞 [index] の直後にある、話し方を表す地の文（なければ null）。
  ///
  /// 長い台詞が複数の文に分かれていても、台詞の終わりの後ろを見る。
  static String? _speechTag(
    List<SpeechSegment> segments,
    List<SpeechRole> roles,
    int index,
  ) {
    var end = index;
    while (end + 1 < segments.length &&
        roles[end + 1] == roles[index] &&
        !_closesQuote(segments[end].text) &&
        segments[end + 1].start - segments[end].end < 2) {
      end++;
    }
    if (end + 1 >= segments.length) return null;
    if (roles[end + 1] != SpeechRole.narration) return null;
    // 段落が変わっていたら、別の文とみなす
    if (segments[end + 1].start - segments[end].end > 1) return null;
    final next = segments[end + 1].text;
    // 「〜」と叫んだ／「〜」って笑った／「〜」、と囁く
    if (!RegExp('^[、，]?(と|って|とか|そう)').hasMatch(next) &&
        next.length > 24) {
      return null;
    }
    return next.length > 40 ? next.substring(0, 40) : next;
  }

  static bool _closesQuote(String text) {
    final trimmed = text.trimRight();
    return trimmed.isNotEmpty &&
        _closingChars.contains(trimmed[trimmed.length - 1]);
  }

  /// 動詞・様子の言葉（主に地の文）からの手がかり。
  static Map<SpeechEmotion, double> _verbCues(String text) =>
      _match(text, _verbLexicon);

  /// 台詞の中の言葉からの手がかり。
  static Map<SpeechEmotion, double> _wordCues(String text) =>
      _match(text, _wordLexicon);

  static Map<SpeechEmotion, double> _match(
    String text,
    Map<SpeechEmotion, List<String>> lexicon,
  ) {
    final result = <SpeechEmotion, double>{};
    lexicon.forEach((emotion, words) {
      var hits = 0;
      for (final word in words) {
        if (text.contains(word)) hits++;
      }
      if (hits > 0) result[emotion] = hits == 1 ? 0.7 : 1.0;
    });
    return result;
  }

  /// 台詞の中の記号からの手がかり。
  static Map<SpeechEmotion, double> _symbolCues(String text) {
    final result = <SpeechEmotion, double>{};
    final exclamations = RegExp('[！!]').allMatches(text).length;
    if (RegExp('[！!][？?]|[？?][！!]').hasMatch(text)) {
      result[SpeechEmotion.surprise] = 0.8;
    } else if (exclamations >= 2) {
      result[SpeechEmotion.shout] = 0.8;
    } else if (exclamations == 1) {
      result[SpeechEmotion.shout] = 0.35;
    }
    final ellipses = RegExp(r'[…‥]|――|\.\.\.').allMatches(text).length;
    if (ellipses >= 2) {
      result[SpeechEmotion.sadness] = 0.45;
    } else if (ellipses == 1) {
      result[SpeechEmotion.sadness] = 0.2;
    }
    // 「あっ」「えっ」のような短い声
    if (RegExp('^[「『]?[あえうおはなへひ]っ').hasMatch(text)) {
      result[SpeechEmotion.surprise] =
          (result[SpeechEmotion.surprise] ?? 0) + 0.4;
    }
    return result;
  }

  static const Map<SpeechEmotion, List<String>> _verbLexicon = {
    SpeechEmotion.shout: [
      '叫',
      '怒鳴',
      '吼',
      '吠え',
      '喚',
      '声を張り上げ',
      '大声',
      '絶叫',
    ],
    SpeechEmotion.anger: [
      '怒',
      '凄ん',
      '睨',
      '吐き捨て',
      '舌打ち',
      '声を荒',
      '噛みつ',
      '苛立',
      '憤',
    ],
    SpeechEmotion.whisper: [
      '囁',
      'ささや',
      '呟',
      'つぶや',
      '小声',
      '耳打ち',
      'ぼそ',
      '独り言',
      '声を潜め',
    ],
    SpeechEmotion.sadness: [
      '泣',
      '涙',
      '嗚咽',
      'しゃくり',
      '寂しげ',
      '悲しげ',
      '力なく',
      '弱々し',
      '項垂',
      'うなだれ',
      '肩を落と',
    ],
    SpeechEmotion.joy: [
      '笑',
      '微笑',
      'ほほえ',
      '嬉しそう',
      '楽しそう',
      'はしゃ',
      '弾ませ',
      'にっこり',
      'にこにこ',
      '頬を緩め',
    ],
    SpeechEmotion.surprise: [
      '驚',
      '目を丸く',
      '素っ頓狂',
      '息を呑',
      '息をのん',
      '目を見開',
      '仰天',
    ],
    SpeechEmotion.fear: [
      '怯',
      '震え',
      '青ざめ',
      '恐る恐る',
      'おずおず',
      '後ずさ',
      '戦慄',
    ],
  };

  static const Map<SpeechEmotion, List<String>> _wordLexicon = {
    SpeechEmotion.joy: [
      'ふふ',
      'あはは',
      'えへへ',
      'うふふ',
      'わーい',
      'やった',
      '嬉し',
      '楽し',
      'ありがと',
      '（笑）',
    ],
    SpeechEmotion.anger: [
      'ふざけ',
      '黙れ',
      'うるさい',
      '許さ',
      'ちっ',
      'くそ',
      'この野郎',
      '殺す',
      'いい加減に',
    ],
    SpeechEmotion.sadness: [
      'ごめん',
      'うう',
      'ぐす',
      '寂し',
      '悲し',
      '辛い',
      'つらい',
      'さよなら',
    ],
    SpeechEmotion.surprise: [
      'えっ',
      'まさか',
      'うそ',
      '嘘',
      'なっ',
      'はあ？',
      'ええっ',
    ],
    SpeechEmotion.fear: [
      'ひっ',
      'ひぃ',
      'きゃ',
      '来ないで',
      '助けて',
      '怖',
      'やめて',
    ],
  };

  /// 文 [index] を読んだあとに置く間（演技 100% のとき）。
  static Duration _pauseAfter(
    List<SpeechSegment> segments,
    List<SpeechRole> roles,
    int index,
  ) {
    if (index + 1 >= segments.length) return Duration.zero;
    final text = segments[index].text.trimRight();
    final gap = segments[index + 1].start - segments[index].end;
    var ms = 0;
    if (gap >= 2) {
      // 空行をはさむ（場面転換や区切り記号の行）
      ms += 900;
    } else if (gap == 1) {
      // 段落の終わり
      ms += 300;
    }
    if (roles[index + 1] != roles[index]) ms += 120;
    if (RegExp(r'(…|‥|――)[」』）)]?$').hasMatch(text)) ms += 300;
    if (RegExp(r'[！!][」』）)]?$').hasMatch(text)) ms += 120;
    return Duration(milliseconds: ms);
  }
}
