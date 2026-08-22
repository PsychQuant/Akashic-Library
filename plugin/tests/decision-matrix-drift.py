#!/usr/bin/env python3
"""CLAUDE.md 的 pre-push 決策矩陣：宣稱值 vs 由兩條語意規則現算的值。

**為什麼有這支**（#407 R27）：那張表錯過一次（R26q 的
`| 正常 | 恢復 | 任一 | 執行 | 執行 |` —— 涵蓋 3 格而「留」欄是
零執行／零執行／執行），而那個錯撐過了好幾輪人＋AI 審查才被發現。表是散文，
沒有任何東西在檢查它；本支把它變成被檢查的。

**它驗什麼、不驗什麼**（誠實邊界，寫在最前面免得被當成更強的保證）：

  驗   ——「表宣稱的值」與「由檔案自己敘述的兩條語意規則現算的值」一致，
         且每一列在它**字面涵蓋的全部格**上成立（笛卡兒積，非只有你檢查過那幾格），
         且 8 列合起來涵蓋全部 12 格。
  不驗 ——那兩條規則本身是否符合**現實**。要驗那個得真的在 12 種組態下各 push 一次。
         規則取自檔案自己的敘述（見下），所以本支抓的是**轉錄錯誤與合併過度宣稱**
         ——R26q 正是後者。

**兩條規則的出處**（不是我發明的，是檔案自己寫的）：

  A「留在 pre-push」= 執行 ⟺ push 是正常 `git push`（hook 沒被繞過）
     **且** `core.hooksPath` 指向本樹（那份 hook 才含這些守衛）。
     出處：檔案的 hooksPath 三值段——「未設定」不隨 clone 傳遞、pre-push 完全不跑；
     「指向主 repo」對本輪守衛命中 0；「指向本樹」merge 後自癒。
     以及 `--no-verify` 那兩列的理由：「它繞過 hook 的**執行**」。
  B「移出、只留 CI」= 執行 ⟺ CI 跑得起來。出處：該欄的定義即是「只留 CI」。
     **範圍**（#407 R27，跨模型審查指名）：這一欄問的是**一次會動到受保護檔案的
     push**。`census-parity.yml` 是 path-scoped，所以對不動到那些檔案的 push，
     移出後是零執行——但那時也無事可查（trigger-coverage 實測零缺口）。表把這個
     範圍寫進了散文，本支只驗表內的 8 列，不驗範圍外的格。

# trigger-coverage: reads CLAUDE.md
"""
import io
import itertools
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# argv[1] 可覆寫要讀的 markdown。**唯一的用途是負控**——它必須在 pristine copy 上
# mutate，不得就地改出貨檔（前一版的 harness 就地改寫版控中的檔案，跨模型審查在審查
# 期間實際觀察到 tracked 檔出現被注入的狀態，#407 R6）。這個參數由
# `decision-matrix-mutations.py` 實際行使——一個沒人走過的參數等於沒有（#407 R9 的
# `--check` 假接口）。
MD = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'CLAUDE.md')

PUSH_VALUES = ['正常', '--no-verify']
CI_VALUES = ['不跑', '恢復']
HP_VALUES = ['未設定', '主repo', '本樹']


def rule_keep(push, ci, hp):
    """A：留在 pre-push。"""
    return '執行' if (push == '正常' and hp == '本樹') else '零執行'


def rule_move(push, ci, hp):
    """B：移出、只留 CI。"""
    return '執行' if ci == '恢復' else '零執行'


def strip_md(cell):
    cell = re.sub(r'`[^`]*`', lambda m: m.group(0).strip('`'), cell)
    return cell.replace('*', '').strip()


def parse_push(c):
    return '--no-verify' if '--no-verify' in c else ('正常' if 'git push' in c or '正常' in c else None)


def parse_ci(c):
    if '恢復' in c:
        return '恢復'
    return '不跑' if '不跑' in c else None


def parse_hp(c):
    if '任一' in c:
        return HP_VALUES          # 該維全部取值
    if '未設定' in c:
        return ['未設定']
    if '主 repo' in c or '主repo' in c:
        return ['主repo']
    if '本樹' in c:
        return ['本樹']
    return None


def parse_outcome(c):
    # **嚴格相等，不做子串比對**（#407 R27，負控寫錯 mutation 時順帶看見的）。
    # 子串版把「執行（只在 merge 後）」讀成無條件的「執行」——安靜丟掉限定詞，
    # 而限定詞正是這張表出過事的地方。嚴格版讓它落進 `<未解析>` 出聲。
    # （子串版另有一個坑：「零執行」含有「執行」，順序寫反就全錯。嚴格版沒這個問題。）
    return c if c in ('執行', '零執行') else None


def main():
    lines = io.open(MD, encoding='utf8').read().split('\n')
    try:
        head = next(i for i, l in enumerate(lines)
                    if l.startswith('> | push 方式 | CI 狀態 | hooksPath |'))
    except StopIteration:
        print('✗ 找不到決策矩陣的表頭（表被改名或移走了？）')
        return 1

    rows = []
    for l in lines[head + 2:]:
        if not l.startswith('> |'):
            break
        cells = [strip_md(c) for c in l[2:].strip().strip('|').split('|')]
        if len(cells) != 5:
            print(f'✗ 列的欄數不是 5：{l[:70]}')
            return 1
        p, c, h = parse_push(cells[0]), parse_ci(cells[1]), parse_hp(cells[2])
        k, m = parse_outcome(cells[3]), parse_outcome(cells[4])
        # **解析不出來要出聲，不可靜默跳過**——只在 happy path 正確的稽核，
        # 會在真正需要它的時候安靜少報一列（mcp-cli-parity 的 ② 記過同型）。
        if None in (p, c, h, k, m):
            print(f'✗ <未解析> 列：{l[:80]}')
            print(f'    push={p} ci={c} hooksPath={h} 留={k} 移出={m}')
            return 1
        rows.append((p, c, h, k, m))

    if not rows:
        print('✗ 表頭之後一列都沒讀到')
        return 1

    print(f'══ 決策矩陣漂移檢查（讀到 {len(rows)} 列）══')
    bad = 0
    for i, (p, c, hs, k, m) in enumerate(rows, 1):
        cover = [(p, c, h) for h in hs]
        keeps = {rule_keep(*x) for x in cover}
        moves = {rule_move(*x) for x in cover}
        ok = keeps == {k} and moves == {m}
        if not ok:
            bad += 1
        lbl = f'{p:<12}{c:<5}{"任一" if len(hs) > 1 else hs[0]}'
        print(f'  {"✓" if ok else "✗"} 列{i} {lbl:<20} 涵蓋{len(cover)}格 '
              f'宣稱({k},{m}) 現算({"/".join(sorted(keeps))},{"/".join(sorted(moves))})')

    seen = {(p, c, h) for p, c, hs, _, _ in rows for h in hs}
    allc = {(p, c, h) for p in PUSH_VALUES for c in CI_VALUES for h in HP_VALUES}
    missing = sorted(allc - seen)
    dup = len([1 for p, c, hs, _, _ in rows for h in hs]) - len(seen)
    print(f'\n  涵蓋 {len(seen)}/{len(allc)} 格'
          + (f'；**缺 {missing}**' if missing else '；無缺口')
          + (f'；**{dup} 格被重複宣稱**' if dup else ''))

    fail = bad or missing or dup
    print(f'\n══ {"矩陣與規則一致、無缺口" if not fail else "**漂移**"} ══')
    return 1 if fail else 0


if __name__ == '__main__':
    sys.exit(main())
