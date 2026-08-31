---
name: akashic-venue-works
description: >-
  venue → works 的外部補完（#423）：給一個期刊（venue key 或 ISSN），把該刊實際發表過的
  文章補進 Akashic store——增量、可重跑、逐筆可審。當使用者說「把某期刊的全部文章收進來」
  「補完這本刊」「這本刊我的庫裡缺哪些」時使用。與 akashic-bootstrap 的分工：那是
  person → works，本 skill 是 venue → works；與 akashic-venue-verify 的分工：那判定
  「這個刊名是不是這個 venue」，本 skill 假設 venue 身分已定、補的是它的目錄。
---

# akashic-venue-works — 把一本期刊的目錄補進庫

## 本體論前提（#420 裁決，2026-08-28）

收進來的是 **`work:` 記錄＋library membership 標記**——不是新 entity、不是 venue 攜帶
目錄（後者違反 `entity-backlink-completeness` 的「venue 記錄的 works 在不得儲存之列」）。

```
libraries:
- <venue-key>-catalog     ← 期刊目錄（我知道存在的）
```

「我讀過／引用過」的集合是**沒有這個標記**的那些。`work:` 的既有語意不動——目錄記錄
仍要能產出參考文獻（`apa7-is-the-work-floor`），識別碼、venue 邊、resolve-* 一族原樣適用。

## 收錄邊界（#423 量測裁決）

| OpenAlex type | 收不收 | 理由 |
|---|---|---|
| `article`、`review` | ✅ | 是 work |
| `supplementary-materials` | ❌ **不收**（計數報告） | 附錄的 DOI 不是另一篇文章——#394 的多值政策原話：「吸收它等於讓該記錄宣稱自己是另一個物件」。正確落點是原文的 attachments（#424 審議中） |
| `erratum`／`paratext`／`editorial`／`letter` | ❌ 預設不收（計數報告） | 邊界類；要收需顯式裁決 |

**丟棄必須可見**（`lossless-intake` 執行細節 3）：排除的每一類都要在報告裡帶計數。

## 兩階段擷取——界線是量出來的（#423 裁決）

**階段 A（API）**：OpenAlex `works?filter=primary_location.source.id:<SID>` cursor 分頁
全量，一次拿齊結構化欄位＋摘要（`abstract_inverted_index` 還原）。實測 Psychological
Methods：83% 有摘要。

**階段 B（safari-browser，只對 `has_abstract:false` 的那批）**：缺摘要的多在 2015 前，
只存在於 JS 渲染的出版商頁。**判準不是 HTTP 狀態碼**——psycnet 對 headless 回 200 的
Angular 空殼（`akashic-venue-verify` 的 403 訊號在這裡不會出現）；判準是**渲染後有沒有
摘要節點**。查完仍無 → 記顯式的「已查證、來源無摘要」，不是留白。每次重跑對
`has_abstract:false` **現算**（新文章的摘要會遲到），不寫死年份窗。

## 匯入序（全部走既有面——不另寫 importer）

1. `akashic libraries create <venue-key>-catalog`（已存在則略過）
2. **增量 diff**：讀庫內全部 DOI（正規形）集合；來源記錄的 DOI 已在庫 → **跳過並記
   conflict**（`import-wos` 語意：拒絕覆寫——期刊目錄是一次性快照，store 可能比它新，
   #420 裁決 (c)）。無 DOI 的來源記錄照 title+year 比對後仍不確定 → 跳過並具名
3. 逐筆 `create-entry`：type `periodical-article`（review 同）、authors 全部 `.literal`
   （`literal-first-then-key`：進庫不猜）、fields 帶 `journaltitle`／`volume`／`number`／
   `pages`（OpenAlex biblio；article-number 刊的 first_page 若非範圍形，落 `eid` 類欄位
   要逐刊看——見該 venue 的 `paginated` 判定）／`abstract`、識別碼 `--doi`／`--pmid`
4. 逐筆 `libraries add`
5. `migrate-venues`（乾跑過目 → `--apply`）：從 `journaltitle` 回填 venues literal
6. `resolve-venues --apply`（exact 命中既有 venue → `.key`＋confirmed verdict）
7. 順手：OpenAlex 給的 ISSN 若庫內缺 → `update-venue --add-issn`（#394 面）
8. **報告**：新增數／conflict 數／各排除類計數／缺摘要清單（階段 B 的輸入）

## 誠實邊界

- 83/17 的摘要覆蓋是 Psychological Methods 的數字——**換一份刊要重量**，不當通則
- OpenAlex 鏡射 Crossref 的欄位（頁碼等）——它不是獨立第二來源（`storyline#7` 教訓）
- 匯入的 authors 是 literal——歸戶是 `resolve-people`／`akashic-person-verify` 的後續，
  本 skill 不做身分判定（`identity-is-judged-not-matched`）
