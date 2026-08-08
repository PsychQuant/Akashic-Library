---
name: akashic-cv
description: "補完一個 person 的學術 CV——ORCID 優先、個人網站次之；聚合來源需顯式指定。Tier 1/2 才直接寫入 store。"
compatibility: Requires the `akashic` CLI and (for Tier 1) che-zotero-mcp.
---

# /akashic-cv — 補完一個人的學術 CV

輸入一個 person key，依**來源權威性**逐層把他的著作補進 store。

現在 store 內一個 person 的作品集合是**被動**形成的：某篇 work 先被匯入，再經
`resolve-people` 把作者槽從 `.literal` 換成 `.key`，那個人才「擁有」它。本 skill 是
**主動**的那一半。

## 權威性階序（沿用 che-zotero-mcp 的 `DATA_SOURCE_CREDIBILITY.md`，不另立一套）

| 層級 | 來源 | 為什麼可信 | 可直接寫入？ |
|---|---|---|---|
| 1 | **ORCID** | 本人維護，**零 disambiguation** | ✅ |
| 2 | **個人網站** / CV / publication list | 本人維護 | ✅ |
| 3 | OpenAlex、Scopus 等聚合來源 | 演算法歸戶，**會錯** | ❌ 預設不採用；要用須 `--allow-tier3` 且逐筆標記來源 |

**「完全一定正確」指的是來源權威性，不是「免確認」。** Tier 1/2 消掉的是
**disambiguation** 的疑問（這篇到底是不是這個人的），不是**寫入**的疑問（store 的
寫入不可逆）。所以流程仍有一次**批次確認**，但**不逐筆問**——逐筆問正是權威性替你
省掉的那件事。

## 四個設計決定（#64 列為待確認的那四項）

1. **skill 住在本 repo 的 `.claude/skills/`**，不做成跨 repo plugin。它吃 store 的
   citekey 慣例、`akashic` 的旗標語意、`.literal`/`.key` 的作者槽模型——這些全都
   住在這裡。跨 repo 重用目前沒有第二個消費者。
2. **個人網站以「貼文字」為主要路徑**，URL 為次。貼 publication list 純文字免掉
   爬蟲與版面適配，而反查 DOI 的那一步（`resolve_references`）本來就吃 reference
   metadata、不吃 HTML。給 URL 時先抓下來、把抽出的清單**顯示給人看過**再往下走。
3. **批次確認，不逐筆**（理由見上）。
4. **不必經 Zotero。** ORCID/CrossRef → Akashic 直達。把 Zotero 設成必經會讓
   store 的完整性取決於一個 GUI app 的 library 狀態，還多一次有損來回。要進
   Zotero 是另一個獨立動作。

## 流程

### 0. 確認人與現況

```bash
akashic query --author <person-key>          # 這個人現在庫內有幾篇
```

（`query` 的旗標是 `--author`——它吃 person key 完全命中或 literal 子字串。
`resolve-people` 那邊才叫 `--person`，兩者不同名。）

沒有 `orcid` 欄就先問使用者，或從 person 的 `profile.contacts` 找 homepage。
**不要用姓名去猜 ORCID iD**——那正是階序要避免的 disambiguation。

### 1. Tier 1：ORCID

用 che-zotero-mcp：

```
mcp__plugin_che-zotero-mcp_zotero__orcid_get_publications(orcid_id: "0000-0003-...")
```

拿到的每筆盡量帶 DOI。缺 DOI 的用 `resolve_references` 反查（CrossRef + OpenAlex +
PubMed）；**反查只用來補 DOI／metadata，不用來擴充清單**——清單的權威來源是 ORCID。

### 2. Tier 2：個人網站 / CV

請使用者貼 publication list（或給 URL，抓下來後把抽出的清單顯示給他看）。逐筆過
`resolve_references` 補 DOI。

### 3. 併集、去重、轉成 TSV

以 **DOI** 為主鍵去重；無 DOI 者用 `title + year` 正規化後比對。與 store 既有記錄
比對（`akashic query`），**已存在的不重建**。

把新的那些寫成 `import-wos` 吃的 tab-delimited 形狀（欄位對照見
`Sources/AkashicWoSImport/WoSImport.swift`）。

### 4. 匯入 + 歸戶

```bash
akashic import-wos /path/to/cv.tsv --dry-run    # 先看會做什麼
akashic import-wos /path/to/cv.tsv              # 作者一律先進 .literal
akashic resolve-people --person <person-key>    # 列出候選，不寫
akashic resolve-people --person <person-key> --apply
```

**`--person` 就是權威性收窄的落點**：它只套用指向這個人的候選。因為 Tier 1/2 已經
保證「這些 work 是他的」，剩下的只是**定位是哪一個作者槽**——那是 alias 完全命中，
不是猜。

某篇的作者槽一個都沒命中 → **報出來，不要猜**。那通常表示這個人的 `names[]` 少了
這篇用的書寫形式；補進 person 的 `names` 再跑一次，比在這裡放寬比對安全。

### 5. 收尾

```bash
akashic doctor
akashic validate
```

`import-wos` 成功後會自己重建 index。

## 鐵律

- **Tier 3 不預設採用。** OpenAlex 的歸戶是演算法產物；把它當權威會把錯誤歸屬寫進
  一個宣稱「本人維護」的 CV 裡，而且事後分不出哪筆是哪一層來的。
- **寫入前一次批次確認。** 顯示「新增 N 篇、歸戶 M 個作者槽、已存在 K 篇不動」再動手。
- **已存在的 work 不重建**，只換作者槽。重建會洗掉人工補過的欄位（`import-wos`
  的 conflict 邏輯已經是這個立場）。
- **來源要留痕。** 哪一層抓到的記在 work 的 source 欄位，事後可稽核。
- **不要用姓名猜 ORCID iD。**

## 已知限制

- Tier 2 目前**沒有自動爬蟲**：給 URL 時是「抓下來 + 人看過」，不是無人值守。個人
  網站的版面沒有共通結構，自動抽取的錯誤會安靜地變成 CV 內容。
- 去重靠 DOI 與 `title+year`。同一篇的 preprint 與 journal 版**會被當成兩筆**——
  那在書目上本來就是兩個記錄，但如果想合併，目前得手動。
- 沒有針對 77 人的批次模式。逐人跑；批次要先解決「一次確認 77 個人的寫入」該長
  什麼樣，那是另一個設計問題。
