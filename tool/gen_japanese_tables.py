"""Shift_JIS（CP932）と EUC-JP の対応表を Dart のソースに書き出す（フォークで追加）。

Python に入っている文字コードの変換表を使う。
出力: lib/utils/japanese_legacy_tables.dart（手で編集しない）

使い方: python3 tool/gen_japanese_tables.py
"""
import base64
import struct
import zlib


def table(prefix, leads, trails, codec):
    out = bytearray()
    for lead in leads:
        for trail in trails:
            try:
                c = bytes(prefix + [lead, trail]).decode(codec)
                v = ord(c) if len(c) == 1 else 0
            except UnicodeDecodeError:
                v = 0
            out += struct.pack('<H', v if v <= 0xFFFF else 0)
    return out


def chunks(name, data):
    text = base64.b64encode(zlib.compress(bytes(data), 9)).decode()
    lines = [text[i:i + 72] for i in range(0, len(text), 72)]
    body = '\n'.join(f"  '{line}'," for line in lines)
    return f'const {name} = [\n{body}\n];\n'


sjis = table([], list(range(0x81, 0xA0)) + list(range(0xE0, 0xFD)),
             range(0x40, 0xFD), 'cp932')
euc = table([], range(0xA1, 0xFF), range(0xA1, 0xFF), 'euc_jp')
euc212 = table([0x8F], range(0xA1, 0xFF), range(0xA1, 0xFF), 'euc_jp')

with open('lib/utils/japanese_legacy_tables.dart', 'w') as f:
    f.write('// tool/gen_japanese_tables.py で作ったファイル。手で編集しないこと。\n')
    f.write('//\n')
    f.write('// 2バイト文字の対応表（UTF-16 の文字番号を2バイトずつ、リトルエンディアン）を\n')
    f.write('// zlib で縮めて base64 にしたもの。\n\n')
    f.write('/// Shift_JIS（CP932）: 1バイト目 0x81〜0x9F・0xE0〜0xFC × 2バイト目 0x40〜0xFC。\n')
    f.write(chunks('shiftJisTable', sjis))
    f.write('\n/// EUC-JP（JIS X 0208）: 0xA1〜0xFE × 0xA1〜0xFE。\n')
    f.write(chunks('eucJpTable', euc))
    f.write('\n/// EUC-JP（JIS X 0212、0x8F で始まる3バイト）: 0xA1〜0xFE × 0xA1〜0xFE。\n')
    f.write(chunks('eucJp212Table', euc212))
