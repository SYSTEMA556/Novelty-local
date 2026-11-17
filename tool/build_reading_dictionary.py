"""ローカル作品の並べ替えに使う読み仮名の辞書を作る。

使い方:
    pip install jamdict-data fugashi unidic-lite
    python3 tool/build_reading_dictionary.py <jamdict.db> assets/dict/readings.tsv.gz

- 語の読み: JMdict（優先度付きの語を優先）
- 人名・作品名の読み: JMnedict（候補が複数ある名前は MeCab+UniDic の解析結果に
  一致する読みを選び、なければ1字ずつの読みで組み立てられるものを選ぶ）
- 1字の読み: KANJIDIC2（音読みを優先）
辞書データは EDRDG のライセンス（CC BY-SA 4.0）に従う。
"""
import sqlite3, sys, gzip, re, unicodedata
db = sys.argv[1]; out = sys.argv[2]
c = sqlite3.connect(db)
def hira(s):
    return ''.join(chr(ord(ch)-0x60) if 0x30A1 <= ord(ch) <= 0x30F6 else ch for ch in s)
KANA = re.compile(r'^[ぁ-ゖァ-ヺー]+$')
def has_kanji(s):
    return any(0x4E00<=ord(ch)<=0x9FFF or 0x3400<=ord(ch)<=0x4DBF or 0xF900<=ord(ch)<=0xFAFF or ord(ch)>=0x20000 or ch=='々' for ch in s)
best = {}  # text -> (rank, reading)
# --- JMdict words ---
kana_by_seq = {}
for kid, seq, text, nok in c.execute("select ID, idseq, text, nokanji from Kana order by ID"):
    kana_by_seq.setdefault(seq, []).append((kid, text, nok))
knr = {}
for kid, text in c.execute("select kid, text from KNR"):
    knr.setdefault(kid, set()).add(text)
knp = {kid for (kid,) in c.execute("select distinct kid from KNP")}
kjp = {kid for (kid,) in c.execute("select distinct kid from KJP")}
for kid, seq, text in c.execute("select ID, idseq, text from Kanji order by ID"):
    if not has_kanji(text) or len(text) > 16: continue
    cands = [k for k in kana_by_seq.get(seq, []) if not k[2] and (k[0] not in knr or text in knr[k[0]])]
    if not cands: continue
    pr = [k for k in cands if k[0] in knp]
    reading = hira((pr or cands)[0][1])
    if not KANA.match(reading): continue
    rank = 0 if kid in kjp else 2
    if text not in best or rank < best[text][0]:
        best[text] = (rank, reading)
# --- Names ---
types = {}
for tid, t in c.execute("select t.idseq, y.text from NETransType y join NETranslation t on t.ID = y.tid"):
    types.setdefault(tid, set()).add(t)
wanted = {'surname','given','fem','masc','person','work','unclass'}
nek = {}
for seq, text, nok in c.execute("select idseq, text, nokanji from NEKana order by ID"):
    nek.setdefault(seq, []).append(text)
from collections import Counter
# 1文字ごとの読み（音・訓・名乗り）
char_readings = {}
for lit, cid in c.execute("select literal, ID from character"):
    rs = set()
    for t, v in c.execute("select r.r_type, r.value from reading r join rm_group g on g.ID = r.gid where g.cid = ?", (cid,)):
        if t == 'ja_on': rs.add(hira(v))
        elif t == 'ja_kun':
            base = v.split('.')[0].strip('-'); rs.add(base); rs.add(v.replace('.', '').strip('-'))
    for (v,) in c.execute("select value from nanori where cid = ?", (cid,)): rs.add(v)
    char_readings[lit] = {r for r in rs if r}
DAK = dict(zip('かきくけこさしすせそたちつてとはひふへほ', 'がぎぐげござじずぜぞだぢづでどばびぶべぼ'))
HAN = dict(zip('はひふへほ', 'ぱぴぷぺぽ'))
def variants(r, first):
    out = {r}
    if not first and r:
        if r[0] in DAK: out.add(DAK[r[0]] + r[1:])
        if r[0] in HAN: out.add(HAN[r[0]] + r[1:])
    for x in list(out):
        if len(x) >= 2 and x[-1] in 'つくちき': out.add(x[:-1] + 'っ')
    return out
def composable(text, reading):
    chars = list(text)
    n = len(chars)
    memo = {}
    def go(i, j):
        if i == n: return j == len(reading)
        if (i, j) in memo: return memo[(i, j)]
        ch = chars[i]
        cands = set()
        if ch == '々' and i > 0: cands = char_readings.get(chars[i-1], set())
        elif ch in 'ヶケヵ': cands = {'が', 'け', 'か'}
        elif not has_kanji(ch): cands = {hira(ch)}
        else: cands = char_readings.get(ch, set())
        ok = False
        for base in cands:
            for v in variants(base, i == 0):
                if reading.startswith(v, j) and go(i + 1, j + len(v)): ok = True; break
            if ok: break
        memo[(i, j)] = ok
        return ok
    return go(0, 0)
votes = {}
is_name = set()
for seq, text in c.execute("select idseq, text from NEKanji order by ID"):
    if not has_kanji(text) or len(text) < 2 or len(text) > 16: continue
    t = types.get(seq, set())
    if not (t & (wanted | {'place'})): continue
    for i, k in enumerate(nek.get(seq, [])):
        r = hira(k)
        if KANA.match(r):
            votes.setdefault(text, Counter())[r] += 1
    if t & wanted: is_name.add(text)
import fugashi
tagger = fugashi.Tagger()
def mecab(text):
    return hira(''.join((w.feature.kana or w.surface) for w in tagger(text)))
for text, counter in votes.items():
    if text not in is_name: continue
    if text in best and best[text][0] <= 1: continue
    if len(counter) > 1:
        guess = mecab(text)
        if guess in counter:
            best[text] = (1, guess); continue
    cands = sorted(counter.items(), key=lambda kv: (-composable(text, kv[0]), -kv[1]))
    best[text] = (1, cands[0][0])
# --- Single kanji fallback (KANJIDIC2) ---
for lit, cid in c.execute("select literal, ID from character"):
    if lit in best: continue
    rows = c.execute("select r.r_type, r.value from reading r join rm_group g on g.ID = r.gid where g.cid = ?", (cid,)).fetchall()
    on = [hira(v) for t, v in rows if t == 'ja_on']
    kun = [v.split('.')[0].strip('-') for t, v in rows if t == 'ja_kun']
    pick = (on or kun)
    if pick and KANA.match(pick[0]):
        best[lit] = (3, hira(pick[0]))
# アプリ側は UTF-16 の並びで二分探索するため、UTF-16 の順に並べる
lines = sorted((f"{k}\t{v[1]}" for k, v in best.items()),
               key=lambda line: line.encode('utf-16-be'))
data = ('\n'.join(lines) + '\n').encode()
with gzip.open(out, 'wb', compresslevel=9) as f: f.write(data)
print(len(lines), len(data), file=sys.stderr)
