import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:novelty/utils/japanese_legacy_tables.dart';

/// UTF-8 以外の日本語の文字コード（Shift_JIS・EUC-JP）を読む（フォークで追加）。
///
/// 古いテキストファイルや、Windows のメモ帳で作ったファイルは
/// Shift_JIS のことが多い。対応表は tool/gen_japanese_tables.py で作っている。
///
/// たとえるなら、昔の暗号表（文字コード）を見ながら、
/// 今の文字（Unicode）に1文字ずつ書き直す係。

/// 読み替えた結果。
class LegacyDecodeResult {
  /// コンストラクタ。
  const LegacyDecodeResult(this.text, this.errors, this.halfWidthKana);

  /// 読み替えた文字列（読めなかった所は「�」）。
  final String text;

  /// 読めなかったバイトの数（少ないほど、その文字コードらしい）。
  final int errors;

  /// 半角カナの数。別の文字コードを読み違えると、半角カナだらけになりやすい。
  final int halfWidthKana;

  /// その文字コードらしくなさ（小さいほどらしい）。
  int get penalty => errors * 100 + halfWidthKana;
}

Uint16List _unpack(List<String> chunks) {
  final bytes = ZLibDecoder().convert(base64.decode(chunks.join()));
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  return Uint16List.fromList([
    for (var i = 0; i + 1 < data.lengthInBytes; i += 2)
      data.getUint16(i, Endian.little),
  ]);
}

// 表は初めて使うときに広げる（使わない人の起動を遅くしない）
final Uint16List _sjis = _unpack(shiftJisTable);
final Uint16List _euc = _unpack(eucJpTable);
final Uint16List _euc212 = _unpack(eucJp212Table);

const _replacement = 0xFFFD;

/// Shift_JIS（Windows の CP932 を含む）として読む。
LegacyDecodeResult decodeShiftJis(List<int> bytes) {
  final out = StringBuffer();
  final units = <int>[];
  var errors = 0;
  var kana = 0;
  void flush() {
    out.write(String.fromCharCodes(units));
    units.clear();
  }

  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i];
    if (b < 0x80) {
      units.add(b);
    } else if (b >= 0xA1 && b <= 0xDF) {
      // 半角カナ
      units.add(0xFF61 + b - 0xA1);
      kana++;
    } else if ((b >= 0x81 && b <= 0x9F) || (b >= 0xE0 && b <= 0xFC)) {
      final t = i + 1 < bytes.length ? bytes[i + 1] : -1;
      final lead = b <= 0x9F ? b - 0x81 : b - 0xE0 + 0x1F;
      final code = t >= 0x40 && t <= 0xFC
          ? _sjis[lead * 0xBD + (t - 0x40)]
          : 0;
      if (code == 0) {
        errors++;
        units.add(_replacement);
      } else {
        units.add(code);
        i++;
      }
    } else {
      errors++;
      units.add(_replacement);
    }
    if (units.length >= 4096) flush();
  }
  flush();
  return LegacyDecodeResult(out.toString(), errors, kana);
}

/// EUC-JP として読む。
LegacyDecodeResult decodeEucJp(List<int> bytes) {
  final out = StringBuffer();
  final units = <int>[];
  var errors = 0;
  var kana = 0;
  void flush() {
    out.write(String.fromCharCodes(units));
    units.clear();
  }

  bool inRange(int i) =>
      i < bytes.length && bytes[i] >= 0xA1 && bytes[i] <= 0xFE;

  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i];
    if (b < 0x80) {
      units.add(b);
      continue;
    }
    var code = 0;
    var length = 1;
    if (b == 0x8E && i + 1 < bytes.length) {
      // 半角カナ
      final t = bytes[i + 1];
      if (t >= 0xA1 && t <= 0xDF) {
        code = 0xFF61 + t - 0xA1;
        kana++;
      }
      length = 2;
    } else if (b == 0x8F && inRange(i + 1) && inRange(i + 2)) {
      code = _euc212[(bytes[i + 1] - 0xA1) * 94 + (bytes[i + 2] - 0xA1)];
      length = 3;
    } else if (b >= 0xA1 && b <= 0xFE && inRange(i + 1)) {
      code = _euc[(b - 0xA1) * 94 + (bytes[i + 1] - 0xA1)];
      length = 2;
    }
    if (code == 0) {
      errors++;
      units.add(_replacement);
    } else {
      units.add(code);
      i += length - 1;
    }
    if (units.length >= 4096) flush();
  }
  flush();
  return LegacyDecodeResult(out.toString(), errors, kana);
}
