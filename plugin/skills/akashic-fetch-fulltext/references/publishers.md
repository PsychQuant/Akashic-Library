# 各出版商的取得規則與已知陷阱

每一條都是**某一天觀察到的站點行為**，不是永久事實——出版商會改版。表中日期是最後一次實測；超過幾個月沒再遇到的規則，用之前先看一眼頁面。規則的程式版是 `akashic fulltext url-rule`（原始碼在 akashic repo 的 `PdfUrlRules.swift`，plugin 安裝處讀不到），改這裡時同步改那裡（並補 repo 內測試的案例）。

所有觀察都在使用者的機構網路下、以使用者自己的 Safari profile 進行。**權限因機構而異**：這裡寫「取得成功」只代表那個機構那一天有權限。

## 規則表

| 站 | 症狀 | 做法 | 觀察 |
|---|---|---|---|
| Taylor & Francis（tandfonline.com）| 跳轉中繼頁先回 `readyState=complete`，文章頁還沒載入，此時找不到 PDF 連結 | 等 PDF 連結出現（`fetch` 的 45 秒等待）；`/doi/pdf/<doi>` 回 `application/pdf` | 2026-09-23，6 篇成功 |
| SAGE（journals.sagepub.com）| `citation_pdf_url` 指向 `/doi/reader/`，回 `text/html`（線上閱讀器）| `/doi/pdf/<doi>?download=true` | 2026-09-23，3 篇成功 |
| SAGE | 頁面 60 秒內 `readyState` 未到 `complete` | `interactive` 即可繼續 | 2026-09-23，1 篇 |
| Wiley（onlinelibrary.wiley.com）| `/doi/pdf/<doi>` 回 HTML 檢視器 | `/doi/pdfdirect/<doi>`；舊式 SICI DOI 原樣帶入即可 | 2026-09-23，2 篇成功 |
| APA PsycNet（psycnet.apa.org）| 有權限時 DOI 跳到 `/fulltext/<id>.html` | `/fulltext/<id>.pdf` | 2026-09-23，3 篇成功 |
| APA PsycNet | 有時停在 `doiLanding?doi=…`，不跳 `/record/` | 從頁面的 `/record/<id>` 連結取 id | 2026-09-23 |
| APA PsycNet | `/fulltext/<id>.pdf` 回 HTTP 200、約 8,028 bytes、內容「Loading…」；書目頁只有 Login／Access 按鈕 | **視為無權限，停**（`fetch` 結束碼 4）。同一期刊前後幾篇有權限、這幾篇沒有，原因未查明 | 2026-09-23，6 篇 |
| Annual Reviews（annualreviews.org）| 「download PDF」是 `href="#"` 的按鈕；第一個 `.pdf` 連結是**補充資料** | 按鈕外層是 POST 表單 `form.ft-download-content__form--pdf`，以表單送出 | 2026-09-23，1 篇 |
| Oxford Academic（academic.oup.com）| 頁內 fetch PDF 回 403「Just a moment…」（Cloudflare）| **中止條款：整批停**（結束碼 6）。2026-09-23 當時是改找 PMC 作者稿繼續——那是在被懷疑之後換路，2026-09-24 起不再這樣做 | 2026-09-23，1 篇 |
| PubMed Central（pmc.ncbi.nlm.nih.gov）| 頁內 fetch PDF 回約 1.8 KB 的防爬蟲驗證頁 | **事先**用 `--prime <PDF URL>`：像人一樣先在分頁開一次 PDF 網址，再從文章頁取。這是預先的一般瀏覽，不是被擋後的繞路；**prime 過仍出現驗證頁 → 中止條款，整批停** | 2026-09-23，1 篇成功 |
| OSF／PsyArXiv、機構典藏（UvA）| — | 2026-09-23 以一般 HTTP 下載成功；**這條路自 #634 起不是本 skill 的取得方式**（一律經 Safari），經 `fetch` 取這幾站沒有量過——遇到照結束碼處理，新量到的寫在這一列 | 2026-09-23，4 篇成功（一般 HTTP 下載）|

## `fetch` 已內建、不必每次想起的陷阱

- **同一網址兩個分頁**：使用者已開著同一頁時，以網址鎖定會比對到兩個分頁，safari-browser 依設計 fail-closed。`fetch` 全程以「視窗＋分頁位置」鎖定，每一步前核對該分頁仍顯示同一站。
- **zsh 保留變數**：`UID` 在 zsh 是唯讀的使用者 ID，賦值會變成「切換使用者」而被拒。這是舊 shell 腳本踩過的；#629 起 `fetch` 是 Swift，不再有這個問題（條目保留當作紀錄：新寫的 shell 片段仍要避開這個名字）。
- **`%PDF` 不等於這篇**：補充資料、作者稿都通過檔頭檢查；`akashic fulltext verify` 比對頁數與首頁標題（門檻與校準資料寫在 akashic repo 內 `FulltextVerify.swift` 的型別註解，plugin 安裝處讀不到）。
