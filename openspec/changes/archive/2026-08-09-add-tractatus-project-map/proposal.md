## Why

目前專案只在設計文件中選擇性引用《邏輯哲學論》，無法證明整部著作的每個正文句段都已被翻譯、解讀並誠實對照到 Akashic-Library。需要一份可機械驗證、可追溯版本與證據、且能明確承認不適用或刻意不遵循的正典語料，避免哲學宣稱超過實作。

## What Changes

- 新增《邏輯哲學論》專案對照正典：以工具內建指紋鎖定維根斯坦序言八段與編號命題 1–7 共 526 條；獻詞與題辭只作來源 metadata，不納入逐句對照；Russell 導論與索引不在範圍內。
- 並排保存德文原文、1922 Ogden／Ramsey 英譯、Pears／McGuinness 英譯或其授權允許的版本參照，以及本專案的臺灣正體中文工作譯文。
- 來源契約只要求 inline edition 以 SHA-256 鎖定實際重製的 snapshot；Pears／McGuinness external reference 不重製內容，改以 bibliography、URL、revision 與 rights note 稽核，且必須省略 `sha256`，避免虛構內容 digest。
- 以命題與句段雙層模型處理不同版本句界不一致；每個來源單位只能依序被一個句段涵蓋，每個句段都必須有中文工作譯文與哲學解讀，對齊形狀只允許 1↔1 或句界不同時的 2↔1／1↔2，並檢查來源單位是否偷藏多句，避免用 mega-segment 冒充逐句「解毒」。
- 每個命題至少保存一筆專案關係，使用封閉的狀態與實現模式，並附逐命題撰寫的理由與現況證據；無對照、僅為類比、刻意不遵循或尚屬願景時也必須明載，不得以跨命題共用樣板冒充逐條判斷。
- 以 `main` 作目前正典；branch、commit 與 issue 只保存為理解形成、修訂或被推翻的歷史脈絡。
- 新增獨立 Swift 工具與型別化函式庫，負責 YAML 載入、固定範圍與版本驗證、corpus 對離線來源 snapshot 的全文回組、結構化專案引用驗證與決定性 Markdown 產生，不把此語料放入 Akashic canonical store。
- 新增 CI 閘門：正典 YAML 驗證失敗或產生的 Markdown 與版控內容不同時，建置失敗。

## Capabilities

### New Capabilities

- `tractatus-project-map`: 可機械驗證的《邏輯哲學論》逐句多版本語料、Akashic 專案對照、歷史證據與決定性並排文件產生。

### Modified Capabilities

（無）

## Impact

- Affected specs: `tractatus-project-map`
- Affected code:
  - New:
    - `docs/tractatus/README.md`
    - `docs/tractatus/sources.yaml`
    - `docs/tractatus/source-snapshots/de-wittgenstein-project.md`
    - `docs/tractatus/source-snapshots/en-ogden-ramsey-1922-wittgenstein-project.md`
    - `docs/tractatus/source-assets/SHA256SUMS`
    - `docs/tractatus/source-assets/images/*`
    - `docs/tractatus/corpus/preface.yaml`
    - `docs/tractatus/corpus/1.yaml`
    - `docs/tractatus/corpus/2.yaml`
    - `docs/tractatus/corpus/3.yaml`
    - `docs/tractatus/corpus/4.yaml`
    - `docs/tractatus/corpus/5.yaml`
    - `docs/tractatus/corpus/6.yaml`
    - `docs/tractatus/corpus/7.yaml`
    - `docs/tractatus/generated/tractatus-project-map.md`
    - `Sources/TractatusDocs/Corpus.swift`
    - `Sources/TractatusDocs/DocumentService.swift`
    - `Sources/TractatusDocs/SourceManifest.swift`
    - `Sources/TractatusDocs/Validation.swift`
    - `Sources/TractatusDocs/Rendering.swift`
    - `Sources/tractatus-doc/main.swift`
    - `Tests/TractatusDocsTests/CorpusValidationTests.swift`
    - `Tests/TractatusDocsTests/CorpusSourceFidelityTests.swift`
    - `Tests/TractatusDocsTests/SourceManifestTests.swift`
    - `Tests/TractatusDocsTests/RenderingTests.swift`
    - `Tests/TractatusDocsTests/TractatusValidationCLITests.swift`
    - `Tests/TractatusDocsTests/TractatusInterfaceTests.swift`
    - `Tests/TractatusDocsTests/TractatusDiskFixture.swift`
    - `Tests/TractatusDocsTests/Fixtures/rendering-expected.md`
  - Modified:
    - `Package.swift`
    - `.github/workflows/ci.yml`
  - Removed: none
