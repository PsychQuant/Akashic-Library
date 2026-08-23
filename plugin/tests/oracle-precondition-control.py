#!/usr/bin/env python3
"""`audit-guards-mutations.py` 兩個**自檢**機制的負控（#407 R67h／R67j）。

為什麼要獨立一支
================
R67 讓 ROBUST 負控拿「守衛在未注入 copy 上的輸出」當 oracle、要求逐字相同；R67e 又
加了「跑兩次比對以驗決定性」。那個前提檢查是 harness 裡唯一一個**失敗會外溢**的機制
（假紅會讓人開始不相信所有紅燈），所以它自己要被檢查。

而 R67e 當時的反向證實只是一支 scratch probe，**它結構上測不到自己要測的路徑**：它
毒化的守衛只有一個 ROBUST case，第一輪就 `continue` 了。跨模型審查（security 席）
指出那條路徑會 `KeyError` 整支 crash——挑一個只有一格的守衛當控制組，等於挑了唯一
不會暴露它的那支。這支檔案存在，就是為了讓那個控制組**不再是隨手挑的**。

**檢查一：ROBUST oracle 的前提**（R67h）。要求 harness 乾淨降級，而不是 crash 或
假裝通過：前提不成立時具名報出是哪一支守衛，且那一支的 ROBUST case 全部不計入
通過數（不是只少一格）。

**檢查二：逐守衛的 baseline**（R67j）。harness 上一版只驗兩支守衛的 baseline，
於是其餘守衛若在注入**之前**就已經紅，它們的控制組會平白通過——控制組宣稱「注入
造成了紅」，而紅早就在那裡。實測當時 10 個 numbers 控制組**全部**照樣報 ✓。
這裡把一個既有守衛在 baseline 就弄紅，要求 harness 在跑任何 case 之前就攔下來。

用法
====
    plugin/tests/oracle-precondition-control.py

（**刻意不寫 `trigger-coverage` 宣告**：它讀的是同目錄的另一支腳本，而同目錄的
腳本本來就在枚舉範圍內——多寫一條會被覆蓋守衛標成「多半多餘，請人確認」。）
"""
import contextlib
import importlib.util
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HARNESS = os.path.join(ROOT, 'plugin/tests/audit-guards-mutations.py')


def _load():
    spec = importlib.util.spec_from_file_location('audit_harness', HARNESS)
    mod = importlib.util.module_from_spec(spec)
    sys.modules['audit_harness'] = mod
    spec.loader.exec_module(mod)
    return mod


def _run(mod, poisoned):
    """跑 harness，但讓 `poisoned` 這支守衛的**未注入**輸出每次都不同。

    各 `with_copy` 是獨立 subprocess，所以印 pid 必然每次不同——這是最小的
    非決定性注入，不改守衛的任何判斷。
    """
    orig = mod.with_copy

    def patched(guard, edits):
        if guard == poisoned and not edits:
            return orig(guard, {poisoned: lambda t: t.replace(
                'import re\n', 'import os\nimport re\nprint(os.getpid())\n', 1)})
        return orig(guard, edits)

    mod.with_copy = patched
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = mod.main()
    return rc, buf.getvalue()


def _check_baseline(mod):
    """把一支守衛在 baseline 就弄紅，harness 必須在跑任何 case 之前攔下。"""
    orig = mod.with_copy
    poison = ('.claude/rules/lossless-intake.md',
              lambda s: s.replace('## 規則', '## 破壞 baseline\n\n實測 42 筆。\n\n## 規則', 1))

    def patched(guard, edits):
        e = dict(edits)
        if guard == mod.NUMBERS_REL:
            p, fn = poison
            prev = e.get(p)
            e[p] = (lambda s: fn(prev(s))) if prev else fn
        return orig(guard, e)

    mod.with_copy = patched
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = mod.main()
    out = buf.getvalue()
    fails = []
    if '在**注入之前**就已經紅' not in out or mod.NUMBERS_REL not in out:
        fails.append('沒有具名報出是哪一支守衛的 baseline 就紅了')
    if 'negative control' in out:
        fails.append('髒 baseline 下仍跑完全部 case 並印出通過數——控制組在空轉')
    if rc == 0:
        fails.append('baseline 髒掉時 harness 仍回 0')
    return fails


def main():
    mod = _load()
    counts = {}
    for _, guard, _, _ in mod.ROBUST:
        counts[guard] = counts.get(guard, 0) + 1

    # **刻意挑 ROBUST case 最多的那一支**（不是隨手挑）：只有一格的守衛在前提
    # 不成立時第一輪就 `continue`，走不到後面的路徑——那正是 R67e 的 probe 的盲點。
    target = max(counts, key=lambda g: counts[g])
    n_cases = counts[target]
    print(f'══ 毒化 {target}（{n_cases} 個 ROBUST case，全樹最多）══')
    if n_cases < 2:
        print('✗ 全樹沒有任何守衛有 2 個以上 ROBUST case——這支控制組退化成測不到'
              '「第二格」那條路徑。加一個 ROBUST case，或刪掉這支並說明為什麼。')
        return 1

    mod = _load()                                   # 乾淨載入，量未毒化的通過數
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        mod.main()
    m = re.search(r'negative control (\d+)/(\d+)', buf.getvalue())
    if not m:
        print('✗ 讀不到未毒化時的通過數——harness 的輸出格式變了')
        return 1
    clean_ok, clean_total = int(m.group(1)), int(m.group(2))

    mod = _load()
    try:
        rc, out = _run(mod, target)
    except Exception as e:                          # noqa: BLE001 —— crash 就是缺陷
        print(f'✗ harness 在前提不成立時**崩潰**而不是乾淨降級：{type(e).__name__}: {e}')
        return 1

    fails = []
    if 'oracle 前提不成立' not in out or target not in out:
        fails.append('沒有具名報出是哪一支守衛的前提不成立')
    m2 = re.search(r'negative control (\d+)/(\d+)', out)
    if not m2:
        fails.append('毒化後讀不到通過數')
    else:
        got = int(m2.group(1))
        want = clean_ok - n_cases
        if got != want:
            fails.append(f'通過數應從 {clean_ok} 掉到 {want}（少掉那 {n_cases} 格），'
                         f'實際 {got}')
    if rc == 0:
        fails.append('前提不成立時 harness 仍回 0')

    for f in fails:
        print(f'  ✗ {f}')
    if not fails:
        print(f'  ✓ 具名報出、{n_cases} 格全部不計入（{clean_ok} → {clean_ok - n_cases}）、rc≠0')
    print()
    print('══ 檢查二：逐守衛的 baseline 驗證 ══')
    b_fails = _check_baseline(_load())
    for f in b_fails:
        print(f'  ✗ {f}')
    if not b_fails:
        print('  ✓ 髒 baseline 被在跑任何 case 之前攔下、具名、rc≠0')

    total = fails + b_fails
    print(f'\n══ {"兩個自檢都會乾淨降級" if not total else f"**{len(total)} 項不符**"} ══')
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main())
