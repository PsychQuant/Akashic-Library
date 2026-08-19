# APA7 下限的一輪（#359 #340 #267 #269 #302 #355 #357）

PR #371–#374，2026-08-19。七張 issue，兩條主線：**APA7 下限的實際修復**與
**不可機械驗證之事的承載機制**。

## 主線一：下限修復

### #359 — §10.5 的 golden fixture

`apa7-style` domain 的 `.bib` 沒有 §10.5，但同 domain 的 `06_reference/APA7manual.md`
有手冊全文。它糾正了憑記憶的猜測：**編號例是 60–63，不是 67–70**。若照記憶造 fixture，
這份「golden 矩陣」會拿著錯的編號宣稱自己是手冊的例子，而沒有任何測試會發現。

手冊的 template 把 §10.5 的 Source 欄寫成 `Conference Name, Location.` ——**會議名稱
就是 source element**。裁決落 (c)：接受依賴的 warning 級，但把它記成明文 known gap。
三條斷言其中一條刻意**斷言現況**（拿掉 `EVENTTITLE` 只是 warning），它會在缺口被修好
時變紅——比一條永遠紅的測試有用。

golden 矩陣的節覆蓋 11 → 12。

### #340 批 A — 缺的欄位一直躺在 Zotero 裡

issue 的前提是「store 自己沒有可用資訊，修法必然涉及外部查證」。對 73 筆有 `zotero_key`
的 error 記錄逐一查 Zotero 之後，**35 筆的答案一直在**：

- 14 筆百科條目的 `encyclopediaTitle`（APA7 10.3 的 source element）
- 21 筆會議發表的 `meetingName`（10.5 的 source element，#359 的 known gap）

兩者都因 `ZoteroMapping.fieldMap` 沒有它們而走殘餘路徑、以別的鍵名入庫。**殘餘收集
（#206）保證「來源給的都收」，但收進來的鍵名若不是 export 面認得的那個，下限仍然跌破。**

新增三條欄位對映（`encyclopediaTitle` → `booktitle`、`meetingName` → `eventtitle`、
`presentationType` → `titleaddon`）與一條型別對映（`encyclopediaArticle` → `.wikipediaEntry`
——後者順帶擋掉「跑一次 `import-zotero` 就把 #325 訂好的 14 筆降回 webpage」的潛伏回歸）。

新命令 `enrich-from-zotero`（CLI）／`akashic_enrich_from_zotero`（MCP）：與 pull 語意
刻意不同，**只加原本不存在的鍵**，作用半徑由呼叫端逐筆指名。四類「沒補到」全部回報。

實測 937 筆真 store：`[ERROR]` 101 → 87、缺 `BOOKTITLE` **14 → 0**、`EVENTTITLE` warning
**25 → 4**、零新增 error、45 筆寫入且零附帶損害。**批 B 未做**（`JOURNALTITLE` 42／
`AUTHOR` 25／`DATE` 20，各需不同證據），#340 保持開啟。

### #355 / #357 — 判準：定義上為真 vs 斷言出處

三節（10.7／10.11／10.15）需要欄位配合，先前只能整批不送。換上判準之後三個變成兩個：

| | 裁決 |
|---|---|
| `review` → `RELATEDTYPE = reviewof` | ✅ 送。`.review` 的意思**就是**「這是一篇評論」 |
| `testInstrument` → `ENTRYSUBTYPE: Database record` | ❌ 它斷言記錄來自 PsycTESTS |
| `socialMediaPost` → `EPRINT: Twitter` | ❌ 它斷言平台 |

**可以送型別已經聲明的東西，不可以送記錄的出處。** `.review` 的 entry type 同步由
`UNPUBLISHED` 改成 `ARTICLE`（附帶效果：它從「未涵蓋」變成「有下限」）。

`WorkTypeSectionAgreementTests` 的探針改走**真正的匯出路徑**——先前自己組 `BibEntry`，
驗的是型別對映而非出貨的東西（同 #353 修掉的 `apa7CheckedTypes` 鏡像）。

#357 的量測**更正了 issue 的分布表**（`report`／`webpage` 兩列對調），而那個對調反轉了
裁決方向：真正錯置的是兩筆 PsyArXiv 預印本（標成 `webpage`／§10.16），已改為
`unpublished-work`／§10.8。`fields.type` 的同名判定為 biblatex 的既定命名，**不改名、
不刪除、不發診斷**（23 筆裡 9 筆是正確用法），改以文件解決。

## 主線二：不可機械驗證之事的承載機制

三張 residue-升格的 question／meeting，共同形狀是「某個東西不可機械驗證，那它由什麼承載？」

- **#267**（claim 與 interpretation 的哲學一致性）→ **具名的第二讀者**。否決作者自審
  checklist 的理由是量測的：`common-spec-prose-enumeration` 記著四輪跨模型盲驗——所有
  blocking finding 全出自跨模型驗證，作者自審每輪都報「完全符合」。否決機械化並附
  **可執行的重啟條件**（對 20 條已知正確的 relation 量假陽性率）。
- **#269**（index 條目的真值）→ **由寫入者負責，audit 只保形式一致性**。理由在實測後
  換過：`acquisition` 就是結構化 kind，缺的是 URL；而即使補上 URL，彙總型 API 結果的
  重抓比對**無法區分「敘述為假」與「上游變了」**，不構成真值抽查。
- **#302**（作者身分的存在論）→ **`analogy_only` 記在 corpus 5.632**，規則檔只加
  「另見」並明寫**不是第七條理由**。不取「記錄後關閉」的理由是該問題已觀察到回歸一次。

三者都補了存續守衛（只留文件的裁決會被「精簡」掉）。

## 驗證

- 全套 **1962 tests / 0 failures / 1 skipped**；`swift build -Xswiftc -warnings-as-errors` 乾淨
- `tractatus-doc validate` + `render --check` 皆乾淨（project_relations 536 → 537）
- MCP 稽核 ① 30 = parity 表 30；CLI 稽核 ② 42 subcommand
- 真 store 的每次寫入都事先記基線、事後逐項比對（entities 未變、porcelain 差額恰為寫入數）

## 兩個過程教訓（寫下來因為它們會再犯）

1. **diagnosis 的數字有相當比例是錯的**——本輪 6 張撞到 3 次。引進規範文字前必須自己對
   真 store 重量一次；#357 那次的錯誤會讓人查錯對象。
2. **本地 `swift test` 綠不等於 push 得過**——兩次成因不同：pre-push 帶
   `-warnings-as-errors`；以及一條拿短字串比對整份輸出的 flaky 斷言（`A5` 撞上
   `entry:AAA54C33`，約 2–3%，已修成只比對目標那一列）。

## 部署（2026-08-20，本輪的後半）

程式碼 merge 到 main 只是一半——store 與已安裝的 binary 都還停在 format 11。完整鏈：

| 步 | 動作 | 結果 |
|---|---|---|
| 1 | `swift build -c release` → 安裝 `~/bin/akashic` **與** `~/bin/akashic-mcp`（各自先備份 `*.pre-format12-20260819`）| 兩者皆新世代 |
| 2 | `migrate-venues` | **已是 no-op**（803 筆早在 format 10→11 時回填，冪等性確認）|
| 3 | `store.yaml` format 11 → 12 | bump 前確認 venue 記錄 0 筆、`authors:` 內 `organization:` 0 個 → 無需資料遷移 |
| 4 | `validate` / `doctor` | ✓ 937 entries／867 people 全過；rc=0、零 quarantine、orphaned 0 |

**refuse-if-newer 實測生效**：舊 binary 現在明確拒讀並指路「三者是各自獨立的 binary，
只升級其中一個仍會撞到同一道防線」。

> **一個 bump 前差點踩到的坑**：`~/bin/akashic-mcp` 是 format-11 世代。**若只更新 CLI
> 就 bump，MCP server 會整份拒讀 store。** 已先本機建置安裝新 MCP binary 再 bump。
> 但 wrapper 依 plugin.json 的版號決定要不要重新下載——**日後 `/plugin update` 會把它
> 換回已發布的舊版**，那需要一次正式 release（`scripts/release-signed.sh`，對外動作）。

### format 12 解鎖了 #305 在等的東西

`bootstrap-venues --apply` ＋ `resolve-venues` 一輪跑完：

- **403 筆 venue 記錄**（370 `periodical` ＋ 32 `publisher`）；型別衝突 **0**
  （#367 那條零實例守衛的預測成立）；5 個非 ASCII 刊名報出待人工指定
- 消歧候選 **798，全部精確命中、歧義 0**；歸戶後剩餘候選 0
- **文章數為 0 的 venue：0 個**——每個 venue 都由反向現算連得回作品，
  `entity-backlink-completeness` 的「反向一律現算」在真實資料上跑通

**這直接回答了 #304 的核心疑慮**：venue 域的消歧歧義是 **0**，而 person 域仍有
**2,123 個未歸戶 author literal**。**兩者不在同一個量級**，而 #304 當時擔心的正是
「會不會像人名一樣爆掉」。

### 一個自查抓到的自己的 bug

第一批 `resolve-venues --apply` 只套用了 **797/798**。原因是我的腳本用 python 的
`'\n'.join()` 寫 id 檔（最後一行無換行符），而 bash 的 `while read` 在無結尾換行時
**會丟掉最後一行**——不是工具的問題。比對 `applied` 與候選集合後補上那一筆。

**教訓**：批次寫入後要比對「送進去的集合」與「回報套用的集合」，不能只看 rc=0。
差 1 筆不會讓任何東西變紅。
