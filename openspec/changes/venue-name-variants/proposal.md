## Why

`Venue.names` 的型別是**時間軸**、spec 宣稱它模型化刊名沿革，而實務上它裝的是**異寫法**。

實測（2026-08-28，全庫 405 筆 venue）：

| | 值 |
|---|---|
| `names` 多筆的 venue | **35** |
| 其中**帶時間欄位**（`start`／`end`／`ended`／`attested`） | **0** |
| 有 `authorized:` 分割 | 402 |
| 有 `variant` 分割 | **0** |

`venue-entity` spec 的 Requirement「Venue name history timeline」帶一個 Scenario——
「a venue whose `names` contains an old title with `end: 2003` and a current title with
`start: 2003`」。**那個 scenario 在 405 筆記錄上零實例。** 而那 35 筆多名字的內容，
逐一看都是同一本刊的不同寫法：`wikipedia` 的四個名字是 zh／en 變體（#339 已記過）、
`plos-one` 的三個是大小寫與縮寫差異。

**一個欄位在說謊**：讀 `Venue.names` 的人會以為拿到時間序，實際拿到任意順序的別名。
`names.current` 在「多筆皆不帶時間」時取哪一筆，是一個沒人裁決過的行為。

## 這推翻一條顯式裁決，不是補一個沒人想過的格子

`openspec/specs/venue-entity/spec.md:11` 寫著：

> flat `names` list with optional `authorized` subset (organization pattern;
> **NOT the nested person partition of format 10**)

那條裁決（`add-venue-entities`，2026-08-17）不是疏漏——它顯式選了 organization 的扁平
模式而**拒絕**了 person 的巢狀分割。本提案主張改它，所以必須說明它當時為什麼對、
現在為什麼不對：

**當時對**：organization pattern 夠用的前提是「`names` 的多筆會用來裝沿革，而別名少到
可以塞進 `authorized` 的補集」。那是一個關於未來資料的預測。

**現在不對**：預測沒有實現。11 天後的實測是沿革 **0** 筆、異寫法 **35** 筆——
被預測會是次要用途的那個，是唯一用途；被預測是主要用途的那個，零實例。

## What Changes

- **`Venue.names` 新增 `variant` 分割**，與既有的 `authorized` 並列。402 筆已有
  `authorized`，所以這是**補上第二個分割**，不是從零建。
- **時間軸語意收窄到只承載沿革**：帶時間欄位的 names item 表示刊名沿革；`variant`
  分割不帶時間（異寫法沒有「從何時起是異寫法」這種事）。
- **`displayName` 的四階回退維持不變**——它目前在異寫法情境下已給出合理結果
  （#422 記載「目前無實測損害」），本提案不動它，只讓它讀到的東西名實相符。
- **既有 35 筆的遷移**：多筆 `names` 中非 `authorized` 的那些搬進 `variant`。
  依 `no-compat-fallback`，**一次改完全部**，不留雙重讀法。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `venue-entity`: 把 `names` 的兩個用途拆開——時間軸只承載沿革，異寫法住 `variant`；
  推翻「NOT the nested person partition」那半句。

## 明確不在範圍內的兩張 issue

#420（venue-driven 匯入）與 #423（venue → works 補完）**不在本提案內**，而這是
一個判斷不是省略。四張 venue issue 是**兩條互不相交的鏈**：

```
鏈 A（建模——「venue 記錄該長什麼樣」）
  #422 別名的格子  ──→  #421 時間軸真的只裝沿革        ← 本提案
鏈 B（範圍——「庫裡有什麼」的意思）
  #420 本體論裁決  ──→  #423 venue → works 的實作
```

鏈 B 卡在一個 repo 答不出的問題。#420 自己寫著：把 4207 筆 Psychometrika 論文全部
寫成 `work:` 記錄，會讓「這個庫裡有什麼」從「我讀過／引用過／寫過的東西」變成
「我知道存在的東西」——**那是本體論變更，不是一個 importer**。那要使用者裁決。

把四張綁成一個 change，會讓鏈 A 這條完全可判定的建模工作，被一個懸而未決的本體論
問題無限期擋住。

## #406 的欄位應該搭同一班車（待你裁決）

**這一節不是本提案的範圍主張，是一個排程觀察。**

#406（70 筆期刊論文缺 `pages`，而「本來就沒有」與「真的漏了」分不出來）的 Expected 是：

> venue 側能持有「本刊是否使用頁碼」的判定，且該判定**留下 verdict 與證據**

那也是一個 **venue 欄位新增 ＋ format bump**。與本提案的 `variant` 分割**性質不同、
成本重疊**：

| | 本提案（#422） | #406 |
|---|---|---|
| 改什麼 | `names` 的兩個用途拆開 | venue 新增一個判定欄位 |
| 為什麼 | 一個欄位在說謊 | 兩種相反的狀態分不出來 |
| **format bump** | 12 → **14** | 也要一次 |
| **三 binary 部署** | 一輪 | 又一輪 |

`no-compat-fallback` 說「要改就一次改完全部」。分兩次做的具體代價是**兩輪**
「build 三個 binary → migrate 乾跑 → per-file trackedness → apply → validate → 手動
bump format」——而那條鏈的每一步都是 CLAUDE.md 記過會出錯的地方（format bump 會打死
三個 binary，只升一個仍整份拒讀）。

**但合併有它自己的代價**，所以這是裁決不是推導：

- 本提案的改動是**機械可逆**的（35 筆重新分類，零新斷言）
- #406 的欄位需要**逐刊判定**（「Frontiers in Psychology 不用頁碼」是一個關於世界的
  斷言，要證據、要 verdict、要能逆轉）——依 `identity-is-judged-not-matched`，那不是
  字串謂詞做得出來的

合併會讓一個零風險的重新分類，等一批需要人逐刊查證的判定。

**三個選項**：

1. **合併**：本提案擴充為「venue 建模的一次 bump」，含 #406 的欄位。一輪部署，但本提案
   要等 #406 的判定工作
2. **維持分開**：本提案先走（快、可逆），#406 另外一輪。兩輪部署
3. **欄位合併、判定分開**：同一次 bump 加上 `variant` **與** #406 的欄位（欄位是
   additive，加了不填是合法的空狀態），判定工作之後慢慢做。**一輪部署，且不互相等**

第 3 個看起來最好，但它有一個要說出來的性質：**加一個沒有任何記錄使用的欄位**，
落在 `zero-instance-guards` 第 9 列（`Organization.ror` 那一列）的形狀——那一列的裁決
是「寫」，理由是「缺席本身在說話」。#406 的欄位同理：venue 沒有這個格子時，讀者會
推論「這個庫分不出 article-number 期刊」，而那正是 #406 的標題。
