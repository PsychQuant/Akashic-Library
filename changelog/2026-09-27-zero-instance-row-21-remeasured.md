# 2026-09-27 `zero-instance-guards` 第 21 列重量（#571）

第 21 列的理由欄與量測段寫著「受保護 58｜顯式字面 21｜glob／衍生 37」。#554 R9 verify 重跑時得到 59｜2｜57，當時的判斷是 `TriggerCoverage.swift` 的路徑字面寫法變了。

實際原因是**清單換了家**：#522 把受保護清單的單一來源搬進 `ProtectedInventory.swift`（檔頭記著理由：持有清單的檔會被 `READS` 誤判為讀了清單上每一個檔），而量測腳本還在 `TriggerCoverage.swift` 裡找字面，所以只找到 2 個。

- 腳本改指 `ProtectedInventory.swift`。重量（2026-09-27）：受保護 70｜顯式字面 22｜glob／衍生 48；`akashic-guards protected-ratchet` 相符 70 條。
- 理由欄的比例改成 48/70，顯式條目 22/22 由 `missing` 逐條具名（結構上恆為全部）。立案時的 58／37／21 與 19/19 留在同一句裡，這份規則檔的紀律是保留全部量測，不只留最新一欄。
- 裁決不變：這一列要說的是「glob 成員對 `missing` 結構上沉默」，比例從 37/58 變成 48/70，只讓這件事更明顯。
- `measured-numbers-audit`、`zero-instance-rows-audit` 通過。
