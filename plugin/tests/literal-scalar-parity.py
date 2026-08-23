#!/usr/bin/env python3
"""`literal-census.sh` 抽 `literal:` 值的 regex vs YAML 純量語義。

**為什麼有這支**（#407 R62）：census 用**裸 regex**抽 `literal:` 的值，而
`distinct literal` 正是整個 literal 歸零 campaign 的**分母**。同一支腳本裡兩個**更窄**
的文字解析風險——`#` 註解判定、`format:` 標記——都已有完整 oracle ＋ mutation；最寬的
那個反而沒有（跨模型審查列為 HIGH）。

**分岔是量過的，不是假設**（R61）：從真實 entity 複製兩筆、只改 `literal` 的**寫法**，
值不變——

    fixtureA:  - literal: "Jacob Cohen"  # 尾註
    fixtureB:  - literal: Jacob Cohen

真正的解碼器兩者都得到 `Jacob Cohen`（1 個 distinct）；census 報 **2**。

**誠實邊界（三條，這支比它的兩個姊妹弱，要說清楚）**：

  · **oracle 不是真的 Swift 解碼器**。姊妹守衛（`store-marker-parity.sh`）拿真
    `akashic` 當 oracle；這裡辦不到——CLI 讀 store 需要 registry key（index 住 store
    之外），fixture store 沒有 key 就沒有 index。實測 `--library <路徑>`（那是
    membership 篩選）與 `AKASHIC_HOME`／`AKASHIC_STORE`／`AKASHIC_ROOT`／覆寫 `HOME`
    **四條路都不通**。所以 oracle 是本檔內的**參考解碼**，只涵蓋下方列舉的寫法。
  · **`_scalar` 從 census 原始碼抽出並執行**，不在這裡重打一份——一份規格的兩個副本
    必然分岔（本 issue 反覆記過）。抽不到、或抽到不只一份，都紅。
  · **只驗單行純量**。區塊／摺疊純量（`|`／`>`）不在列舉內：census 的區塊切法本來就
    看不到它們，那是另一個缺口，本支不主張涵蓋。

# trigger-coverage: reads plugin/skills/*/scripts/literal-census.sh
"""
import io
import os
import re
import sys
import textwrap

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)
CENSUS = 'plugin/skills/akashic-literal-campaign/scripts/literal-census.sh'

# 「這一行 YAML」→「正確解碼後的值」。封閉列舉：每一列都是一個 YAML 純量寫法。
CASES = [
    ('- literal: Jacob Cohen',              'Jacob Cohen'),
    ('- literal: "Jacob Cohen"',            'Jacob Cohen'),
    ("- literal: 'Jacob Cohen'",            'Jacob Cohen'),
    ('- literal: Jacob Cohen  # 尾註',       'Jacob Cohen'),
    ('- literal: "Jacob Cohen"  # 尾註',     'Jacob Cohen'),
    ('- literal: "Cohen, J."',              'Cohen, J.'),
    ('- literal: "a \\"quoted\\" name"',      'a "quoted" name'),
    ("- literal: 'it''s'",                  "it's"),
    # #407 R63（跨模型審查指名）：帶變音符的人名在這個 store 很常見，而 ASCII-safe
    # 的 YAML emitter 會把它們寫成 `\uXXXX`。照抄下一個字元會得到字面的 `u00e9`。
    ('- literal: "Andr\\u00e9 Weil"',        'André Weil'),
    ('- literal: "caf\\xe9"',                'café'),
    ('- literal: "a\\tb"',                   'a\tb'),
    # #407 R64（跨模型審查指名）：`\U` 是 8 位，非 BMP（CJK 擴充 B、emoji）。
    ('- literal: "\\U00020000"',              chr(0x20000)),
    # #407 R66（跨模型審查指名）：YAML 雙引號純量還有這些跳脫，漏掉會輸出字面的字母。
    ('- literal: "a\\_b"',                   'a' + chr(0xA0) + 'b'),
    ('- literal: "a\\Nb"',                   'a' + chr(0x85) + 'b'),
    ('- literal: "a\\eb"',                   'a' + chr(27) + 'b'),
    ('- literal: "a\\vb"',                   'a' + chr(11) + 'b'),
]


def _census_scalar():
    """把 census 的 `_scalar` **抽出來執行**——不在這裡重打一份。

    一份規格的兩個副本必然分岔（本 issue 反覆記過）。抽不到、或抽到不只一份，都紅。
    """
    src = io.open(CENSUS, encoding='utf8').read()
    # **用縮排界定函式本體，不靠空行**（#407 R63）：上一版的非貪婪樣式在**第一個空行**
    # 就停——在 `_scalar` 裡插一行純排版的空行，切出來的仍是**語法有效**的片段，
    # `exec` 不會拋，兩道既有檢查也不會紅，而那個被截斷的 `_scalar` 對單引號／未加引號
    # 的值一律回 `None`。**靜默切錯比切不到危險**（跨模型審查指名）。
    lines = src.split('\n')
    try:
        a = next(k for k, l in enumerate(lines) if l.startswith('    def _scalar(s):'))
    except StopIteration:
        return None, '從 census 抽不到 `_scalar`——抽取式與宣告寫法脫節了'
    # 空行與**任意縮排的註解行**都不終止切片（#407 R64，跨模型審查指名）：一行
    # 縮排不足的註解——維護者加一句範圍說明時很自然會左對齊——會讓切片提前結束，
    # 而截斷後的本體**仍然語法有效**（每個分支都自帶 return），`exec` 不拋。
    b = a + 1
    while b < len(lines) and (not lines[b].strip()
                              or lines[b].lstrip().startswith('#')
                              or lines[b].startswith('        ')):
        b += 1
    # **切完要驗結構完整**：本體的最後一個非空、非註解行必須是 `return`。只驗
    # 「`exec` 沒拋」擋不住截斷——那正是上一版的漏洞。
    tail = [l for l in lines[a:b] if l.strip() and not l.lstrip().startswith('#')]
    if not tail or not tail[-1].strip().startswith('return'):
        return None, ('切出的 `_scalar` 本體最後一行不是 `return`——切片可能被截斷了'
                      f'（最後一行：{tail[-1].strip()[:40] if tail else "（空）"}）')
    # **縮排不足的註解行不進切片**：它們不終止切片（見上），但若原樣納入，
    # `textwrap.dedent` 的共同前綴會塌成空字串、`exec` 反而炸掉（#407 R64 當場踩到）。
    body = [l for l in lines[a:b]
            if not (l.strip().startswith('#') and not l.startswith('        '))]
    m = type('M', (), {'group': lambda self, i: '\n'.join(body)})()
    if src.count('def _scalar(s):') != 1:
        return None, f"census 裡有 {src.count('def _scalar(s):')} 份 `_scalar`（須恰好 1）"
    ns = {'re': re}
    exec(textwrap.dedent(m.group(1)), ns)
    return ns['_scalar'], None


def main():
    scalar, err = _census_scalar()
    if err:
        print(f'✗ {err}')
        return 1

    rx = re.compile(r'^- literal: (.*)$', re.M)
    bad = []
    for line, want in CASES:
        m = rx.search(line)
        got = scalar(m.group(1)) if m else None
        if got != want:
            bad.append((line, want, got))

    print(f'══ `literal:` 純量解碼 parity：{len(CASES)} 種寫法 ══')
    for line, want, got in bad:
        print(f'  ✗ {line}\n      正確 {want!r}｜census 得到 {got!r}')
    print(f'\n══ {"全部一致" if not bad else f"**{len(bad)} 種寫法分岔**"} ══')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
