/// 読み方の辞書を見る・登録する画面（フォークで追加）。
///
/// 読み上げ中のバーから開くと、今の文を見ながら登録でき、
/// 登録したらその文を読み直して確かめられる。
/// 本棚の ⋮ から開くと、すべての登録を一覧で直せる。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:novelty/read_aloud/read_aloud_controller.dart';
import 'package:novelty/read_aloud/reading_dictionary.dart';

/// 読み方の辞書のシートを出す。
///
/// [controller] を渡すと、今の文の表示・読み直しと「この作品だけ」の登録ができる。
/// 渡さないと、すべての登録を一覧で直す画面になる。
Future<void> showReadingDictionarySheet(
  BuildContext context, {
  ReadAloudController? controller,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _ReadingDictionarySheet(controller: controller),
  );
}

class _ReadingDictionarySheet extends StatefulWidget {
  const _ReadingDictionarySheet({this.controller});

  final ReadAloudController? controller;

  @override
  State<_ReadingDictionarySheet> createState() =>
      _ReadingDictionarySheetState();
}

class _ReadingDictionarySheetState extends State<_ReadingDictionarySheet> {
  final _dictionary = ReadingDictionary.shared;

  String? get _scope => widget.controller?.dictionaryScope;

  Future<void> _edit([ReadingRule? original]) async {
    final rule = await showDialog<ReadingRule>(
      context: context,
      builder: (_) => _RuleDialog(original: original, workScope: _scope),
    );
    if (rule == null) return;
    if (original != null) await _dictionary.remove(original);
    await _dictionary.put(rule);
    if (mounted) setState(() {});
  }

  Future<void> _remove(ReadingRule rule) async {
    await _dictionary.remove(rule);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final rules = controller == null
        ? _dictionary.rules
        : _dictionary.rulesFor(_scope);
    final current = controller?.currentSegment?.text;
    final small = Theme.of(context).textTheme.bodySmall;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollController) => ListView(
        controller: scrollController,
        children: [
          ListTile(
            title: const Text('読み方の辞書'),
            subtitle: const Text(
              '読み間違える言葉に、正しい読みを登録します。本文の表示は変わりません。',
            ),
            trailing: FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('登録'),
              onPressed: () => unawaited(_edit()),
            ),
          ),
          if (controller != null && current != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('今の文（長押しで言葉を選んでコピーできます）', style: small),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: SelectableText(current),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextButton.icon(
                  icon: const Icon(Icons.replay),
                  label: const Text('今の文を読み直す'),
                  onPressed: () =>
                      unawaited(controller.playFrom(controller.index)),
                ),
              ),
            ),
          ],
          const Divider(),
          if (rules.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('まだ登録はありません'),
            ),
          for (final rule in rules)
            ListTile(
              title: Text('${rule.surface} → ${rule.reading}'),
              subtitle: Text(rule.isGlobal ? 'すべての作品' : 'この作品だけ'),
              onTap: () => unawaited(_edit(rule)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '消す',
                onPressed: () => unawaited(_remove(rule)),
              ),
            ),
        ],
      ),
    );
  }
}

/// 登録・修正のダイアログ。
class _RuleDialog extends StatefulWidget {
  const _RuleDialog({this.original, this.workScope});

  final ReadingRule? original;

  // 「この作品だけ」に使う範囲（null なら、すべての作品にしか登録できない）
  final String? workScope;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final _surface = TextEditingController(
    text: widget.original?.surface,
  );
  late final _reading = TextEditingController(
    text: widget.original?.reading,
  );
  late bool _onlyThisWork =
      widget.original != null
          ? !widget.original!.isGlobal
          : widget.workScope != null;

  @override
  void dispose() {
    _surface.dispose();
    _reading.dispose();
    super.dispose();
  }

  void _save() {
    final surface = _surface.text.trim();
    final reading = _reading.text.trim();
    if (surface.isEmpty || reading.isEmpty) return;
    final scope = _onlyThisWork
        ? (widget.workScope ?? widget.original?.scope)
        : null;
    Navigator.pop(
      context,
      ReadingRule(
        surface: surface,
        reading: reading,
        scope: scope ?? ReadingRule.globalScope,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canScope =
        widget.workScope != null ||
        (widget.original != null && !widget.original!.isGlobal);
    return AlertDialog(
      title: Text(widget.original == null ? '読み方を登録' : '読み方を直す'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _surface,
            autofocus: widget.original == null,
            decoration: const InputDecoration(
              labelText: '本文での書き方',
              hintText: '例：天音',
            ),
          ),
          TextField(
            controller: _reading,
            decoration: const InputDecoration(
              labelText: '読み（ひらがな・カタカナ）',
              hintText: '例：あまね',
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          if (canScope)
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('この作品だけ')),
                ButtonSegment(value: false, label: Text('すべての作品')),
              ],
              selected: {_onlyThisWork},
              onSelectionChanged: (v) =>
                  setState(() => _onlyThisWork = v.first),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
