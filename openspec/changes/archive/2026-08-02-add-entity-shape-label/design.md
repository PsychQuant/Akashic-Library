## Context

本 change 落實 `add-formal-concept-boundary` 的 D1 判準（形狀選擇），把它從規範變成記法。判準本身與標示機制無關；本 change 決定的正是標示機制。

已驗證的事實：`Entry` 與 `Person` 的已知 key 集合交集只有 `{id, type}`；legacy 佈局用目錄判別形狀（`entries/` 的載入迴圈不呼叫 peek）；真實 store 有 536 筆 work、0 筆 person 檔案。

## Goals / Non-Goals

**Goals:**

- 讓形狀名不再是某個後設欄位的值。
- 消滅 `? :` 全稱後備——不明的東西必須 quarantine，且錯誤訊息要能**指名**是什麼不被認得。
- 讓 `type:` 只剩一個意思（書目類型）。
- 保留表達層級與交集的能力，使本體不必是平坦分割。

**Non-Goals:**

- 不引入 `kind:`。
- 不引入書目類型白名單。
- 不改 legacy 目錄的載入路徑。
- 不實作層級推導（上位標籤的自動補全）。

## Decisions

### E1：形狀名是裸標籤，不是後設欄位的值，也不是完全省略

三個候選寫法：

```yaml
# ① kind: person        —— 設立一個叫 kind 的後設欄位，person 是它的值
# ② person:             —— 裸標籤（採用）
# ③ （無標籤）          —— 形狀由 key / names / profile 的組成顯示
```

**否決 ①（`kind:` 封閉列舉）。** 它把「種類」**物化**成 schema 裡的一個可查詢欄位：有值域、可比較、可 `WHERE kind = ...`。一旦形式概念成為一個可操作的欄位值，就是 Tractatus 4.1272 說的把形式概念當真正的概念用。

**否決 ③（純欄位組成判別）。** 兩個致命問題：

1. **它需要「identity 欄位名跨形狀唯一」這條約束，而那條約束讓 identity 欄位名兼差當形狀名。** `citekey` / `key` / `orgkey` / 將來的 `venuekey`——形狀資訊被塞進欄位的名字裡。這正是本專案在拆的那種一名二職（`type:` 兼形式種類與書目類型）。標籤在 ③ 底下並沒有消失，只是偽裝成欄位名，而且被迫兼任 key。
2. **組成只能決定一個形狀，標籤可以有多個。** 一旦本體不是平坦分割（層級、交集），③ 在檔案層就沒有詞彙。這在本專案是可預見的：`Author` 已經需要 person 與 organization 都能當作者（#6 的法人作者），而將來的 `venue` 與 organization 的欄位幾乎相同——③ 只能靠發明 `venuekey` 來區分，等於承認標籤是必要的。

**採用 ②。** 形狀名以一個沒有值的頂層鍵出現。沒有後設欄位，`person` 不是誰的值；不明的形狀能給出**具名**的錯誤（「不認得的形狀 `view`」），比 ③ 的「找不到 identity 欄位」更貼近提議者實際想做的事。

**曾提出的反對（已回應）**：標籤是被記錄內容蘊含的，因此是衍生值，而衍生值不該進正典（§5）。這個反對只在 ③ 的約束成立時有效——一旦承認可能有兩個形狀共用同一組欄位（venue vs organization），標籤就不是被蘊含的，它是原生資訊。

### E2：標籤取自封閉集合，缺席或不認得一律 quarantine

| 情況 | 行為 |
|---|---|
| 恰好一個已知標籤 | 用它決定 decoder |
| 多個已知標籤 | 用**最具體**的決定 decoder（見 E3） |
| 含不認得的標籤 | quarantine：「不認得的形狀 `<名稱>`」 |
| 沒有任何標籤 | quarantine：「缺少形狀標籤」 |
| 標籤的值非空 | quarantine：「形狀標籤不得帶值」 |

`type: view` 落在「沒有任何標籤」；`view:` 落在「不認得的形狀」。兩條路都被擋。

**標籤值必須為空**是為了關掉一扇門：允許帶值就等於重新造出一個後設欄位，只是名字換成形狀名。

### E3：標籤可多個，但只寫最具體的

本體可以有層級（person ⊑ agent）與交集。標籤集合因此是一個集合而非單值。

但**上位標籤不寫進檔案**——「person 是 agent」是 schema 的事實，不是每一筆記錄的事實，寫進 536 個檔是把同一件事複製 536 份。檔案只寫無法由 schema 推出的部分，也就是最具體的那些標籤。

本 change **不實作推導**，只確立這個形狀（集合、只寫最具體）。目前封閉集合是 `work`、`person`，兩者無層級關係，所以實際上每筆恰好一個標籤。

### E4：`type:` 收窄為書目類型

- work：`type:` 仍為必填、值域開放，行為逐字不變。
- person：不再寫出 `type: person`；讀取時保留 `type` 在 `knownPersonKeys` 內（移出去會讓它被 tolerant-preserve 當未知欄位保存並重新寫出，與目的相反），但忽略其值。
- **矛盾即 quarantine**：`type: person` 與 `work:` 標籤同時出現時不得挑一邊。

### E5：bump store format 到 3，並補標籤到既有檔案

既有 536 筆 work 檔沒有 `work:` 標籤，新的載入器會判定「缺少形狀標籤」。因此本 change 含一次**補標籤遷移**：每個既有 entities 檔加一行標籤，其餘內容逐字不變。

沿用 `StoreMigration` 既有的順序紀律：先全量預檢（含 encode 預演）、再寫、後刪、最後 bump format。中斷時寧可多一份檔案，永遠不丟資料。

format bump 讓舊 binary 對新 store 回報「請升級」，而不是對每個檔案報與真正原因無關的錯誤——這正是 #24 要消滅的失敗模式。

### E6：標籤只在 format 3 起強制；舊格式讀取時以欄位組成回退（實作時發現）

實作 E5 時發現一個順序死結：**遷移程式必須先讀得動未貼標籤的 store，才能替它貼標籤。** 若讀取端無條件要求標籤，format 2 的 store 一開啟就整批 quarantine，`akashic migrate` 連載入都做不到，使用者被鎖在一個無法自行脫離的狀態。

因此判別分兩種嚴格度，由 store format 決定：

| store format | 缺標籤時 | 理由 |
|---|---|---|
| ≤ 2 | 以欄位組成回退（有 citekey → work、有 key → person）；判不出來才 quarantine | 舊資料本來就沒有標籤，拒絕它等於拒絕所有既有 store |
| ≥ 3 | quarantine | 這個格式的檔案是本 change 之後寫的，沒有理由缺標籤 |

不認得的標籤、標籤帶值、多個互不從屬的標籤、標籤與 `type:` 矛盾——**這四種在兩個格式下都 quarantine**。它們是明確的錯誤，不是舊格式的正常狀態。

**替代方案（已否決）：讓遷移用一條繞過讀取端的私有路徑。** 那會讓遷移看到的資料與載入器看到的不同，而遷移正是最需要兩者一致的時刻（#35 的教訓：先驗、再寫、後刪，前提是「驗」用的是真正的載入路徑）。

## Implementation Contract

**Behavior**：載入 `entities/` 下的檔案時，形狀由裸標籤決定；標籤缺席、不認得、或帶值的檔案進 quarantine 並附**具名**理由；`type:` 不再參與形狀判別。

**Interface / data shape**：

- `EntityKind.peek(_:)` 簽章不變，判別依據改為標籤；新增四種 quarantine 理由。
- 每個 entities 檔頂層多一個無值的形狀標籤鍵；person 的輸出少一行 `type: person`；work 的其餘輸出逐字不變。
- store format marker 由 2 變 3。

**Verification**：

- 新測試檔涵蓋 E2 的五種情況各至少一例，含 `type: view` 與 `view:` 兩個實測案例。
- 536 筆真實 work 記錄補標籤後全部載入成功，且除標籤行外逐位元相同。
- 帶兩個標籤的記錄以最具體者決定 decoder。
- `person: true` 這類帶值標籤被 quarantine。
- format 3 的 store 被設定為 format 2 的 binary 拒絕並要求升級。
- 遷移中斷後重跑為冪等，且任何階段都不丟資料。

**Out of scope**：legacy `entries/` 與 `people/` 的載入路徑；書目類型的值域；organization 形狀；層級推導；affiliation 的型別。
