# 第九輪：訊息說保留就要真的保留

2026-08-26。**三席只跑成一席** —— 另外兩席撞到週用量上限
（`You've hit your weekly limit · resets Aug 28`），所以**本輪覆蓋不完整**，
而缺的正是「驗我有沒有再犯時態錯誤」與「CLI／MCP 兩面的缺口是否也是假的」那兩席。

唯一跑成的一席找到 4 個（1 HIGH、2 MEDIUM、1 LOW）。本次修掉 HIGH 與其中一個 MEDIUM。

## HIGH：丟棄被誤述成保留

R8 為部分成功寫的訊息逐字是「其餘 token 的形狀不認得；**原字串保留在 fields 供人裁**」。

那句話描述的是 **pull** 的行為（`applyBiblatexFields` 在 `parsed == false` 時把原字串
留在 `entry.fields`）。但這段程式碼住在 **enrich**（add-only）路徑，那裡
`case "doi","pmid","isbn"` **只 append 訊息、從不寫 `added[k]`** —— 於是那個解析不出的
token 在 enrich 之後**不存在於 store 的任何地方**，而訊息叫使用者去 `fields` 找它。

**比沉默更糟。** `lossless-intake` 執行細節 3 要的是「丟棄必須可見」，這裡丟棄被
**誤述成保留** —— 使用者讀完會判斷「資料還在、之後再處理」，於是永遠不會回頭補。

**修法讓那句話變真，而不是改成一句誠實的訃告**：殘留欄位的用途**正是**裝那些解不出
的值（與 pull 一致），所以 add-only 該做的是真的把它加進去。

## MEDIUM：部分成功不是「刻意不採用」

它先前借 `refusedIdentifiers` 通道，而那個欄位的 doc 逐字是「Zotero 給了識別碼但
**刻意不採用**」。部分成功**既不是刻意**（解析不出是我們的限制，不是裁決）
**也不是不採用**（解出的那些已經採用了）。

三個消費面全部照契約渲染，所以 CLI 會在剛印完 `+ isbn = 978…` 的下一行印
`✗ 不採用：isbn「978… 1-4338-3216」`。MCP 面最尖 —— 消費端是 LLM，它只看得到鍵名
的語意（refused），於是可能去補一個**已經寫進去**的值。

新增 `partiallyParsedIdentifiers` 通道，依 `mcp-cli-parity` 兩面同時接上
（CLI 用 `◐` 而非 `✗`，MCP 用獨立鍵名）。

## 修法自己帶出的一個缺口

改完之後跑測試才發現：分支條件是 `nothingToAdd && refused.isEmpty`，**沒有考慮
`partial`**。若某筆只有部分成功而無其他可補值（entry 已有該欄位與結構化值），
它會落進 `unchanged` —— 而 `unchanged` 的語意是「Zotero 給不出缺著的欄位」，
那對這一筆為假，且部分成功的訊息**被靜默丟棄**。

**這是同一個病在新分類上重演**，而它是被那支「全部解不出仍走 refused」的測試
撞出來的 —— 我當初寫那支是為了守住既有語意，結果它先抓到了新語意的洞。

## 負控

| 拿掉什麼 | 結果 |
|---|---|
| 「真的保留原字串」那一行 | ✅ 紅 |
| 把 `partial` 併回 `refused` | ✅ 紅 |

2220 測試 0 失敗。

## 尚未處理（本輪剩餘）

- **MEDIUM**：pmid 排除的前提只稽核 `fieldMap`，而 `fields["pmid"]` 由
  `fieldMap[z] ?? FieldKey.normalized(z)` 決定 —— 後半無人稽核，且 Zotero 日後加一個
  `PMID` 欄位就會翻轉，**我方零程式碼改動**
- **LOW**：`addedPMIDs = probe.pmid` 已成結構性死碼，而註解仍說「probe 帶得出來」

## MEDIUM（續修）：判準問錯了問題

R8 的條件寫成「`pmid` 不在 `fieldMap` 裡 ⇒ 不跟隨」。而決定 `fields["pmid"]` 存不存在的是
**兩條路徑**：`fieldMap[z] ?? FieldKey.normalized(z)`。`FieldKey.normalized("PMID")` → `"pmid"`，
而 `ZoteroReader` 的 SQL 是**泛型**的 —— Zotero DB 裡任何 fieldName 都會流進來。

所以 Zotero 日後加一個 `PMID` 欄位就會讓 `fields["pmid"]` 出現，**我方零程式碼改動**，
而舊條件**仍然「為真」**（fieldMap 確實沒有那一列）。後果：殘留永不被移除、結構化的
舊值遮蔽上游的新值，兩面都不印出也沒有任何 diagnostic —— 而識別碼**終結指涉**。

**正確的問法不是「這個欄位在不在對映表裡」，是「上游這次到底有沒有給值」。**

```swift
if let rawPMID = fields["pmid"] {
    let p = followUpstream(rawPMID, existing: entry.pmid, field: "pmid")
    ...
}
```

這同時解掉三件事：今天（nil → 不動，R8 修的那件事保住）、未來（有值 → 跟隨）、
以及**判準不再依賴一個只稽核得到一半的前提**。

## LOW：那段註解自己活過來了

`addedPMIDs = probe.pmid` 的可達性有過一段插曲：R8 把 `pmid` 整個移出跟隨清單，於是
`probe.pmid` 從「因**資料**而恆空」變成「因**契約**而恆空」—— 這一行成了結構性死碼，
而上方那句「probe 帶得出來」在呼叫點讀起來仍像它可達。

R9 換掉判準之後**它又活了**。註解因此不必改成訃告，只需把這段插曲記在呼叫點
（讀那三行的人看不到另一個模組）。

**這是本輪第二次「修法讓一句原本會變假的話回到真」** —— 前一次是部分成功的訊息。
兩次的共同點：**與其把描述改成符合壞掉的行為，不如把行為修成符合原本正確的描述。**

## 負控（全部四條）

| 拿掉什麼 | 結果 |
|---|---|
| 「真的保留原字串」那一行 | ✅ 紅 |
| 把 `partial` 併回 `refused` | ✅ 紅 |
| 整段 pmid 跟隨 | ✅ 紅 |
| 改成無條件跟隨（退回 R7 的 bug） | ✅ 紅 |

2222 測試 0 失敗。**R9 的四條全部修完。**
