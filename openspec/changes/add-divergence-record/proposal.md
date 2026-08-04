## Why

同一性的歧異目前只能當場判斷掉，判斷過程留不下來。

store 已有「寧可分割，絕不合併」的哲學，`bootstrap-people` 也確實照做——同一個人的兩種寫法會建成兩筆記錄。但分割之後兩筆各自失憶：沒有地方記「這兩筆可能是同一個」，沒有入口把它們合起來，也沒有地方記「我當時在 A 與 B 之間選了 A，理由是 X」。

量測顯示問題不在既有資料而在流程：store 內 822 筆 person 只有 1 筆帶分割後綴，但最近一次資料補完作業遭遇了七次歧異，其餘六次都在寫入之前被判斷掉，判斷只以散文形式留在筆記、commit message、或已捲走的對話裡。實例包含同一篇論文三次執行產生三種 citekey、同一個機構出現 21 種寫法、以及兩個聚合器對同一位作者姓名的比對結果不一致。

## What Changes

- 新增 `divergence:` 裸標籤實體，承載**未決的同一性問題**：候選清單、當時的判斷、判斷所依據的證據。它是短暫的——消歧完成後刪除，歷史託給版本控制
- 新增消歧入口：**合併 + 全庫參照重寫 + 刪檔**的原子操作。沿用既有 citekey 改名路徑已具備的參照遷移能力
- 刪除前驗證 store 位於 git 工作樹內；不在則拒絕刪除（「git 有紀錄」是部署假設，須被驗證而非相信）
- 判斷的形狀從 `add-provenance-references` 的 `ProvenanceReference` **抽出共用件**：`judgement` + `rests-on`（不含 `field:`），兩個變更共用同一組詞彙
- **BREAKING（spec）**：`entity-shape-label` 的「shape labels 取自封閉集合」條款新增一個成員
- **BREAKING（spec）**：`entity-boundary` 登記本判定——`divergence` 通過該 spec 自己的 shape-selection test

## Non-Goals

- **不把判斷遷移到倖存的實體**。那需要實體帶 `references:`，而該欄位屬於 `add-provenance-references` 的範圍（且該變更只規劃給 person 與 organization，未含 work）。本變更若順手實作等於搶先實作另一個變更的一半，製造兩個變更對同一組型別的競爭寫入權。列為該變更落地後的後續工作。**誠實記錄的降級**：在那之前，消歧時判斷隨記錄一起刪除，只留在版本歷史裡
- **不涵蓋 organization**。`Academia Sinica` 的 21 種寫法確實是一筆待表達的歧異，但機構是否該建成實體本身尚未決定（Akashic-Library#70），現在納入會把未決的設計寫死
- **不做自動偵測**。歧異應該是被主張的，不是被偵測的。實測顯示「姓與名首字母相同」的組有 123 組、涉及 422 筆，其中絕大多數是真正不同的人；自動偵測會製造大量噪音
- **不引入 tombstone**。使用者已拍板消歧後刪除，版本控制承擔歷史
- **不動既有記錄**。無 `divergence` 記錄的 store 載入與寫回位元組不變

## Capabilities

### New Capabilities

- `divergence-record`: 未決同一性問題的記錄形狀，及其消歧與刪除的生命週期

### Modified Capabilities

- `entity-shape-label`: 封閉集合新增成員
- `entity-boundary`: 登記 `divergence` 通過 shape-selection test 的判定

## Impact

- Affected specs: `divergence-record`（新增）、`entity-shape-label`（修訂）、`entity-boundary`（修訂）
- Affected code:
  - New: `Sources/AkashicCore/Divergence.swift`、`Sources/akashic/DivergenceCommands.swift`
  - Modified: `Sources/AkashicCore/YAML.swift`、`Sources/AkashicStoreIO/LibraryStore.swift`、`Sources/akashic/CLI.swift`、`openspec/specs/entity-shape-label/spec.md`、`openspec/specs/entity-boundary/spec.md`
  - Removed: (none)
- Affected consumers: 任何列舉實體形狀的消費端——schema 驗證、佈局檢查、index 重建、關聯式匯出、MCP 工具面
