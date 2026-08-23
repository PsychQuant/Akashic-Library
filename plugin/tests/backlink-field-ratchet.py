#!/usr/bin/env python3
"""`entity-backlink-completeness.md` 的 14 條邊：**新欄位必須先被裁決**。

**為什麼有這支**（#407 R51）：那張封閉列舉表**錯過三次**（該檔自己記著：宣稱窮盡卻漏
三條、補了形狀沒窮舉欄位、新增一條邊卻沒改表）。它因此附了一段可執行的稽核程序，
第 ③ 步是「逐欄位問：它會被序列化嗎？它的值指涉另一個實體嗎？」——**那一步是人的
判斷**，不能由腳本代做。

所以本支**不裁決**，只做**棘輪**：把當下六個型別檔裡的 `public var` **與 `public let`** 全部釘住。
新出現一個就紅，訊息要求人跑規則的第 ③ 步、再把它加進下面的清單。

**誠實邊界**：

  · **釘的是全部欄位，不是「看起來像 reference 的」**。上一版用型別排除純量當候選
    偵測（42 個），而跨模型審查指出 `public var seeAlso: [String]` 這種**直接掛在
    頂層型別上的 key 陣列**會被判成純量而漏掉——`cites`／`related` 之所以被涵蓋，
    只是因為它們包在 `relations: Relations` 這個非純量結構裡。謂詞比它要管的東西窄，
    所以整個拿掉：全部欄位都要裁決，那本來就是規則第 ③ 步的字面要求（#407 R52）。
  · 宣告**跨行**時上一版的逐行 regex 也看不到；改成先摺平空白再抓。
  · **`public let` 也算**（#407 R53，跨模型審查指名）：上一版只抓 `var`，而第 13 條邊
    的解析形式 `VerdictPairingValue` 的 `holderKind`／`holder` 正是 `public let`——
    一條真的 entity 指標整個在棘輪之外。
  · **不驗那 14 列的裁決內容對不對**（那要人判斷），但**列的葉欄位必須存在於 Swift**
    ——R57 起加的第二道，見 `_table_edges()`。
  · 欄位被**刪掉**也會紅（清單與現況不等），那是刻意的——刪一條邊同樣要改表。

**它讀的是 Swift，不是那份規則**（#407 R51）：本支拿六個型別檔與自己釘住的清單比對，
**不打開** `entity-backlink-completeness.md`。先前在這裡宣告讀那份規則是**假宣告**——
守衛的痕跡檢查當場警告。真正的依賴是下面那條。

# trigger-coverage: reads Sources/AkashicCore/*.swift
"""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)
FILES = ['Models', 'Organization', 'Divergence', 'Temporal', 'Provenance', 'Venue']
# 已裁決過的欄位（#407 R52 釘住當下狀態，**全部** `public var`）。新增一個 → 先跑
# `entity-backlink-completeness.md` 的第 ③ 步，再把它加進這裡。
ADJUDICATED = {
    'Divergence.candidates',
    'Divergence.id',
    'Divergence.judgement',
    'Divergence.key',
    'Divergence.prefers',
    'Divergence.question',
    'Divergence.restsOn',
    'Divergence.shape',
    'Divergence.statement',
    'Divergence.unknownFields',
    'Models.akashic',
    'Models.all',
    'Models.attachments',
    'Models.authorListCompleteness',
    'Models.authorized',
    'Models.authors',
    'Models.citekey',
    'Models.cites',
    'Models.date',
    'Models.dateIsConfirmedAbsent',
    'Models.description',
    'Models.died',
    'Models.displayName',
    'Models.fields',
    'Models.id',
    'Models.importedAt',
    'Models.isEmpty',
    'Models.key',
    'Models.kind',
    'Models.libraries',
    'Models.libraryID',
    'Models.message',
    'Models.name',
    'Models.names',
    'Models.note',
    'Models.openalex',
    'Models.orcid',
    'Models.orphanedAt',
    'Models.path',
    'Models.profile',
    'Models.provenance',
    'Models.raw',
    'Models.references',
    'Models.related',
    'Models.relations',
    'Models.severity',
    'Models.sources',
    'Models.status',
    'Models.tags',
    'Models.thesis',
    'Models.title',
    'Models.type',
    'Models.unknownFields',
    'Models.variant',
    'Models.venues',
    'Models.zoteroHash',
    'Models.zoteroKey',
    'Models.zoteroVersion',
    'Organization.authorized',
    'Organization.displayName',
    'Organization.dissolved',
    'Organization.founded',
    'Organization.id',
    'Organization.key',
    'Organization.names',
    'Organization.note',
    'Organization.parents',
    'Organization.references',
    'Organization.unknownFields',
    'Provenance.encoded',
    'Provenance.field',
    'Provenance.holder',
    'Provenance.holderKind',
    'Provenance.kind',
    'Provenance.literal',
    'Provenance.value',
    'Temporal.administrative',
    'Temporal.affiliations',
    'Temporal.appointments',
    'Temporal.attested',
    'Temporal.contacts',
    'Temporal.current',
    'Temporal.end',
    'Temporal.endedUnknown',
    'Temporal.entries',
    'Temporal.fields',
    'Temporal.inSerializationOrder',
    'Temporal.isEmpty',
    'Temporal.isOpen',
    'Temporal.latestPastSegment',
    'Temporal.note',
    'Temporal.range',
    'Temporal.ranks',
    'Temporal.sorted',
    'Temporal.source',
    'Temporal.start',
    'Temporal.usesAttested',
    'Temporal.usesEndedUnknown',
    'Temporal.value',
    'Venue.authorized',
    'Venue.displayName',
    'Venue.id',
    'Venue.key',
    'Venue.names',
    'Venue.note',
    'Venue.references',
    'Venue.type',
    'Venue.unknownFields',
}


RULE = '.claude/rules/entity-backlink-completeness.md'


def _table_edges():
    """從那張表抽出 14 條邊各自的**葉欄位名**。

    **為什麼要讀表**（#407 R57，跨模型審查指名為 HIGH）：上一版只比對自己的
    `ADJUDICATED` 字面，**完全不打開那份規則**——於是同一個 commit 裡加一個欄位、
    再把它追加進 `ADJUDICATED`，棘輪就綠了，而表一列都沒動。守衛可以被**編輯它自己的
    fixture** 來消音。

    現在多一道：表裡每一列的 `Type.field` 路徑，其**葉欄位**必須真的存在於六個型別檔。
    列被改名／刪掉，或 Swift 那側改名，都會紅。

    誠實邊界：只比**葉名**（`Person.profile.affiliations` → `affiliations`），不驗
    它掛在哪個型別上——巢狀路徑（`akashic.relations.cites`）的中間段不在那六個檔的
    頂層宣告裡，逐段驗證需要型別解析。
    """
    if not os.path.exists(RULE):
        return None, '找不到規則檔'
    rule = io.open(RULE, encoding='utf8').read()
    rows = re.findall(r'^\| (\d+) \| (.*?) \| (.*?) \|', rule, re.M)
    if not rows:
        return None, '表一列都沒讀到——抽取式與表的寫法脫節了'
    out = []
    for num, where, _ in rows:
        m = re.search(r'`([A-Z][A-Za-z]*\.[A-Za-z.]+)`', where)
        if not m:
            return None, f'第 {num} 列抽不到 `Type.field` 路徑'
        out.append((num, m.group(1), m.group(1).split('.')[-1]))
    return out, None


def main():
    seen = set()
    for f in FILES:
        p = f'Sources/AkashicCore/{f}.swift'
        if not os.path.exists(p):
            print(f'✗ 找不到 {p}——規則指定的六個型別檔之一不在了，稽核程序脫節')
            return 1
        flat = re.sub(r'\s+', ' ', io.open(p, encoding='utf8').read())
        for m in re.finditer(r'public (?:var|let) (\w+)\s*:', flat):
            seen.add(f'{f}.{m.group(1)}')

    edges, err = _table_edges()
    table_fails = []
    if err:
        table_fails.append(err)
    else:
        leaves = {n.split('.')[-1] for n in seen}
        for num, path, leaf in edges:
            if leaf not in leaves:
                table_fails.append(f'表第 {num} 列的 `{path}`——葉欄位 `{leaf}` '
                                   f'**在六個型別檔裡找不到**（列被改名了，還是 Swift 改名了？）')

    new = sorted(seen - ADJUDICATED)
    gone = sorted(ADJUDICATED - seen)
    print(f'══ 欄位棘輪：現況 {len(seen)}｜已裁決 {len(ADJUDICATED)} ══')
    for n in new:
        print(f'  ✗ **新欄位未經裁決**：{n}——請跑 entity-backlink-completeness.md 的'
              f'第 ③ 步（它會被序列化嗎？值指涉另一個實體嗎？），再加進 ADJUDICATED')
    for n in gone:
        print(f'  ✗ 欄位消失：{n}——若它是一條邊，表也要改')
    for f in table_fails:
        print(f'  ✗ {f}')
    if edges:
        print(f'  （表 {len(edges)} 列，葉欄位全部對得上 Swift）'
              if not table_fails else '')
    print(f'\n══ {"無未裁決欄位" if not (new or gone) else f"**{len(new) + len(gone)} 處"} ══')
    return 1 if (new or gone or table_fails) else 0


if __name__ == '__main__':
    sys.exit(main())
