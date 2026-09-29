# 重跑驗證規則的校準：`akashic fulltext calibrate`

`akashic fulltext verify` 用的門檻（首頁要有一行就是記錄標題、DOI 分三級證據）是 2026-09-24 在 29 份真實 PDF 上量出來的
（自己的標題被收 22/28、別篇標題被收 0/808）。規則改了、或出現新種類的 PDF，就重量一次。**#629 把量測腳本移植成 `akashic` 子命令時沒有重跑那組
29 份**（那批 PDF 與當時的 Crossref 標題不在本機），所以「22/28、0/808」是舊腳本量的，不是移植後的工具量的；新舊工具的一致性只在本機能湊到的
較小語料上驗過（見 akashic repo 的 changelog `2026-09-29-b13p-verify-r1.md`）。

本檔說怎麼重現它。**這不是每次取全文都要做的事**，也不是 skill 流程的一步。

## 需要什麼

1. **一個放 PDF 的資料夾**（遞迴掃 `*.pdf`，略過隱藏檔）。每份要有**首頁印著的 DOI**（沒有 DOI 的略過並在 stderr 計數）。這些是第三方全文，
   放在 git 工作樹之外（`$TMPDIR` 之類），不要進任何 repo。
2. **一個放 Crossref 回應的資料夾**（`--crossref`）：每個檔是 `https://api.crossref.org/works/<DOI>` 的回應（`{"message": {…, "DOI": …, "title": […]}}`），
   **檔名不重要**——以回應裡的 `message.DOI` 對回 PDF。`akashic fulltext calibrate` 不連網：取回是你的事，經 safari-browser、照
   [web-access.md](../../akashic-bootstrap/references/web-access.md) 的程序（頁內 fetch、逐筆、請求之間跑節奏工具、狀態碼決定存法、中止條款）。
   只有 HTTP 200 的本文存成 `<crossref 目錄>/<序號>.json`；404（Crossref 沒有這個 DOI）不存——那個 DOI 會一直被列為「缺」，用 `--partial` 量其餘的，並在結論裡寫有 N 個 DOI 沒有記錄。

## 步驟

```bash
akashic fulltext calibrate "<PDF 資料夾>" --crossref "<Crossref 回應資料夾>"
```

第一次跑，Crossref 資料夾多半是空的。結束碼 **3** 表示還缺回應，stdout 逐個列出**要取的 DOI 與完整網址**（Tab 分隔，DOI 已百分比編碼）：

```text
缺 2 個 DOI 的 Crossref 回應（經 safari-browser 取下面的網址，存進 --crossref 目錄後重跑）：
  10.1037/a0038889	https://api.crossref.org/works/10.1037/a0038889
  …
```

網址是這個命令自己組的，DOI 是從第三方 PDF 的文字層讀出來的——**形狀不合格的 DOI 不會出現在這個清單裡**（含 `'`、`"`、反斜線、`$`、反引號、`#`、`?`、`%`、
空白，或有 `.`／`..` 路徑段），另外在「另有 N 個 DOI 形狀不合格」下面列出，不組網址、不取，那些檔量不到。取回並存好之後**重跑同一條命令**，直到不再缺。

## 結束碼

| 碼 | 意思 |
|---|---|
| 0 | 量完，而且沒有「別篇標題被收」 |
| 1 | 有「別篇標題被收」（規則放行了不該放行的別篇，逐筆列在 `WRONG ACCEPT`）；或一般失敗（資料夾不存在、`--crossref` 不是目錄，訊息具名） |
| 3 | 還缺 Crossref 回應（或有形狀不合格的 DOI）；沒有 `--partial` 時**不印任何數字**——只涵蓋一部分檔案的數字不冒充全部 |
| 4 | **一個檔案都沒量到**（資料夾裡沒有「首頁帶 DOI、而且 `--crossref` 有那個 DOI 的記錄」的 PDF）。輸出的 `0/0` 不是校準結果 |

**`--partial`**：明說「我接受數字只涵蓋有記錄的檔案」。有缺記錄的 DOI 時仍量現有的，並先印一行 `--partial：以下數字只涵蓋有 Crossref 記錄的 N 個檔案`。
用它是為了先看趨勢；要拿數字下結論就補齊記錄再跑不帶 `--partial` 的那一次。

## 怎麼讀輸出

```text
files with a DOI and a Crossref title: N
── title rule                       ← 只看標題規則（titleMatch）
   own title accepted:        a/b   ← 每個檔對它自己的標題，應該被收
   main title only accepted:  c/b   ← 只用主標題（第一個 : ? — 之前），應該被收
   wrong title accepted:      d/M   ← 每個檔對其他每個標題，應該被拒；非零就是問題
── whole decision, record DOI       ← 整個判定（assess，含中繼資料 DOI、記錄 DOI、頁碼範圍）
```

- 「整個判定」的別篇欄近乎套套邏輯：每個檔的 DOI 是從它自己的首頁讀出來的，別筆記錄的 DOI 不可能相符——它守的是迴歸，量不到 `FulltextVerify` 裡寫的回應文／勘誤殘餘。
- 檔名含 `supplement` 的不算「文章」（own／main 只量文章，別篇欄量全部）。
- **數字只對那個語料成立**：換一批 PDF 數字就不同。不要把別的語料的數字寫成「校準結果」；寫語料是什麼、幾份、標題從哪來。
- Crossref 記錄不是唯一的標籤來源：用 store 裡那筆 work 的標題與頁碼包成同一個形狀的 JSON 也可以（標題當標籤），但要說明標籤是 store 的，不是 Crossref 的。

## 需要 `akashic` CLI 含這個子命令

`akashic fulltext calibrate` 是 #629 加進 `akashic` CLI 的；plugin 只自動下載 `akashic-mcp`、不出貨 CLI。舊 binary 上這條命令印
`unexpected arguments: 'fulltext', 'calibrate'`、結束碼 64（見 web-access.md〈開始前〉第 4 點）。
