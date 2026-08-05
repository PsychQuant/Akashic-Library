## Context

歧異的三種可能附著層級，只有一個通過既有 spec 的判準。

`openspec/specs/entity-boundary/spec.md` 定義了 entity-hood 的判別測試：

> The discriminating test SHALL be whether the candidate corresponds to a record shape — that is, whether it determines which fields exist and therefore which decoder the loader dispatches to. Identity, a stable name, aliases, and a change history are necessary but NOT sufficient.

歧異記錄要承載候選清單、判斷、證據參照——那是一組它自己的欄位，需要它自己的 decoder。它通過該測試。對照被同一份 spec 拒絕的 `view`：理由是「a view has no record shape of its own, and the loader would decode it as some existing shape」；歧異記錄不是這種情況。

另外兩個選項在結構上更弱：

| 選項 | 障礙 |
|---|---|
| 實體上的欄位 | 雙向一致性無人負責（A 記了 B，B 要不要記 A）。且依「消歧後刪除」的生命週期，刪除時得編輯倖存者——一個刪除操作膨脹成刪除加修改 |
| 關聯 | `Relations` 只存在於 work 記錄，person 記錄完全沒有這個欄位，且其種類是封閉的兩個值。走這條得先把關聯泛化到 person，那是比本變更更大的前置工作 |

實體選項自足：建立時是一個新檔，消歧時刪掉那個檔，兩個當事實體本身完全不用動。

## Goals / Non-Goals

**Goals**

- 讓「這裡曾經分岔過」成為可記錄的事實，而不是必須當場消解的障礙
- 讓判斷與其依據共用既有的 provenance 詞彙，不發明第二套
- 讓消歧是一個有紀錄、參照不斷裂的原子操作

**Non-Goals**

- 判斷遷移到倖存實體（見 proposal 的 Non-Goals；依賴 `add-provenance-references`）
- organization 的歧異（依賴 Akashic-Library#70 的機構建模決定）
- 自動偵測歧異候選
- tombstone 或任何 store 內的歷史保存機制

## Decisions

### D1：裸標籤取名 `divergence`

它只斷言「分岔發生過」，不預設兩個候選是同一個。被否決的替代：

- `merge-candidate` —— 預設了它們是同一個，與「寧可分割，絕不合併」的中立立場相違
- `ambiguity` —— 在資料庫語境常指別的東西（型別歧義、查詢歧義）
- `identity-question` —— 語意最精確但過長，且與既有標籤（`work` / `person` / `organization`）的單詞慣例不一致

### D2：判斷型形狀是抽出的共用件，不是複製

`add-provenance-references` 的 `ProvenanceReference` 實際是兩層組合：一個指名宿主欄位的 `field:`，加上擷取型（`url` / `retrieved` / `status` / `media-type` / `content`）或判斷型（`judgement` / `rests-on`）二選一的內容。

`field:` 的語意是「這筆 reference 支持宿主記錄的哪個欄位」。歧異記錄的判斷不是關於欄位，是關於**哪個候選才對**——同一個型別在兩處會有兩種語意。

所以把 `{judgement, rests-on}` 定義成獨立的共用型別：`ProvenanceReference` 由 `field:` 與它組合，`divergence` 直接使用它。一套詞彙、兩種組合方式。

本變更先落地時該共用型別由本變更引入；`add-provenance-references` 落地時複用而非重定義。兩者若順序相反亦成立——後到者複用先到者。

### D3：消歧是原子操作，不是「刪一個檔」

被併掉的候選很可能已被其他記錄引用。直接刪檔會留下指向不存在鍵的參照，佈局檢查的孤兒計數會跳，但那時已經壞了。

操作定義為：**合併（把來源的名稱等別名併入倖存者）→ 全庫參照重寫 → 刪除歧異記錄與被併記錄**。既有的 citekey 改名路徑已具備「搬檔加全庫關聯遷移」的能力，消歧沿用同一條路徑；差別在改名的目標鍵不存在，而消歧的目標鍵已存在且要吸收來源的別名。

### D4：刪除前驗證版本控制生效

「git 有紀錄所以可以刪」是部署假設而非 store 保證——store 可以建在版控之外的任何位置，那裡刪除就是真的沒了。

刪除前檢查 store 位於 git 工作樹內；不在則拒絕刪除並說明原因。這與 store 既有的 fail-closed 風格一致（編碼自檢、版本過新拒讀、存檔寫入前驗證排除生效）——寫入前拒絕而非事後修補。

### D5：歧異記錄不帶「已解決」狀態

依使用者拍板的生命週期，記錄在消歧完成時刪除，所以它從不進入已解決狀態。這讓形狀更小：只需要未決的問題與候選，不需要狀態機。

副作用是判斷會隨記錄消失（見 proposal 的 Non-Goals）。這是明知的暫時降級，不是遺漏。

## Implementation Contract

### 可觀察行為

1. store 可以承載 `divergence` 記錄。無此類記錄的既有 store，載入與寫回位元組不變。
2. `divergence` 記錄自報：一個說明未決問題的文字、兩個以上的候選參照、選填的判斷與其依據。
3. 候選參照指名同一種實體形狀的鍵。跨形狀的候選（一個 person 與一個 work）拒絕載入。
4. 消歧命令接受一個歧異記錄與一個倖存候選，執行合併、全庫參照重寫、刪除，並報告改寫了哪些記錄。
5. 消歧在 store 不位於 git 工作樹內時拒絕執行，錯誤說明原因與如何繞過。
6. `divergence` 記錄的序列化與其他形狀一致：排序後輸出、未知欄位逐位元組保留、寫出前自檢讀得回同一個值。
7. 既有的檢查與佈局報告把歧異記錄計入其摘要。**承載若不可觀察就不可驗證**——記錄載入成功卻不出現在任何輸出裡，使用者無從分辨「載入了」與「被靜默忽略」。

### 介面與資料形狀

```yaml
divergence:
id: 6577DE3B-DAFE-5CC0-A9DE-2E04030737B3
question: 是否為同一人
candidates:
- key: fann-cathy-s-j
- key: fann-cathy-s-j-2
judgement: 兩者的姓與 given initials 一致，差異僅在連字號與句點的排版慣例
rests-on:
- sha256:9a23d701e4fe4888a2c3d5e7f9b1c4d6e8a0b2c4d6e8f0a2b4c6d8e0f2a4b6c8
```

- `question` 必填，說明未決的是什麼
- `candidates` 必填，至少兩筆，每筆是 `key:` 形式的實體參照
- `judgement` 與 `rests-on` 選填，成對出現（有其一無其二則拒絕載入）；形狀與 `add-provenance-references` 的判斷型 reference 相同，不含 `field:`
- 新增 Swift 型別於新檔：歧異記錄本身，以及 `{judgement, rests-on}` 的共用型別

### 失敗模式

| 情況 | 行為 |
|---|---|
| `candidates` 少於兩筆 | 拒絕載入，錯誤說明歧異至少需要兩個候選 |
| 候選跨越不同實體形狀 | 拒絕載入，錯誤同時指名兩個候選與各自的形狀 |
| 候選指名的鍵不存在 | 消歧時拒絕執行，錯誤指名找不到的鍵（**非載入時**——見下方修正） |
| 有 `judgement` 無 `rests-on`（或反之） | 拒絕載入，錯誤說明兩者成對 |
| 消歧時指定的倖存者不在候選清單內 | 拒絕執行，錯誤列出實際的候選 |
| store 不在 git 工作樹內 | 拒絕刪除，錯誤說明版本控制是刪除的前提 |
| 參照重寫過程中單筆寫入失敗 | 收容該筆、繼續其餘、結束時報告失敗清單並以非零碼退出；不留「部分改寫且索引過期」的撕裂狀態 |

### 實作階段的兩處修正

**「候選指名的鍵不存在 → 拒絕載入」改為「消歧時拒絕」。** decode 沒有 store 存取（這正是
`shape:` 必須寫在記錄裡而非推導的同一個理由），載入時無從判斷某個鍵存不存在。而把它做成
載入後的跨記錄 **error**，會在有人手動刪掉一個候選檔時鎖死整個 store 的寫入面——store 對
懸空參照的既有立場是 warning 而非 error，理由是「解析中途本來就會有」。真正危險的是拿一筆
候選不存在的記錄去執行消歧，所以檢查落在那裡：`resolveDivergence` 找不到候選就擲錯並指名該鍵。

**消歧會一併遷移其他歧異記錄的候選。** spec 寫的是「store 內**每一個**指名被併實體的參照」，
而另一筆歧異記錄的 `candidates` 也是參照。遷移後若候選塌縮到少於兩個，那筆記錄提的問題已被
本次消歧回答，一併刪除——留著會寫出一份 decode 拒收的檔（少於兩個候選），那是靜默的損壞。

### 驗收條件

- `swift test` 全綠
- 新增測試：建立含兩個候選的 `divergence` 記錄，`akashic validate` 通過
- 新增測試：`candidates` 只有一筆 → 載入被拒且錯誤訊息指名該條件
- 新增測試：候選跨形狀 → 載入被拒
- 新增測試：`judgement` 與 `rests-on` 只有其一 → 載入被拒
- 新增測試：消歧後，原本指向被併鍵的記錄改為指向倖存鍵，且歧異記錄與被併記錄的檔案都不存在
- 新增測試：store 不在 git 工作樹內時消歧被拒，且檔案未被刪除
- 新增測試：`divergence` 記錄 encode 後 decode 再 encode，位元組相同

### 範圍邊界

**在範圍內**：`divergence` 形狀的型別、編解碼與驗證；`EntityKind` 封閉集合的擴充；消歧命令與其註冊；版控驗證；`entity-shape-label` 與 `entity-boundary` 兩份 spec 的修訂；person 與 work 兩種候選。

**在範圍外**：organization 候選；實體上的 `references:` 欄位；判斷遷移到倖存者；自動偵測；歧異的查詢或圖形化；tombstone。

## Risks / Trade-offs

- **新增實體形狀是不可逆的擴張**。封閉集合一旦多一個成員，每個消費端都得認得它，判斷錯了收回的成本很高。緩解：spec 層先把「什麼算歧異記錄」寫死（未決的同一性問題，非任意註記），避免它變成雜物抽屜
- **判斷會隨記錄刪除**。這是 D5 的已知代價。若之後發現需要常態查詢「這個鍵當初跟誰混淆過」，得回頭加 tombstone——那會推翻本次的生命週期決定。緩解：把該風險寫進 spec 的說明，讓推翻時知道推翻的是什麼
- **共用型別的所有權可能被兩個變更爭奪**。本變更與 `add-provenance-references` 都會用到 `{judgement, rests-on}`。緩解：D2 明定先到者引入、後到者複用；兩者的 spec 都指向同一個定義
- **與序列化正規化的順序耦合**。新形狀的位元組形式必須從第一天就是正規的，否則重演「同一份資料兩種寫法」。緩解：驗收條件含 round-trip 位元組相同；若 `add-canonical-serialization-form` 先落地則直接沿用其規則
