import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:novelty/local_library/meta_rules.dart';
import 'package:novelty/local_library/work_meta_detector.dart';

/// 作者の読み取りルールの設定画面。
///
/// ルールの有効／無効・順番・自作の正規表現・ファイル名の除去パターンを
/// 編集し、試し欄で結果を確かめてから全作品に再適用できる。
class LocalMetaRulesPage extends HookConsumerWidget {
  /// コンストラクタ。
  const LocalMetaRulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rulesAsync = ref.watch(metaRulesProvider);
    final sampleName = useTextEditingController(
      text: '00001_20140101_1200_作品名.txt',
    );
    final sampleHead = useTextEditingController(text: '「作品名」\n作者:作者名\n');
    useListenable(sampleName);
    useListenable(sampleHead);

    final rules = rulesAsync.value;
    if (rules == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('作者の読み取りルール')),
        body: Center(
          child: rulesAsync.hasError
              ? Text('読み込めませんでした: ${rulesAsync.error}')
              : const CircularProgressIndicator(),
        ),
      );
    }

    final notifier = ref.read(metaRulesProvider.notifier);
    void save(MetaRuleSet updated) => unawaited(notifier.save(updated));

    return Scaffold(
      appBar: AppBar(
        title: const Text('作者の読み取りルール'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'reset') {
                final ok = await _confirm(
                  context,
                  title: '初期設定に戻す',
                  message: '自作ルールと除去パターンは削除されます。よろしいですか？',
                );
                if (ok) await notifier.resetToDefaults();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reset', child: Text('初期設定に戻す')),
            ],
          ),
        ],
      ),
      body: ReorderableListView(
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.only(bottom: 32),
        header: _TryPanel(
          rules: rules,
          sampleName: sampleName,
          sampleHead: sampleHead,
        ),
        footer: _Footer(
          rules: rules,
          onSave: save,
          sampleName: sampleName.text,
        ),
        onReorder: (oldIndex, newIndex) {
          final list = [...rules.rules];
          final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
          list.insert(target, list.removeAt(oldIndex));
          save(rules.copyWith(rules: list));
        },
        children: [
          for (var i = 0; i < rules.rules.length; i++)
            _RuleTile(
              key: ValueKey(rules.rules[i].id),
              index: i,
              rule: rules.rules[i],
              onToggle: (enabled) {
                final list = [...rules.rules];
                list[i] = list[i].copyWith(enabled: enabled);
                save(rules.copyWith(rules: list));
              },
              onEdit: rules.rules[i].isCustom
                  ? () async {
                      final edited = await showRuleEditor(
                        context,
                        rule: rules.rules[i],
                        strips: rules.strips,
                        sampleName: sampleName.text,
                        sampleHead: sampleHead.text,
                      );
                      if (edited == null) return;
                      final list = [...rules.rules];
                      if (edited.isDeleted) {
                        list.removeAt(i);
                      } else {
                        list[i] = edited.rule!;
                      }
                      save(rules.copyWith(rules: list));
                    }
                  : null,
            ),
        ],
      ),
    );
  }
}

/// ルール1件の行。
class _RuleTile extends StatelessWidget {
  const _RuleTile({
    required this.index,
    required this.rule,
    required this.onToggle,
    this.onEdit,
    super.key,
  });

  final int index;
  final MetaRule rule;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Checkbox(
        value: rule.enabled,
        onChanged: (value) => onToggle(value ?? false),
      ),
      title: Text('${index + 1}. ${rule.label}'),
      subtitle: Text(
        rule.description,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: onEdit,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '編集',
              onPressed: onEdit,
            ),
          ReorderableDragStartListener(
            index: index,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.drag_handle),
            ),
          ),
        ],
      ),
    );
  }
}

/// 試し欄。入力したファイル名・本文で、どのルールが当たるかを表示する。
class _TryPanel extends StatelessWidget {
  const _TryPanel({
    required this.rules,
    required this.sampleName,
    required this.sampleHead,
  });

  final MetaRuleSet rules;
  final TextEditingController sampleName;
  final TextEditingController sampleHead;

  @override
  Widget build(BuildContext context) {
    final result = WorkMetaDetector.detectDetailed(
      fileName: sampleName.text,
      head: sampleHead.text,
      rules: rules,
    );
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('試す', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              controller: sampleName,
              decoration: const InputDecoration(
                labelText: 'ファイル名',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: sampleHead,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: '本文の冒頭',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            _ResultRow(label: '作者', value: result.meta.author ?? '（不明）'),
            _ResultRow(label: '作品名', value: result.meta.title),
            _ResultRow(
              label: '採用ルール',
              value: result.rule?.label ?? '（どれにも当てはまらない）',
            ),
            _ResultRow(label: '除去後の名前', value: result.cleanedName),
            const SizedBox(height: 8),
            Text(
              '読み取りルール（上から順に試し、最初に当たったものを使います。'
              '≡ をドラッグで並べ替え）',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

/// ルール一覧の下：追加ボタン・除去パターン・再判定。
class _Footer extends ConsumerWidget {
  const _Footer({
    required this.rules,
    required this.onSave,
    required this.sampleName,
  });

  final MetaRuleSet rules;
  final ValueChanged<MetaRuleSet> onSave;
  final String sampleName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('正規表現ルールを追加'),
            onPressed: () async {
              final created = await showRuleEditor(
                context,
                strips: rules.strips,
                sampleName: sampleName,
                sampleHead: '',
              );
              final rule = created?.rule;
              if (rule == null) return;
              onSave(rules.copyWith(rules: [...rules.rules, rule]));
            },
          ),
        ),
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('ファイル名から取り除く部分', style: theme.textTheme.titleSmall),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            '判定の前に、ファイル名から一致した部分を消します（作品名にも使われます）。',
            style: theme.textTheme.bodySmall,
          ),
        ),
        for (var i = 0; i < rules.strips.length; i++)
          SwitchListTile(
            value: rules.strips[i].enabled,
            title: Text(rules.strips[i].name),
            subtitle: Text(rules.strips[i].pattern),
            secondary: rules.strips[i].isBuiltin
                ? const Icon(Icons.lock_outline)
                : IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: '編集',
                    onPressed: () async {
                      final edited = await showStripEditor(
                        context,
                        strip: rules.strips[i],
                        sampleName: sampleName,
                      );
                      if (edited == null) return;
                      final list = [...rules.strips];
                      if (edited.isDeleted) {
                        list.removeAt(i);
                      } else {
                        list[i] = edited.strip!;
                      }
                      onSave(rules.copyWith(strips: list));
                    },
                  ),
            onChanged: (enabled) {
              final list = [...rules.strips];
              list[i] = list[i].copyWith(enabled: enabled);
              onSave(rules.copyWith(strips: list));
            },
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('除去パターンを追加'),
            onPressed: () async {
              final created = await showStripEditor(
                context,
                sampleName: sampleName,
              );
              final strip = created?.strip;
              if (strip == null) return;
              onSave(rules.copyWith(strips: [...rules.strips, strip]));
            },
          ),
        ),
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('この設定で全作品を再判定'),
              onPressed: () => unawaited(runRedetectAll(context, ref)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            '手で作者を直した作品は再判定しません。',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// 全作品を再判定する（確認・進行中表示・結果通知つき）。
Future<void> runRedetectAll(BuildContext context, WidgetRef ref) async {
  final ok = await _confirm(
    context,
    title: '全作品を再判定',
    message: '現在のルールで、すべての作品の作者・作品名を読み取り直します。'
        '件数が多いと少し時間がかかります。',
  );
  if (!ok || !context.mounted) return;

  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('再判定しています…')),
            ],
          ),
        ),
      ),
    ),
  );

  String message;
  try {
    final changed = await ref.read(localWorksProvider.notifier).redetectAll();
    message = '$changed 件の作者・作品名が変わりました';
  } on Object catch (e) {
    message = '再判定に失敗しました: $e';
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// 編集ダイアログの結果（削除なら [isDeleted]）。
class RuleEditResult {
  const RuleEditResult._(this.rule, {this.isDeleted = false});

  /// 編集後のルール。
  final MetaRule? rule;

  /// 削除されたか。
  final bool isDeleted;
}

/// 除去パターン編集ダイアログの結果。
class StripEditResult {
  const StripEditResult._(this.strip, {this.isDeleted = false});

  /// 編集後の除去パターン。
  final StripPattern? strip;

  /// 削除されたか。
  final bool isDeleted;
}

/// 自作ルールの作成・編集ダイアログ。キャンセルなら null。
Future<RuleEditResult?> showRuleEditor(
  BuildContext context, {
  required List<StripPattern> strips,
  required String sampleName,
  required String sampleHead,
  MetaRule? rule,
}) {
  return showDialog<RuleEditResult>(
    context: context,
    builder: (_) => _RuleEditorDialog(
      rule: rule,
      strips: strips,
      sampleName: sampleName,
      sampleHead: sampleHead,
    ),
  );
}

class _RuleEditorDialog extends HookWidget {
  const _RuleEditorDialog({
    required this.rule,
    required this.strips,
    required this.sampleName,
    required this.sampleHead,
  });

  final MetaRule? rule;
  final List<StripPattern> strips;
  final String sampleName;
  final String sampleHead;

  @override
  Widget build(BuildContext context) {
    final name = useTextEditingController(text: rule?.name ?? '');
    final pattern = useTextEditingController(
      text: rule?.pattern ?? r'^(?<author>.+?)_(?<title>.+)$',
    );
    final target = useState(rule?.target ?? RuleTarget.fileName);
    final sample = useTextEditingController(
      text: target.value == RuleTarget.fileName ? sampleName : sampleHead,
    );
    useListenable(pattern);
    useListenable(sample);

    final error = validatePattern(pattern.text);
    final preview = error == null
        ? _preview(target.value, pattern.text, sample.text)
        : null;

    return AlertDialog(
      title: Text(rule == null ? 'ルールを追加' : 'ルールを編集'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'ルールの名前'),
            ),
            const SizedBox(height: 12),
            SegmentedButton<RuleTarget>(
              segments: [
                for (final t in RuleTarget.values)
                  ButtonSegment(value: t, label: Text(t.label)),
              ],
              selected: {target.value},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                target.value = selection.first;
                sample.text = target.value == RuleTarget.fileName
                    ? sampleName
                    : sampleHead;
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pattern,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: '正規表現',
                errorText: error,
                errorMaxLines: 3,
                helperText: '(?<author>…) で作者、(?<title>…) で作品名',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sample,
              minLines: 1,
              maxLines: target.value == RuleTarget.head ? 5 : 1,
              decoration: InputDecoration(
                labelText: target.value == RuleTarget.fileName
                    ? '試すファイル名（除去パターン適用前）'
                    : '試す本文の冒頭',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              preview ?? '',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      actions: [
        if (rule != null)
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              const RuleEditResult._(null, isDeleted: true),
            ),
            child: const Text('削除'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: error != null
              ? null
              : () => Navigator.pop(
                  context,
                  RuleEditResult._(
                    MetaRule.custom(
                      id:
                          rule?.id ??
                          'custom:${DateTime.now().microsecondsSinceEpoch}',
                      name: name.text.trim(),
                      target: target.value,
                      pattern: pattern.text,
                      enabled: rule?.enabled ?? true,
                    ),
                  ),
                ),
          child: const Text('保存'),
        ),
      ],
    );
  }

  String _preview(RuleTarget target, String pattern, String sample) {
    final testRule = MetaRule.custom(
      id: 'preview',
      name: '',
      target: target,
      pattern: pattern,
    );
    final result = WorkMetaDetector.detectDetailed(
      fileName: target == RuleTarget.fileName ? sample : '',
      head: target == RuleTarget.head ? sample : '',
      rules: MetaRuleSet(rules: [testRule], strips: strips),
    );
    if (result.rule == null) return '→ 当てはまりません';
    final author = result.meta.author ?? '（なし）';
    return '→ 作者: $author ／ 作品名: ${result.meta.title}';
  }
}

/// 除去パターンの作成・編集ダイアログ。キャンセルなら null。
Future<StripEditResult?> showStripEditor(
  BuildContext context, {
  required String sampleName,
  StripPattern? strip,
}) {
  return showDialog<StripEditResult>(
    context: context,
    builder: (_) => _StripEditorDialog(strip: strip, sampleName: sampleName),
  );
}

class _StripEditorDialog extends HookWidget {
  const _StripEditorDialog({required this.strip, required this.sampleName});

  final StripPattern? strip;
  final String sampleName;

  @override
  Widget build(BuildContext context) {
    final name = useTextEditingController(text: strip?.name ?? '');
    final pattern = useTextEditingController(
      text: strip?.pattern ?? r'\s*\(\d{2}-\d{2}-\d{2}\)$',
    );
    final sample = useTextEditingController(text: sampleName);
    useListenable(pattern);
    useListenable(sample);

    final error = validatePattern(pattern.text);
    final cleaned = error == null
        ? WorkMetaDetector.cleanFileName(sample.text, [
            StripPattern(id: 'preview', name: '', pattern: pattern.text),
          ])
        : null;

    return AlertDialog(
      title: Text(strip == null ? '除去パターンを追加' : '除去パターンを編集'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: '名前'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pattern,
              style: const TextStyle(fontFamily: 'monospace'),
              decoration: InputDecoration(
                labelText: '取り除く部分の正規表現',
                errorText: error,
                errorMaxLines: 3,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: sample,
              decoration: const InputDecoration(labelText: '試すファイル名'),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(cleaned == null ? '' : '→ $cleaned'),
            ),
          ],
        ),
      ),
      actions: [
        if (strip != null)
          TextButton(
            onPressed: () => Navigator.pop(
              context,
              const StripEditResult._(null, isDeleted: true),
            ),
            child: const Text('削除'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: error != null
              ? null
              : () => Navigator.pop(
                  context,
                  StripEditResult._(
                    StripPattern(
                      id:
                          strip?.id ??
                          'strip:${DateTime.now().microsecondsSinceEpoch}',
                      name: name.text.trim().isEmpty
                          ? '自作の除去パターン'
                          : name.text.trim(),
                      pattern: pattern.text,
                      enabled: strip?.enabled ?? true,
                    ),
                  ),
                ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  return result ?? false;
}
