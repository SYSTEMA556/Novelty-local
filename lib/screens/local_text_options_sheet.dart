import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/screens/local_import.dart';

/// テキストの読み込み方（文字コード・本文の掃除・表記ゆれ）を選ぶシートを出す。
///
/// UTF-8 以外のファイルは、この設定に関係なく読める。
/// ここで選ぶのは、その先の「そろえる（正規化）」をするかどうか。
Future<void> showLocalTextOptionsSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _TextOptionsSheet(parentContext: context, parentRef: ref),
  );
}

class _TextOptionsSheet extends ConsumerWidget {
  const _TextOptionsSheet({
    required this.parentContext,
    required this.parentRef,
  });

  // シートを閉じたあとに変換を始めるための、シートの外側の context と ref
  final BuildContext parentContext;
  final WidgetRef parentRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options =
        ref.watch(localTextOptionsProvider).value ?? const LocalTextOptions();
    final notifier = ref.read(localTextOptionsProvider.notifier);
    final small = Theme.of(context).textTheme.bodySmall;

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: const Text('テキストの読み込み設定'),
              subtitle: Text(
                [
                  'Shift_JIS・EUC-JP などの UTF-8 以外のファイルは、',
                  'この設定に関係なく読めます。',
                ].join(),
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text('元のファイルを UTF-8 に書き直す'),
              subtitle: Text(
                [
                  '取り込み・再スキャンのとき、UTF-8 以外の元のファイルを ',
                  'UTF-8 で保存し直します。読めない文字があるファイルは書き直しません。',
                ].join(),
              ),
              value: options.convertSourceToUtf8,
              onChanged: (v) => unawaited(
                notifier.save(options.copyWith(convertSourceToUtf8: v)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.sync_alt),
                label: const Text('取り込み済みのフォルダを今すぐ書き直す'),
                onPressed: () {
                  Navigator.pop(context);
                  if (!parentContext.mounted) return;
                  unawaited(convertSourcesToUtf8(parentContext, parentRef));
                },
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              title: const Text('本文の掃除'),
              subtitle: Text(
                [
                  'HTML のタグや ［＃改ページ］ などの注記を消して表示します。',
                  '切ると、ファイルに書かれたとおりに出します。',
                ].join(),
              ),
              value: options.cleanMarkup,
              onChanged: (v) =>
                  unawaited(notifier.save(options.copyWith(cleanMarkup: v))),
            ),
            SwitchListTile(
              title: const Text('表記ゆれをそろえる'),
              subtitle: Text(
                [
                  '全角の英数字（Ａ１）を半角（A1）に、半角カナ（ｶﾞ）を全角（ガ）に',
                  'そろえます。「！」「？」や全角スペースはそのままです。',
                ].join(),
              ),
              value: options.unifyWidth,
              onChanged: (v) =>
                  unawaited(notifier.save(options.copyWith(unifyWidth: v))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                [
                  '本文の掃除・表記ゆれは、次に作品を開いたときから反映されます。',
                  '元のファイルや本棚の中身は変えません。',
                  '切り替えると、しおりの位置が少しずれることがあります。',
                ].join(),
                style: small,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
