#!/usr/bin/env python3
"""`entity-backlink-completeness.md` 的 14 條邊：**新欄位必須先被裁決**。

**為什麼有這支**（#407 R51）：那張封閉列舉表**錯過三次**（該檔自己記著：宣稱窮盡卻漏
三條、補了形狀沒窮舉欄位、新增一條邊卻沒改表）。它因此附了一段可執行的稽核程序，
第 ③ 步是「逐欄位問：它會被序列化嗎？它的值指涉另一個實體嗎？」——**那一步是人的
判斷**，不能由腳本代做。

所以本支**不裁決**，只做**棘輪**：把當下六個型別檔裡的 `public var` **全部**釘住。
新出現一個就紅，訊息要求人跑規則的第 ③ 步、再把它加進下面的清單。

**誠實邊界**：

  · **釘的是全部欄位，不是「看起來像 reference 的」**。上一版用型別排除純量當候選
    偵測（42 個），而跨模型審查指出 `public var seeAlso: [String]` 這種**直接掛在
    頂層型別上的 key 陣列**會被判成純量而漏掉——`cites`／`related` 之所以被涵蓋，
    只是因為它們包在 `relations: Relations` 這個非純量結構裡。謂詞比它要管的東西窄，
    所以整個拿掉：全部欄位都要裁決，那本來就是規則第 ③ 步的字面要求（#407 R52）。
  · 宣告**跨行**時上一版的逐行 regex 也看不到；改成先摺平空白再抓。
  · **本支不驗表裡那 14 列對不對**，只驗「沒有未經裁決的新欄位溜進來」。
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
    'Provenance.kind',
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


def main():
    seen = set()
    for f in FILES:
        p = f'Sources/AkashicCore/{f}.swift'
        if not os.path.exists(p):
            print(f'✗ 找不到 {p}——規則指定的六個型別檔之一不在了，稽核程序脫節')
            return 1
        flat = re.sub(r'\s+', ' ', io.open(p, encoding='utf8').read())
        for m in re.finditer(r'public var (\w+)\s*:', flat):
            seen.add(f'{f}.{m.group(1)}')

    new = sorted(seen - ADJUDICATED)
    gone = sorted(ADJUDICATED - seen)
    print(f'══ 欄位棘輪：現況 {len(seen)}｜已裁決 {len(ADJUDICATED)} ══')
    for n in new:
        print(f'  ✗ **新欄位未經裁決**：{n}——請跑 entity-backlink-completeness.md 的'
              f'第 ③ 步（它會被序列化嗎？值指涉另一個實體嗎？），再加進 ADJUDICATED')
    for n in gone:
        print(f'  ✗ 欄位消失：{n}——若它是一條邊，表也要改')
    print(f'\n══ {"無未裁決欄位" if not (new or gone) else f"**{len(new) + len(gone)} 處"} ══')
    return 1 if (new or gone) else 0


if __name__ == '__main__':
    sys.exit(main())
