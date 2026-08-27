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
> | ~~`plugin-guards.yml`（ubuntu，1×）~~ | **已刪除** | 2026-08-27（#435）——見下 |
> | `census-parity.yml`（macOS；現在也涵蓋 `plugin/**` 與原 ubuntu 那份的全部 paths） | ✅ | ❌ **帳號層付款失效**（見下）——run 全部 `failure` 且 **steps=0**（runner 層拒跑） |
>
> **`plugin-guards.yml` 已於 2026-08-27 刪除**（#435）：它跑在 ubuntu（1× 計費），
> 設計理由是「純 python／bash 的守衛不必點 10× 的 macOS runner」。**守衛遷成 Swift 之後
> （#433）那個理由不再成立**——`run-guards.sh` 需要 `swift build`，而 ubuntu runner 沒有
> toolchain，那個 workflow 必然失敗。兩者當時跑的已經是**同一個命令**
> （`bash .githooks/run-guards.sh`），差別只在 paths。
>
> 留著一個必然失敗的 workflow 比沒有它更糟：它會訓練人忽略紅燈。paths 合併進
> `census-parity.yml`，`trigger-coverage` 驗證覆蓋仍完整（**35/35、零缺口、workflow 2 份**
> ——那是本機證據）。
>
> **代價**：所有 plugin 改動現在都點 10× 的 macOS runner。2026-08 兩度把免費額度燒光正是
> 這個形狀，所以這不是零成本的決定——但它是必然的，除非在 ubuntu 裝 Swift toolchain
> （#435 記著兩個候選，兩者都無法在 CI 恢復前驗證）。
>
> **「macOS runner 帳務擱置」這個說法在 2026-08-26 被更正——範圍與原因都寫窄了。**
> 逐字的原因取自 check-run annotation（`gh api /repos/<r>/check-runs/<jobId>/annotations`）：
>
> > The job was not started because recent account payments have failed or your
> > spending limit needs to be increased. Please check the 'Billing & plans'
> > section in your settings
>
> **不是 macOS-only、也不是分鐘數用完**：ubuntu 的 `plugin-guards.yml` 同樣 `steps=0`，
> 而 2026-08 全帳號 Actions 用量只有 6 分鐘（且 Akashic-Library **從未計費過**——
> runner 沒啟動就不計費）。最可能的失敗款項是 **Git LFS 儲存 10.2 GB vs 免費額度 1 GB**
> （2026-05 產生 $0.70 淨額，是唯一一筆真的要付錢的）。
>
> **診斷路徑值得記**：`gh run view --log-failed` 回「log not found」（沒跑就沒有 log），
> `gh run list` 只說 `failure`。真正的訊息在 **check-run 的 annotation** 裡——
> 那是唯一說得出原因的地方。中途我曾因「其他 repo 在 6/7 月有用量」而推翻帳號層假設，
> 那個推翻是錯的：那些用量在付款失效**之前**。
>
> 修法在使用者的網頁端（Settings → Billing & plans），不在這個 repo 裡。
>
> **左欄「已接上」現在是逐對意義的完整**（2026-08-23 實測，#407 R45b）：
> `trigger-coverage.py` 對 **22 個受保護檔全部報「CI 未覆蓋 0」**——每一對
> (受保護檔 × 讀它的守衛) 都存在一個 workflow 同時在該檔改動時觸發、且執行該守衛。
> 這比本表原先的狀態強：先前有數格只靠 pre-push 兜住。
>
> **右欄沒有跟著變。** 上表三格的「實際執行」仍如上：hooksPath 指向主 repo（merge 後
> 自癒）、ubuntu 從未執行（branch 未 push）、macOS 帳務擱置。**「每一對都有 workflow
> 會跑它」與「那些 workflow 跑得起來」是兩件事**——而這正是本段一開始就在說的那件事，
> 只是換了一層：先前的落差在「有沒有接上」，現在的落差只剩「跑不跑得起來」。
>
> **目前唯一實際跑過它們的路徑是本機手動執行**（含端到端 `bash .githooks/pre-push`，
> 2026-08-23 實測 exit=0、339 秒）。這一格寫在這裡，是因為
> 「接上觸發點」與「觸發點會跑」是兩件事，而把後者寫成既成事實正是這條規則要防的
> 那種斷言——它在 R8 verify 被具名。
>
> **pre-push 的耗時分布**（2026-08-23 重量，#407 R29——上一版的數字全部過期，
> 而且其中一句是**假的**）：
>
> | | 2026-08-22 | 2026-08-23 早 | 2026-08-23 晚 | 2026-08-23 深夜（競爭下） | 2026-08-23 深夜（乾淨） | **2026-08-27（乾淨，現行）** |
> |---|---|---|---|---|---|---|
> | 守衛支數與總時 | 11 支 59.4 秒 | 13 支 66.5 秒 | 15 支 77.1 秒 | 19 支 99.6 秒 | 20 支 149.3 秒 | **21 支 121.1 秒** |
> | 最大一支 | `marker-parity-mutations.py` 52.5 秒（88%） | 57.2 秒（86%） | 57.3 秒（74%） | 69.4 秒（70%） | 91.9 秒（62%） | **62.2 秒（51%）** |
> | 其餘 | 十支 7 秒 | 12 支 9.3 秒 | 14 支 19.8 秒 | 18 支 30.2 秒 | 19 支 57.4 秒 | **20 支 58.8 秒** |
> | **整個 pre-push** | 「59 秒」 | ≈252 秒 | 端到端實測 337 秒 | 端到端 778 秒 | 端到端 595 秒（#407 R67k） | 未重量 |
>
> **第六欄在同一個 session 內量了兩次，兩個數字都真**（2026-08-27）：先量到
> **99.5 秒**，把 `trigger-coverage` 的負控改成**兩版並驗**（每個 case 同時跑
> Python 與 Swift 並要求輸出逐字相同）之後是 **121.1 秒**。差額 21.6 秒是換到
> 「Swift 版**有**負控」的代價——在此之前 runner 跑 Swift 而負控驗 Python，
> 那個缺口兩邊都是綠的。表上寫現行配置；**不要拿 121 減 21.6 當成「退化」**。
>
> 這張表在同一個 session 內過期一次，與它下面記過的「同一天內就過期了一次」同型
> ——而那正是它保留全部欄位而非只留最新一欄的理由。
>
> **第六欄多一支守衛卻快了 50 秒，原因具名**（2026-08-27，#433／#431）：兩支負控
> harness 的 `with_copy()` 都在複製整個 `.claude`——**2.0 GB／25,519 個檔**，其中
> `.claude/worktrees/` 佔 2.0 GB（IDD 的隔離工作樹），而守衛要的只有 144 KB 的規則檔
> （private repo，外部讀者取不到）。單次 `copytree` **16.51 秒 → 0.07 秒**。
> `oracle-precondition-control.py`（它 import 前者並多次呼叫 `with_copy`）**5 分 44 秒
> → 8.2 秒**。同輪另修 Swift 版守衛的 `globFiles()`（天真地 enumerate 整個 repo root，
> 同樣為那 2 GB 付錢）。
>
> **這件事全程綠燈**——兩支 harness 慢了十倍而從未報錯，而本節自己下面就寫著
> 「四分鐘的 pre-push 在頻繁 push 時會被 `--no-verify` 繞過，那時**所有**守衛等於
> 不存在」。慢是這條規則的失效路徑，不是效能潔癖。
>
> **最後一列刻意寫「未重量」而不是沿用 595**（本表自己的紀律：寫出條件而不是只寫
> 數字）。守衛那一段快了 50 秒，但 `swift test` 佔 pre-push 的大頭且本輪沒重量，
> 拿 595 減 50 是推論不是量測——而那正是本表第四欄的註記在防的那個動作。

> **第五欄（競爭下）的兩個數字與其餘各欄不可直接相比**（#407 R67f）：量測當時有一個
> 21-agent 的跨模型審查 workflow 在同一台機器上跑。留著它是因為刪掉會讓「778」這個
> 曾經被寫進本檔的數字失去脈絡；**寫出條件而不是只寫數字**正是本 issue 要求的事。
>
> **最後一欄是乾淨環境重量**（`bash .githooks/pre-push`，rc=0，無其他重負載）。
> 它比「337 秒」那一欄多出來的部分有具名的來源：新增 5 支守衛、`audit-guards-mutations`
> 因 R67j 的逐守衛 baseline 驗證從 16.7 → 30.6 秒、`marker-parity-mutations` 本身也
> 隨 fixture 成長。**不要拿 595 減 337 當成「退化」**——中間隔著 5 支新守衛與一個
> 新的自檢層。
>
> **上面那格先前寫「≈263 秒」，那是分項相加、不是端到端實測**（#407 R41）。第一次
> 真的整支跑（`bash .githooks/pre-push …`）量到 **337 秒**，且該次 `Tests/` 剛被改過
> 因而含一次重編；分項相加是 3.1 ＋ 182.7 ＋ 77.1 ＝ **263 秒**，可視為未重編時的下界。
> 兩個數字都真、量的不是同一件事——**先前只有一個數字而它被標成「整個 pre-push」**。
>
> **這張表在同一天內就過期了一次**（#407 R37）：R29 量完之後又加了兩支守衛
> （`audit-guards-mutations.py` 10.4 秒、`measured-numbers-audit.py` 0.03 秒），於是
> 「13 支 66.5 秒」立刻不成立。**這正是 R36 那支守衛在管的形狀，而它管不到 CLAUDE.md**
> ——它只掃 `.claude/rules/` 與 `plugin/rules/`。記在這裡，不擴充它的範圍：擴進來的話
> 這張表**每次加守衛都會擋 push**，而那個摩擦沒有對應的好處（表本來就該跟著改）。
>
> **「59 秒的 pre-push」是假的**：那個數字只涵蓋守衛。同一個 hook 還跑
> `swift build`（3.1 秒，暖狀態）與 `swift test`（**182.7 秒**）——後者一支就佔整個
> hook 的 **72%**，是那支 57 秒守衛的三倍。上一版量了守衛就把總和寫成 pre-push 的耗時，
> **一個真的量測被用來支撐一個那個量測沒問的性質**（`assertions-must-be-measured` §2 的
> 判準，這次踩在它自己記過的形狀上）。
>
> **後果是裁決的方向也要改**：把那支守衛移出 CI，hook 從 **263 → 205 秒（−22%）**，
> 不是先前寫的「59 → 7 秒（−88%）」。它**不是** pre-push 慢的原因；`swift test` 才是。
>
> 它慢是有理由的——14 個 mutation × 46 fixture × 真 CLI，每次都在 pristine copy 上跑
> ——但那個理由不要求它在**每次 push** 都跑。
>
> **守衛能否生效的瓶頸不是正確性，是人願不願意等**：**四分鐘**的 pre-push 在頻繁 push 時
> 會被 `--no-verify` 繞過，那時**所有**守衛等於不存在。而移出這一支只把四分鐘變成三分十五
> ——**壓力仍在**。
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
> | 正常 `git push` | 不跑 | 未設定 | 零執行 | 零執行 |
> | 正常 `git push` | 不跑 | 指向主 repo | **零執行** | 零執行 |
> | 正常 `git push` | 不跑 | 指向本樹 | **執行** | **零執行** |
> | 正常 `git push` | 恢復 | 未設定 | 零執行 | **執行** |
> | 正常 `git push` | 恢復 | 指向主 repo | **零執行** | **執行** |
> | 正常 `git push` | 恢復 | 指向本樹 | 執行 | 執行 |
> | `--no-verify` | 不跑 | 任一 | 零執行 | 零執行 |
> | `--no-verify` | 恢復 | 任一 | 零執行 | **執行** |
>
> **表格的格只放封閉詞彙的 token，註記一律在散文裡**（#407 R30，跨模型審查指名的
> 失效讓這條從慣例升成規則）。先前每個格都帶括號註記（`不跑（**現況**）`、
> `指向本樹（merge 後）`…），而那六個註記**逐一對照後全部可從下方散文還原**——
> 它們是第二份副本。於是有一種安靜的失效：只改註記（「未 merge」→「已 merge」）
> 而不動 token 與結果欄，守衛照樣全綠，人卻會照註記把那一列讀成另一個值。
>
> **兩個猜關鍵字的檢查都被實測否掉**：「註記含本欄其他值的 token」對現行 8 列誤傷 0
> 卻**抓不到**那個情境（註記寫「已 merge」而非「指向本樹」）；「hooksPath 註記含
> `merge`」抓得到形狀卻**誤傷 2 列**（「merge 後」與「未 merge」都合法）。所以不寫
> 檢查——**改成讓那個矛盾寫不出來**：格裡出現 `（` 即 `<未解析>`，守衛出聲。
> 這是 `entity-backlink-completeness` 引 3.325 的同一個立場。
>
> **現況是第 2 列**（正常 push × CI 不跑 × hooksPath 指向主 repo；2026-08-23 實測
> `core.hooksPath` 指向 `/Users/che/Developer/Akashic-Library/.githooks`、main 最近三次
> CI 皆 `failure`）。**目標是第 6 列**（正常 push × CI 恢復 × 指向本樹）——merge 之後
> hooksPath 自癒，macOS 帳務恢復後 CI 跟上，那時兩個選項在執行上等價。各 hooksPath 值
> 的意義見下方三點。
>
> **「目標是第 6 列」這句話是被審查逼出來的**（#407 R31）：R30 說「六個註記全部可從
> 散文還原」——**對那六個為真，但它證不到「格層級的資訊一律不會失去」**。跨模型審查
> 指出一個對稱的註記：`執行（**目標**）`。實測整段只有一句指認現況（就是上一句），
> **沒有任何句子指認目標**。所以註記禁令的代價是實的：**你得自己寫一句散文**——本段
> 就是那一句。代價可接受（散文是單一來源），但不能說成零。
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
> **前提：判準要在「那一列字面涵蓋的全部格」上評，不是在你手上那幾格上評**
> （#407 R26y，本段自己改過兩次——初版說的是別的東西，見第 3 點）。一列合併後涵蓋的格
> ＝**各維取值集合的笛卡兒積**；「每一個結果欄都不影響」要對這整組成立。
>
> **這個公式對退化情形是 total 的**（#407 R26z，DA 席指名的邊界）：零維變動的一組格
> （單格、或重複的同一格）笛卡兒涵蓋就是它自己，結果必然一致，判準說「可合併」而合併
> 後那一列**等於原本那一列**——不產生任何假陳述。前一版把前提寫成「唯一變動的那一維」，
> 那個寫法在零維變動時無定義；換成涵蓋集合之後這一格自動閉合，不需要額外的排除條款。
>
> 這一句同時解掉三件事：
>
> 1. **本輪 finding 的立論不成立。** 該席主張同一組維度換個錨點會得到相反判定
>    （`--no-verify` × hooksPath，一讀 ✅、一讀 ❌）。**實測那兩讀收攏的是不相交的兩組格**
>    （`{(--no-verify,不跑,*)}` vs `{(*,恢復,本樹)}`，交集為空）——是**兩個不同的 merge**，
>    各有各的涵蓋集合。判準對不同的問題給不同的答案，是它該做的事。
> 2. **R26q 那次錯在哪，現在說得出來。** 它拆掉的是 `| 正常 | 恢復 | 任一 | 執行 | 執行 |`，
>    涵蓋 3 格而「留」欄是零執行／零執行／執行——不一致。（那一列連摘要值都錯：三格裡
>    兩格是零執行。）
> 3. **本表只做單維合併，但那是選擇不是必然。** 上一版寫「變動 ≥2 維的一組格根本收攏
>    不了」，**實測為假**：窮舉出 **14 個**變動 ≥2 維而涵蓋集合結果一致、因此不說謊的
>    row-set，最小的是 `(正常,不跑,未設定)` 與 `(--no-verify,不跑,主repo)`（涵蓋 4 格
>    全是零執行／零執行）。同一版還寫「這正是 R26q 的形狀」，**也為假**——R26q 那列的
>    「任一」只在 hooksPath 一欄，變動 1 維、形狀合法。真正的代價是：那一列宣稱 4 格而
>    你只檢查了 2 格，**多出來的是推論不是量測**，而 R26q 正是同型推論為假的實例。
>    本表因此只做單維合併；那個限制下「被合併的維度」唯一確定（就是那一維），錨點無從挑。
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
> **窮舉過的其他候選**（#407 R27 補兩項——前一版寫「都不是維度」而漏了它們，
> 兩項都由跨模型審查在攻**模型**而非攻散文時找到）：
>
> | 候選 | 是不是維度 | 裁決 |
> |---|---|---|
> | push 目標 | 否 | 只有一個 remote |
> | hook 檔的執行權限 | 否 | git 不要求 `+x`，且實測已是 `-rwxr-xr-x` |
> | **這次 push 有沒有動到受保護檔案** | **是** | **真的第四維，刻意不加**。`census-parity.yml` 是 path-scoped（實測 `paths:` 列出 census／生成表／`tests/**`／`StoreVersion.swift`），而 pre-push 對**每一次** push 都跑。新增的 12 格全部可判定：不動到時「移出」零執行**但也無事可查**（trigger-coverage 實測零缺口即此背書），「留」則是純浪費 52 秒。加它會讓表變 24 列而不翻轉任何裁決，只把「移出」的優勢再放大 |
> | **遠端有沒有強制點** | **否，但它是裁決意義的前提** | 它不改變任一格的執行／零執行，卻決定那個「執行」有沒有後果。見下方對「純效益」的更正 |
>
> **所以「移出」欄的正確讀法是「一次會動到受保護檔案的 push」**——上一版的表沒寫出這個
> 隱含範圍，於是「移出＝執行 ⟺ CI 恢復」漏掉了 path 條件。
>
> **「留著提供預設保護」只在第二列成立**（merge 後、CI 仍不跑）。上一版把那一列的結論
> 推廣到「正常 push」整體——**與 R26f／R26m 精確同型的第三次**：都是把某一格的結論
> 推廣成整欄，而**這次被忽略的前提就寫在本檔上方**（觸發點表第 1 格）。
>
> **而 macOS 恢復後（下半兩列），兩個選項在兩種 push 方式下都等價**（就**執行**而言）。
>
> **但「移出是純效益」是過度斷言**（#407 R27，跨模型審查指名）。執行不等於有後果，
> 而兩邊的後果不同：
>
> | | 守衛紅了會怎樣 | 實測依據 |
> |---|---|---|
> | 留在 pre-push | **中止這次 push** | `.githooks/pre-push` 是 `set -eo pipefail`，非零 exit 讓 git 放棄推送 |
> | 移出、只留 CI | **只回報，擋不住任何東西** | required status check 在本 repo 結構上不可用——`gh api …/branches/main/protection` → 403「Upgrade to GitHub Pro or make this repository public」（2026-08-23 重跑仍是） |
>
> 所以「移出」換到的是速度（實測 263 → 205 秒，−22%；**不是**更早版本寫的
> 59 → 7 秒），付出的是**阻擋力**。而阻擋力目前只存在於
> **一格**：正常 push × hooksPath 指向本樹。這個 trade-off 在三個欄位裡看不到，因為那
> 三欄量的是「跑不跑」不是「擋不擋」——**這正是上一版把它讀成純效益的原因**。
>
> **上一版這裡寫「全部四種情境下等價」**（#407 R26m，DA 席指名）：「macOS 恢復後」已經把
> CI 維度釘死，只剩 push 方式一個自由維度＝**2 格**，說「四種」在計數上就錯；而照字面讀，
> 上面兩段自己承認的 Row 1（正常 push × 不跑）正是**不等價**的那格。**這是 R26h 剛修過的
> 同一個錯**——把條件限定的結論推廣到全部情境，三輪內第二次，且發生在修完它的同一段裡。
>
> **這兩列正是決定的關鍵，而三列版看不到它們**，因為它把「CI 恢復」寫成單一列，掩蓋了那個
> 條件**對兩個維度同時起作用**。
>
> **仍然待解的是現況的下半**：`--no-verify` ＋ macOS 不跑 ＝ 兩者都歸零，而**四分鐘**的
> pre-push 正是讓人想按那個開關的原因。留著不是沒有代價——但移出這一支也解不掉那個原因
> （見上方耗時表：`swift test` 佔 72%）。
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
