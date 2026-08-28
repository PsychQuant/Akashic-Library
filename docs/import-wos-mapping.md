# `import-wos` 欄名對映（正典）

`akashic import-wos` 吃 Web of Science 匯出的 **tab-delimited** 文字檔（逗號分隔加
`--csv`；xlsx 先另存）。本檔是欄名對映的**使用者可讀正典**——程式端的正典是
`Sources/AkashicWoSImport/WoSImport.swift` 的 `entry(from:)`＋`consumedColumns`
（封閉列舉，由 `testEveryConsumedColumnIsDeclared` 機械釘住；本檔逐欄對應該集合，
兩者不一致時**以程式端為準**並回來修這裡）。

## 具名對映（12 欄——`consumedColumns` 全集）

| WoS 欄名（字面） | 去向 | 語意 |
|---|---|---|
| `Authors` | `authors`（`.literal`） | 縮寫形；只在 `Author Full Names` 缺席時當顯示名 |
| `Author Full Names` | `authors`（`.literal`） | 顯示用全名**優先**（給人看的）；與 `Authors` 同列拆分 |
| `Article Title` | `title` | 也是 citekey 的材料 |
| `Publication Year` | `date`（合成） | 與 `Publication Date` 合成 `"<year> <date>"`（trim）；缺 date 時單獨作 `date` |
| `Publication Date` | `date`（合成） | 同上 |
| `Source Title` | `fields["journaltitle"]` | — |
| `Volume` | `fields["volume"]` | — |
| `Issue` | `fields["number"]` | biblatex 慣例：期數是 `number` 不是 `issue` |
| `DOI` | `fields["doi"]` | wos-intake skill 的 DOI 補查**寫回本欄**（填空非覆寫） |
| `Start Page`＋`End Page` | `fields["pages"]` | 合成 `start--end`（兩欄都在才合成） |
| `Group Authors` | `authors` 追加（`.literal`） | 經 corporate 大括號標記保護（#6），export 不切壞 |

- citekey：首作者＋年份＋標題推導（衝突時去重）；type 一律 `article`。

## 殘餘收集（#206 無損契約）

具名對映之外的**每一個**欄位原樣進 `fields`：

- 欄名經 `FieldKey.normalized` 轉合法 biblatex 鍵；**依欄名排序**處理（決定性）
- **不覆寫已對映鍵**——對映結果經語意處理（pages 合成、date 併年日），撞名時語意勝出
- 無法正規化、或撞鍵被讓位的欄位 → 匯入報告的 `droppedColumns`（**丟棄必須可見**）

## 匯入行為

- **idempotent**：判準＝citekey＋內容。已存在且相同 → `unchanged`；不同 → `conflicts`
  （**不覆寫**——store 可能比 WoS 新）；既有記錄缺的欄位可回填 → `enriched`（只多不少）
- `--dry-run` 報告：`created`／`unchanged`／`enriched`／`conflicts`／`droppedColumns`
- **兩個面、同一條路徑**（#290）：CLI `akashic import-wos <path>` 與 MCP
  `akashic_import_wos {path, csv, dry_run}` 都走 `WoSImport.run`——報告欄位同源；
  MCP 的 `path` 是 server 本機路徑（stdio 同機前提，非內容上傳）
- **欄名的字集事實**：CJK 欄名（如「備註欄」）`isLetter` 為真 → 照 #206 收進
  `fields`，**不會**進 `droppedColumns`；只有正規化為空的純符號欄名才會被丟（可見）
- 匯入前的清單 QA（DOI 補查、同篇雙列、分母定案）見 plugin 的 `akashic-import-wos`
  skill；匯入後的重複偵測（DOI 共用組＋同標題同年）由 `akashic doctor` 負責（#94）

## 歷史

- #206：無損匯入契約（殘餘收集的由來與 21 欄靜默消失的失敗史）
- #286：本檔設立——skill 側欄名快照降級為便利複本、以本檔為正典
