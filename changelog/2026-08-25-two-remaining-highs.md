# 「不猜」被實作成「靜默丟」，以及 pre-flight 只查了六分之二

2026-08-25 傍晚。補跑那三席留下的兩條 HIGH，兩條都修完。

## 一、認不出的 ISSN qualifier 在 decode 當下消失

```swift
public var qualifier: String? { medium?.rawValue }        // ← 舊
```

`withQualifier` 走 `q.flatMap(ISSNMedium.init(loose:))`，認不出回 `nil`；`qualifier`
再從 `medium` 反推——於是磁碟上任何不在封閉三值內的寫法，**在一次 decode/encode
往返之後就不見了**。沒有 diagnostic、沒有 `invalidField`、沒有任何回報。

偵測不到還有第二層：`VenueYAML.encode` 的 canary 是 `guard back == v`，而
`Identifier.==` **刻意只比 `normalized`**（那是 dedup 的前提，不能改）。所以
canary 兩側都看不到 qualifier——`encode(decode(x))` 掉了一個 qualifier，它照樣通過。

而 `Online` 正是 Crossref／Zotero 對電子 ISSN 最常見的寫法。

### 修法照既有慣例，不發明新的

識別碼本來就有「讀取面原樣保留 ＋ `validate` 報 diagnostic」的形狀（`raw` vs
`normalized`、`IdentifierDiagnostics.nonNormal`）。qualifier 照抄：

- `ISSN.qualifierRaw` ——磁碟上那個字串，原樣保留
- `medium` ——認得出才有值，認不出就是 `nil`（**不猜**）
- `Venue.validate()` ——`qualifierRaw != nil && medium == nil` 時報 warning，
  並直接給出改法（`Online → electronic`）

**註記自己寫著「認不出回 nil——不猜」，而「不猜」被實作成「靜默丟」。**
那是 `lossless-intake` 執行細節 3 具名為最糟的那一種形式。

## 二、pre-flight 只查了六分之二

`migrate-identifiers` 的 pre-flight 判定 venue 寫不寫得成，先前查兩件事：venue 記錄
存在、venue 檔受 git 追蹤。而 `writeVenue` 實際上有**六道**會 throw 的閘：

1. `StoreKey.isValid(v.key)`
2. `format >= 11`
3. venue type 的 format 12 閘
4. `assertIdentifierReferencesWritable`（**本 change 自己新加的那道**）
5. `assertNoErrors(v.validate())`
6. （加上 pre-flight 已有的 trackedness）

第 5 道最容易踩到：`AuthorizedNames.validateDisjointPartitions` 對「同一個名字同時在
authorized 與 variant」回 `.error`，那是**既有真實 store 就可能有的狀態，與本 change
無關**。

寫入順序是 work 先（`fields.issn` 已移除）、venue 後。venue 那格 throw 之後例外直接
穿出 `run()`：

- work 檔失去 `fields.issn`，venue 從未收到那個號 → **ISSN 在 store 裡消失**
- `report` 連同 `plans`／`applied`／`blockers` 一起被丟棄——例外在 CLI 印任何東西
  **之前**就拋出，操作者拿不到「哪些檔已經被改了」

而**乾跑無法預告**：pre-flight 的事實集合刻意設計成乾跑與 apply 相同，而這四道閘
不在那個集合裡，所以乾跑會全綠。

### 修法：抽出來，不複製

`LibraryStore.assertVenueWritable(_:format:)` ——`writeVenue` 與 pre-flight 呼叫
**同一份**清單。

複製一份閘門清單到 pre-flight 是最直覺的修法，而它必然分岔——**分岔的方向正好是
「pre-flight 說可以、實際寫入時 throw」，也就是這個缺陷本身**。

同時修掉一個相關的小缺陷：trackedness 失敗時原本沒 `continue`，於是同一個 venue
會再被下一道檢查評一次、可能產生兩則 blocker。

## 兩支測試，各自有負控

- `testUnrecognizedQualifierSurvivesRoundTripAndIsReported`——把 `qualifier` 改回
  `medium?.rawValue` → 轉紅
- `testPreflightCatchesAVenueThatWriteVenueWouldReject`——釘住的是**機制**
  （pre-flight 走 `assertVenueWritable` 的同一份清單、不靠例外傳遞失敗），
  不是某一道特定的閘

全套 **2189 測試、0 失敗**。真實 store 無回歸（`psychological-bulletin` 的
`1939-1455（electronic）、0033-2909（print）` 仍在位，validate 57 則診斷不變）。

## 這三席一共找到五條，全部是我今天寫的

而其中兩條違反的正是我今天引用過三次的那條規則。跨模型的獨立審查抓到了我讀三遍
都沒看到的東西——`common-spec-prose-enumeration` 記過的那個對照事實，今天是第五、
第六個實例。
