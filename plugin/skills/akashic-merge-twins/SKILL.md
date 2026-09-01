---
name: akashic-merge-twins
description: >-
  work↔work 攣生合併（#456／#459）：同一篇作品的多筆記錄（DOI 單／雙斜線攣生、匯入
  近重複）判定並併成一筆，走 divergence 管線（record-divergence → judgement →
  resolve-divergence）。當使用者說「合併攣生」「這兩筆是同一篇」「重複記錄清一清」
  「merge twins」時使用。與 akashic-disambiguate 的分工：那是 literal→key 的消歧
  （歧義列判定），本 skill 是 record↔record 的同一性判定——#459 裁決兩者是不同管線，
  不混在一份 skill。與 akashic-venue-works 的分工：那邊的攣生收攏只做提名，本 skill
  接手判定與合併。

  「寫下的世界斷言要先量過」是本 skill 的執行紀律——見 rules/assertions-must-be-measured.md。
---

# akashic-merge-twins — 把同一篇作品的多筆記錄併成一筆

## 概念定位（#459 裁決，2026-09-01）

攣生合併是**廣義身分判定、非狹義消歧**——`identity-is-judged-not-matched` 全文適用
（字串謂詞只提名、判定要證據、判定留 verdict），但走 **divergence 管線**，不是
resolve-* 的 literal→key 管線。裁決全文見該 rule 的「record↔record 同一性」節。

**識別碼例外在攣生上兩邊都不裁決**：單／雙斜線是兩個都真的 DOI（相等不觸發）；
DOI 不等也不證明是兩篇（#394 終局：**一筆 work 多 DOI**）。

## 提名——兩個謂詞取聯集，都只是提名

```
候選組 ＝ DOI 斜線折疊相同 ∪ 同年＋正規化標題相同
```

實測（Psychological Methods，2026-09-01）：折疊 195 組 ∪ 同題 199 組 ＝ **211 組**，
各有 **12／16 組獨佔命中**——單一謂詞都會漏，聯集是必要的。已知假陰性：標題轉寫
變體（`H₀` vs `H-sub-0`）只有折疊謂詞抓得到；作者 typo 攣生（`Balakrishnon`）只有
同題謂詞抓得到。

**三筆組會被雙重提名**（2 候選子集＋3 候選全集是不同的 frozenset）——除重或接受
雙筆 divergence 並在 resolve 時現場查詢（見執行序第 5 步）。

## 判定——逐組證據，兩類終局

比對欄位（**七個都要比，實測缺一不可**）：volume／number／pages／authors／year／
title／**date**。證據分層：

- **全欄一致（僅 DOI 斜線形不同）** → MERGE
- **作者轉寫變體**（`Jr.`/`III` 錯位、`Anonymous` 頂替、姓氏 typo）而卷期頁一致 → MERGE
- **卷期頁不同** → REFUTE——同名不是同篇。實測三型：期刊事務欄目（同名公告每期
  刊一次）、同題兩部曲（相鄰頁碼、兩個真 DOI）、正文 vs 目次頁

實測比例：211 組 → 204 MERGE ＋ 7 REFUTE。**REFUTE 不是雜訊，是判定**——但見下方
誠實邊界（work 域的 refute verdict 目前無 home）。

## keeper 選擇

1. 有 abstract 側 > 欄位多側 > citekey 乾淨側（無 dedupe 後綴）
2. **作者品質覆蓋 citekey 慣例**：`Jr.` 壞解析產出的假姓 citekey（`f1997model`）
   不當 keeper，即使它「較短較乾淨」
3. 逐組覆核方向——實測 3／16 REVIEW 組要換 keeper，1 組 doomed 側才是完整名

## 執行序（每組）

1. **差集補平（合併前，必要）**——「work 消歧不搬欄位」（#75）：doomed 獨有的資料
   不補就隨檔案消失。規則（本批裁決史）：
   - **識別碼**（doi／pmid／isbn 三種都要）：聯集入 keeper——丟識別碼＝丟身分判定
   - **date**：非佔位側勝（OpenAlex 對只知年份的記錄填 `-01-01`）；兩側皆非佔位且
     不同 → 停下人工
   - **abstract**：取長側（實測五型壞版本：空白差異、掉頭截斷、錯誤段落、尾部
     截斷 stub、長短版並存）
   - **authors**：壞轉寫丟棄、完整名側勝——**不自動猜，逐組裁決**
2. **commit store**（trackedness 前提：消歧刪檔前，所有將刪檔案必須被 git 追蹤）
3. `record-divergence --candidate k:work --candidate d:work --judgement <證據一句>
   --rests-on <證據報告的 sha256 digest> --prefers <keeper>`
4. **再 commit**（divergence 記錄檔也要 tracked）
5. `resolve-divergence <id> --survivor <keeper>`——**id 現場查詢，不要存**：
   divergence id 由候選集推出，先 resolve 的組會讓重疊組的候選遷移、**id 重算**。
   同一 keeper 命中多筆 divergence 時全部要輪到（cand[0] 的歧義實測漏過一組）
6. 鏈式合併（A←B 且 B←C）按**拓撲序**：B←C 先跑

## 合併閘是最後防線，不是敵人

`resolve-divergence` 的差集閘逐欄位**比原值**（不是比鍵、不是比首行、不是正規化比）
——本批預掃與閘的粒度差了五次（date／abstract 值級／abstract 續行／authors 逐位／
pmid），每次都是閘對。**預掃模擬閘就要用閘的粒度**；預掃漏了也沒關係——閘會擋，
補平重跑即可，不會有損失落地。

## 報告紀律

- **寫下的世界斷言要先量過**——提名組數、判定比例、差集計數都是當場量的，不寫
  「應該是」；見 [`assertions-must-be-measured`](../../rules/assertions-must-be-measured.md)
- 乾跑報告先行（逐組 keeper／doomed／證據／判定），`store-source` 存證拿 digest，
  該 digest 就是每筆 judgement 的 `--rests-on`
- REFUTE 逐組附理由；差集裁決史（誰的 abstract 被丟、為什麼）記入 store commit 與
  issue 報告
- 完成量測：entries 淨減數＝unique doomed 數；多 DOI work 計數；殘留 divergence 數

## 效能事實

record ~1.4 秒／組、resolve ~4 秒／組（每次 CLI O(n) 全庫 load——#455 的既有形狀）。
204 組全批含五輪撞閘裁決約 1 小時；純機械時間約 20 分鐘。萬筆級大刊先看 #455。

## 誠實邊界

- **REFUTE verdict 無 home**：「查證過、不是同一篇」在 work↔work 域沒有持久化機制
  （person 域有 resolution-rejected、work 域沒有）——REFUTE 判定只活在報告裡，
  重跑提名會再提出同一配對。機制補上前，重跑時先讀前次報告的 REFUTE 清單
- **venue verdict 不隨 merge 遷移**（#460）：doomed 的 venue `resolution-confirmed`
  合併後變 stale（實測 204 條）——修復與清理見該 issue，本 skill 不處理
- 所有數字是 Psychological Methods 單刊單批的實測——**換刊要重量**，比例不外推
- 合併不可逆（全庫改寫＋刪檔）——乾跑報告與逐組證據是硬步驟，**不得批次自動
  apply 未經人過目的判定**
