# 第三輪 verify 的 6 個 HIGH：修完 4 個，其中一個推翻了我自己的裁決

2026-08-25 下午到傍晚。PR #425 的最終 verify（`wf_6956ee30-f9b`，3/3 席）找到 **6 個
HIGH，全部是新的**——prompt 明列了前兩輪已修的 57 項並要求不得重複報，所以這 6 條是
真正的差集。本篇記已修的 4 條。

## 一、形狀升級會改壞合法的 format-13 檔（最會毀資料的那條）

```swift
if !v.hasPrefix("value:") { lines[i] = "- value: \(v)" }   // 舊
```

它假設「不是 `value:` 開頭 ⇒ 是 format-12 的裸純量」。而 **YAML mapping 無序**——
一個完全合法的 format-13 元素只要寫成 `- qualifier: print` 開頭，就被改成
`- value: qualifier: print`，該檔從此讀不出來。

**quarantine 守衛擋不住它**：守衛在寫入之後才跑，於是它把**本命令剛製造的**損壞
回報成「本命令沒認出的寫法」。RED 的失敗訊息逐字就是那句話。

而這個寫法不是憑空假設——**守衛自己的錯誤訊息就叫使用者「需人工改成 `- value: …`
後重跑」**，手改時把 qualifier 放前面完全自然。工具的復原指示會把人引到毀資料的路上。

修法把判準從「猜一種寫法」換成「判斷一個性質」：**有沒有 YAML 鍵結構**。安全的理由
可驗證——ISSN 與 ISBN 的值**不含冒號**，所以「含 `<鍵>:`」與「是裸的識別碼」互斥。

同源的第二個缺陷：**續行**（`  qualifier: print`）讓序列模式提早結束，其後的裸純量
元素全部漏掉，而漏掉的檔在同一次 run 的下一行就被 quarantine。

## 二、遷移之後重跑 WoS，每一筆從 `unchanged` 變 `conflict`

`Entry` 是**合成** Equatable，而 #394 給它加了 `doi`／`pmid`／`isbn`／`references`
四個儲存屬性；`entry(from: row)` 只寫 `fields["doi"]`——probe 的結構化欄位**恆為空**。

於是 `a == b` 必然為假 → 走回填 → 回填後的 `mergedCheck == probeCheck` 也必然為假
→ 落 conflicts。而 conflict 路徑刻意不覆寫，所以 `enriched` 回填**此後永遠不會再
fire**：`lossless-intake` 的「規則要及於已匯入的記錄」對全庫 664 筆帶 DOI 的 work 失效。

**這是同一段註解記載的 #206 verify H1，被結構化欄位原封不動重新裝填一次。**

既有的三支 idempotency 測試對它是盲的：**它們都在同一次 run 內建檔＋重跑**，
結構化欄位全程為空。

## 三、venue 側合併丟 qualifier

`for v in raws where !merged.contains(v)` 走 `Identifier.==`，而它**刻意只比
`normalized`**（dedup 的前提，不能改）——所以先進來的勝出、**不論它有沒有 qualifier**。

同一個檔案裡的 `normalizedUniqueQualified` 明寫了偏好規則，**跨 work 累積到 venue
那一步沒有套用它**。而那是**真實資料的形狀**：同一份期刊被多篇引用，只有其中一篇帶
括號註記，而那一篇的 citekey 不一定排在前面。

## 四、pull 路徑——而這一條推翻了我自己的裁決

原本的計畫是「pull 也拒收 ISSN」，與 enrich 對稱。重讀 spec 原文之後改了：

> THEN the store SHALL treat that as a **misplacement**, **AND** the ISSN SHALL be
> stored on the venue record that the work's venue edge names

**「treat as misplacement」是搬走，不是拒收**——而 `migrate-identifiers` 正是靠
`fields.issn` 把它搬到 venue。importer 若直接丟掉，那條路永遠不會發生。

所以真正該修的是**遮蔽**：`BibExport`／`CSLExport` 的條件先前是
`if fields["issn"] == nil`，只在 work 沒有殘留時才拉 venue。**方向反了**——識別碼住
在它所識別的實體上，venue 的那個才是正典，work 的殘留是過渡態。

**這推翻了我在 §8 寫的註解**（「遷移略過的那些仍在 fields，不得被覆蓋」）。那句話
當時看起來很有道理，因為它用的是「保守側」的語言。但這裡的兩個值不是「舊的 vs 新的」，
是**過渡態 vs 正典**——保守側保護錯了對象。

## 兩個反覆出現的修法形狀

| 缺陷 | 直覺修法 | 為什麼錯 |
|---|---|---|
| pre-flight 沒模擬寫入閘 | 把閘門清單複製到 pre-flight | 分岔方向 ＝「pre-flight 說可以、寫入時 throw」 |
| venue 合併丟 qualifier | 在合併處也寫一次偏好規則 | 分岔方向 ＝「其中一處安靜丟掉 qualifier」 |

兩次的正解都是**抽出共用的一份**（`assertVenueWritable`／`mergePreferringQualified`）。
而關鍵不是「DRY 比較好」——是**分岔的方向剛好就是那個缺陷本身**。

## 負控的第四個教訓：粒度太粗也會讓它不紅

WoS 那條的第二支測試，在**整行移除**的 mutation 下**不會紅**——不是測試無效，是
**因果鏈被截斷**：`==` 一旦失敗就走 conflict 路徑、根本不寫檔，於是殘留也不會出現。
只有精準的 mutation（保留 `b.doi = a.doi`、只移除 `removeValue`）才讓它轉紅。

今天四次「負控沒紅」，前三次是 fixture 寫錯，這次是 **mutation 把兩個獨立的修改綁成
一個**。共同結論不變：**負控沒紅時，第一個該懷疑的是負控本身。**

## 尚未修（2/6，各帶完整診斷）

1. **乾跑拒跑而 `--apply` 成功。** 形狀升級只在 `apply == true` 寫檔，所以乾跑時裸
   純量還在 → quarantine → 守衛 throw；`--apply` 卻先升級再 load 因而成功。違反本命令
   自己寫下的契約（「乾跑與 apply 得到**同一組** blockers」），且錯誤訊息**說了假話**
   ——它斷言那是「沒認出的寫法」，而實測觸發值正是它認得的形式。需裁決：乾跑時形狀
   升級要「模擬」還是實寫。
2. **`entryDict`／`get-entry` 對 work 的 `doi`/`pmid`/`isbn` 全盲。** 與已修的 venue
   ISSN 同族、換一個 entity kind。應比照 `VenueSurfaceTests` 加反射守衛，否則下一個
   欄位會再漏一次。
