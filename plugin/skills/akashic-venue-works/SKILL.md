---
name: akashic-venue-works
description: >-
  venue → works 的外部補完（#423）：給一個期刊（venue key 或 ISSN），把該刊的文章補進
  Akashic store——增量、可重跑、逐筆可審。當使用者說「把某期刊的全部文章收進來」
  「補完這本刊」「這本刊我的庫裡缺哪些」時使用。與 akashic-bootstrap 的分工：那是
  person → works，本 skill 是 venue → works；與 akashic-venue-verify 的分工：那判定
  「這個刊名字串是不是這個 venue」，本 skill 假設 venue 身分已定、補的是它的目錄。

  「寫下的世界斷言要先量過」是本 skill 的執行紀律——見 rules/assertions-must-be-measured.md。
---

# akashic-venue-works — 把一本期刊的目錄補進庫

## 前置：venue 身分要先判定，不在本 skill 內

給的是 ISSN 或刊名時，先把「它對應庫內哪個 venue key、OpenAlex 哪個 source ID（SID）」
判定掉——那是 `akashic-venue-verify` 的工作（判定、留證）。本 skill 從「(venue key, SID)
已確立」開始。**不要**因為 OpenAlex 的搜尋回了一個像的 SID 就直接開跑。

## 本體論前提（#420 裁決，2026-08-28）

收進來的是 **`work:` 記錄＋library membership 標記**——不是新 entity、不是 venue 攜帶
目錄（後者違反 `entity-backlink-completeness` 的「venue 記錄的 works 在不得儲存之列」）。

```
libraries:
- <venue-key>-catalog     ← 期刊目錄（我知道存在的）
```

#420 裁決原文：「我讀過／引用過」那個集合，是**沒有這個 library 標記**的那些，或另一個
顯式 library。`work:` 的既有語意不動——目錄記錄仍要能產出參考文獻
（`apa7-is-the-work-floor`），識別碼、venue 邊、resolve-* 一族原樣適用。

## 收錄邊界

| OpenAlex type | 收不收 | 依據 |
|---|---|---|
| `article`、`review` | ✅ | 是 work |
| `supplementary-materials` | ❌ **不收**（計數報告） | **已裁決**（#423／#394 多值政策原話：「吸收它等於讓該記錄宣稱自己是另一個物件」）。候選落點是原文的 attachments（#424 審議中——審議定案前這是候選不是定論） |
| `erratum`／`paratext`／`editorial`／`letter` | ❌ 預設不收（計數報告） | **預設，未經顯式裁決**——要收（或要把 erratum 綁回原文）需要開裁決，不得引本表冒充已裁決 |

**丟棄必須可見**（`lossless-intake` 執行細節 3）：排除的每一類都要在報告裡帶計數。

## 兩階段擷取——界線是量出來的（#423 量測）

**階段 A（API）**：OpenAlex `works?filter=primary_location.source.id:<SID>` cursor 分頁。
拿到的是「**OpenAlex 在擷取時點、該 filter 視圖下所知的全部**」——不等於真實世界的完整
目錄（primary_location 是 OpenAlex 的視圖；漏收要靠重跑與其他來源交叉）。結構化欄位＋
摘要（`abstract_inverted_index` 還原）一次取齊。

**階段 B（瀏覽器渲染頁）**：**工具選擇與各站點的判準／坑見
[references/site-access.md](references/site-access.md)**（升級階梯、psycnet 的 Incapsula
邊界、不干擾使用者的縮小視窗方案、節奏——都是量過的）。**先做攣生收攏（見下）再現算**
`has_abstract:false` 的清單
——順序錯了會把攣生的無摘要側白白送瀏覽器（Psychological Methods 實測：原始 261 筆，
收攏後真缺 151 筆）。判準**不是 HTTP 狀態碼**——psycnet 對 headless 回 200 的空殼；判準
是**渲染後有沒有摘要節點**。查完仍無 → 記顯式的「已查證、來源無摘要」，不是留白。每次
重跑對清單**現算**。

**已知限制（誠實記錄）**：conflict＝拒絕覆寫，所以**重跑不會把遲到的摘要補進已建記錄**
——那是 enrich 型的另一條路（同 `enrich-from-zotero` 的 add-only 形），不在本 skill。

## DOI 攣生——收攏是提名，合併是裁決

APA 九〇年代的 DOI 正式形帶**雙斜線**（`10.1037//…`），OpenAlex 對同文常存單／雙斜線
**兩筆記錄**，且摘要常只在一側（Psychological Methods 實測：197 對攣生；第一次執行沒
收攏，建出 195 組近重複——清理見 #456）。

依 `identity-is-judged-not-matched`：斜線折疊是**字串謂詞，只夠提名不夠判定**。所以：

- **diff 階段**：單／雙斜線折疊後相同 → 當**攣生候選**跳過不建，逐對記進報告的
  `twin-candidates` 區（含兩個 DOI 與兩側摘要有無），**留給人審**
- **不**自動合併任何既有記錄——合併（兩個 DOI 都真，正確形是一筆 work 多 DOI，
  #394 先例）是逐筆裁決，屬 #456 的範圍

## 匯入序（全部走既有面——不另寫 importer）

1. `akashic library create <venue-key>-catalog`（已存在則略過）
2. **增量 diff**：讀庫內全部 DOI（正規形）；已在庫 → **跳過並記 conflict**
   （`import-wos` 語意：拒絕覆寫——期刊目錄是一次性快照，store 可能比它新，#420 裁決 (c)）。
   攣生候選同上節。無 DOI 的來源記錄：title+year 折疊**只是提名**——不確定就跳過並具名，
   確定要建也要在報告裡逐筆留下比對依據
3. 逐筆 `create-entry`：type `periodical-article`、authors 全部 `.literal`
   （`literal-first-then-key`：進庫不猜）、fields 帶 `journaltitle`／`volume`／`number`／
   `pages`／`abstract`、識別碼 `--doi`／`--pmid`
4. 逐筆 `library add`（**冪等**：已是成員即 no-op——重跑安全，中斷後重跑會補上漏掉的
   membership）
5. `migrate-venues` **乾跑逐筆過目** → `--apply`：從 `journaltitle` 回填 venues literal
6. `resolve-venues` **先列候選過目**（歧義與未命中要報出來）→ `--apply`。exact 命中寫
   confirmed verdict 是該面的既有契約（#304 的 venue-name-exact）；本刊零歧義是
   **這一刊的結果，不外推**——下一刊有歧義就逐筆人裁
7. OpenAlex 給的 ISSN 若庫內缺：**先核對**（print／electronic 角色、確屬本刊）再
   `update-venue --add-issn`——ISSN 寫入是 venue 身分斷言，不是順手動作
8. **報告（逐筆可審的實體）**：新增／conflict／twin-candidates／各排除類計數／
   缺摘要清單（階段 B 輸入）——每筆帶 citekey 或 DOI 與處置，不只總數

## 驗收基準（Psychological Methods，2026-09-01 實測——單刊數字，換刊要重量）

1545 新建／11 conflict／0 失敗批；1548 venue 邊歸戶（本刊零歧義）；83%（1295/1556）帶
摘要；攣生 197 對（未收攏的代價＝195 組近重複，#456）；真缺摘要 261 → 151（96% 集中
1996–1999）；electronic ISSN 補 1 個（核對後）。

**效能事實（#455）**：逐筆走既有面＝每筆 2 個 process × O(n) 全庫 load ＋ O(n) index
rebuild → 全批 **O(n²)**（實測每筆 2 → 6 秒、1545 筆約 3 小時）。大刊（數萬筆）在 #455
的批次 create 面落地前**不要**用本 skill 全量跑。

## 誠實邊界

- **寫下的世界斷言要先量過**——排除計數、覆蓋率、conflict 數都是當場量的，不寫「應該是」；
  見 [`assertions-must-be-measured`](../../rules/assertions-must-be-measured.md)
- 83/17 的摘要覆蓋、零歧義歸戶、攣生規模都是 Psychological Methods 的數字——**換一份刊
  要重量**，不當通則
- 本次量測中 OpenAlex 的書目欄位（頁碼等）與 Crossref 一致可追溯——**這些欄位**不構成
  獨立第二來源（`storyline#7` 教訓）；其他欄位的獨立性未量測，不宣稱
- 匯入的 authors 是 literal——歸戶是 `resolve-people`／`akashic-person-verify` 的後續，
  本 skill 不做身分判定（`identity-is-judged-not-matched`）
