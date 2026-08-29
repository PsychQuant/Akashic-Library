# venue.paginated 的判定面：「本刊用不用頁碼」從此有格子可判、有證據可查

2026-08-30，#406。欄位本身已隨 #422 的 format 14 落地（`Venue.paginated: Bool?`），
但落地時四項缺口具名：寫不進去、驗證讀不了、floor 檢查不消費、45 個 venue 群沒判定。
本 change 補齊程式側三項；資料側（33 刊判定）同日完成於 store。

## 為什麼判準屬 venue 不屬 work

`Frontiers in Psychology` 的每一篇都沒有頁碼；`The Annals of Statistics` 的每一篇都有。
「這篇缺 pages 是不是缺陷」由**刊物的分頁制**決定，不由那篇論文決定。四個外部書目來源
（Crossref／OpenAlex／Zotero／識別碼覆蓋率）全部量過、全部不提供頁碼——決定這批記錄
該不該被報缺陷的事實，不存在於任何外部書目來源裡，只存在於「這本刊用不用頁碼」這個
刊物層級的判定中。

## 判定，不是設定

依 `identity-is-judged-not-matched`：「本刊不用頁碼」是關於世界的斷言。所以寫入面
（CLI `update-venue --paginated --judgement --rests-on`／MCP `akashic_update_venue` 的
`paginated`+`judgement`+`rests_on`）**強制**理由與證據：

- judgement 缺席 → 整個呼叫拒絕、零寫入
- rests-on 缺席或 digest 形狀壞 → 同拒（驗證借 `ProvenanceReference` 平面 init——
  單一驗證入口，不另寫一套）
- 證據先經 `store-source` 內容定址入庫，判定的 reference 以 digest 指向它
- (field, value, kind) 完整相等冪等；**翻轉判定留史**（判定會錯，錯了要能回溯）——
  這裡實測抓到 `ResolutionLedger.appendIfAbsent` 只比 (field, value)，對 value 恆 nil
  的純量欄位會把翻轉判定吞掉，故改用 `Equatable` 全比對

## `nil` 不得折成任何預設值

floor 檢查（`apa7Report` 的 `PAGES` recommended）只對**判定為 false** 的刊抑制；
`nil`（未判定）與 `true` 照報。未判定折成預設會讓所有沒查過的刊靜默通過下限檢查——
那正是 `lossless-intake` 點名的「靜默是最糟的形式」。

## 量測（端到端驗收）

33 刊判定寫入後，PAGES warning **70 → 45**——差額 25 筆**恰好**全是判 false 刊的成員：

| 判定 | 刊數 | 例 | 效果 |
|---|---|---|---|
| false（article-number 制／repository） | 17 | BMC 家族、Frontiers、JoVE、arXiv、SSRN | 25 筆假陽性歸零 |
| true（傳統頁碼刊） | 16 | Annals 家族、Psychometrika、Statistica Sinica | 缺頁確認為真缺 → #449 回補 |
| nil（跨切換點／證據不足，具名） | ~10 | Environmetrics、Statistics and Computing、BRM | 照報——時間軸升級的觸發實例 |

證據解讀的關鍵區辨（判定 statement 逐刊記載）：Crossref 覆蓋率低有兩種成因——
(a) 刊真的不用頁碼（article-number 高佐證）；(b) 出版商不上傳 page 給 Crossref
（Project Euclid 家族——刊實際有頁碼，庫內同刊帶頁記錄佐證）。把 (b) 誤判成 (a)
會讓真缺頁被靜默豁免。

## 跨切換點的刊留 nil——時間軸升級的觸發實例

Environmetrics（2017 切換）庫內持有 1996（有頁）與 2026（缺頁）跨越切換點——`Bool?`
對它說不出真話，判 false 對 1996 為假、判 true 對 2026 為假。依 diagnosis 紀律留
nil 並具名。這是 #422 落地 `Bool?`（而非時間軸）時預告的觸發條件的第一批實例
（另有 Statistics and Computing、Behavior Research Methods）；升級裁決另議，
不在本 change。
