# 2026-09-27 多個 DOI 的匯出：第一個進 DOI，其餘進 addendum（#543）

`Entry.doi` 是清單：一筆 work 可以有多個 DOI（#394 的裁決；多數是 APA 一九九〇年代的 `10.1037//x` 與 `10.1037/x` 成對，兩個都是真的號）。`.bib` 匯出卻把整個清單用逗號串成**一個** `DOI` 欄位。biblatex 的 `DOI` 裝一個 DOI、渲染成一條連結，串起來的是一個不存在的 DOI——live store **202 筆**（issue 立案時是 196）的連結是死的。

**裁決（使用者 2026-09-27）：清單第一個進 `DOI`，其餘進 `addendum`。**

- `.bib`：`DOI` 只放清單第一個。其餘以「Other DOI(s): …」接進 `addendum`；已有 addendum 時接在後面，不覆蓋來源給的內容。其餘的號仍是真的號，丟掉等於丟掉一次身分判定，而讀 .bib 的人會以為那是全部。
- csl-json：同一個形狀（單值的 `DOI` 被逗號串接），比照處理。其餘接進 `note`，因為 CSL 沒有 addendum。兩面用同一個函式（`BibExport.appendingOtherDOIs`），同一句話。
- 單一 DOI 不產生 addendum／note。
- live store 202 筆多 DOI 的記錄裡，已有 addendum 的 0 筆。
- 測試（`IdentifierExportTests`）：
  - 三個 DOI → 第一個進 `DOI`、其餘進 addendum、第一個不重複；
  - 已有 addendum 時接在後面；
  - 單一 DOI 不產生 addendum；
  - csl-json 那面。

  原本釘住逗號串接的 `testMultipleIdentifiersAreAllEmitted` 改寫成新契約（它的理由「不得只留一個」仍成立，其餘的號現在住在 addendum）。實作前三條紅；csl-json 那條的負控（CSLExport 換回修正前）2 個斷言失敗。
- `pmid`／`isbn` 維持逗號串接：它們不渲染成連結，沒有死連結的問題。
