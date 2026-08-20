# 一整夜的批次：五張 issue 關閉、一個 skill、六個識別碼型別，以及五次我自己弄錯（#383–#396）

2026-08-21 凌晨。使用者睡前交代「用 `/idd-all` 把所有 issue 解完、`/disambiguity` 做成 skill、
然後解完那 100 篇」。這份記錄的重點不在清單有多長，而在**這一夜有五個地方是我自己弄錯、
而每一次都是「去執行」才發現的**。

## 主線：那 100 篇其實早就全歸戶了——問題在別的地方

第一件事是量。`統計所研究成果100篇_作者_篇名_刊名20260717.xlsx` 的 100 筆，**100/100 已在
store，1112 個作者位全部有 key、零 literal**。

看起來已經做完了。但打開其中一筆：

```yaml
citekey: huang2025causal
authors:
- key: i-yang-hwai            # ← Yang, Hwai-, I
- ...
- key: ablm-yen-tsung-huang   # ← Ablm, Yen-Tsung Huang
```

**全部有 key ≠ 做完。** 它們歸到了壞掉的身分上，而零 literal 的報表看起來一模一樣。

### 根因與 #389 的假設相反

#389 的 Notes 寫「根因未定位……兩個形狀都指向**姓名切分**的同一族問題」。查證推翻了它：
xlsx 的 `Author Full Names` 欄**逐字含有切壞形**——

> `Huang, Yi-Ting; Hsu, Yao-Chun; Yang, Hwai-, I; …; Ablm, Yen-Tsung Huang`

切壞的是**上游 WoS 匯出本身**。我們的 importer 忠實收下了它給的東西，那正是
`lossless-intake` 要求的行為。**要修的是資料，不是 code。**

### 同一篇論文在 xlsx 出現兩次，兩列各錯一半

| xlsx 列 | 第 5 位作者 | 第 7 位作者 |
|---|---|---|
| 原文列 | `Lai, Tai-Hsuan` ✓ | `Ablm, Yen-Tsung Huang` ✗ |
| 更正啟事列 | `Lai, Tai-Shuan` ✗ | `Huang, Yen-Tsung` ✓ |

這推翻了 `work-sources.md` 的一句話——它說更正啟事記錄「**它的作者欄可能是對的**」。實測是
兩列**各錯一半**，拿任一列校正另一列都會引入新的錯。裁決要回 DOI（Crossref 一次確定兩者）。
該句已收窄為「它只是**第二個觀察**」。

順帶：`lai-tai-shuan` 是 #389 原本沒列到的**第 5 筆**。

### 切壞形沒有丟棄

`Ablm, Yen-Tsung Huang` 與 `Lai, Tai-Shuan` 降為倖存者的 **variant**。它們是**真實觀察到的
WoS 署名形**——記著它，下次同樣的匯入會正確提名而非再建一筆重複；而 variant 不印進
`.bib`，所以 `lossless-intake` 與「印對名字」兩者兼顧。

收尾：那 100 篇的四項驗收全綠（在 store 100/100、literal 0、壞身分 0、跌破 APA7 下限 0）。

## 五次我自己弄錯

### 一、code-reading 給了一個看似合理的推論，跑一次就推翻

從 `BibExport.swift` 讀出「`for key in entry.fields.keys.sorted()` 逐鍵原樣轉出」，而量測顯示
`zotero_key`／`imported_at` 等各 527 筆「在 fields 裡」。結論呼之欲出：**匯入記帳外洩進 `.bib`**。
正要開 issue。

實際跑一次 `export-bib`：輸出只有 TITLE／AUTHOR／DATE／EDITION／ISBN／LOCATION／PUBLISHER。
**沒有任何記帳鍵。** 它們住在 typed 的 `provenance:` 區塊。

### 二、上一則的根因：`grep -A<N>` 會越過 YAML 區塊邊界

`grep -A200 "^fields:"` 撈到了下一節的子鍵。固定行數的 `-A` 對 YAML 是錯的工具——要按縮排
收斂。重量後 `fields` 內相異鍵 38 個，不含任何記帳鍵。

**這個錯誤差點讓我開一張不存在的 bug。**

### 三、只看 `tail` 把 37 組低估成 4 組

`validate | tail -5` 看到 4 組「同題同年不同 DOI」，寫進診斷。`validate | grep -c` 才發現是
**37 組**。引用自己先前量的數字之前，重量一次。

### 四、在 pre-push 跑測試的同時對真 store 寫入

`git push` 的 pre-push hook 跑測試，而我同時在對 `~/.akashic` 套用候選。守衛抓到了：

```
🚨 真實 ~/.akashic 在測試期間被改動
變動（1）：/entities
```

push 失敗，而背景 wrapper 回報 exit 0（那是 pipeline 的 exit，不是 git 的）——**兩層誤導疊
在一起**。守衛做對了事；教訓是測試在飛時不要動 store。

### 五、把「N.-V.」讀成 Noun-Verb

使用者說「我有取名的規範，通常是 N.-V.」。我據此把新 skill 取名 `akashic-ambiguity-resolve`
（名詞在第二位）並在檔內註明「依 N-V 規範」。

但 Foresay `MP02` 規則 3 明寫 **verb second**——「N」是 **Namespace** 不是 Noun。而 #392 的
Expected 表**早就逐字寫著正確答案** `akashic-disambiguate`，我沒照它。已改名（零外部引用，
無遷移成本），失敗史留在該 skill 檔內。

## 兩個「去用它才現形」的 bug

### `--tier <寬鬆層> --apply` 結構上不可能成功

CLI 端的閘要求寬鬆層必須 `--tier` 具名（放行），但呼叫 service 時**從不傳 `confirmTiers`**，
於是 service 端的閘無條件拒絕。一條有文件、有說明、走不通的路——`mcp-cli-parity` 記的
「tier-acknowledgment 參數列 follow-up」就是這條沒接上的線。

**兩道閘各自都「正確」，錯的是它們之間沒接上。** 修好後 reorder 62 列一次套用成功。

### `renameEntry` 從未遷移 `judgement.prefers`

為了列出 person key 的參照面而回頭讀 `entity-backlink-completeness` 的封閉列舉表時，發現
citekey 那邊也漏了同一格。漏掉的後果**安靜**：`resolve-divergence` 用
`prefers != survivor` 擋下不一致，而 `prefers` 指著一個已不存在的 key 時，**任何** survivor
都不等於它——那筆歧異永遠消不掉，而改名什麼都沒說。與 #232 verify NEW-1 同型。

**那張封閉列舉表不只是文件，是可以拿來稽核程式的清單。**

## 歸戶進度

| tier | 起點 | 收尾 |
|---|---:|---:|
| `exact` | 29 | **0** |
| `reorder` | 62 | **0** |
| `initials` | 129 | **30** |

全庫作者位：key 1597 → **1747**（42.2% → 46.1%），literal 2183 → **2033**。

`initials` 的 99 列各有理由：3 列只是連字號差異（套用）、68 列兩邊都是完整全名且不同（否決）、
14 列機構相符（判定）、9 列機構互斥（否決）、5 列「部分縮寫、其餘逐字相同」（判定）。

剩下的 30 列**不是「還沒看」**，是庫內與 OpenAlex 兩條路都用盡了。

## 新東西

- **`akashic-disambiguate` skill**（使用者口語的 `/disambiguity`）——歧義列判定的方法論。與
  `akashic-person-verify`（單配對外部證據鏈）與 `akashic-literal-campaign`（批次編排）的接縫
  是：本 skill 先用成本低一個量級的**庫內**證據。四條判準 ＋ `references/ambiguity-traps.md`
- **`Sources/AkashicCore/Identifier.swift`**——六個識別碼 value type（#394 的可逆半邊）。
  判準是**介面深度**：若欄位型別是 `String?`，這個抽象什麼都沒藏、刪掉不會壞任何東西。
  19 個測試全用真實值，check digit 手算核對
- **`identity-is-judged-not-matched` 的識別碼例外節**——六種具名、封閉列舉，並明寫識別碼
  **終結指涉、不終結描述**
- **`akashic rename-person`**——person key 的改名路徑。**不是照抄 `rename`**，兩者的參照集合
  各自照封閉列舉窮舉

## 使用者的一句話改了兩處文件

「不要改名吧，因為不是所有東西都是 doi」——這不只否決了一個改名提案，它同時指出了
`work-sources.md` 的一般化方向：**反向判定的形狀對六種識別碼都成立**，只是查詢端點不同
（Crossref／OpenLibrary／ISSN Portal／Europe PMC／ORCID API／ROR API）。

## 關閉與剩下的

關閉：#383（診斷對但修法是範疇錯誤）、#384（歧義 100 → 0）、#386（PR #397）、#388、#389、#395。

剩 7 張，**每一張的 blocker 都需要使用者**：#396（30 列換來源或顯式接受）、#394（format
12→13 不可逆）、#393（那五筆 citekey）、#392（plugin 更名要卸載重裝）、#365（等具體用途，
且 WoS 匯出要勾 `Reprint Addresses` 才有供給端）、#340（兩大索引都查不到刊名）、#285
（`parking-lot`）。

七張全部帶工具掃得到的 `### Blocking` 或 `parking-lot` label——依
`blocked-issues-must-be-scannable` 稽核，零不合規。
