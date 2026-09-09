# `paginated` 判定可以撤回，翻轉的每一筆各自帶值（#500）

裁決取自 issue 自己的 Key Decisions（2026-09-04，候選 1；`### Blocking` 是 `(none)——進 implement`）。

## 兩個原本**寫不出來**的東西

**(b) 撤回判定。** 翻轉 true↔false 可以（留史），但撤回到誠實的未判定狀態沒有面。阻礙不只是少
一個參數：`validateReferenceAttachment` 對 `field: paginated` 要求「記錄的 `paginated` 非 nil」，
所以「退回 nil 但保留判定史」**在驗證層就寫不出來**——要嘛丟掉全部 reference（違反「翻轉留史」），
要嘛改規則。`resolve-venues demote`（#418）在這個域的對應物因此不存在。

**(c) 翻轉語意。** value 恆 nil 時資料層看不出哪句理由對應哪個值；同 statement 翻回時
`(field, value, kind)` 冪等會吞掉新翻轉。

## 值域

`paginated` 自此是 D2「純量欄位不收 value」的**明文例外**，三值封閉：`true`／`false`／`nil`
（後者＝撤回，是一筆帶理由與證據的**判定**，不是刪除）。

**不是**「凡是判定型純量都收 value」——那句話會在下一個純量上長出沒人同意的答案；要收就再明寫
一個例外。

## 兩面

CLI `--clear-paginated`／MCP `clear_paginated`，照 #258 對 `set-status` 的既有裁決：**省略不等於
清除**（省略 `paginated` 的意思是「這次不動它」；若讓省略等於清除，一次只想改 note 的呼叫會把
判定抹掉）。與 `paginated` 同時給即拒絕——一次呼叫只能說一件事。撤回同樣要 `judgement`：
撤回本身是判定。

## 相容路徑與退場

**舊筆（value 缺席）放行**，並依 `no-compat-fallback` 第 2 條附退場條件與**量它的指令**（兩個數字
相等時把 `if let v` 改成 `guard let v else { throw }` 並刪掉那段）。落地當日：33 筆 paginated
reference、帶 value **0** 筆。

## 端到端實測

```
--paginated true  → value: true,  judgement: 有頁碼
--paginated false → value: false, judgement: 改判：線上無頁碼
--clear-paginated → value: nil,   judgement: 證據不足，撤回
paginated 欄位：已撤回；三筆判定史都在；重新載入乾淨
```

`testFlipsWithTheSameStatementAreNotSwallowed` 用**同一句理由**做 true → false → true，得
`["true", "false"]`：第三筆與第一筆完整相等所以冪等吞掉（對），第二筆的 value 不同所以留著
——這正是 (c) 要的分得開。

## 兩則更正

- 既有測試 `testVenuePaginatedReferenceAttachmentRules` 釘的是**被拿掉的那兩條規則**，改寫並在
  其中記下「它們正是 (b) 寫不出來的原因」。
- issue 的 Impact 列了 `openspec/specs/venue-entity`／`provenance-reference` 的 normative 更新
  ——**實測沒有對象**：`openspec/` 全樹對 `paginated` 零命中。規則住在 `Provenance.swift` 的
  doc comment 與測試裡。

PR #538。
