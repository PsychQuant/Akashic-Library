#!/usr/bin/env python3
"""`entity-backlink-completeness.md` 的 14 條邊：**新欄位必須先被裁決**。

**為什麼有這支**（#407 R51）：那張封閉列舉表**錯過三次**（該檔自己記著：宣稱窮盡卻漏
三條、補了形狀沒窮舉欄位、新增一條邊卻沒改表）。它因此附了一段可執行的稽核程序，
第 ③ 步是「逐欄位問：它會被序列化嗎？它的值指涉另一個實體嗎？」——**那一步是人的
判斷**，不能由腳本代做。

所以本支**不裁決**，只做**棘輪**：把當下六個型別檔裡**非純量**的 `public var` 釘住
（42 個）。新出現一個就紅，訊息要求人跑規則的第 ③ 步、再把它加進下面的清單。

**誠實邊界**：

  · 「非純量」是**排除法**（型別不是 `String`／`Int`／`Bool`／`Date`／`UUID`／`URL`
    及其陣列／可選）。這是候選偵測，不是「它是一條邊」的判定。
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
SCALAR = re.compile(r'^\[?(String|Int|Int64|Bool|Double|Date|UUID|URL)\??\]?\??$')

# 已裁決過的非純量欄位（#407 R51 釘住當下狀態）。新增一個 → 先跑
# `entity-backlink-completeness.md` 的第 ③ 步，再把它加進這裡。
ADJUDICATED = {
    'Divergence.candidates',
    'Divergence.judgement',
    'Divergence.shape',
    'Divergence.unknownFields',
    'Models.akashic',
    'Models.attachments',
    'Models.authorListCompleteness',
    'Models.authors',
    'Models.fields',
    'Models.kind',
    'Models.names',
    'Models.profile',
    'Models.provenance',
    'Models.references',
    'Models.relations',
    'Models.severity',
    'Models.thesis',
    'Models.type',
    'Models.unknownFields',
    'Models.venues',
    'Organization.names',
    'Organization.parents',
    'Organization.references',
    'Organization.unknownFields',
    'Provenance.kind',
    'Temporal.administrative',
    'Temporal.affiliations',
    'Temporal.appointments',
    'Temporal.contacts',
    'Temporal.current',
    'Temporal.entries',
    'Temporal.fields',
    'Temporal.inSerializationOrder',
    'Temporal.latestPastSegment',
    'Temporal.range',
    'Temporal.ranks',
    'Temporal.sorted',
    'Temporal.value',
    'Venue.names',
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
        for line in io.open(p, encoding='utf8'):
            m = re.search(r'public var (\w+)\s*:\s*([^={\n]+)', line)
            if m and not SCALAR.match(m.group(2).strip()):
                seen.add(f'{f}.{m.group(1)}')

    new = sorted(seen - ADJUDICATED)
    gone = sorted(ADJUDICATED - seen)
    print(f'══ 非純量欄位棘輪：現況 {len(seen)}｜已裁決 {len(ADJUDICATED)} ══')
    for n in new:
        print(f'  ✗ **新欄位未經裁決**：{n}——請跑 entity-backlink-completeness.md 的'
              f'第 ③ 步（它會被序列化嗎？值指涉另一個實體嗎？），再加進 ADJUDICATED')
    for n in gone:
        print(f'  ✗ 欄位消失：{n}——若它是一條邊，表也要改')
    print(f'\n══ {"無未裁決欄位" if not (new or gone) else f"**{len(new) + len(gone)} 處"} ══')
    return 1 if (new or gone) else 0


if __name__ == '__main__':
    sys.exit(main())
