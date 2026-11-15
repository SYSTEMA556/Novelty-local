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
        'ファイルへのアクセスが許可されませんでした。'
        '「ファイルを選んで取り込む」をお試しください',
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
  if (context.mounted) await _runImport(context, ref, paths);
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

  if (context.mounted) await _runImport(context, ref, paths);
  // FilePickerがコピーした一時ファイルは取り込み後に消す
  try {
    await FilePicker.platform.clearTemporaryFiles();
  } on Object catch (e) {
    debugPrint('Failed to clear FilePicker cache: $e');
  }
}

/// 進捗ダイアログを出しながら取り込み、結果を表示する。
Future<void> _runImport(
  BuildContext context,
  WidgetRef ref,
  List<String> paths,
) async {
  final progress = ValueNotifier<(int, int)>((0, paths.length));
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('取り込み中'),
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (context, value, _) {
              final (done, total) = value;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: total == 0 ? 0 : done / total),
                  const SizedBox(height: 12),
                  Text('$done / $total 件'),
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
    result = await ref
        .read(localWorksProvider.notifier)
        .importFiles(
          paths,
          onProgress: (done, total) => progress.value = (done, total),
        );
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
  await _showResultDialog(context, result);
}

Future<void> _showResultDialog(BuildContext context, LocalImportResult result) {
  final failed = result.failedFiles;
  const maxShown = 20;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('取り込み完了'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('追加：${result.added} 件'),
            Text('取り込み済みのため省略：${result.skipped} 件'),
            if (failed.isNotEmpty) ...[
              Text('読み込めなかった：${failed.length} 件（UTF-8以外の可能性）'),
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
