# venues 與 thesis 補上三個讀取面——而守衛在 pre-push 擋下過我一次

2026-08-28，#426。`akashic get-entry` 與 MCP 的 `entryDict` 完全不顯示 `venues` 與
`thesis`，而兩者都在磁碟上。

`venues` 是 `entity-backlink-completeness` 封閉列舉的**第 14 條邊**——work 通往 venue 的
唯一路徑，而 #394 之後 ISSN 就住在那個 venue 上。**一個看不到 `venues` 的 `get-entry`，
說不出這篇文章的 ISSN 是從哪裡來的。**

## 三個面，三條獨立路徑

| 面 | 檔案 | 形狀 |
|---|---|---|
| MCP | `AkashicService.entryDict` | dict payload |
| CLI | `GetEntryCommand` | **逐欄位 print**，不是泛型迴圈 |
| App | `EntryViews.EntryDetailView` | SwiftUI `LabeledContent` |

CLI 與 MCP 共用 `entryDict` 的**資料**，但人可讀面另有一套逐欄位 print，所以實際要改
三處。這正是那條規則執行細節 2 的「一個 entity kind 的讀取面只能有一條實作路徑」對
entry **尚未成立**的地方——venue 那面已收斂，entry 這面沒有。不在同一輪修（scope guard），
測試註解已具名。

## knownGaps 清空，機制保留

兩支 `EntrySurfaceTests` 各有一張表記著 venues／thesis 指向 #426。修完**要清空**——留著
會讓守衛對修好的東西仍然跳過。

表清空但機制保留。刪掉它的話，下一個缺口只剩兩條路：混進 `exempt`（於是待辦偽裝成裁決），
或讓守衛紅著（於是所有紅燈失效）。`zero-instance-guards` 第 6 列講的正是後者的外溢。

## 守衛擋下過一次，而它的 doc 對這一格是錯的

第一版的 App 面：

```swift
case .literal(let s): return "\(s)（未歸戶）"
```

venue 的 literal 是 WoS／Zotero 的第三方原文，與 `authors` 的 literal 同源——**沒有消毒**。
`DisplaySinkCoverageTests` 在 pre-push 擋下並具名 `EntryViews.swift:111  s`。

它的 doc 寫著「case 行的短變數值是盲點」。那句話對 `entryDict` 那面成立（該處靠人工＋
測試釘），對 App 面**不成立**：這次它看得到。記下來是因為那個措辭會讓人以為所有 case
行都是盲點，而實測不是。

## 一個沒有實例可驗的半邊

**`thesis` 面無實例可驗**：store 裡帶 `ThesisFacts` 的記錄 **0 筆**（有 5 筆 `type: thesis`
但都沒有那個結構）。本輪只實測到 `venues`：

```
$ akashic get-entry chen2025exploring --library ~/.akashic
venues	@journal-of-computational-and-graphical-statistics   ← 新增
```

`thesis` 那半靠反射守衛與型別檢查，不是靠跑出來的輸出。寫出來，是因為「4 tests
0 failures」讀起來像兩半都驗過了。

## 同輪的其他事

- **#392**：四個 skill 依 MP02 改名（動詞歸第二位）。歷史記錄（`changelog/`、
  `openspec/changes/archive/`）刻意不改——那是當時的事實。sed 一度改到 `archive/`，
  違反 `archived-protection`，已還原。
- **#406**：全量 dry-run 證明 Zotero 補不回任何 pages（**0/70**），把 issue 的抽查
  升級成全量。並更正一個懷疑：`ZoteroMapping.fieldMap` 一直有 `"pages": "pages"`，
  不是 #340 那種「收進來卻用錯鍵名」。
- **#424 裁決 A 被寫入面擋住**：三筆記錄的 DOI 要升格而**沒有任何面寫得進去**。手改
  YAML 時 `dweck1975role` 沒有 `akashic:` 區塊，插入的錨點靜默不匹配而移除已執行，
  那筆 DOI 一度消失（`git checkout` 還原）。這是 #394 自己寫的重新裁決條件所需的
  第一個實例。
