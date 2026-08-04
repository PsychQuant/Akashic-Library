## Why

`docs/store-format.md` §3 規定「`names` 的**第一個是顯示名**」——一個位置式約定，沒有型別、沒有驗證、沒有任何守護。6 個 consumer 依賴它（含 `BibExport`，決定匯出書目印出的作者名），而任何寫入者重排 `names` 就會無聲改掉一個人對外的名字。

實測全 store 868 位 person：`names.first` **84.6%（734 筆）是引用形**（`Guan, Yongtao` 這種索引系統的機械變換），0% 是自然語序。而且這個破壞在 2026-08-05 已經真實發生一次——外部 pipeline 為了縮小 diff 重排 names，把一位人員的顯示名換成了引用形。

## What Changes

- **BREAKING**：廢除「`names` 第一個是顯示名」的位置式約定。`names` 的順序不再帶任何語意。
- 新增 `authorized` 欄位：`names` 的**子集**，列出對外可稱呼的名字。
- 顯示解析改為 `displayName(script:)`：script 相符的 authorized → 任一 authorized → `key`。**不** fallback 回 `names` 的任一元素。
- script 為**推導值不儲存**——只需區分同一個人名字之間的粗分割（Han / Latn），不需 ISO 15924 全集、不需封閉 enum。
- **BREAKING**：store format marker 由 `2` bump 到 `3`（欄位語意變更，依 §5.0 準則 MUST bump）。
- `validate` 新增兩條不變式：`authorized` ⊆ `names`；每個 script 至多一個 authorized。
- `doctor` 新增檢查：報出無 authorized form 的記錄。
- 6 個讀 `names.first` 的 consumer 改讀 `displayName`。
- 提供 migration：機械提名 + 人工採納（候選唯一即自動，多候選用非引用形提名，仍歧義則留空由 doctor 報）。

## Capabilities

### New Capabilities

- `authorized-name`: 實體對外可稱呼的名字——身分確定之後才被**指定**的表述，per-script，與其餘名字變體及索引系統產生的引用形分離。

### Modified Capabilities

- `organization-entity`: organization 的 `names` 是 `TimelineOf<String>`（時間軸），其 `displayName` 目前取 `names.current`；需與 person 的 authorized 機制對齊，使「哪個名字對外」在兩種實體上是同一個問題的同一個答案。

## Impact

- Affected specs: `authorized-name`（新增）、`organization-entity`（修改）
- Affected code:
  - New:
    - Sources/AkashicCore/AuthorizedName.swift
    - Tests/AkashicKitTests/AuthorizedNameTests.swift
  - Modified:
    - Sources/AkashicCore/Models.swift
    - Sources/AkashicCore/Organization.swift
    - Sources/AkashicCore/YAML.swift
    - Sources/AkashicStoreIO/LibraryStore.swift
    - Sources/AkashicExport/BibExport.swift
    - Sources/AkashicExport/CSLExport.swift
    - Sources/AkashicExport/RelationalExport.swift
    - Sources/AkashicMCPKit/AkashicService.swift
    - docs/store-format.md
  - Removed: (none)
