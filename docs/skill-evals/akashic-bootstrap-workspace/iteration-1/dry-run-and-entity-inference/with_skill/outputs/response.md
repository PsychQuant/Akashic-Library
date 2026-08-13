# 這三篇論文的乾跑報告

依 `akashic-bootstrap` skill 的流程處理：先查 store 已有什麼 → 查 Crossref 書目 → 四訊號驗證 + 反向驗證 → 產出這份可審的乾跑清單。**目前尚未寫入任何東西**，原因見文末「為什麼停在乾跑」。

## 前置檢查

- `akashic doctor --library <store>`：12 works、12 people、0 relations、0 orphaned、23 個未歸戶作者裸字串。
- `akashic validate --library <store>`：12/12 works、12/12 people 全數通過 schema 驗證。
- 對 store 全文搜尋三篇論文的標題關鍵字，**確認三篇都不在 store 裡**，無重複風險。
- store 的 git 工作樹目前 ahead of origin 1 commit、無未追蹤變更（在這份 store 自己的範圍內乾淨），有退路。

## 會寫入的內容（乾跑）

### 新建 work（3 筆）

**1. yang2026fourier**
```
title: Fourier analysis of spatial point processes
type: article
date: 2026-02-01
authors:
- literal: Junho Yang
- literal: Yongtao Guan
fields:
  doi: 10.3150/25-bej1862
  journaltitle: Bernoulli
  volume: 32
  number: 1
```
判定依據：Crossref 標題完全相符（相似度 1.00）、期刊名完全相符、年份相符、`type: journal-article`。反向驗證：用 DOI `10.3150/25-bej1862` 回查，標題／期刊／卷期／作者一致。Crossref 未回傳頁碼（`page: null`），故不補 `pages` 欄位。作者機構（Crossref `author[].affiliation`，僅供參考、未寫入）：Yang — Institute of Statistical Science, Academia Sinica；Guan — School of Data Science, CUHK-Shenzhen。

**2. jou2025generalized**
```
title: A Generalized Mean Approach for Distributed-PCA
type: article
date: 2025-10-24
authors:
- literal: Zhi-Yu Jou
- literal: Su-Yun Huang
- literal: Hung Hung
- literal: Shinto Eguchi
fields:
  doi: 10.1080/10618600.2025.2561234
  journaltitle: Journal of Computational and Graphical Statistics
  volume: 35
  number: 2
  pages: 685-693
```
判定依據：標題／期刊名相似度均為 1.00、`type: journal-article`。反向驗證：DOI `10.1080/10618600.2025.2561234` 回查一致。**日期待人工判定**：Crossref 給了兩個日期——online-first 為 2025-10-24（即上面採用的 `issued`），印刷卷期（vol.35 issue.2）標的是 2026-04-03。上面用的是 Crossref 的 canonical `issued` 日期；若你偏好用印刷年份，citekey 會變成 `jou2026generalized`，兩者都告訴你一聲，由你選。作者機構（僅供參考）：Jou、Huang — Institute of Statistical Science, Academia Sinica；Hung Hung — Institute of Health Data Analytics and Statistics, NTU；Eguchi — Institute of Statistical Mathematics, Tokyo。

**3. chu2024pseudo**
```
title: Pseudo datasets explain artificial neural networks
type: article
date: 2024-04-10
authors:
- literal: Yi-Chi Chu
- literal: Yi-Hau Chen
- literal: Chao-Yu Guo
fields:
  doi: 10.1007/s41060-024-00526-9
  journaltitle: International Journal of Data Science and Analytics
  volume: 20
  number: 2
  pages: 1263-1304
```
判定依據：標題／期刊名相似度均為 1.00、`type: journal-article`。反向驗證：DOI `10.1007/s41060-024-00526-9` 回查一致。**日期待人工判定**：同上模式——online-first 2024-04-10（採用中）vs. 印刷卷期（vol.20 issue.2）2025-08；偏好印刷年份的話 citekey 會是 `chu2025pseudo`。Crossref 這筆沒有任何作者機構資料（三位作者的 `affiliation` 欄位都是空的）。

### 作者處理方式（本次不新建 person）

上面 3 筆合計 9 個作者槽、對應到 **9 個不同人名**：Junho Yang、Yongtao Guan、Zhi-Yu Jou、Su-Yun Huang、Hung Hung、Shinto Eguchi、Yi-Chi Chu、Yi-Hau Chen、Chao-Yu Guo。逐一比對過 store 現有 12 筆 `person:` 實體與既有的裸字串作者，**這 9 人目前都沒有對應的 person 實體**，所以上面全部用 `literal:` 表示（裸字串，未歸戶），不新建 person key。

**Yi-Hau Chen 是一個值得注意的發現**：這個名字的字串「Yi-Hau Chen」已經以未歸戶裸字串的形式出現在 store 現有的 **4 筆** works 裡（`yc2009associations`、`chen2020association`、`yang2017composite`、`shen2015model`），但目前沒有任何 `person:` 實體對應到他。這篇新論文會讓這個字串第 5 次出現。這不影響能不能寫入這篇新論文，但如果之後想幫 Yi-Hau Chen 建一個 person 實體，`resolve-people` 可以一次把這 5 筆（4 舊 + 1 新）都歸戶掉——算是「追關係順便告訴你還缺什麼」的例子。要不要建這個 person，以及要不要幫其他 8 人建 person，都留給你決定；建議留到你確認「作者到底要不要建成實體」之後，用 `akashic bootstrap-people` 走正規入口處理。

### 待人工判定（3 筆）

- **jou2025generalized 的日期年份**：online-first (2025) vs. 印刷卷期 (2026)，見上方。
- **chu2024pseudo 的日期年份**：online-first (2024) vs. 印刷卷期 (2025)，見上方。
- **Yi-Hau Chen 的歸戶時機**：見上方「作者處理方式」——本次不動，留給你決定。

## 為什麼停在乾跑（沒有寫入）

Skill 本身的骨架是「先看 store → 再查外部 → 驗證 → **乾跑** → 才寫」，第 5 步「寫入」明文要求「使用者明確同意後才寫」——乾跑報告本身就是給人審的那個停頓點，不是走個過場。這次還額外疊了一個結構性理由：

這次任務環境限定只能用本機 CLI 二進位（`.build/.../akashic`），且明確禁止呼叫任何 `mcp__*akashic*` 工具（那些指向另一個真實 store）。但 skill 自己的文件（`writing-to-the-store.md`）記載得很清楚：**新建 work 唯一的正規入口是 `akashic_create_entry` 這個 MCP 工具**；CLI 這邊我逐一核對過原始碼（`Sources/akashic/CLI.swift`）的完整子指令清單——`import-zotero`、`validate`、`export-bib`、`resolve-people`、`doctor`、`query`、`graph`、`rename`、`library`、`file`、`migrate`、`export-tables`、`import-wos`、`bootstrap-people`——**沒有任何一個能建立新的 work 實體**。也就是說，在這個任務給定的工具範圍裡，本來就沒有「不手刻 YAML、且不繞過 MCP 限制」的合規寫入路徑。

面對這個缺口，唯一站得住腳的做法就是不硬闖：不用暫存指令偽裝成別的格式塞進 `import-wos`，也不手刻 YAML 塞進 `entities/`（那正是 skill 明文警告過、會產生兩種位元組表示、事後不可逆的錯誤繞法）。所以這份乾跑報告就是這次任務的完整交付——資料查清楚了、驗證做完了、寫入前該有的判斷點也標好了，只等一句「apply」，屆時在有 `akashic_create_entry` 可用的環境（真正的 store、非這個受限的測試沙盒）走正規入口寫入即可。
