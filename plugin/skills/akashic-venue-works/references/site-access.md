# 站點存取手冊 — venue → works 補完會碰到的網站怎麼爬

本檔記「哪個網站用什麼判準、踩過什麼坑」。**每一節的結論都是量過的**
（附日期與當時條件，依 `assertions-must-be-measured`）；數字是單站單日的實測，
**換網站或隔久了要重量，不得類推**。新網站＝加一節，不改總括判準（本檔刻意沒有）。

**取得一律經 safari-browser**（Akashic-Library 的專案預設，#634）：程序、分頁鎖定、
插值前的形狀檢查與中止條款見 akashic-bootstrap 的
[web-access.md](../../akashic-bootstrap/references/web-access.md)。本檔各節記的**其他
工具**（curl／WebFetch、agent-browser、osascript）是 2026-08-31／09-01 量到的失敗形狀
與當時的作法，**不是可選的路徑**。

## 取得路徑，與已量過而不再走的路

| 對象 | 路徑（一律經 safari-browser） | 失敗時的樣子 |
|---|---|---|
| 結構化 API（OpenAlex／Crossref） | 頁內 fetch（web-access.md 的〈取一次 API〉），永遠先試 | 欄位缺席（≠ 世界裡不存在，見 Crossref 節） |
| 需要 JS 渲染的頁 | 使用者自己 profile 的真 Safari 分頁，讀渲染後的節點（web-access.md 的〈讀渲染後的頁面〉） | 依賴使用者機器與登入態，無法 CI 化 |

已量過、**不再走**的（量測紀錄，留著是為了說明為什麼只剩上面兩條）：

| 工具 | 量到的失敗形狀 |
|---|---|
| 裸 HTTP（curl／WebFetch） | SPA 回 200 空殼——**狀態碼不是判準** |
| 渲染瀏覽器（agent-browser Chromium） | 指紋防護（Incapsula 等）回擋截頁 |

失敗都要記下**失敗的形狀**（空殼／擋截頁／渲染節流）。2026-09-01 那批量測時的做法是被擋就換工具往上升級；
**2026-09-24 起被擋就是中止條款、整批停**（web-access.md），不換工具、不換來源。

## OpenAlex（API——目錄與摘要的第一站）

- `works?filter=primary_location.source.id:<SID>`，cursor 分頁；摘要在
  `abstract_inverted_index`，要自己還原成文字。禮貌池：帶 `mailto` 參數。
- 實測（2026-08-31，Psychological Methods）：1,556 works，83%（1295/1556）帶摘要。
- **坑：雙斜線 DOI 攣生**。APA 一九九〇年代的 DOI 正式形帶雙斜線（`10.1037//…`），
  OpenAlex 對同文常存單／雙斜線兩筆，摘要常只在一側（實測 197 對）。斜線折疊
  是字串謂詞——**只夠提名不夠判定**（`identity-is-judged-not-matched`），
  處置見 SKILL.md 的攣生節。
- 拿到的是「OpenAlex 在擷取時點、該 filter 視圖下所知的全部」，不等於真實目錄。

## Crossref（API——佐證用，不當第二來源）

- 用途：抽樣當 pagination-regime 證據（#406 的逐刊判定）。
- **沉默有兩個原因**：真的 article-number regime，或**出版商根本沒 deposit**
  （Project Euclid／IMS 一族實測如此，2026-08-30）。所以**只取正訊號**：
  artnum 高 ⇒ false、page 高 ⇒ true、沉默 ⇒ nil（不是 false）。
- 書目欄位（頁碼等）與 OpenAlex 同源可追溯——**不構成獨立第二來源**
  （`storyline#7` 教訓）。

## psycnet.apa.org（APA PsycNet——目前碰過最難的一站）

工具 × 結果（2026-09-01 實測，151 筆批次）：

| 工具 | 結果 |
|---|---|
| curl／裸抓 | HTTP **200** 但 Angular 空殼——判準不可用狀態碼 |
| agent-browser（Puppeteer Chromium） | **Incapsula 擋截頁**：`Request unsuccessful. Incapsula incident ID: …` |
| safari-browser CLI | 可過，但 `open` 必前景（干擾使用者）；未鎖分頁時 **front-tab 漂移**——實測探測讀到使用者自己開的網站 |
| osascript 專用縮小視窗 | 過 Incapsula、完整渲染、不佔前景；~9 秒/筆（縮小不影響渲染，實測） |

**現行取法（未實測——批次前先以 1 筆 PsycNet DOI 試跑）**：照 web-access.md 的〈讀渲染後的頁面〉——在使用者自己 profile
開一個帶一次性 fragment 的分頁、以 `--profile`＋`--url-endswith` 鎖定；同一分頁重用，逐筆導航到帶新碼的網址，再探測渲染後的
節點。這條路**沒有量過**：PsycNet 的跳轉鏈（`doi.org → doi.apa.org → psycnet.apa.org/doiLanding → record`，外加 Incapsula
擋截頁）保不保留 fragment、`open --new-tab` 現在是不是仍必前景、~9 秒/筆的節奏在這條路下是否成立，三件都沒有量。**保留不了
fragment 的話，這個鎖法讀不了這一站**（web-access.md：鎖不到就停、不退回子字串或視窗編號），而中止條款不許換工具——所以**批次前
先用 1 筆 PsycNet DOI 試跑**；試跑不通就停下來回報使用者，不要開批次。上表 safari-browser 那一列的 front-tab 漂移是**未鎖分頁**
時量到的，現行鎖法就是針對它。

**2026-09-01 那批實際用的做法（有量測的既有紀錄——不是指示）**：#423 的 151 筆用的是 osascript 專用縮小視窗，單一視窗、單一
分頁、全程 osascript；過 Incapsula、完整渲染、不佔前景、~9 秒/筆（縮小不影響渲染，實測）：

```applescript
-- 一次性：建專用視窗並縮小（縮小不影響渲染，實測）
make new document with properties {URL:"about:blank"}
set miniaturized of window id WID to true
-- 每筆：重用同一分頁導航 + 鎖定探測
set URL of current tab of window id WID to "<doi-url>"
do JavaScript "…" in current tab of window id WID
```

這個做法**不經 safari-browser、不帶 profile 鎖**，專案預設（取得一律經 safari-browser）不許把它當 skill 的取得指令，**所以它在這裡
只是紀錄，不是指示**：說明上面的現行取法換掉了什麼、為什麼要先試跑。要不要在這一站改用它，是使用者的決定，不是本 skill 的預設。
（#634 曾把這個配方連同標題「正解」一起拿掉、換成沒量過的鎖法；#634 的驗證指出那是行為退化，所以把量過的做法留成紀錄。）

- **判準是渲染後的摘要節點**（`.abstract, [class*="abstract" i], #abstract`），
  不是狀態碼、不是 landing URL。
- 等待：10 秒；`NOABSTRACT` 且未 landed 再等 8 秒重探一次（慢載入）。
- 雙斜線 DOI 會停在 doiLanding 頁、無摘要節點 → 記 `none-verified`（顯式的
  「查過、來源無」），不是留白。
- 跳轉鏈 `doi.org → doi.apa.org → psycnet.apa.org/doiLanding → record`：
  取樣太早拿到的是中繼站 URL，分類 `landing-failed` 前先確認等完跳轉。
- **VPN 幫倒忙**：Incapsula 放行靠的是住宅 IP＋真 Safari 指紋的組合；資料中心
  出口更容易被擋，批次中途換 IP 還會斷 session token。
- 節奏：151 筆、~9 秒/筆、單日跑完無封鎖（2026-09-01，osascript 路徑）。大批量先放慢
  （Cauchy 抖動，做法見 web-access.md 的〈取一次 API〉段末的「節奏」），**不換 IP**——被擋就是中止條款。

## 通用紀律（跨站）

1. **逐筆記** `retrieved` 時間戳＋landing URL＋status（`got`／`none-verified`／
   `landing-failed`／`error`）——「查過沒有」與「沒查到」是兩件事，混在一起就是
   `lossless-intake` 說的最糟形式（靜默）。
2. **只有 `got`／`none-verified` 算完成**；failed／error 在重跑時必須重試——
   第一版腳本把所有記錄過的 DOI 都算完成，failed 永遠不會重試（實測踩到）。
3. 結果檔用 `store-source` 存進內容定址的 sources/（digest 可引用、blob 不進
   git remote）。
4. 批次結束關掉自己開的分頁——第一版累積了 79 個分頁在使用者的 Safari 裡。現行做法：整批沒有觸發中止條款時，用同一把
   鎖關掉（web-access.md 的〈其他〉；`safari-browser close --help` 列出 `--profile`／`--url-endswith`，沒有實跑）；關不掉或
   觸發中止條款時不關，把分頁列給使用者。
5. 取得途中出現懷疑是自動化的訊號（含 Incapsula 擋截頁）：整批停，見 web-access.md。

## 誠實邊界

- 真 Safari **綁定使用者的機器與登入態**：無法 headless、無法 CI、
  無法換機器重現。它是「量過之後不得不」的選擇，不是偏好。
- 本檔的通過／被擋結論都是**當日快照**——防護規則會改版，隔月重跑前先用 1 筆
  重驗，不要直接引本檔的結論開全量。
