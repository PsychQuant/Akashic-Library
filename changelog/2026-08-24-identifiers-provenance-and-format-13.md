# 識別碼能說出自己從哪來了——以及三個「守衛比我先想到」的時刻（#394 §5–§6）

2026-08-24 晚間。接續同日的 §4（`2026-08-24-identifiers-serialized.md`）。這一輪把
`ProvenanceReference` 的可附著欄位擴到識別碼，並把 store format 的支援上限升到 13。

## §5：基數決定走哪條驗證分支

清單型（`issn`／`doi`／`pmid`／`isbn`）要求 reference 帶 `value` 指名支持的是哪一個；
純量型（`ror`）拒收 `value`。不是風格選擇——一筆記錄級的 reference 若不說支持清單裡的
哪一個，**其餘的識別碼會看起來有來源而其實沒有**。

**成員判定走正規形。** 磁碟上是 `0003-066x`、reference 寫 `0003-066X` 時仍須對得上，
否則遷移前的記錄會因為一個大小寫而整筆拒讀，§4 好不容易建立的「讀取面寬容保留」
就被這裡抵銷掉了。

## `Entry.references`：spec 的一句話逼出來的新邊

provenance-reference spec 寫得很硬：

> An identifier that **cannot carry a reference** SHALL NOT be treated as a first-class
> field of the record.

而 `Entry` **原本沒有 `references` 欄位**——`Models.swift` 裡那個屬於 `Person`。照上面
那句的字面，work 的 `doi`／`pmid`／`isbn` 在補上它之前**不算一等公民**，而那正是本
change 的標題所主張的東西。

所謂「加進白名單」也不是加一個字串：白名單實際上是每個型別各自 `validateReferenceAttachment`
裡的 `switch`，work 沒有 `references` 陣列就沒有 switch 可以加 case。使用者裁定補齊，
於是封閉列舉多了第 15 條邊（`.claude/rules/entity-backlink-completeness.md`）。

值域**刻意只有三個識別碼欄位**。work 的其餘欄位（`title`／`date`／`fields.*`）要不要能
攜帶來源是另一個問題，本 change 不裁決——寫下來是為了讓「只有三個」是一個看得見的
選擇，而不是一個沒人注意到的省略。

## venue 的附著驗證：補一個洞之前先量，差點是災難

`Venue` 有 `references` 欄位，卻**沒有 `validateReferenceAttachment`**——那個方法只有
person 與 organization 有，`VenueYAML.decode` 也從不呼叫。於是今天一筆 venue reference
可以寫**任何**欄位名而照樣載入。這是 #304 建立 venue 形狀時留下的。

補上驗證等於突然開始拒絕東西。動手前先量真實 store：

```
venue 檔數: 405
venue references 的 field 分布: {'resolution-confirmed': 817}
```

**全部 817 筆都是 verdict。** 漏掉那一格，405 筆 venue 記錄會在下一次載入時全部拒讀。

而且第一版測試把 verdict 的 `value` 憑直覺寫成 `venue:<key> :: <literal>`，測試自己先紅
——實際形狀是 `work:<citekey> :: <literal>`，**持有者是作品**（那筆 work 的 venue literal
被判定成這個 venue），不是 venue 自己。量了才知道。

## 合併檢查：守衛逼出一個我沒想到的裁決

加完 `Entry.references` 之後，`testEntryFieldCoverageOfMergeCheck` 紅了——它用反射數
`Entry` 的儲存屬性（16 → 17），並要求同步更新「合併兩筆 work 時哪些欄位會被丟掉」。

答案不是照抄識別碼那三行。兩者**不重疊**：倖存者與被併者帶著**同一個** DOI 時，識別碼
差集為空、那三行完全不出聲，但被併者可能是唯一記著「這個號是從哪裡查到的」的那一筆。
丟掉它不會讓任何識別碼消失，只會讓一個**有來源的值安靜地變成沒來源的值**。

這是 spec 那句話在合併面的對偶：能攜帶 reference、但合併時被靜默丟掉，等於沒有。

## §6：format 13——照 design 去量，量出來的跟它不一樣

design.md 說 bump 的理由是「識別碼欄位加入白名單，而白名單是 strict 層，舊 binary 讀到
未知的 `field` 值是整檔 quarantine」。

實測（把 `6a234d4` 建成 format-12 binary，餵同一份 fixture）：

| 新形狀 | format-12 binary 的行為 |
|---|---|
| `organization` 帶 `field: ror` | **整檔 quarantine** |
| `venue` 帶 `issn:` ＋ `field: issn` | **載入**，落 tolerant-preserve |
| `work` 帶 `references:` ＋ `doi:` | **載入**，落 tolerant-preserve |

**只有一種是硬觸發。** 原因就是上一節那個洞：附著驗證只有 person 與 organization 有，
venue 先前沒有、work 連欄位都沒有，所以舊 binary 沒有東西可以擲錯。

venue 與 work **仍併入同一個 bump**，但理由換成 format 11 對 `venues:` 用過的那個：
「保留而不解讀」對一條 ref 邊等於反向查詢靜默漏資料；provenance 更尖銳——一筆不被解讀
的 reference 不會被附著驗證，於是它可以指向一個不存在的值而沒有人發現。

## write gate 只擋 reference，不擋識別碼欄位本身

這也是從量測長出來的。識別碼欄位是 additive（上表 b／c），而對它設閘會讓
`migrate-identifiers` 在 bump 之前**跑不動**——那正是 design 自己在否決「讀取時拒讀
非正規值」時寫下的「先有雞先有蛋」。

**真實 store 的 `format:` 仍是 12，本輪刻意不動。** design 的部署順序把 bump 排在
遷移跑完並驗證之後的最後一步，理由是遷移必須跑在舊解碼器上。

## 量測

| | |
|---|---|
| `swift test` | 2128 tests, 0 failures（§5 完成時） |
| 真實 store | 937 entries／865 people／405 venues／1 divergence，零 quarantine |
| 新增測試 | `IdentifierProvenanceTests` 14 條、`Format13GateTests` 8 條 |
| 封閉列舉 | 14 → **15 條邊** |
| store format | `supported` 12 → **13**；`store.yaml` 仍是 12 |

## 還沒做

§7（匯出面：結構化值勝過 `fields` 殘留）、§8（`migrate-identifiers`，唯一會**寫**真實
store 的一節）、§9（兩面對等與收尾）。

§9 要處理的已知小缺口：`validate` 的摘要行是「N entries、N people、N libraries 全部
通過」，**沒有數 venue 與 organization**——它們現在會被檢查了，但摘要仍不提它們。
