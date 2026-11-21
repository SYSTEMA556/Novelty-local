/// 作品の「カード」表示（フォークで追加）。
///
/// 動画アプリのサムネイルのように、作品を2列のカードで並べるための部品。
/// 小説にはサムネイルが無いので、絵の代わりに次の3つでカードの「顔」を作る。
/// - 背景の色：ジャンル（ローカルの作品は作者）ごとに決まった色
/// - 大きな題名
/// - ひとこと：あらすじの最初の一文など
///
/// ランキング（なろう・カクヨム）とローカル本棚のグリッドの両方で使う。
library;

import 'package:flutter/material.dart';

/// [seed]（ジャンルや作者）ごとに決まった、カードの背景色。
///
/// 同じ [seed] なら毎回同じ色になる。白い文字が読めるよう暗めにする。
Color novelCardColor(String seed) {
  // 文字列から 0〜359 の色相を決める（FNV-1a）
  var hash = 0x811c9dc5;
  for (final unit in seed.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.42, 0.32).toColor();
}

/// あらすじから、カードに載せるひとこと（最初の一文）を作る。
///
/// 改行や空白はまとめ、句点・感嘆符・疑問符までを1文とする。
/// [maxLength] 文字を超えるときは切って「…」を付ける。
String? novelCardBlurb(String? story, {int maxLength = 60}) {
  if (story == null) return null;
  final text = story.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return null;
  final end = RegExp('[。！？!?]').firstMatch(text)?.end ?? text.length;
  final sentence = text.substring(0, end);
  if (sentence.length <= maxLength) return sentence;
  return '${sentence.substring(0, maxLength)}…';
}

/// 作品のカード。
class NovelCard extends StatelessWidget {
  /// コンストラクタ。
  const NovelCard({
    required this.title,
    required this.colorSeed,
    required this.onTap,
    this.rank,
    this.label,
    this.blurb,
    this.badge,
    this.meta,
    this.progress,
    this.onLongPress,
    super.key,
  });

  /// 題名。
  final String title;

  /// 背景色を決める文字列（ジャンルや作者）。
  final String colorSeed;

  /// 順位（無ければ出さない）。
  final int? rank;

  /// 右上の小さな見出し（ジャンル名・作者名など）。
  final String? label;

  /// ひとこと（あらすじの最初の一文など）。
  final String? blurb;

  /// 左下の札（「連載」「完結」「短編」など）。
  final String? badge;

  /// 右下の小さな情報（ポイント・話数など）。
  final String? meta;

  /// 読んだ割合（0〜1。無ければ出さない）。
  final double? progress;

  /// 押したとき。
  final VoidCallback onTap;

  /// 長押ししたとき。
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = novelCardColor(colorSeed);
    final dark = HSLColor.fromColor(base).withLightness(0.18).toColor();
    const onCard = Colors.white;
    final dim = onCard.withValues(alpha: 0.78);
    final rankValue = rank;
    final labelText = label;
    final blurbText = blurb;
    final badgeText = badge;
    final metaText = meta;
    final progressValue = progress;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [base, dark],
            ),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 150),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 順位と見出し
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (rankValue != null)
                        Text(
                          '$rankValue',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: rankValue <= 3
                                ? const Color(0xFFFFD54F)
                                : onCard,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      const Spacer(),
                      if (labelText != null)
                        Flexible(
                          flex: 4,
                          child: Text(
                            labelText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: dim,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 題名（サムネイルの太い見出しの代わり）
                  Text(
                    title,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: onCard,
                      fontWeight: FontWeight.bold,
                      height: 1.25,
                    ),
                  ),
                  if (blurbText != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      blurbText,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: dim),
                    ),
                  ],
                  const Spacer(),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (badgeText != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: dim),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badgeText,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: onCard,
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      if (metaText != null)
                        Expanded(
                          child: Text(
                            metaText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: dim,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (progressValue != null) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: progressValue,
                      color: onCard,
                      backgroundColor: onCard.withValues(alpha: 0.25),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
