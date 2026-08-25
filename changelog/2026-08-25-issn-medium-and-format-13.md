# 模型記錄了「有幾個」，卻沒記錄「憑什麼是幾個」——#394 收尾四項

2026-08-25 中午到下午。ensemble verify 的剩餘四項一次做完：ISSN medium 的 schema、
`rewritingProvenance` 空殼、`enrich-from-zotero` 寫回殘留、format 13 bump。

## 決定性的那筆資料

`entity-identifier/spec.md` 為每種識別碼的**基數**列了證據。ISSN 那列逐字是：

> `1554-351X` and `1554-3528` are the **print and electronic** ISSNs of one journal

而那個例子**就在庫裡**（`behavior-research-methods`），模型說不出哪個是哪個。ISBN 那列
同理：「separate ISBNs across **editions**」，而遷移剝掉的正是 `hardcover`／`alk. paper`。

實測：39 個帶 ISSN 的 venue 裡 **18 個正好帶兩個號**，而順序毫無規律
（`psychological-bulletin` 電子在前、`psychometrika` 紙本在前）。

**spec 用來證成這個欄位是清單的那個區分，模型表達不出來。**

## 形狀怎麼選的

`qualifier` 進 `Identifier` 協定（預設 `nil`），**存在識別碼型別內**——所以 `[ISSN]`
的型別不變，稍早 lens 窮舉出的十幾個消費端**一處都不用改**。

YAML **一律 mapping**（`- value: X` ＋選填 `qualifier:`），不做「純量＝未知、mapping＝已知」
的雙形狀。理由不是 `no-compat-fallback` 的字面（它的三個例外類別是封閉列舉，雙形狀
不屬於任何一類，援引它反而是該規則自己禁止的類推），而是兩件實測的事：

1. **既有先例三比一**。`authors`／`venues`／`affiliations` 的二態全部編成 mapping、
   靠鍵的有無做 switch。唯一的「純量 vs mapping」先例（affiliation 的 `value`）
   **收斂到同一個語意狀態**（裸純量一律視為 `.literal`），不是分裂語意。
2. **雙形狀的分支住在唯一的解析入口**，沒有具名出口——「誰還在走舊形狀」grep 不出來。

**ISSNMedium 封閉、ISBN 的 qualifier 自由文字。** 不對稱有依據：前者是 ISSN 標準定義的
三個角色，後者沿用 MARC 020 $q 的語意而值域本來就開放（庫內出現過 `alk. paper`）。
把開放的寫成封閉，會在第一個沒想到的值上把資料擋在門外。

## 雞生蛋：遷移工具讀不到它要遷移的東西

改完解碼器的當下，真實 store **68 檔立刻 quarantine**——而 `migrate-identifiers` 走
`store.load()`，於是那 68 檔根本不在它看得到的集合裡。

`no-compat-fallback` 的例外條款正是為此存在，三條逐條滿足：

| 條件 | 落地 |
|---|---|
| 不住 default 位置 | 解碼器維持嚴格；`upgradingIdentifierShape` 只有遷移命令呼叫，一次 grep 看完 |
| 附可執行的退場量測 | `grep -A5 -E '^(issn\|isbn):' ~/.akashic/entities/*.yaml \| grep -cE '^\S*-- [^v]'` 回 0 即可刪 |
| 退場即刪 | 寫進 doc comment |

它**必須在 `load` 之前跑**，而且同樣受 trackedness 閘管制——第一版繞過了那道閘，
是自己看出來補的。

## 三個「測試通過的理由是錯的」

這一輪抓到三次，全部是我自己寫的 fixture：

1. `WoSImportTests` 用 `10.1/abc` 當 DOI——**註冊者需 ≥4 碼**，形狀不合法。改讀
   `canonicalDOIs` 之後它落回標題比對，於是 4 支測試「以為在測 DOI 身分、實際測到
   標題年份」。
2. `testResidueDoesNotOverwriteAStructuredIdentifier` 用 `10.1/residue`——同一個問題，
   遷移本來就不會用它覆寫，負控因此沒紅。
3. `VenueSurfaceTests` 的第一次負控只改 `.map` 的來源，而 `if !record.issn.isEmpty`
   仍含該子字串，守衛的子字串比對照樣命中。

三次的共同形狀：**負控沒紅時，第一個該懷疑的是負控本身，不是守衛。**

## 一個結構性的發現：Behavior 條目沒有可執行的驗收

`tasks.md` **21/21 全勾、0 未勾**，而 verify 找到 5 CRITICAL。追下去發現：
`design.md` 的 Implementation Contract **第一句 Behavior**——

> `akashic venue <key>` 對帶 ISSN 的 venue 顯示其 ISSN 清單

——**從頭到尾沒有被滿足過**，直到今天上午才修。`swift test` 全綠、14 支 plugin 守衛
全綠、驗收條件的數字（64→0、0→39）全部通過。

因為 **Behavior 條目是散文，沒有任何測試把它們釘住**。`swift test` 驗型別與序列化，
驗不到「使用者跑這個命令看得到什麼」。

同一份驗收條件還有第二個洞：它為 DOI 修過兩次、為 ISSN 補過一次，**唯獨沒為 ISBN 修**
——而 ISBN-10→13 換算是同一個 change 內親自裁定的，實測 29 筆裡 23 筆值會變，全部
不在「除 15 筆之外」的帳裡。

## 我自己的兩個操作錯誤（記下來）

1. **又把 `--apply` 跑了兩次**——為了看報告的頭與尾。這個 session 稍早才記過同一件事。
   破壞性命令不得為了看輸出而重跑；要看全部就導進檔案。
2. **workflow 的第一版讓 5 個 agent 全滅**：我叫它們去讀 `CLAUDE.md` 與
   `.claude/rules/*.md`——那些是這個 repo 最大的檔案，sonnet agent 一讀就進 compact
   迴圈。燒了 3.7M token 換到零產出。規則內容本來就在我的 context 裡，不該叫它們重讀。

## 尚未做

- `Organization` **完全沒有單筆讀取面**（只有 `add-` 與 `resolve-`），所以 `ror` 不是
  payload 漏欄位而是整個面不存在。補它要先走 `mcp-cli-parity` 的兩面裁決
- 其餘 34 個 venue 的 ISSN medium 仍 unknown——要查 ISSN portal，而外部查證是
  design 明列的 out of scope
- **`logic` 與 `security` 兩個 verify lens 至今沒跑起來**（兩輪都 API 中斷），
  而它們正是最該看 `Identifier.swift` 的兩席
