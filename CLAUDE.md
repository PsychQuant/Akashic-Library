<!-- SPECTRA:START v1.0.2 -->

# Spectra Instructions

This project uses Spectra for Spec-Driven Development(SDD). Specs live in `openspec/specs/`, change proposals in `openspec/changes/`.

## Use `/spectra-*` skills when:

- A discussion needs structure before coding → `/spectra-discuss`
- User wants to plan, propose, or design a change → `/spectra-propose`
- Tasks are ready to implement → `/spectra-apply`
- There's an in-progress change to continue → `/spectra-ingest`
- User asks about specs or how something works → `/spectra-ask`
- Implementation is done → `/spectra-archive`
- Commit only files related to a specific change → `/spectra-commit`

## Workflow

discuss? → propose → apply ⇄ ingest → archive

- `discuss` is optional — skip if requirements are clear
- Requirements change mid-work? Plan mode → `ingest` → resume `apply`

## Parked Changes

Changes can be parked（暫存）— temporarily moved out of `openspec/changes/`. Parked changes won't appear in `spectra list` but can be found with `spectra list --parked`. To restore: `spectra unpark <name>`. The `/spectra-apply` and `/spectra-ingest` skills handle parked changes automatically.

<!-- SPECTRA:END -->

## Parked change 不進版本控制（#72）

> 上面那段由 Spectra 自動維護，這段是本 repo 的規則。

`spectra park` 把 change 移到 **`.git/spectra-app/changes/`**。`.git/` 底下的內容 git 從不追蹤（那是它自己的目錄），所以：

- 連 `.gitignore` 規則都不需要——它根本沒進入候選集合，`git check-ignore` 也不回報任何東西
- **parked change 的全部設計產出只存在於單一台機器上**
- `spectra list --parked` 與 `spectra status` 都正常回報（artifacts 全部 `done`），從工具的角度看不出任何異常

生命週期裡因此有一個裸露窗口：

```
propose ──→ park ──────────────→ apply ──→ archive
            └── 不在版控 ─────────┘        └─ 進版控 ─┘
```

**規則**：park 只用於「今天不做、而且丟了也無所謂」的東西。任何要保留的設計——尤其是對應著仍開啟 issue 的——**不要停在 parked 狀態**。要暫時挪開就 `spectra unpark <name>` 搬回 `openspec/changes/`（那裡是 tracked）再 commit；`openspec/changes/` 裡有未完成的 change 不是問題，那本來就是它的用途。

實際踩過：三個 change、18 檔、124 KB 的設計工作曾同時停在 parked（#72）。park 位置本身屬 Spectra.app 的行為，不在本 repo 可修範圍。

## Rules

**`.claude/rules/` 下的每一條規則，本 repo 的所有實踐都必須遵守。** 它們不是建議、
不是風格偏好、也不是「參考一下」——是本 repo 已經付過代價換來的裁決。

三條執行語意：

1. **規則勝過臨場判斷。** 當某條規則與「這次這樣做比較快／比較合理」衝突時，以規則為準。
   規則存在的理由通常正是「當時也覺得那樣比較合理」。
2. **覺得規則錯了就顯式改規則**，不要靜默偏離。改法是在同一個變更裡改那個檔案、寫下
   為什麼、附上量測——每條規則的「觸發過的實例」段就是為此而存在。
3. **規則的封閉列舉不得依性質相似類推。** 好幾條規則刻意用「封閉表 ＋ 逐列理由」而不給
   總括判準（理由見全域 `common-spec-prose-enumeration`）。遇到表裡沒有的情形，**加一列**，
   不要從既有列推導。

寫給會照著執行的人與模型看。

| 規則 | 一句話 |
|---|---|
| [lossless-intake.md](.claude/rules/lossless-intake.md) | 匯入不得有損——來源給了什麼就收什麼；不收的只有秘密與隱私邊界兩類，且丟棄必須報出來 |
| [literal-first-then-key.md](.claude/rules/literal-first-then-key.md) | 每個 entity reference 先以 literal 進庫、再經顯式消歧升格 key——進庫不猜、升格留 verdict；終局是全域 literal 歸零（#303/#304） |
| [identity-is-judged-not-matched.md](.claude/rules/identity-is-judged-not-matched.md) | 身分是**判定**出來的不是**比對**出來的——`literal → key` 是 AI 判斷函數，不得由字串謂詞單獨做出；Jaccard 實測同一人 0.40／不同人 0.50，提名是 recall 不是判定 |
| [mcp-cli-parity.md](.claude/rules/mcp-cli-parity.md) | 新增任一面（MCP／CLI）的能力時必須裁決另一面——三張封閉裁決表（MCP／CLI-only／橫切選項）+ 四步機械稽核（#259 起雙向，#310 補橫切面），缺口不得安靜累積 |
| [entity-backlink-completeness.md](.claude/rules/entity-backlink-completeness.md) | 呈現 entity 時所有相關 entity 都要看得到——反向一律現算不儲存；可儲存的關係邊是一張封閉列舉表＋可執行稽核（條數見該檔，摘要刻意不複述——複述過的數字會與表分岔） |
| [no-compat-fallback.md](.claude/rules/no-compat-fallback.md) | 不留相容 fallback——要改格式就一次改完全部；例外須離開 default 位置、附退場量測、退場即刪 |
| [replace-endnote-and-zotero.md](.claude/rules/replace-endnote-and-zotero.md) | 目標是完全取代 EndNote 與 Zotero——檔案住 Akashic、位元組複製進 store、對 Zotero 的 pull 是過渡、能力缺口記 issue 不得靠「回去用 Zotero」帶過 |
| [apa7-is-the-work-floor.md](.claude/rules/apa7-is-the-work-floor.md) | 一筆 work 的資訊下限是「能產出正確的 APA7 參考文獻」——ch10 的 113 例是驗收矩陣、`Entry.type` 的值域須**細分**（非等於）ch10 的 16 節；下限不是上限，分類可更細不可更粗 |
| [zero-instance-guards.md](.claude/rules/zero-instance-guards.md) | 為「還沒發生過的形狀」寫守衛是一列一列裁決出來的——封閉決策表＋理由欄同列，刻意不給總括判準（那會在邊界上長出沒人同意的答案）|
| [blocked-issues-must-be-scannable.md](.claude/rules/blocked-issues-must-be-scannable.md) | 被阻塞的 issue 必須把「在等什麼」寫在工具掃得到的三個位置之一，不得只寫在散文裡——四次「空等」的實測（#314）＋哪些「等」需要標記的封閉裁決表 |

> **plugin 另有自己的規則目錄。** `plugin/rules/` 隨 plugin 走（plugin 安裝到哪，規則就在哪），
> 由 skill 以相對路徑引用——**不像上表那樣自動注入**。目前一條：
> [`assertions-must-be-measured`](plugin/rules/assertions-must-be-measured.md)，管「寫下一句可能是錯的話
> 之前先回答四個問題」（不是分類法——理由見該檔）。刻意不列進上表：那張表的語意是「自動注入的 repo 規則」，
> 混進去會讓那個性質變成謊話（#407）。
>
> **那條規則有守衛，而守衛有 negative control。** `plugin/tests/`（覆蓋、散文，
> 純 python／bash）與 `plugin/skills/akashic-literal-campaign/scripts/tests/`
> （store-marker parity ＋ hash 表漂移，拿建好的 CLI／Swift 當 oracle）。**支數不寫死**——每輪都在長，而寫死的計數會與目錄分岔（這正是本 repo 反覆記過的形狀）。要知道有幾支就跑 `ls plugin/tests/*.{sh,py} plugin/skills/*/scripts/tests/*.{sh,py}`。
>
> **觸發點已接上，但 2026-08-21 實測：一個都沒在跑**（#407 R8 verify）：
>
> | 觸發點 | 檔案 | 實際執行 |
> |---|---|---|
> | `.githooks/pre-push`（全部） | ✅ | ❌ `core.hooksPath` 指向**主 repo** 的 `.githooks`，那份對這些守衛 0 命中——worktree 的修改不是實際生效的那份。**merge 到 main 後自癒** |
> | `plugin-guards.yml`（ubuntu，1×） | ✅ | ⬜ 從未執行（branch 未 push） |
> | `census-parity.yml`（macOS；只在 census／parity 測試／生成表／oracle 改動時觸發） | ✅ | ❌ macOS runner 帳務擱置——main 最近 8 次 CI run 全部 `failure` 且 **steps=0**（runner 層拒跑） |
>
> **目前唯一實際跑過它們的路徑是本機手動執行。** 這一格寫在這裡，是因為
> 「接上觸發點」與「觸發點會跑」是兩件事，而把後者寫成既成事實正是這條規則要防的
> 那種斷言——它在 R8 verify 被具名。
>
> **pre-push 的耗時分布**（2026-08-22 實測，#407 R26c）：11 支合計 **59.4 秒**，其中
> `marker-parity-mutations.py` 一支 **52.5 秒**（88%），其餘十支合計 7 秒。它慢是有理由的
> ——14 個 mutation × 46 fixture × 真 CLI，每次都在 pristine copy 上跑——但那個理由不要求
> 它在**每次 push** 都跑。
>
> **守衛能否生效的瓶頸不是正確性，是人願不願意等**：59 秒的 pre-push 在頻繁 push 時會被
> `--no-verify` 繞過，那時**所有**守衛等於不存在。
>
> **現在不動它——但上一版把這個裁決寫得像已權衡完畢，那是錯的**（#407 R26f，DA 席指名）。
> 誠實的版本是：
>
> **情境空間是 2×2**（push 方式 × CI 狀態）——上一版（R26h）把它壓成三列，缺了第四種
> （#407 R26j，自己窮舉時找到）：
>
> **實際上是 2×2×2**（push 方式 × CI 狀態 × **hook 是否指向本樹**）——第三個維度是
> #407 R26n 補的，DA 席指名：
>
> **不用「任一」合併**（#407 R26q，DA 席指名——合併偷渡了「CI 恢復與 merge 同步發生」
> 這個沒有依據的耦合。兩者邏輯上互不蘊含：CI 恢復是外部帳務事件，merge 是我的動作）：
>
> | push 方式 | CI 狀態 | hooksPath | 留在 pre-push | 移出、只留 CI |
> |---|---|---|---|---|
> | 正常 `git push` | 不跑（**現況**） | 未設定（他人 clone 的預設） | 零執行 | 零執行 |
> | 正常 `git push` | 不跑（**現況**） | 指向主 repo（**本 worktree 現況**） | **零執行** | 零執行 |
> | 正常 `git push` | 不跑（**現況**） | 指向本樹（merge 後） | **執行** | **零執行** |
> | 正常 `git push` | 恢復 | 未設定 | 零執行 | **執行** |
> | 正常 `git push` | 恢復 | 指向主 repo（**未 merge**） | **零執行** | **執行** |
> | 正常 `git push` | 恢復 | 指向本樹 | 執行 | 執行 |
> | `--no-verify` | 不跑 | 任一（hook 被繞過） | 零執行 | 零執行 |
> | `--no-verify` | 恢復 | 任一（hook 被繞過） | 零執行 | **執行** |
>
> **`--no-verify` 那兩列可以合併**——它繞過 hook 的**執行**，而 hooksPath 只決定 hook
> **檔案的位置**：被跳過時，檔案在哪都一樣。**這是有理由的合併，不是「任一」的省略。**
>
> **合併的條件**（#407 R26r→R26t→R26v→R26w，改了四次，每次修完都露出下一層歧義）：
>
> > **在該列所討論的那個具體值下，被合併的維度對每一個結果欄都不影響。**
>
> 三個限定各修掉一層：**「那個具體值」**（不是該維度的所有值，#407 R26w）、
> **「每一個結果欄」**（不是任一欄，R26v）、**「不影響結果」**（不是「兩維度彼此
> 獨立」，R26t）。
>
> **前提：被合併的維度不是選的，是算出來的**（#407 R26y）。它是**你所要收攏的那組格
> 裡唯一變動的那一維**；其餘各維在該組格裡取同一個值，那些值就是錨點。所以「哪一維
> 當錨點」沒有自由度——**就這一個歧義而言**，判準句不必再加第四個限定，缺的是這個
> 前提。（不主張判準自此完備：這一段已經改過五次，每次都是修完才露出下一層。）
>
> **這一格是 requirements 席的探針找到的，但它的結論相反**：該席主張同一組維度換個
> 錨點會得到相反判定（`--no-verify` × hooksPath，一讀 ✅、一讀 ❌）。**實測那兩讀
> 收攏的是不相交的兩組格**（`{(--no-verify,不跑,*)}` vs
> `{(*,恢復,本樹)}`，交集為空）——是**兩個不同的 merge**，不是同一個 merge 的兩種
> 讀法。判準對不同的問題給不同的答案，是它該做的事。
>
> **而變動 ≥2 維的一組格根本收攏不了**：實測取 `(正常,不跑,本樹)` 與
> `(--no-verify,恢復,本樹)`，收攏後只能寫成 `| 任一 | 任一 | 本樹 |`，那一列字面
> 涵蓋 4 格、其中 **2 格從未檢查**，且 4 格的結果**兩兩不同**——那一列會說謊。
>
> **這個形狀在本檔的歷史裡零實例**（上一版寫「這正是 R26q 拆掉的那個合併的形狀」，
> **實測為假**）。R26q 拆掉的是 `| 正常 | 恢復 | 任一 | 執行 | 執行 |`——「任一」只在
> hooksPath 一欄，**變動 1 維**、形狀合法；它的病是那三格的「留」欄不一致
> （零執行／零執行／執行），也就是 **R26v 那一層**（每一個結果欄），不是本段這一層。
> （那一列連摘要值都錯：三格裡兩格是零執行。）**寫一個零實例的前提**，理由是不寫的話
> 讀者會以為「哪一維當錨點」可以挑——而挑得動正是本輪 finding 的整個立論。
>
> **量詞那一層最尖**：`--no-verify` 那列在「該維度**所有**值」的讀法下**應該不可合併**
> ——不帶旗標時 hooksPath 決定一切——而那與下表自己給它的 ✅ 矛盾。**示範列自己是
> 有爭議的案例**，直到量詞被寫出來為止（DA 席指名）。
>
> | 案例 | 兩維度彼此獨立？ | 一方的值讓另一方**對結果**無關？ | 可合併？ |
> |---|---|---|---|
> | `--no-verify` × hooksPath | 是 | **是**（跳過執行 ⇒ 檔案在哪無關） | ✅ |
> | 「CI 恢復」× hooksPath | 是（外部帳務 vs 我的 merge） | **否**（兩者都影響結果） | ❌ R26q 拆掉 |
> | push 方式 × CI 狀態 | 是 | **否**（兩者都影響結果） | ❌ |
>
> **第一欄三個都是「是」，所以它區分不了**——用它會把後兩列誤判成可合併。判準必須是
> 第二欄：**合併是在主張「這一欄在這些列裡不影響結果」**，那是一個需要理由的斷言，
> 不是省略。
>
> **「結果」指的是所有結果欄，不是任一欄**（#407 R26v——拿判準測它沒提到的案例時
> 才浮出來的殘留歧義）。這張表有**兩個**結果欄（留／移出），而
> 「CI 恢復 × hooksPath」正好在中間：
>
> | 固定 CI=恢復，變動 hooksPath | 留在 pre-push | 移出 |
> |---|---|---|
> | 未設定 | 零執行 | 執行 |
> | 指向主 repo（未 merge） | 零執行 | 執行 |
> | 指向本樹 | **執行** | 執行 |
>
> **「移出」欄一致、「留」欄不一致**——讀成「任一欄無關即可合併」就會合併掉一個有
> 差異的格，而**那正是 R26q 拆掉的那個合併當初的樣子**（它是因為「移出」欄看起來
> 一致而被合併的）。所以：**每一個結果欄都要無關，才可以合併。**
>
> **兩個先前被合併掩蓋的格**：CI 恢復 ＋ 未 merge 時，**留在 pre-push 是零執行而移出是
> 執行**——那時「移出」不只等價，是**嚴格更好**。而 `--no-verify` ＋ CI 恢復時，
> **移出才有執行**。
>
> **`hooksPath` 有三個值，不是兩個**（#407 R26p，窮欲第四維時找到）：
>
> - **未設定** — `core.hooksPath` 是 `.git/config` 的 **local** 設定，**不隨 clone 傳遞**。
>   任何新 clone 的人 pre-push **完全不跑**，而且**不需要主動繞過**。這是現行狀態下
>   **最常見的零執行路徑**。
> - **指向主 repo** — 本 worktree 此刻的狀態：`/Users/che/Developer/Akashic-Library/.githooks`，
>   那份對本輪守衛**命中 0**（實測 `grep -c 'measured-claims-audit\|trigger-coverage'` → 0，
>   本 worktree 的那份是 3）。
> - **指向本樹** — merge 到 main 後自癒。
>
> **前兩個值下（且 CI 不跑時），留與不留沒有差別。**——上一版寫「在 merge 之前，留與
> 不留沒有差別」而**沒加 CI 條件**，與表格「CI 恢復 ＋ 未 merge」那格的內容矛盾
> （#407 R26q）。
>
> **窮舉過的其他候選（都不是維度）**：push 目標（只有一個 remote）、hook 檔的執行權限
> （git 不要求 `+x`，且實測已是 `-rwxr-xr-x`）。
>
> **「留著提供預設保護」只在第二列成立**（merge 後、CI 仍不跑）。上一版把那一列的結論
> 推廣到「正常 push」整體——**與 R26f／R26m 精確同型的第三次**：都是把某一格的結論
> 推廣成整欄，而**這次被忽略的前提就寫在本檔上方**（觸發點表第 1 格）。
>
> **而 macOS 恢復後（下半兩列），兩個選項在兩種 push 方式下都等價**——那時「移出」是純
> 效益：pre-push 從 59 秒降到 7 秒，而 7 秒的 hook 沒人想繞過。
>
> **上一版這裡寫「全部四種情境下等價」**（#407 R26m，DA 席指名）：「macOS 恢復後」已經把
> CI 維度釘死，只剩 push 方式一個自由維度＝**2 格**，說「四種」在計數上就錯；而照字面讀，
> 上面兩段自己承認的 Row 1（正常 push × 不跑）正是**不等價**的那格。**這是 R26h 剛修過的
> 同一個錯**——把條件限定的結論推廣到全部情境，三輪內第二次，且發生在修完它的同一段裡。
>
> **這兩列正是決定的關鍵，而三列版看不到它們**，因為它把「CI 恢復」寫成單一列，掩蓋了那個
> 條件**對兩個維度同時起作用**。
>
> **仍然待解的是現況的下半**：`--no-verify` ＋ macOS 不跑 ＝ 兩者都歸零，而 59 秒的
> pre-push 正是讓人想按那個開關的原因。留著不是沒有代價。
>
> **它為什麼不能掛在會跑的 ubuntu workflow 上**：`marker-parity-mutations.py` 要真的
> `akashic` binary 當 oracle（`store-marker-parity.sh` 找不到就 `exit 2`），而那需要
> `swift build`——所以它只能在 macOS。
>
> **與 `--no-verify` 無關的遠端強制點目前不存在**：branch protection 的 required status
> checks 在這個 repo **結構上不可用**——重跑指令與當次輸出：
>
> ```
> $ gh api repos/PsychQuant/Akashic-Library/branches/main/protection
> {"message":"Upgrade to GitHub Pro or make this repository public to enable this
>  feature.","status":"403"}                                    # 2026-08-23 觀察
> ```
>
> **所以這是待解，不是已權衡完畢。** 兩條可能的出路（都未做）：(a) macOS runner 恢復後
> 把它移出 pre-push、只留 CI；(b) repo 轉公開或升級方案後加 required status check。
>
> **上表的「已接上」那一欄現在有守衛在量**（`plugin/tests/trigger-coverage.py`，
> #407 R19）。它問的不是聯集而是**逐對**：對每個受保護檔案 × 每個讀它的守衛，
> 是否存在一個 workflow 同時在該檔改動時觸發、且執行該守衛。判準取自
> `census-parity.yml` 自己的檔頭——「兩者合起來涵蓋五支」在檔案集合的聯集意義上
> 成立，在任一次變更的意義上不成立，而後者才是觸發點要保證的事。當下實測**零缺口**，
> pre-push 涵蓋全部。**右欄（「實際執行」）它量不到**——那需要 CI 真的跑起來，
> 而那三格的狀態如上。
>
> **`ci.yml` 的 `paths-ignore` 仍排除 `plugin/**`**——理由已從「plugin 沒有測試
> 讀取」換成純計費（macOS runner 10×）。它另有一個 parity step，但那是第二層：
> 它的觸發是 push-to-main ＋ 該 paths-ignore，所以**只改 census 時它反而被跳過**
> ——`census-parity.yml` 補的正是那一格（#407 R7 verify：守衛的觸發條件與它保護
> 的檔案剛好互斥）。
>
> 兩支 negative control 各自證明對應的守衛會紅，並且**mutate 一份 copy 而不是
> 出貨檔**：前一版就地改寫版控中的檔案，跨模型審查在審查期間實際觀察到 tracked
> 的 `literal-census.sh` 出現三種被注入的狀態（#407 R6）。
