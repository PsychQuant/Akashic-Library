# 2026-10-01 `akashic-verify-venue` 加「對外形」步驟：查證確立正式刊名時指定或確認 `authorized`，按需判定（#566）

使用者 2026-10-01 對 #600 的裁決「按需判定」取代 #566 立案時的全量 campaign：既有的機械 `authorized` 不跑一輪，只在查證或攣生合併碰到那一本時判定。

## 背景

#554 給 venue 的 `authorized` 補了判定面（`update-venue --authorize`／`akashic_update_venue.authorize`），但做判定的流程一端沒接上：`akashic-verify-venue` 為 ISSN 有「查到就順手 `add_issn`」（#556），查證刊名的同一條證據鏈對「這本刊的對外形是什麼」卻沒有任何一句指向 `authorize`；`akashic-merge-twins` 亦無。2026-09-11 實測 live store：venue 485 筆、470 筆有 `authorized`、470/470 都是 `VenueBootstrap` 取第一個名字的機械值。

#566 立案時要的是一輪 campaign（同 #303 literal 歸零的形狀）。#600 的裁決改成按需：

> 既有 479 筆機械 authorized 不跑全量 campaign，只在攣生合併或查證撞到那本刊時判定。`akashic-verify-venue` 加一個 authorize 步驟（#566）。判定要留的記錄形狀由 #564 決定：2026-10-01 已裁「留，含確認既有值」。

#564 同日落地（store format 22）：`--authorize` 必附 `--judgement`，對已是對外形的名字再說一次寫一筆「確認：」，新指定寫「指定：」，同書寫系統被換下的舊指定寫「撤回：」。所以「確認既有值」這個最常見的結論現在寫得進 store，進度量測才不會對它恆回 0。

## 改了什麼

- `plugin/skills/akashic-verify-venue/SKILL.md`
  - 報告多**第 5 項**：本次要指定或確認的對外形（venue key、名字、現況、動作、理由、證據 digest）。閘是使用者確認第 5 項；一句裸的「apply」只確認配對，第 4 項（ISSN）一樣各問各的。注入防線那句（「不能代替報告第 2／4 項的確認」）同步改成第 2／4／5 項。
  - Step 3 新增一條「查證確立了本刊的正式刊名時，對外形也要判定——按需，不是 campaign」，與 ISSN 那一條對稱：
    - 範圍＝這次碰到的那一本，不掃全庫、不批次；
    - 列進第 5 項的門檻同「什麼時候可以停」（至少兩源、第 4 源只當佐證、第 2 項說不可判定的不列；已有判定記錄的不重判，除非這次查證與它衝突）；
    - 兩種結論：**確認**（名字已是 `authorized`）與**指定**（同書寫系統被換下、留在 names 不標 variant）；
    - 寫法：`akashic_update_venue` 的 `authorize`＋`judgement`（可附 `rests_on`），單獨一次呼叫，理由不自己加前綴；
    - 需要 store format ≥ 22（不足具名拒絕，升 marker 是使用者的動作）；
    - 攣生合併撞到這一本時：機械值只提醒、照併；被併者的 `authorized` 帶判定記錄而合併被拒時的出路（在被併者撤回、或在倖存者指定，都要理由）；
    - 進度量測與一段唯讀的 PyYAML 腳本。
  - frontmatter 描述與開頭兩句補上第 5 項。
- `plugin/skills/akashic-merge-twins/SKILL.md`：**只加一條誠實邊界**，不加流程。這個 skill 只併 work，work 合併不動 venue 的 `authorized`；venue 攣生的查證與合併走 `akashic-verify-venue`。這條邊界指向那邊的 Step 3，不重複內容。
- `plugin/CHANGELOG.md`：補 #566 一節。plugin 版號沒有動（同 #692：skill 文字改動）。

## 進度量測（唯讀，2026-10-01 live store）

量的是「`authorized` 至少有一筆名字分類判定記錄的 venue 數」，分母是有 `authorized` 的 venue 數。`authorized != [names[0]]` 不再是量測：確認既有的 `names[0]` 不改變 `authorized`，那樣量對最常見的結論恆為 0（#566 立案時就點出這一點，而 #564 之前它**只抓換過名字的**）。

```
venue 485｜有 authorized 470｜其中至少一筆名字分類判定記錄 0｜讀不到的檔 0
store format: 18
```

腳本取自 skill 檔內那一段原文（抽出後直接執行，不是另寫一份）。正控制：同一支腳本對暫存 store（format 22，兩個 venue 各寫了確認、指定與撤回記錄）回 `venue 2｜有 authorized 2｜其中至少一筆名字分類判定記錄 2｜讀不到的檔 0`，所以 0 不是腳本讀不到記錄。**這個數字記的是步驟被用過幾次，不是要追到 470 的目標。**

## 沒有改程式

純 skill 文字與文件。#566 的 `### Blocking` 列了 #567（`migrate-venue-variants` 退場）：本分支的 `Sources/` 已沒有那條命令（`git grep migrate-venue-variants -- Sources` 只剩註解與一句錯誤訊息指路），GitHub 上 #567 本身截至 2026-10-01 仍標 open。#564 的 blocking 已落地（本分支的基底就含它）。#567 當初擋 campaign 的理由是每一次 `--authorize` 都會餵給那條命令的補集規則；命令在本分支已不存在，所以這一條不再擋這個變更。

## 驗證

沒有對 live store 寫入：live store 是 format 18，`authorize` 要求 format ≥ 22。步驟裡的三種情形用 format 22 的暫存 store 實跑過（`AKASHIC_HOME` 指向暫存目錄、以真的 `akashic` binary）：

| 情形 | 命令 | 結果 |
|---|---|---|
| 確認（名字已是 `authorized`） | `update-venue psychometrika --authorize PSYCHOMETRIKA --judgement …` | `alreadyAuthorized` 列出該名字、`judgementsRecorded` 1、YAML 多一筆 `field: authorized`、`judgement: 確認：…` |
| 指定（換下機械值的全大寫形） | `update-venue psychometrika --authorize Psychometrika --judgement …` | `authorizedRemoved` 列出 `PSYCHOMETRIKA`、`judgementsRecorded` 2（一筆「撤回：同書寫系統改指定「Psychometrika」——理由」、一筆「指定：理由」），`names` 兩個名字都在、不標 variant |
| 攣生合併，被併者的 `authorized` 帶判定記錄且會被降級 | `resolve-divergence <id> --survivor psychometrika --library … --dry-run` | 「拒絕合併：被併的…帶有名字分類的判定記錄…出路（都要理由）：在被併者上 update-venue … --unauthorize …；或在倖存者上 update-venue … --authorize …」，與 skill 寫的出路逐字對得上 |

`akashic_venue`（MCP）的回應讀得到這些判定記錄：`authorized` 清單與 `references` 裡的 `field: authorized` 項（`statement`、`rests_on`）；CLI `akashic venue` 的對應是 `〔authorized〕` 與 `[authorized]` 行。skill 兩種讀法都寫了。

## 誠實邊界

- **沒有對真的出版商頁或 Crossref／ISSN Portal 實跑這一步**：skill 的證據鏈部分不在本次範圍，第 4 源仍只當佐證（#692）。
- **沿革多段的刊，對外形取哪一段**：skill 建議現行那一段、並要求寫進理由；store 沒有規定，這是這次補的建議、不是裁決，使用者可翻。
- `docs/store-format.md` 的「`authorized` 為選填」一段仍寫「#600 的 authorize campaign 需要那個清單」：#600 裁決後沒有 campaign，這句已過期；本次不改該文件（範圍外），留給下一次碰到那一段的變更。
