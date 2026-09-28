# 2026-09-28 export-tables 多一張 publication_doi 表（#657）

`export-tables` 的 `publication` 表一列一筆 work，而 `Entry.doi` 是清單（#394）。`publication.doi` 一直只輸出第一個 DOI，其餘的號沒有任何一張表收，匯出時也不說。

這一欄原本是零實例下的顯式裁決（2026-08-25，#394）：當時全庫帶多於一個 DOI 的 work 是 0 筆，取第一個不丟任何東西。程式註解寫了觸發條件：出現任何一筆帶兩個結構化 DOI 的 work 就重裁，正解是另立一張 publication_doi 表，不是在 CSV 欄位裡塞分隔符。觸發條件最晚在 2026-09-09 已經成立（#543 立案時量到 196 筆），但那句話只是註解，`validate` 不報多 DOI，沒有任何東西提醒要重裁。直到 2026-09-27 #543 R1 verify 指出這個匯出面，才立了 #657。

## 改了什麼

**依註解自己寫下的那句重裁：另立 `publication_doi` 表。**

- `publication_doi(publication_id, doi_seq, doi)`，一個 DOI 一列。`doi_seq` 0 是主 DOI，其餘依 store 裡的順序。正規形（小寫）相同的號只留一列，`doi_seq` 在去重之後連續；沒有 DOI 的 work 沒有列。
- **`publication.doi` 保留，只放第一個。** 這與 #543 對 `.bib` 的 `DOI` 欄、csl-json 的 `DOI` 的裁決一致（第一個是主 DOI），既有的下游查詢不必改。要全部的號就 join `publication_doi`。
- 兩張表讀同一個函式（`RelationalExport.exportedDOIs`），所以「`publication.doi` 等於 `doi_seq = 0` 那一列」是構造出來的，不靠兩處各自取 `.first` 碰巧一致。去重規則與 `.bib` 的 `BibExport.otherDOIs` 相同。讀的是 `canonicalDOIs`：遷移前只有 `fields.doi` 殘留的記錄也有列，與 `publication.doi` 從 #394 起的讀法相同。
- `load.sql`：建表（外鍵指向 `publication`、主鍵 `(publication_id, doi_seq)`、`UNIQUE (publication_id, doi)`）、子表先 drop、母表先載入。`doi` 不設全域 UNIQUE：同一個 DOI 可以掛在兩筆 work（跨記錄的重複，#79），live store 的副本裡有 16 個。
- `--view` 走同一條 `RelationalExport.tables`，外延外的 work 的 DOI 不會出現，外鍵閉合。
- CLI 結尾多一行：「N 筆 work 帶多個 DOI：publication.doi 只放第一個，全部在 publication_doi」。讀 `publication.csv` 的人因此知道那一欄不是全部。
- CI 的 load.sql 端對端加一筆兩個 DOI 的 work，並斷言 `publication_doi.csv` 有兩列。原本的 fixture 沒有任何 work，這張表只有表頭，灌它的那一行從沒灌過資料。README 的 CI 檢查表同步加一列。
- `akashic-bootstrap` skill 那句「`doi` 欄只放第一個」補上全部的號在哪裡。

## 量測

live store 的唯讀副本（python 複製 `entities/`、`libraries/` 與 `store.yaml` 到暫存目錄，binary 以暫存的 `AKASHIC_HOME` 與 `--library` 執行）：

- 2,563 筆 work，`publication_doi` 2,444 列；
- 202 筆 work 帶多個 DOI：194 筆兩個、8 筆三個；
- `publication.doi` 與 `doi_seq = 0` 那一列不一致 0 筆，`doi_seq` 不連續 0 筆，16 個 DOI 掛在不只一筆 work；
- 用 python 的 duckdb 1.5.5 載入時，publication_doi 的外鍵、主鍵、UNIQUE 全部成立。

## 測試

- `RelationalExportTests` 新增 6 支：三個 DOI 得三列且依序、一個 DOI 一列、沒有 DOI 沒有列、`publication.doi` 等於 `doi_seq` 0；正規形相同的只出一列；只有 `fields.doi` 殘留也有列；新表在 `all` 裡且排在 `publication` 之後；DDL 的外鍵、主鍵、UNIQUE、drop 與載入順序；每張依位置載入的表，DDL 欄位順序與 CSV 表頭一致（涵蓋既有四張）。
- `ViewExportTests` 新增 1 支：view 匯出只含外延內的 DOI，外鍵閉合。
- `ExportTablesCLITests` 新增 1 支：真的 binary 寫出三列的 `publication_doi.csv`，`publication.csv` 只有第一個，結尾有那一行。
- 另跑 `SanitizationBoundaryTests`、`PackageManifestTests`。

負控（逐一改壞、跑測試、反向編輯還原並以 `cmp` 確認與備份逐位元組相同）：

1. 從 `all` 拿掉新表：2 支轉紅（`all` 的排序測試、CLI 測試）。
2. 每筆只出第一個 DOI：4 支轉紅（RelationalExport 2、View 1、CLI 1）。
3. 拿掉去重：1 支轉紅。
4. load.sql 拿掉灌表那一行：1 支轉紅。
5. DDL 的 `doi_seq` 與 `doi` 對調：欄位順序測試轉紅。
6. 拿掉 CLI 結尾那一行：CLI 測試轉紅。
7. CI 那一步：從 fixture 拿掉第二個 DOI，模擬腳本在計數斷言失敗（exit 1）。

## 規則

- `two-kinds-of-edits` 不加列：`export-tables` 不寫 store。
- `mcp-cli-parity`：`akashic_export` 列與 CLI-only 表的 `export-tables --view` 列都重新確認過，裁決不變。那兩列沒有列出匯出哪幾張表，所以不改。
- `zero-instance-guards` 不加列：新表對應的是 202 筆實例，不是零實例。

## 誠實邊界

- 原本的裁決只寫在程式註解裡，沒有進 `zero-instance-guards` 的表，觸發條件也沒有任何機制會出聲。本次沒有補這種機制，只把註解改成過去式並寫上日期。
- 量 live store 副本時另外發現一個既有問題，與本次無關：`load.sql` 的 `UPDATE organization SET parent_id …`（#92 的兩步載入）遇到三層機構鏈就失敗。live store 有 `data-science-statistical-cooperation-center → institute-of-statistical-science → academia-sinica` 這條鏈，python 的 duckdb 1.5.5 報外鍵錯誤；最小重現是三列的自我參照表在同一個 UPDATE 裡設兩層 parent，同一版本下只設一層則通過。CI 用的是 brew 的 duckdb CLI，版本不同，沒有在那裡量過。CI 的 fixture 只有兩層，所以即使同樣會壞也抓不到。上面的 publication_doi 量測是跳過那一句後得到的。
