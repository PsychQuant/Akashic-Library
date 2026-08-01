# Store YAML 輸入 profile — 設計

**日期**：2026-08-01
**狀態**：設計定案，待實作（實作 gated on PR #25 merge）
**動機來源**：#23（v1.3 tolerant-preserve）R1–R11 的守衛增生
**相關**：#24（version marker）、#26（known 層演化語意）、#31（可見性完整度）

---

## 1. 問題

`Sources/AkashicCore/YAML.swift` 從 211 行長到 1000+ 行（本 spec 撰寫時 958，R9–R11 後續增長），
其中 #23 一個 issue 貢獻了 +670 行以上（328 → 1000+，+200%），而**這 630 行沒有一行是新功能** —— 全部是為了「舊
binary 讀新 store 不要爆炸」這個相容性需求，去對抗 YAML 規格本身的表面積。

十一輪 verify 的 findings 幾乎全落在 YAML 語法邊界，與文獻管理領域無關：

| 輪次 | 打的是什麼 |
|------|-----------|
| R2 | raw-text 保留載體（毀檔） |
| R3 | 區塊切分錯位家族 |
| R4 | 行尾守衛（LS/PS/CR 全文掃描） |
| R5 | 語意 canary 不變式、known shape 靜默剝除 |
| R6 | 行尾守衛限縮到 CR、`strictString` → `scalarString` |
| R7 | 平移不變式、NEL 回歸守衛、closed-shape tagged-shadow |
| R8 | 毀字守衛全檔化、null-as-absent、`fields`/`attachments` 鍵層 guard |
| R9 | null-as-absent 限縮 collection、`fields` 鍵 core-tag、CR 判別式 |
| R10 | CR 判別式回歸 R8 保護、`fields` 鍵閉集、importZotero rebuild 收容 |
| R11 | merge/value 改判 tag、complex key 在 compose 前擋、`fields` 字串面 fail-closed |

根因是一個結構性的不對稱：

> **寫入端只產生 YAML 的一個小子集，讀取端卻必須接受整個 YAML 規格。**

讀取端之所以要接受全規格，是因為 #23 的前提就是「檔案可能由別的 binary、別人、
Dropbox 同步寫進來」。於是每一個 YAML 的冷僻角落都變成必須處理的輸入。

同專案的 config 層（[phase4c design](2026-07-30-akashic-phase4c-multifile-design.md)
的 config parser 段）已經對同一個問題做過退卻：config parser 是 hand-rolled
**平面 subset**，明文「不支援多行字串、anchor/alias、巢狀超過一層、flow style」，
並要求「請用 `akashic file` 指令維護而非手寫進階 YAML」。entry/person 層還沒做
同樣的退卻，而且踩得更深 —— 因為它有跨 binary 相容性需求。

## 2. 現況證據（實測，非推估）

對真實 library 的 **536 個 YAML 檔**掃描（`entries/` + `people/`），並以真正的 YAML
parser 取 ground truth（不只 regex）：

| 特徵 | 命中檔數 |
|------|---------|
| anchor / alias（parser 事件層確認） | **0** |
| 非標準 tag（parser 事件層確認） | **0** |
| BOM / NEL / LS / PS / tab / CR | **0** |
| 註解行 / multi-doc `---` / block scalar `\|` `>` / flow style | **0** |
| 巢狀深度 | 僅 1–2 層 |

初掃的 13 個 anchor/alias「命中」與 3 個 inline-comment「命中」**全部是 regex 的
false positive**：前者是期刊名裡的 `&amp;`（`Sociological Methods &amp; Research`）
與引號內的 PsycINFO 關鍵字標記（`'*Achievement *Mind ...'`），後者是摘要裡的
`Harvard Book List (edited) 1938 #162` —— emitter 已把含 ` #` 的值 quote 起來，
parser 完整保留，無資料損失。

**結論：真實 corpus 的遷移成本為零。**

附帶更正一個常被引用的 YAML-over-JSON 論點：536 個檔案裡**一行註解都沒有**。
§5 的註解歸屬保留機制目前保護的是一個實際上沒被使用的能力。

## 3. 非目標

- **不換序列化格式**。ADR 3（metadata 檔案化、git-first）要的可讀 diff 與手改友善
  依然成立；換 JSON 是拿決策層的價值換實作層的方便。
- **不在本次拆除既有守衛**。本 spec 只加 gate（止血）；拆除是後續獨立 issue（§8）。
- **不實作 #24**。store 端的 version marker 與 refuse-if-newer 仍由 #24 承載。
  本 profile 與之互補：profile 約束**語法**，#24 約束**版本**。

## 4. Profile 定義（normative）

**Store YAML profile**：下列語法為 profile 外，其餘 YAML 語法照舊放行。

> **profile 不自帶版本號（刻意）**：profile 是 store 格式版本的一個**性質**，不是獨立的
> 版本軸。它隨引入它的那個 store 格式版本走（本 spec 落地時是 v1.4 或後續版本，視 #25
> merge 後的編號而定）。
>
> 理由：獨立版本號現在沒有任何消費者——沒有東西讀它、沒有東西依它做決定。而 store 端的
> version marker 本來就由 #24 承載；再立一條軸只會讓「舊 binary 讀新檔的行為由哪一條
> 版本決定」變成沒有答案的問題。profile 若要不相容地收緊（例如未來禁 block scalar），
> 那就是一次 store 格式版本 bump，由 #24 的 marker 標示——**一條軸，一個 marker**。

| 禁止 | 對應的實際失敗 |
|------|--------------|
| anchor `&x` / alias `*x` | 展開放大（R8 verify F4 的 20× CPU；billion-laughs 的唯一來源） |
| explicit tag `!x` / `!!x` | tagged-shadow（R8 cross-model lens 的 CRITICAL；R7 的 `keyStrings` 守衛） |
| merge key `<<:` | 隱式繼承使「未知 key」不再是局部性質。**判準必須是 tag 不是鍵名字串**（R11：`!!merge foo:` 的字串面是 `foo`） |
| ~~顯式 complex key `? key`~~（R11 加、**R12 移除**） | 見 §5.3——文字層判不到。真正要禁的是 **anchor/alias 本身**（已在第一列），alias 落在 key 位置只是它的一個後果 |
| BOM（U+FEFF 開頭） | 現行為靜默剝除（`stripLeadingBOM`），改為拒收 |
| CR / CRLF / NEL(U+0085) / LS(U+2028) / PS(U+2029) | 行尾家族（R4→R6→R7 三輪震盪） |

**明確放行**（與「緊 profile」方案的差異，刻意保留未來演化空間）：

- block scalar `|` / `>`（長摘要、notes 的自然寫法）
- flow style `[a, b]` / `{k: v}`
- 任意巢狀深度
- 任意 plain scalar 內容（含 `&amp;`、`*text*`、` #` 等字面字元）

### 4.1 選擇「寬」而非「緊」的代價（誠實記載）

被放棄的**緊 profile**是：在上表之外**額外禁** block scalar `|` `>`、flow style
`[a, b]`、以及巢狀深度上限（3 層）——亦即只允許 block style、平面 scalar、引號字串。
真實 corpus 完全落在這個更小的子集內（實測 0 命中 block scalar / flow style，深度僅
1–2 層），所以緊 profile 同樣是零遷移成本。

差別在**未來**：緊 profile 下要存長文字（notes、長摘要）只能用引號字串，不能用
`|` 多行寫法。

代價是可拆的守衛顯著變少。`scalarString`、`splitBlocks`、`verifyBlockOracle` 這一整組
raw-text 機械在寬 profile 下**拆不掉**（block scalar 與任意深度仍放行），緊 profile 下
可以整組退場：

| | 寬 profile（本 spec 採用） | 緊 profile（放棄） |
|---|---|---|
| `YAML.swift` 預估 | 958 → 約 800 | 958 → 450–550 |
| 長文字寫法 | `\|` block scalar 可用 | 只能引號字串 |
| raw-text 機械 | 保留 | 可整組退場 |

換得的是：未來要存長文字時不必回頭改 profile。這是刻意的取捨。

## 5. Gate 機制

```
profileGate(text) throws
├─ Tier 0  文字層，無條件拒（**必須在 compose 之前**）
│    BOM / CR / NEL / LS / PS                    → violation
│
├─ Tier 1  存在性前濾 — O(n)
│    文字中不含 & 且不含 * 且不含 ! 且不含 "<<"
│    → 放行（實測 523/536 走此路）
│
└─ Tier 2  僅對含上述 byte 的檔（實測 13/536）
     Yams.compose(text)          ← 安全：COW 共享，不展開
     guarded walk（沿用現有 200k 預算）：
       node.anchor != nil               → violation(.anchor)
       node.tag 為 explicit 非標準       → violation(.tag)
       mapping key == "<<"              → violation(.mergeKey)
```

### 5.1 為什麼 Tier 1 是 sound 的

YAML 規格要求：anchor 必須寫 `&`、alias 必須寫 `*`、explicit tag 必須寫 `!`、
merge key 必須寫 `<<`。這四個字元序列一個都不出現 ⇒ 這四種語法一個都不可能存在。

**無 false negative**，只有 false positive（`&amp;` 落到 Tier 2），而 false
positive 的唯一代價是多走一次精查。

### 5.2 為什麼不用事件層 gate

事件層掃描是 O(檔案文字) 而非 O(展開後的樹)，理論上最理想。但
**Yams 不公開事件層** —— `Parser` 只暴露 `nextRoot()` / `singleRoot()`，兩者都會
compose，`Event` 型別是 internal。不 fork Yams 就走不了這條路。

Tier 1 的存在性前濾是它的廉價替代：對 97% 的檔案達到同樣的 O(n) 效果。

### 5.3 攻擊面（R11 重寫——原文的安全宣稱已被實測推翻）

**原文（錯）**：「`Yams.compose(text)` ← 安全：COW 共享，不展開」「billion-laughs
必然含 `&` 與 `*` → 必進 Tier 2 → 現有預算 fail-closed」。

**實測反例**（PR #25 R11 verify，security lens）：`Yams.compose` 的
`Parser.checkDuplicates` 對每個 key node **遞迴 hash**（無 memoisation）。把 alias
放在**顯式 complex key** 位置時，展開發生在 compose **內部**：

| fixture | 大小 | 結果 |
|---|---|---|
| `? *a15` complex key | 927 B | **36.3 s CPU、45 s timeout 被殺** |
| 對照：同 bomb 不放 complex key | — | **0.03 s** → 正確 quarantine |

對照組證明既有預算對 **value 側**有效；complex-key 路徑**完全繞過**它。

**這不只是措辭錯誤——兩層 gate 的設計本身有洞**：bomb 必然含 `&` 與 `*` → 依原
設計被路由到 Tier 2 → Tier 2 呼叫 `compose` → 掛死。**profile gate 反而成為攻擊
的必經之路。**

**R12 再更正**：R11 曾在此提議「`? ` 是文字層可偵測的，加進 Tier 0 即可」。
**該提議也是錯的**，已於 PR #25 實作後被 R12 verify 推翻並 revert：

| 繞道形式 | 大小 | 結果 |
|---|---|---|
| `*a12: 1`（block 隱式 alias key，**無 `?`**） | 630 B | 25 s timeout |
| `{? *a12 : 1}`（flow 顯式，`?` 不在行首） | 645 B | 25 s timeout |
| `{*a12: 1}`（flow 隱式） | 636 B | 25 s timeout |

YAML 的 mapping key **根本不需要 `?`**。而且該守衛還會誤殺 block scalar 與折行
續行中以 `? ` 開頭的合法內容（實測：`note: |` 內含 `? what is this` 被 quarantine，
且因 encode 內含 decode canary 而永遠寫不回）。

**修正後的正確陳述**：`? ` 不是可用的判準。唯一可靠的文字層判準是 **anchor/alias
本身**（§4 第一列已禁）——沒有 `&` 就沒有 DAG，沒有 DAG 就沒有指數展開。但真實
corpus 有 63 檔含 `&`（`&amp;` 在期刊名裡）、5 檔含 `*`（引號內的關鍵字標記）、
1 檔兩者皆有，所以**存在性掃描會誤殺**——Tier 1 的前濾必須是 quote-aware 的，
或改由 Tier 2 在 compose **之前**用其他機制（如 fan-out 預算）。這是本設計實作時
必須先解決的問題，不是可以延後的細節（見 #36 的三個候選方向與各自代價）。

### 5.4 Gate 位置

`EntryYAML.decode` / `PersonYAML.decode` / `LibraryYAML.decode` 的入口，在既有
解析邏輯之前。Gate 通過後，下游可以假設輸入 in-profile。

## 6. 錯誤語意

Profile violation → **quarantine**（沿用既有機制：檔案原封不動、升級 binary 後
恢復），但帶**獨立的 reason 分類** `profileViolation(kind:)`，不與「未知欄位」
或「形狀不符」混用。

理由：三者的修法完全不同 —— 未知欄位要升級 binary、形狀不符要看 schema、
profile violation 要改檔案本身。`doctor` 應分開列出，使用者才知道該做什麼。

## 7. 自我一致性（MUST）

**`encode` 的產物必須通過同一個 gate。**

R5 與 R6 各踩過一次「寫得出、讀不回」的自我毒化（emitter 產出 plain `2026`，
strict decode 拒收自家產物）。Profile 引入同一陷阱的新版本：若 Yams emitter 在
節點共享時會吐 anchor，Akashic 就會寫出自己拒收的檔案。

既有的 `encodeCanary` 已在做「產物能否 parse 回來」的自檢；profile gate 掛進同一
處即可，成本近乎零。

**實作第一步必須先驗證**：Yams emitter 在餵入共享節點時是否產生 anchor。若會，
profile 必須同步約束 emitter 設定（而非只約束 decode 端）。此為本設計唯一未經
實測的技術前提。

## 8. 後續 issue（拆除，gated on 本 issue land）

| 守衛 | 可否拆 |
|------|-------|
| 三份 `oracleBudget = 200_000` | ~~Tier 1 檔案可證明不需要 → 條件性跳過~~ **R11 撤回**——該提議建立在「compose 安全」這個已被推翻的前提上（見 §5.3）。預算在修正後的設計裡仍然必要 |
| tagged-shadow 相關（`keyStrings`、R7 guard） | 可拆 —— gate 已擋 |
| `assertLFOnly` / `assertNoLossyContentChars` | 合併進 Tier 0（收攏，非刪除） |
| `stripLeadingBOM` | 變成 Tier 0 的拒收條件 |
| `scalarString` / `splitBlocks` / `verifyBlockOracle` | **拆不掉**（block scalar 與任意深度仍放行） |

拆除必須逐個進行，每拆一個跑一次完整 test suite，且 profile gate 必須先 land
並在前面擋著。

## 9. 測試

- 每條禁止語法一個 negative case（anchor / alias / tag / merge key / BOM / 五種行尾）
- **false-positive 迴歸**：`journaltitle: Sociological Methods &amp; Research`
  與 `- '*Achievement *Mind *Self-Control'` 必須通過（這是初掃 13 個假命中的形狀）
- Tier 1 / Tier 2 分流各自被覆蓋
- billion-laughs 仍 quarantine（沿用 security lens 的 1.3 KB fixture）
- **complex-key bomb 在 compose 之前被擋**（R11；測試若失效會 hang 而非 fail，那本身就是訊號）
- **反向**：值裡的 `?`、`?foo:` 這類非 indicator 形不得誤判
- encode 產物過 gate（§7）
- corpus-level 迴歸：536 個真實檔案全數 in-profile

## 10. 升級方向的相容性代價

本變更引入新的「v1.3 可載入、profile 後 quarantine」路徑：**BOM 開頭的檔案**
（現行靜默剝除、之後拒收）。真實 corpus 零命中，但這與其他升級方向不相容屬
同一類，應併入 `README.md`「Store 格式版本」的嚴格化表格與 `docs/store-format.md`
§5 的對應 bullet。

> **R11 更正**：原文寫「必須併入 §5 **末段**的清單」——§5 末段（「混版部署」）
> 並沒有那樣一份清單，各條嚴格化是分散在各 bullet 內的。錨點已改指實際位置。
> 同一個錯誤原本也出現在 README（「詳見 §5 末段」），已一併修正。

> **R11 更正之二**：原文說「其餘四類在 v1.3 下本來就會 quarantine 或毀字」——
> 這句話**不成立**。`? key`（顯式 complex key，本 spec 於 R11 補進禁止清單）在
> v1.3 下不但不 quarantine，還會在 `Yams.compose` 內部指數展開把消費端掛死
> （實測 636 bytes → 36 s CPU → timeout）。該缺口已於 PR #25 的 R11 修復
> （文字層守衛，compose 之前），但本節原本的樂觀敘述是錯的，照實更正。

## 11. 實作順序

1. **等 PR #25 merge**（本 gate 會碰 `YAML.swift` 的 decode 入口，與未 merge 的
   958 行有衝突面）
2. 驗證 §7 的 emitter anchor 前提
3. §4 profile 定義寫入 `docs/store-format.md` §5
4. 實作 gate（§5）+ 錯誤分類（§6）+ 自我一致性（§7）
5. 測試（§9）
6. 後續 issue：拆除（§8）
