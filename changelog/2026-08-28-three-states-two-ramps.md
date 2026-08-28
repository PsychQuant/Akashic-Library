# `Author` 有三態，只有兩態接得起來

2026-08-28，#443。`.literal` → `.organization` 的升格面。

## 缺口是怎麼被看見的

不是有人回報，是**分類 #443 的 1,443 個 literal 時掉出來的**：

```
1× Center for History and New Media     ← George Mason University 的中心
1× 教育部                                ← 政府機關
```

兩筆都不是人。`Author` 的三態（#323）裡有 `.organization` 這一格，所以模型**能表達**
它們——但沒有路徑寫進去：

| 從 | 到 | 有路徑嗎 |
|---|---|---|
| `.literal` | `.key`（人） | ✅ `resolve-people --apply` |
| `.literal` | **`.organization`** | ❌ **只能在建檔時指定** |
| `.key` | `.literal`（降格） | ❌ （venue 有 `demote`，person 沒有）|

既有記錄的唯一出路是手改 YAML——而那是同日稍早差點弄丟一筆 DOI 的那條路。

## 這與 #394 的缺口同型

「模型能表達，但沒有路徑寫進去」。#394 那批（識別碼的四個寫入面）同日補完，這是同一
族剩下的一格——只是它屬於 authorship 而不是識別碼，所以不在那張表裡。

**兩者被看見的方式也相同**：都不是報錯，是有人想做一件事然後發現做不到。這種缺口不會
出現在任何測試的紅燈裡。

## 為什麼放在 `resolve-people` 而不是新命令

**作用對象相同**——都是 work 的一個作者位。放進 `resolve-organizations` 才是錯的：
那個命令管的是 person 的 affiliations 與 org 的 parents，從不碰 work 的 authors。

但**它不是消歧**：org key 由呼叫端顯式給，不經提名，所以沒有 tier、沒有候選清單。
與 #386 的 `judge` 同型（per-id 顯式指名 ＋ judgement 必填 ＋ 不提供批次）。

## judgement 必填，理由與 #386 同

判定會錯，而錯了要能回溯。**一個沒有理由的判定，事後與「不知道為什麼這樣」無法區分。**
空字串在 service 層拒絕，不是靠呼叫端自律。

## 三個負向測試，其中一個測的是「一半套用」

- `testAttributeToOrganizationRequiresJudgement` — 空理由拒絕
- `testAttributeToOrganizationRefusesAnAlreadyResolvedSlot` — 已歸戶不覆寫（改已歸戶的邊是**修正**不是升格，需要自己的出口——同 #418 對 `repoint`／`demote` 的裁決）
- `testAttributeToOrganizationRejectsWholeBatchOnUnknownOrg` — **第二筆壞掉時第一筆也不寫**

第三個刻意驗**第二筆**壞：第一筆完全合法，若實作是逐筆寫入，它會先寫成功再失敗——
留下一個「一半套用」的狀態，比整批失敗難修得多。

## 沒有動真資料

路徑做好了，但那兩筆機構**還沒修**——建 organization 要先選 key（`moe` 還是
`ministry-of-education`？），而那是命名裁決不是查證。留給使用者。
