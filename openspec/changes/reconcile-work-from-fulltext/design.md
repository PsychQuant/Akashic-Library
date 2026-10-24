## Context

#742：使用者要用作品本身的全文更正既有記錄。觸發實例 `claw2018framework`（Claw et al., 2018, *Nature Communications* 9:2957）的作者列取自 Crossref：20 位，第 6、7 位順序與 PDF byline 相反，13 位聯盟成員被列成作者，團體名沒有 corporate 標記，`export-bib` 把它照人名切開。PDF 第 1 頁 byline 是 7 位（6 位個人＋1 個團體），成員名單在第 7 頁。

現況（2026-10-21，HEAD 494412f9）：

- 會改 `authors` 的面全是局部的：`resolve-people` 的 apply／judge／attribute-org 改一格的身分；`--split-author`／`--un-split`／`--drop-author` 改一格的數量；`enrich --include-absent-authors` 只在 `authors` 全空時補；Zotero pull 以 Zotero 覆寫未歸戶的 literal（只對主來源是 Zotero 的 work）。沒有面能新增 byline 有而 store 沒有的作者、重排、或整組替換。
- `Entry.validateReferenceAttachment` 的 `field: authors` 只收兩種 judgement（拆分 `拆為 ⟦a⟧ ⟦b⟧：理由`、移除 `移除：理由`），value 都是**已退役**的 literal。`docs/store-format.md` 寫明作者位的來源若要記，要另開一格並替會被拆、被移除、被升格的作者位設計定位。
- `AuthorListCompletenessWitness`（`akashic.author-list-completeness`）綁著 work UUID、作者列快照與 fingerprint；decode 時快照與作者列不符即整檔隔離。全庫沒有任何寫入者，live store 0 筆。
- `PDFReader.read` 以 `pdftotext -l 2` 只讀前兩頁，供 `fulltext verify`／`take` 判斷「這份 PDF 是不是這一篇」，不比對書目欄位。
- `update-entry` 的 MCP 描述與 schema 計入 `tools/list` 位元組預算：main（`494412f9`）上是 60,000，現行 59,159（2026-10-20 量），剩約 840 bytes。使用者 2026-10-21 於 #578 裁決把預算提高到 65,000、不拆分 MCP server（原話「提高預算好了，還是你覺得要拆不同mcp，哪一種比較好」），觸發點就是本 change 的 `replace_authors`；守衛常數 `StdioE2ETests.toolsListByteBudget` 在 main 上仍是 `60_000`，由本 change 改（D10）。

使用者 2026-10-21 的四項裁決（#742 Decision comment），其中裁決 3 於 2026-10-24 改判（#742 Decision comment，原話「我覺得要叫bestOCR才行」）：

1. 先做獨立的新 skill，再接在 `akashic-fetch-fulltext` 之後當下一步。
2. 團體成員要記錄（原話「需要紀錄，不然團體可能以後會換成員」）；作者列照 byline，成員不留在 `authors`，記在那一篇 work 上，是出版當時的名單。
3. 沒有文字層的 PDF 由 skill 呼叫 bestOCR，把掃描頁轉成逐頁文字後照常比對；OCR 得到的值在乾跑報告標「OCR」，一律要使用者 apply 才寫入；只有 bestOCR 不可用、轉出失敗或信心不足時，才標成無法核對並說出原因（D14）。2026-10-21 的原裁決是「標成無法核對、跳過，不做 OCR」；改判的理由是跳過會讓沒有文字層的舊文獻永遠留著登記機構給的錯，而這類文獻正是最需要回作品本身核對的一群。
4. 整份替換作者列時，綁著舊 fingerprint 的完整性證言會失效：移除它，並在報告列出。

## Goals / Non-Goals

**Goals:**

- 一個 CLI＋MCP 對等的入口，能整組替換一筆 work 的作者列，且不安靜丟掉任何已歸戶的身分判定。
- 替換之後 store 說得出依據：哪一份全文（digest）、第幾頁、理由。
- 團體作者的成員名單記在那一篇 work 上，逐字、照原文次序、帶依據與頁序。
- 一個 skill 把「讀全文 → 逐欄比對 → 乾跑給人看 → 人確認後寫入」串起來；確定性的轉文字與比對做成 `akashic` 子命令。
- 沒有文字層的全文也能核對：skill 以 bestOCR 多引擎共識轉出逐頁文字，OCR 讀出的值在乾跑表標「OCR」，共識不足的欄位不提議（D14）。
- `claw2018framework` 的形狀在 scratch store 上端到端可重現：7 位作者、團體帶 corporate 標記、13 位成員記在 work 上、`export-bib` 正確、`validate`／`doctor` 綠。

**Non-Goals:**

- **非作者欄位（標題、卷、期、頁碼或 article number、日期）的寫入與其依據記錄**：`compare` 會比對並列出不一致，但本 change 不新增它們的寫入面；既有路徑（`update-entry --remove-field` 再 `enrich`）寫得進值，卻記不下「出自哪份全文第幾頁」——`enrich` 的 retrieval 記錄要 url 與 HTTP 狀態，而 `sources/index.jsonl` 沒有這兩欄；而 `update-entry` 沒有 references 腿，再加一條要另外佔用 MCP 位元組預算（D10），應在自己的 issue 裡量過再定。另開 issue 追蹤（tasks 的最後一組）。
- **成員名單的歸戶**：成員以字串進庫，不是二態 ref；把成員升格為 person key 的面不在本 change（見 D6）。
- **團體成員的時間軸**：團體做成 organization 實體、帶成員沿革，是另一件事（#742 Diagnosis 的 Residue）。
- **完整性證言的寫入**：本 change 只移除失效的證言，不寫新的（見 D2）。
- **Akashic binary 內建 OCR**：OCR 只在 skill 裡經 bestOCR 做（D14）；CLI、akashic-mcp、App 都不呼叫任何 OCR 引擎，也不把 bestOCR 列為建置或執行的依賴。
- **部分頁沒有文字層的 PDF**：`hasTextLayer` 是整份的判定（D11）；有文字層、但個別頁沒有字母的 PDF，這一輪不對那幾頁做 OCR。skill 需要的欄位若落在那幾頁，該欄標成無法核對並說明是哪一頁；要不要對個別頁做 OCR，留待之後另案。
- **改 live store**：`claw2018framework` 只產出乾跑結果與要執行的命令，由使用者決定套用。
- **#685 的全庫稽核**：本 change 提供工具，不做稽核本身。

## Decisions

### D1 作者列替換掛在 update-entry，兩面共用一個 JSON 解析器

替換腿是 `update-entry --replace-authors <JSON 檔>`（CLI）與 `akashic_update_entry.replace_authors`（MCP，同一個 JSON 物件）。`update-entry` 已經是 work 的部分更新面，命令層已過 #298 的目標確認閘（`WriteGateRulings` 的 `update-entry` 一格是 `.gated`，閘在 `--apply`），新腿不必另設閘。

兩面同一個解析器（`enrich` 的 `decodeProposals` 先例：CLI 讀檔、MCP 把 `Value` 編回 JSON 再解），未知鍵在任何一層都整批拒絕。MCP 的 schema 只宣告 `replace_authors: {type: object}` 加一句描述、形狀指向 CLI `--help`——不展開成巢狀 schema，因為 #578 的裁決要求接近預算時先瘦 input schema（D10）。

替換腿單獨呼叫，不與 `remove_fields`／`add_sources`／`remove_zotero_sources`／`remove_sources` 組合（既有腿的同一條契約）。

**考慮過的另一條路**：開新命令 `replace-authors`。不採：它要另一格 `WriteGateRulings`、另一個 MCP 工具（新工具的描述與 schema 比一個參數貴得多），而它做的仍是「部分更新一筆 work」。

### D2 作者列的依據寫成替換記錄，不寫完整性證言

依據住在 `Entry.references` 的 `field: authors`，作為第三種記錄（替換記錄）。不採用 `AuthorListCompletenessWitness`，三個理由：

1. 證言綁著作者列的確切快照，decode 時不符即**整檔隔離**；而升格（literal → key，`literal-first-then-key` 的常態工作）、拆分、移除都會改變快照，目前沒有任何寫入者會同步證言。寫證言等於讓之後每一次正常的歸戶都把檔案打進隔離。
2. 證言的用途是讓「X 不是 W 的作者」可以判為 fails（`add-evidenced-proposition-negation`）。依 byline 寫的作者列是完整的，但聯盟成員是否算作者，是裁決 2 刻意不放進 `authors` 的那一題；把它做成可判定的否定命題超出本單。
3. 替換記錄失效時只出 warning（D8），不隔離；它描述的是「替換當時依據什麼」，之後的升格不讓它失效。

### D3 替換記錄的文法與唯一解析器

- `field: authors`、**value 缺席**、kind 是 judgement、rests-on **恰好一個** digest（全文 PDF）。拆分與移除記錄的 value 必填，所以 value 缺席就足以在形狀上把三者分開；仍然由 statement 前綴雙重確認。
- statement 文法：`替換為 ⟦a⟧ ⟦b⟧ … ⟦z⟧；依據第 N 頁：理由`
  - 每段 `⟦…⟧` 是替換後作者列那一位寫進 store 的值，逐字（團體位含 corporate 大括號；`from` 沿用的已歸戶位寫成 `key:<person key>` 或 `organization:<org key>`）。段數等於作者列長度，至少 1 段。
  - 段內不得含 `⟦` 或 `⟧`（拆分記錄的同一條規則）。
  - `N` 是 PDF 的實體頁序，從 1 起算，不是印刷頁碼。
  - 理由非空。
- 解析器只有一個（`AuthorListReplacementRecordValue`，與 `SplitRecordValue`、`AuthorRemovalRecordValue` 並列），寫入面與附著驗證都呼叫它。
- 一筆 work 至多一筆替換記錄：新的替換會移除舊的（D5）；decode 遇到兩筆即視為不合法（與「重複的判定記錄」不同類，這是值域約束）。
- rests-on 的 digest 必須合法且不是空內容的 digest（沿用 `ProvenanceReference.isValidDigest`）。

### D4 已歸戶的位置要被沿用或明列釋放

新作者列的每一位是 `{"literal": …}`、`{"group": …}` 或 `{"from": i}` 之一。`from` 原樣沿用舊作者列第 i 位（從 0 起算，與 `resolve-people` 的作者位索引同一套），三種狀態都可沿用。

舊作者列中每一個 `.key`／`.organization` 位，必須被某個 `from` 沿用，或列在 `release`（`{"index": i, "reason": …}`）。兩者都沒有即整批拒絕、零寫入，訊息逐位列出。理由：替換時安靜丟掉一個 key 等於撤銷一個身分判定（`identity-is-judged-not-matched`），而不經人手的「依名字自動對回」是字串謂詞做身分判定，本 repo 明令禁止。

- `release` 只收已歸戶的位置（literal 不需要釋放，直接不寫進新列即可，放進 `release` 即拒絕）。
- 同一個舊位置不得既被 `from` 又被 `release`，也不得被兩個 `from` 沿用。
- `release` 不刪任何判定記錄；person／organization 上仍以舊 literal 指向本 work 的 confirmed 判定，列在報告（D5 的 `verdictsOnRetiredLiterals`）。

### D5 舊作者列的記錄一併移除並逐筆列出

替換實寫時，這筆 work 上描述舊作者列的記錄全部移除：`field: authors` 的拆分記錄、移除記錄、先前的替換記錄，以及 `akashic.author-list-completeness` 證言（裁決 4）。每一筆逐字列在報告（`recordsRemoved`、`witnessRemoved`）。實寫前要求該 work 檔已 commit 且乾淨（`assertRecordsRecoverable`），被移除的記錄在 git 裡有副本——比照 `--un-split` 刪除拆分記錄的既有裁決（#513／#659）。

報告另列 `verdictsOnRetiredLiterals`：person 與 organization 記錄上，value 形如 `work:<本 work 的 citekey> :: <literal>` 的 confirmed 判定，而該 literal 不在新作者列的任何 literal 位。只列不改。

### D6 團體成員名單住在 work 頂層的 group-members，成員是字串

形狀：

```yaml
group-members:
- group: "{Summer internship for INdigenous peoples in Genomics (SING) Consortium}"
  rests-on: sha256:<64 hex>
  page: 7
  members:
  - <成員 1，逐字>
  - <成員 2，逐字>
```

- `group` 逐字等於作者列中一個團體位的值（含 corporate 標記）。寫入時必須對得上；之後該位被 attribute-org 升格為 organization，名單照留（它記的是作品裡寫的團體名）。
- `members` 至少一位，次序照原文，不得有逐字重複。
- `rests-on` 一個合法 digest、`page` 是 PDF 實體頁序。依據直接寫在名單上，不另寫 `Entry.references` 記錄：名單只由替換腿寫，理由已在替換記錄裡。
- 住頂層而不住 `akashic` 命名空間：成員名單是作品本身說的書目事實（與 `authors` 同類），不是 Akashic 的簿記。
- 成員是字串，不是 `.literal`／`.key` 二態 ref。理由：目前沒有任何面能把成員升格為 person key；做成二態 ref 就是新的關係邊（`entity-backlink-completeness` 的封閉列舉要加一列），`rename-person` 與 person 合併都得遷移它，而它在這一輪不會有任何 key。升格為 ref 是一次顯式裁決，屆時另開 change（tasks 的 follow-up issue）。
- 替換腿的 `groupMembers` 鍵：**有給**（含空陣列）→ 整組替換名單；**沒給** → 保留舊名單中 `group` 仍對得上新作者列團體位的組，其餘移除並列在報告（`groupMembersRemoved`）。

### D7 store format 23 一次管兩個新形狀

替換記錄與 `group-members` 共用一次 bump：`StoreVersion.supported` 22 → 23，新增常數 `authorListReplacementFormat = 23`。寫入閘：一筆 work 帶替換記錄或 `group-members` 時，只能寫進 marker ≥ 23 的 store，否則拒絕並說出所需格式（比照 split 的 format 16、移除的 17）。舊 binary 遇到 marker 23 整份拒讀；CLI、akashic-mcp、App 三個 binary 一起升，marker 由使用者在三者都升完之後升。

### D8 替換記錄失效時出 warning

`StoreHealth` 新增一族 warning（前綴 `作者列替換記錄與目前的作者列對不上`，計數進 doctor 與 App）：替換記錄的段數與目前作者列長度不同，或某一位是 `.literal(s)` 而 `s` 與同位的段不是位元組相同。目前位是 `.key`／`.organization` 時一律視為相符（升格是常態工作）。warning 不擋寫入；處置是用全文重新核對後再替換一次。

### D9 Zotero pull 保留帶替換記錄的作者列

`ZoteroImporter` 的更新分支今天在「沒有任何已歸戶作者」時以 Zotero 覆寫作者列。條件改為：沒有已歸戶作者**且**沒有替換記錄時才覆寫；有替換記錄時保留，記進既有的 `authorsPreserved`。依據 #639：作品本身是書目的依據，登記機構與 Zotero 是線索；全文核對過的作者列被下一次 pull 改回去，會安靜推翻一個判定。pull 對 `fields` 的整份替換不在本 change 的範圍（非作者欄位的 Non-Goal）。

### D10 MCP 位元組預算提高到 65,000，schema 仍不展開

- 依使用者 2026-10-21 的 #578 裁決，守衛常數 `StdioE2ETests.toolsListByteBudget` 由 `60_000` 改為 `65_000`；常數上方的裁決史註解與 `.claude/rules/mcp-cli-parity.md` 的〈工具描述有位元組預算〉段各補一句這次裁決（日期、65,000、不拆分 MCP 的三個理由指向 #578）。
- `replace_authors` 的 schema 仍是不展開的 object，描述一句指向 CLI `--help`。預算提高不是展開 schema 的理由：#578 的裁決同時寫明，下次接近預算時先瘦 input schema，再考慮提高。
- apply 時量 `tools/list`（`StdioE2ETests.testToolsListResponseStaysWithinByteBudget`），實測值寫進 changelog。超出 65,000 時不再自行調高，停下回 #578 請使用者裁決，在那之前不推。
- **考慮過的另一條路**：拆成讀、寫兩個 MCP server。使用者不採，理由記在 #578：active store 是各 server 的 session 狀態，拆開後會讀一個 store、寫另一個而沒有錯誤訊息；兩個 server 通常都開著，送進 context 的位元組總數不變；plugin、簽章與 parity 裁決表都得跟著拆。

### D11 確定性計算做成 fulltext 子命令，判讀留給 skill 裡的模型

- `akashic fulltext text --citekey <ck> [--source <digest>] --out <file>`：從 work 的 `akashic.sources` 取一份 PDF（`sources/index.jsonl` 的 media-type 是 `application/pdf`），以 `pdfinfo` 取頁數、`pdftotext` 逐頁取文字，寫成 JSON 到 `--out`。work 連了不只一份 PDF 而沒給 `--source` 時拒絕並列出各 digest。`--out` 必須在任何 git 工作樹之外（全文是第三方有版權的內容，`fulltext take` 的同一條規則）。新函式另開，不改 `PDFReader.read` 的兩頁行為，`fulltext verify`／`take` 不受影響。
- 沒有文字層的判準：所有頁的文字都不含任何 Unicode 字母（general category L）。`hasTextLayer: false` 是 skill 走 OCR 路徑的觸發條件（D14）；`fulltext text` 本身只判定、不做 OCR。
- `akashic fulltext compare --citekey <ck> --proposal <file> [--out <file>]`：讀 store 現值與模型寫的提議 JSON，逐欄輸出比對表，作者列不同時另輸出一份可直接交給 `update-entry --replace-authors` 的 JSON；提議中的 `from`／`release` 以替換腿的同一個驗證器先驗，讓會被拒的提議在乾跑階段就說出來。不寫 store。
- 判讀（哪一行是 byline、人名怎麼切、哪一段是成員名單）由 skill 內的模型做；`two-kinds-of-edits` 的「提名（程式）→ 判定（AI／人）→ 落地（程式）」。

### D12 akashic-verify-work skill 的邊界

- 只讀本機 `sources/` 的全文；不連網，所以不涉及 `web-access-via-safari-browser`。需要 OCR 時只用 bestOCR 的本機引擎，全文不離開本機（D14）。
- 每次執行先乾跑：表格每列是「欄位／store 現值／作品本身（PDF 頁序）／文字來源（文字層或 OCR）／提議寫入」。使用者明確同意後才以 `update-entry --replace-authors … --apply` 寫入；unattended 時只產出乾跑。
- PDF 不在本機、work 沒有連任何全文：標成無法核對並說出原因，不猜。沒有文字層不在此列，改走 D14 的 OCR 路徑；只有 D14 列出的情形（bestOCR 不可用、轉出失敗、信心不足）才因 OCR 而標成無法核對。
- 非作者欄位的不一致只列出，並說明目前的寫入路徑記不下依據（Non-Goals）。
- `akashic-fetch-fulltext` 的最後一步指向本 skill（裁決 1 的第二步）。

### D13 規則表各加的列

- `plugin/rules/source-of-truth-over-consent.md`：加「團體署名與成員名單」一列——依據是作品本身的 byline 與文末（或作品內任何位置）的成員名單；使用者的話是線索。
- `docs/rulings/two-kinds-of-edits.md`：`update-entry --replace-authors` 是 AI 編輯（判定哪一份才是 byline；理由與依據必填、留替換記錄、可由 git 取回）；`fulltext text`／`compare` 不寫 store，不進此表（此表只收寫入面）。
- `docs/rulings/mcp-cli-parity.md`：`akashic_update_entry` 一列追加「#742 重新確認，裁決不變、契約有改」；CLI-only 表加 `fulltext text`／`fulltext compare`（skill 的內部步驟，理由同 `references` 一列）。
- `docs/rulings/zero-instance-guards.md`：D8 的 warning 一列。
- `Sources/akashic/WriteGateRulings.swift`：`fulltext text`、`fulltext compare` 登記為不寫 store。

### D14 沒有文字層時，skill 逐頁呼叫 bestOCR 多引擎共識（裁決 3，2026-10-24 改判）

- **觸發**：`fulltext text` 回 `hasTextLayer: false`（判準見 D11）。
- **由誰呼叫**：skill 經 bestOCR plugin 的 MCP 工具呼叫，Akashic 的三個 binary 不呼叫。理由：binary 的輸出要確定，而 OCR 的結果取決於本機裝了哪些引擎、哪個版本；把它留在 skill 層，替換腿與 `compare` 的契約一個鍵都不用加。
- **怎麼呼叫**：
  - 用 bestOCR 的 `consensus`，不用單一引擎的 `ocr`。兩者的差別是：`consensus` 會輸出低共識複核清單（`.consensus.md` 以 ⚠ 標出、`.consensus.json` 列出），`ocr` 不輸出任何信心值，用它就沒有東西可以判斷信心足不足。
  - 一次只送一頁：`pages` 依序設為 `"1"` 到 `"<pageCount>"`。這樣替換記錄的頁序 `N` 由呼叫方式就確定，不必從 bestOCR 的輸出反推哪段文字在哪一頁。
  - `out_dir` 設在 `fulltext text` 用的同一個暫存目錄（git 工作樹之外），用完即丟。理由與 `fulltext text` 的 `--out` 規則相同：輸出是第三方有版權的全文。
  - 不指定任何 `cloud.*` 引擎（`consensus` 不帶 `engines` 時用全部本機引擎）。`cloud.*` 會把文件送出本機，與 D12 只讀本機的邊界衝突。
- **信心不足的判準**：一個欄位的提議值所依據的文字，只要有一項落在該頁的低共識複核清單裡，這一欄就標成無法核對（信心不足），不提議。作者列與團體成員名單是同一欄，因為兩者由同一次替換寫入：byline 或成員名單任何一項低共識，作者列整欄不提議，`compare` 的提議也不送出。
- **bestOCR 不可用或轉出失敗**：以下三種情形，整筆 work 標成無法核對，說出是哪一種，並附一行說明裝好 bestOCR plugin 後可以再核對：
  1. 這個 session 沒有 bestOCR 的 MCP 工具；
  2. `list_engines` 回報可用的本機引擎少於兩個（`consensus` 至少要兩個）；
  3. 任何一頁的 `consensus` 回錯誤。
  只有一個本機引擎時，**不**退回用 `ocr`：沒有共識就沒有信心可量，量不到不能當作量過。
- **標記與寫入**：
  - 乾跑表每一列的「文字來源」欄寫「OCR」或「文字層」。
  - OCR 列的寫入閘與 D12 相同：使用者在 session 內明確同意才 apply，unattended 不寫。沒有另設自動寫入的路。
  - 作者列依 OCR 文字替換時，替換記錄的理由要寫明「依 bestOCR 多引擎共識辨識」，並列出這次參與的引擎 id。這樣 store 日後說得出這一筆依據的是 OCR 文字，不必另加欄位。
- **考慮過的另一條路**：讓 `fulltext text` 在沒有文字層時自己呼叫 bestOCR，輸出 OCR 文字。不採：binary 會多一個外部引擎依賴，同一份 PDF 的輸出會隨本機引擎改變，`fulltext text` 也就不再是確定性的計算。

## Implementation Contract

**Behavior**

- 對一筆 work 跑 `akashic update-entry <citekey> --replace-authors <檔>`（不帶 `--apply`）印出計畫，不寫任何檔；帶 `--apply` 時寫入作者列、替換記錄、`group-members`，移除舊記錄與證言，重建 index。
- MCP `akashic_update_entry` 帶 `replace_authors`、`dry_run` 預設 true；回傳與 CLI 同一份 payload。
- `akashic validate` 對失效的替換記錄印 warning，exit 0；`akashic doctor` 與 App 顯示這一族的計數。
- `akashic import-zotero` 對帶替換記錄的 work 保留作者列，記進 `authorsPreserved`。
- `akashic fulltext text`／`compare` 只寫 `--out` 指定的檔。
- `akashic-verify-work` 遇到 `hasTextLayer: false` 時，逐頁呼叫 bestOCR `consensus`（不用 `cloud.*` 引擎、不退回單一引擎），乾跑表標出每一列的文字來源；低共識的欄位與 bestOCR 不可用時標成無法核對（D14）。

**Interface / data shape**

替換腿的 JSON（CLI 檔與 MCP 物件同形，鍵名 lowerCamelCase）：

```json
{
  "source": "sha256:<64 hex>",
  "page": 1,
  "reason": "<非空，≤ 4,096 bytes>",
  "authors": [{"literal": "<人名>"}, {"group": "<團體名，不含大括號>"}, {"from": 19}],
  "release": [{"index": 12, "reason": "<非空，≤ 4,096 bytes>"}],
  "groupMembers": [{"group": "<與某個 group 項逐字相同>", "page": 7, "members": ["<成員>"]}]
}
```

`release` 與 `groupMembers` 可省略。回傳 payload 的鍵：`citekey`、`dryRun`、`unchanged`、`authorsBefore`、`authorsAfter`、`released`、`recordsRemoved`、`witnessRemoved`、`groupMembersAfter`、`groupMembersRemoved`、`verdictsOnRetiredLiterals`（MCP 面截 20 筆並附 `verdictsOnRetiredLiteralsTotal`／`truncated`，CLI 全列）。

`fulltext text` 的輸出：`{"citekey", "source", "pageCount", "hasTextLayer", "pages": [{"page": 1, "text": "…"}]}`。

`fulltext compare` 的提議輸入：`{"source", "authors": {"page", "items": [同替換腿的作者項]}, "release": [...], "groupMembers": [...], "title": {"value", "page"}, "volume": {...}, "issue": {...}, "pages": {...}, "articleNumber": {...}, "date": {...}}`（作者以外的欄位都可省略）；輸出：`{"citekey", "rows": [{"field", "store", "proposed", "page", "status"}], "replaceAuthors": <替換腿 JSON 或 null>, "refusal": <替換腿驗證器的拒絕訊息或 null>}`，`status` ∈ `same`／`differs`／`absentInStore`／`notProposed`。

**Failure modes**（全部整批拒絕、零寫入、訊息具名）

- JSON 任一層有未知鍵、缺必填鍵、型別不對。
- `source` 不是合法 digest、是空內容的 digest、沒有連在這筆 work 的 `akashic.sources`、本機 `sources/` 沒有這份內容。
- `page` 不是 ≥ 1 的整數；`reason` 空白或超過 4,096 bytes。
- `authors` 為空；某一項不是恰好一個鍵；`literal`／`group` 空白、前後有空白、含 `⟦` 或 `⟧`、超過 65,536 bytes；`literal` 本身帶 corporate 大括號（要用 `group`）。
- `from` 超出範圍、同一位被沿用兩次；`release` 指到 literal 位、指到被 `from` 沿用的位、重複；有已歸戶位既沒被沿用也沒被釋放。
- `groupMembers` 的 `group` 對不上任何團體項、同一組出現兩次、`members` 為空或有逐字重複。
- store marker < 23；work 無法唯一定位（`unlocatableCitekeys`）；實寫時 work 檔未 commit 或不乾淨。
- 與其他 `update-entry` 腿同一次呼叫。

**Acceptance criteria**

- 以 `claw2018framework` 的形狀建 scratch store（20 位作者、其中一位是已歸戶的 key）跑完替換：作者列 7 位、第 6 位是 `{Summer internship … (SING) Consortium}`、第 7 位以 `from` 沿用原本的 key；13 位成員記在 `group-members`；替換記錄的 statement 解析出 7 段；`export-bib` 的 AUTHOR 把團體輸出為一個 corporate 名；`validate` 與 `doctor` 沒有新的 error 或 warning。
- 每一條 failure mode 都有一個測試，且負控（移除那條檢查）會讓它變紅。
- format 22 的 store 上實寫被拒，訊息說出 23。
- 替換後再對同一筆 split 一位，`validate` 出 D8 的 warning。
- 主來源是 Zotero、帶替換記錄的 work，pull 之後作者列不變且列在 `authorsPreserved`。
- `fulltext text` 對有文字層的 PDF 回 `hasTextLayer: true` 與全部頁；對只有圖片的 PDF 回 `false`；`--out` 落在 git 工作樹內時拒絕。
- `StdioE2ETests.toolsListByteBudget` 是 `65_000`，`tools/list` 實測不超過 65,000 bytes。
- 對只有圖片的三頁 fixture PDF 跑 skill：`consensus` 被呼叫三次（`pages` 為 `"1"`、`"2"`、`"3"`），沒有任何 `cloud.*` 引擎；乾跑表的列標「OCR」。在沒有 bestOCR 工具的 session 跑同一份：整筆標成無法核對，原因指名缺少的工具，且 `update-entry` 沒有被呼叫。
- `Sources/` 內沒有任何對 bestOCR 或其他 OCR 引擎的呼叫。

**Scope**

- In：上列 CLI／MCP 腿、兩個 fulltext 子命令、新 skill（含 D14 的 OCR 路徑）與 `akashic-fetch-fulltext` 的指向、format 23、D8 warning、D9 pull 規則、規則表與 `WriteGateRulings`、`docs/store-format.md`、`writing-to-the-store.md`、plugin 殼 0.13.7、changelog。
- Out：Non-Goals 所列各項。

## Risks / Trade-offs

- [MCP 預算在 main 上只剩約 840 bytes] → 依 #578 裁決提高到 65,000；schema 仍不展開、描述一句；超出 65,000 時停下回 #578（D10）。
- [format bump 打三個 binary] → 三者同一個 release；marker 由使用者在三者都升完後升；changelog 寫部署順序。
- [模型抽錯 byline 而提議看起來是對的] → 一律先乾跑給人看，apply 要明確同意；`compare` 只產生提議，不寫。
- [released 的 key 留下指向已退役 literal 的 confirmed 判定] → 報告逐筆列出；不自動刪（程式編輯不刪判定編輯的產物）。
- [替換記錄與之後的拆分／移除並存而失效] → D8 warning；重新核對後再替換即消失。
- [`fulltext text` 的輸出含第三方全文] → `--out` 必須在 git 工作樹之外，skill 用暫存目錄，用完即丟。
- [成員是字串，日後要升格時得遷移] → 升格是顯式的下一個 change；現在的字串就是 `literal-first-then-key` 說的誠實狀態。
- [OCR 把字認錯，而且多個引擎錯得一樣] → 共識只能擋住引擎之間意見不一的錯；同樣的錯認仍可能過關。所以 OCR 列一律標出來源、一律要人確認，替換理由寫明依據是 OCR（D14）。
- [逐頁呼叫多引擎共識很慢] → 接受。只有沒有文字層的 PDF 才走這條路，而頁序必須由呼叫方式保證（D14）。
- [bestOCR 的引擎或版本換了，同一份 PDF 轉出不同文字] → 替換理由列出參與的引擎 id；要重新核對時，用當時的全文重跑一次即可，store 不依賴 OCR 輸出可重現。

## Migration Plan

- 沒有資料遷移：兩個新形狀都是新增的。
- 部署順序：同一個 release 出 CLI、akashic-mcp、App → 使用者更新三者 → 使用者把 marker 升到 23 → 之後才寫得進替換記錄。在那之前替換腿對 format 22 的 store 拒絕實寫（乾跑照常）。
- 回滾：替換前要求 work 檔已 commit，任何一次替換都能以 git 取回舊檔。
- live store 的 `claw2018framework`：實作完成後產出乾跑結果與命令，交給使用者。

## Open Questions

（none。原本的一題「`tools/list` 超過 60,000 時要不要調高預算」，使用者已於 2026-10-21 在 #578 裁決：提高到 65,000、不拆分 MCP，見 D10。）
