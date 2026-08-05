## Why

Store 的序列化順序沒有單一權威。encoder（`PersonYAML.encode` / `OrganizationYAML.encode` / `EntryYAML.encode`）產出一種形狀，外部寫入者（storyline 的 R pipeline、手寫記錄）產出另一種，而沒有任何入口能把後者打回前者。全 store 實測顯示分界完全乾淨：encoder 寫的 636 個 work 檔 0% 偏離，其餘 79 檔 100% 偏離。

更嚴重的是，`organization-entity` spec 內有一條 SHALL 已經被真實資料違反——「loaded and re-encoded → byte-identical to the input」與同一個 Requirement 內的「Timeline equality SHALL remain independent of storage order」互斥。實測 `ching-shui-cheng` 記錄 decode 後 re-encode 得到 `BYTE-IDENTICAL: false`。encode canary 抓不到，因為 Timeline 相等性刻意忽略順序（見 `Sources/AkashicCore/Temporal.swift` 的設計註解），那個決定同時讓 canary 對「靜默重排」失明。

## What Changes

- **BREAKING（序列化輸出）**：`TimelineOf` 的相等性順序與序列化順序分離。相等性維持全序（`range` 相同時比 `value`）；序列化改為「依 `range` 排序，`range` 相同時保留寫入順序」。受影響的是寫出的位元組，不是任何 in-memory 型別的 API 形狀
- **BREAKING（spec 修訂）**：`organization-entity` 的 byte-identical 要求限縮為「**canonical 輸入**讀寫後 byte-identical」，並新增 idempotence 要求（任意合法輸入經一次正規化後即為不動點）
- 新增 `akashic fmt` 子命令：無旗標時就地把記錄重寫為 canonical form；`--check` 只回報偏離並以非零碼退出，不寫檔
- 正規化實作為 decode + encode，**不引入獨立的 normalizer 型別**——encoder 已是 canonical form 的唯一定義，第二份定義會重演本 change 要修的病
- 既有 79 筆記錄（77 person、2 organization）以獨立提交 reflow，不與任何語意改動同批
- 明文記錄不納入本次的 canonical form 面向：Yams emitter 的折行寬度維持現狀

## Capabilities

### New Capabilities

- `canonical-serialization`: 記錄寫出的位元組形式由單一權威定義，且提供讓任何寫入者對齊該形式的入口

### Modified Capabilities

- `organization-entity`: byte-identical 要求限縮為 canonical 輸入，並補上 idempotence

## Impact

- Affected specs: `canonical-serialization`（新增）、`organization-entity`（修訂）
- Affected code:
  - New: `Sources/akashic/FormatCommands.swift`
  - Modified: `Sources/AkashicCore/Temporal.swift`、`Sources/AkashicCore/YAML.swift`、`Sources/akashic/CLI.swift`、`openspec/specs/organization-entity/spec.md`
  - Removed: (none)
- Affected data: `~/.akashic/entities/` 內 79 筆記錄的位元組形式（77 person、2 organization）；636 筆 work 記錄零改動
- Affected consumers: 任何直接寫入 store 的外部 pipeline——storyline 的匯出腳本、Akashic-Library#64 的 CV 補完流程、Akashic-Library#68 的部分更新入口
