import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:novelty/local_library/local_library_models.dart';
import 'package:novelty/local_library/local_library_providers.dart';
import 'package:permission_handler/permission_handler.dart';

/// 取り込み方法を選ぶボトムシートを表示する。
Future<void> showLocalImportSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('フォルダを選んで取り込む'),
            subtitle: const Text('フォルダ内（サブフォルダ含む）の .txt をすべて取り込みます'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await importFromFolder(context, ref);
            },
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('取り込んだフォルダを再スキャン'),
            subtitle: const Text('増えたファイルを追加し、書き換わったファイルを取り込み直します'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await showRescanSheet(context, ref);
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_copy_outlined),
            title: const Text('ファイルを選んで取り込む'),
            subtitle: const Text('複数選択できます。権限の許可は不要です'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await importFromFiles(context, ref);
            },
          ),
        ],
      ),
    ),
  );
}

/// フォルダを選び、中の .txt をすべて取り込む。
Future<void> importFromFolder(BuildContext context, WidgetRef ref) async {
  if (!await _ensureStoragePermission()) {
    if (context.mounted) {
      _showSnackBar(
        context,
        [
          'ファイルへのアクセスが許可されませんでした。',
          '「ファイルを選んで取り込む」をお試しください',
        ].join(),
      );
    }
    return;
  }

  final dirPath = await FilePicker.platform.getDirectoryPath(
    dialogTitle: '取り込むフォルダを選択',
  );
  if (dirPath == null) return;

  final List<String> paths;
  try {
    paths = await _listTextFiles(Directory(dirPath));
  } on FileSystemException catch (e) {
    if (context.mounted) _showSnackBar(context, 'フォルダを読めませんでした: ${e.message}');
    return;
  }

  if (paths.isEmpty) {
    if (context.mounted) _showSnackBar(context, 'このフォルダに .txt ファイルが見つかりませんでした');
    return;
  }
  // フォルダを覚えておき、あとで「再スキャン」できるようにする
  if (context.mounted) {
    await _runWithProgress(
      context,
      ref,
      title: '取り込み中',
      task: (onProgress) => ref
          .read(localWorksProvider.notifier)
          .scanFolder(dirPath, onProgress: onProgress),
    );
  }
}

/// 覚えているフォルダの一覧を出し、再スキャンする。
Future<void> showRescanSheet(BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(localWorksProvider.notifier);
  final sources = await notifier.sources();
  if (!context.mounted) return;
  if (sources.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('再スキャンするフォルダがありません'),
        content: Text(
          [
            '「フォルダを選んで取り込む」で取り込んだフォルダを覚えておき、',
            'あとから再スキャンできます。以前に取り込んだフォルダも、',
            'もう一度選べば覚えます（取り込み済みの作品は重複しません）。',
          ].join(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('閉じる'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await importFromFolder(context, ref);
            },
            child: const Text('フォルダを選ぶ'),
          ),
        ],
      ),
    );
    return;
  }

  Future<void> rescan(
    Future<LocalImportResult> Function(
      void Function(int done, int total) onProgress,
    )
    task,
  ) async {
    if (!await _ensureStoragePermission()) {
      if (context.mounted) {
        _showSnackBar(context, 'ファイルへのアクセスが許可されませんでした');
      }
      return;
    }
    if (context.mounted) {
      await _runWithProgress(context, ref, title: '再スキャン中', task: task);
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: StatefulBuilder(
        builder: (sheetContext, setState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('すべて再スキャン'),
              subtitle: Text('${sources.length} 個のフォルダ'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await rescan(
                  (onProgress) => notifier.rescanAll(
                    onProgress: (_, done, total) => onProgress(done, total),
                  ),
                );
              },
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final path in sources)
                    ListTile(
                      leading: const Icon(Icons.folder_outlined),
                      title: Text(
                        path.split('/').where((e) => e.isNotEmpty).last,
                      ),
                      subtitle: Text(
                        path,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        await rescan(
                          (onProgress) => notifier.scanFolder(
                            path,
                            onProgress: onProgress,
                          ),
                        );
                      },
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'このフォルダを忘れる（作品は消えません）',
                        onPressed: () async {
                          await notifier.forgetSource(path);
                          setState(() => sources.remove(path));
                          if (sources.isEmpty && sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// ファイルを複数選んで取り込む。
Future<void> importFromFiles(BuildContext context, WidgetRef ref) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['txt'],
    allowMultiple: true,
    dialogTitle: '取り込むテキストファイルを選択',
  );
  if (result == null) return;

  final paths = [
    for (final file in result.files)
      if (file.path != null) file.path!,
  ];
  if (paths.isEmpty) return;

  if (context.mounted) {
    await _runWithProgress(
      context,
      ref,
      title: '取り込み中',
      task: (onProgress) => ref
          .read(localWorksProvider.notifier)
          .importFiles(paths, onProgress: onProgress),
    );
  }
  // FilePickerがコピーした一時ファイルは取り込み後に消す
  try {
    await FilePicker.platform.clearTemporaryFiles();
  } on Object catch (e) {
    debugPrint('Failed to clear FilePicker cache: $e');
  }
}

/// 進捗ダイアログを出しながら取り込み・再スキャンし、結果を表示する。
Future<void> _runWithProgress(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required Future<LocalImportResult> Function(
    void Function(int done, int total) onProgress,
  )
  task,
  String unit = '件',
  bool convertOnly = false,
}) async {
  final progress = ValueNotifier<(int, int)>((0, 0));
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(title),
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (context, value, _) {
              final (done, total) = value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: total == 0 ? 0 : done / total),
                  const SizedBox(height: 12),
                  Text('$done / $total $unit'),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  LocalImportResult? result;
  Object? error;
  try {
    result = await task((done, total) => progress.value = (done, total));
  } on Object catch (e) {
    error = e;
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
  }

  if (!context.mounted) return;
  if (error != null || result == null) {
    _showSnackBar(context, '取り込みに失敗しました: $error');
    return;
  }
  await _showResultDialog(context, ref, result, convertOnly: convertOnly);
}

/// 覚えているフォルダにある UTF-8 以外の元のファイルを、UTF-8 で書き直す。
Future<void> convertSourcesToUtf8(BuildContext context, WidgetRef ref) async {
  final store = await ref.read(localLibraryStoreProvider.future);
  if (!context.mounted) return;
  if ((await store.loadSources()).isEmpty) {
    if (context.mounted) {
      _showSnackBar(context, 'フォルダから取り込んだ作品がありません');
    }
    return;
  }
  if (!await _ensureStoragePermission() || !context.mounted) return;
  await _runWithProgress(
    context,
    ref,
    title: '元のファイルを UTF-8 に書き直しています',
    unit: 'フォルダ',
    convertOnly: true,
    task: (onProgress) async {
      final r = await store.convertSourcesToUtf8(onProgress: onProgress);
      return LocalImportResult(
        added: 0,
        skipped: 0,
        failedFiles: const [],
        nonUtf8: r.nonUtf8,
        converted: r.converted,
      );
    },
  );
}

Future<void> _showResultDialog(
  BuildContext context,
  WidgetRef ref,
  LocalImportResult result, {
  bool convertOnly = false,
}) {
  final failed = result.failedFiles;
  final missing = result.missingIds;
  final onlyConverted = convertOnly;
  const maxShown = 20;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('完了'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 文字コードの変換だけをしたときは、取り込みの件数は出さない
            if (!onlyConverted) ...[
              Text('追加：${result.added} 件'),
              if (result.updated > 0)
                Text('書き換わっていたため取り込み直し：${result.updated} 件'),
              Text('変わりなし・取り込み済み：${result.skipped} 件'),
            ],
            if (result.nonUtf8 > 0 || onlyConverted)
              Text('UTF-8 以外（Shift_JIS など）として読んだ：${result.nonUtf8} 件'),
            if (result.converted > 0 || onlyConverted)
              Text('元のファイルを UTF-8 に書き直した：${result.converted} 件'),
            if (onlyConverted && result.converted < result.nonUtf8)
              Text(
                [
                  '書き直さなかった ${result.nonUtf8 - result.converted} 件は、',
                  '読めない文字があるか、書き込めない場所のファイルです',
                ].join(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (missing.isNotEmpty)
              Text('元のフォルダから消えていた：${missing.length} 件（本棚には残しています）'),
            for (final folder in result.missingFolders)
              Text('見つからないフォルダ：$folder'),
            if (failed.isNotEmpty) ...[
              Text('読み込めなかった：${failed.length} 件（文字コードを判別できない等）'),
              const SizedBox(height: 8),
              for (final name in failed.take(maxShown))
                Text('・$name', style: Theme.of(context).textTheme.bodySmall),
              if (failed.length > maxShown)
                Text('ほか ${failed.length - maxShown} 件'),
            ],
          ],
        ),
      ),
      actions: [
        if (missing.isNotEmpty)
          TextButton(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text('消えていた ${missing.length} 件を本棚から削除しますか？'),
                  content: const Text('しおり・読書位置も一緒に消えます。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('キャンセル'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('削除'),
                    ),
                  ],
                ),
              );
              if (ok != true) return;
              await ref
                  .read(localWorksProvider.notifier)
                  .delete(missing.toSet());
              if (context.mounted) Navigator.pop(context);
            },
            child: Text('消えた ${missing.length} 件を削除'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// フォルダ内（サブフォルダ含む）の .txt を名前順で列挙する。
Future<List<String>> _listTextFiles(Directory dir) async {
  final paths = <String>[];
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.txt')) {
      paths.add(entity.path);
    }
  }
  return paths..sort();
}

/// フォルダ内のファイルを直接読むための権限を確保する。
///
/// Android 11以降は「全ファイルへのアクセス」、それ以前はストレージ権限が必要。
Future<bool> _ensureStoragePermission() async {
  if (!Platform.isAndroid) return true;
  if (await Permission.manageExternalStorage.isGranted) return true;
  if (await Permission.manageExternalStorage.request().isGranted) return true;
  return Permission.storage.request().isGranted;
}

void _showSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
