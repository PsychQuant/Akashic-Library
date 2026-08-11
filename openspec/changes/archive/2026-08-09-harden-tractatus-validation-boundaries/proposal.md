## Why

封存後的獨立完工稽核證明正典資料本身完整，但 strict validator 仍有五個 false-negative 邊界：部分不可信輸入可在 construction mode、evidence locator、離線圖資、外部版本參照或 incomplete diagnostics 路徑中逃過檢查。這會讓著作權、來源誠信與可行動診斷的規格承諾出現假綠，因此必須在交付前補齊。

## What Changes

- 來源快照即使在 corpus 尚無任何卷時也必須解析 authorial structure；`--allow-incomplete` 只放寬缺卷，不放寬 malformed snapshot、digest、權利或來源誠信。
- evidence locator 改以結構位置解析 Swift symbol、XCTest method 與完整 Spectra requirement heading，拒絕只出現在註解、字串或較長 heading 中的偶然文字。
- 離線圖資驗證涵蓋 renderer 會處理的所有 rich-text 欄位，並使用和 renderer 一致的 Markdown image path 語法，包括含空白的相對路徑。
- external-reference edition 只接受對應 scope record 的固定命題參照；將譯文或其他長篇內容塞進 `edition_references` 必須以 `license-violation` 拒絕。
- construction mode 同時遇到 missing volume／proposition 與實質錯誤時，stderr 必須保留完整 incompleteness 清單和排序後 diagnostics。
- 以真實 validator／CLI fixture 加入五組先紅後綠的回歸測試，並重跑全套 build、tests、strict validate 與 render check。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `tractatus-project-map`: 明確補強來源快照 fail-closed、結構化 evidence、全 rich-text 圖資、external-reference 權利邊界與 construction diagnostics 的驗證情境。

## Impact

- Affected specs: `tractatus-project-map`
- Affected code:
  - Modified:
    - `Sources/TractatusDocs/SourceManifest.swift`
    - `Sources/TractatusDocs/Validation.swift`
    - `Sources/TractatusDocs/Rendering.swift`
    - `Sources/TractatusDocs/DocumentService.swift`
    - `Tests/TractatusDocsTests/SourceManifestTests.swift`
    - `Tests/TractatusDocsTests/CorpusValidationTests.swift`
    - `Tests/TractatusDocsTests/RenderingTests.swift`
    - `Tests/TractatusDocsTests/TractatusValidationCLITests.swift`
  - New: (none)
  - Removed: (none)
- Public CLI command names、YAML schema 與 Akashic store／App／MCP 行為不變；不新增套件依賴。
