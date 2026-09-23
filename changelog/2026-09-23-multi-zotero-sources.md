# 一筆記錄可帶多個 Zotero 來源，store format 18（#605）

## 為什麼

同一篇論文同時放在個人 Zotero library 與共享群組 library（本例為 Reference_JTIRT）是正常用法。Akashic 以
`(library_id, zotero_key)` 為匯入身分（#3），於是把它匯成兩筆 entry；要合併時，合併閘又把兩個不同的 zotero key
當成「來源衝突」擋下（#157）。這類攣生在結構上合併不了，唯一出路是去 Zotero 刪掉其中一份——而群組那份是
別人也在用的共享文獻，個人那份帶著收藏夾分類，兩邊都不該為了 Akashic 內部的一致性被刪。實例是
kiki830621/storyline#16 的三組攣生。

定位：**Zotero 是曾經匯入過的上游之一，key 是來源紀錄，不是身分判準**。只讀、單向，不寫回 Zotero。

## 改了什麼

- `Entry.additionalProvenance`，YAML 寫在頂層 `provenance_additional:`（元素形狀同 `provenance`；空則不寫出，
  535 筆既有記錄零 diff）。
- **只有主來源能以再匯入改寫書目欄位**；附加來源命中只更新該來源自己的 version／hash／orphan。附加來源有變動而
  未套用 → `secondarySourceChanged`；在 Zotero 端被刪 → `secondarySourceOrphaned`；恢復 → `secondarySourceRestored`。
- orphan 逐來源判定。
- 合併：倖存者主來源**原樣保留**，沒有就維持沒有（不升格——保留那筆的欄位是人選的版本）；其餘來源併入附加來源，
  同一來源去重。沒記 `library_id` 的來源不得收成附加來源（匯入端無法比對，合併閘擋）。
- **「只有附加來源、沒有主來源」是合法狀態**：這筆的欄位不會被任何 Zotero 條目改寫。App 的「與 Zotero 脫鉤」
  拿掉已刪除的主來源與已 orphan 的附加來源，活著的附加來源原樣保留、不升格；主來源已 orphan 而附加來源仍活著時
  拒絕丟垃圾桶。
- store format 17 → 18。頂層鍵本屬 additive，**仍 bump 的理由是語意**：format-17 binary 會保留但不比對附加來源，
  再匯入時安靜地重新造出攣生。

## 驗證

- 每項行為先 RED 後 GREEN；全套測試（既有 3 個命題模組外部 probe 失敗除外，與本 issue 無關）。
- 兩輪 5-AI verify（Codex 因額度兩輪皆缺席）：R1 29 列（3 blocking，同一根因），R2 27 列（2 blocking，皆為守衛
  配套）；修正後守衛全綠。兩個設計點由使用者裁決：脫鉤不升格、無來源倖存者不升格。
- store 副本端對端：storyline#16 三組全部合併，倖存者各帶主＋附加來源；Zotero 全 library 再匯入，被併的三筆
  沒有被重新建出。

## 升級前置

CLI／akashic-mcp／App 全升 v18 世代 → 手動把 `store.yaml` 改成 `format: 18`。marker bump 前不 push store repo。

## Follow-up

#606（附件複製進 Akashic 檔案區）、#607（legacy 裸 key 比對順序）、#608（變動偵測分不出 hash 定義改變）、
#609（附加來源 orphan 無處可裁決）、#610（同一來源被多筆宣稱）。
