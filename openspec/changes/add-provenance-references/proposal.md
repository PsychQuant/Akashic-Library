## Why

一筆記錄的欄位開始來自**互不相同的權威來源**，而 store 只有一個結構化的 provenance 欄位（`TemporalValue.source`），且它掛在最細的時間段層級。

證據（Akashic-Library#64 的實測，2026-08-03）：同一個 person 記錄裡，`profile.affiliations` 來自機構名冊頁、`orcid` 來自 ORCID public API 加人工判定、著作來自三個不同管道。判定的推理過程無處可放——目前有一筆別名判定被塞進整筆記錄的 `note` 自由文字，另有 41 筆 ORCID 的判定依據被迫離開 store、存在另一個 repo 的 CSV 裡。store 說「這個人的 ORCID 是 X」，但「我們怎麼知道的」不在 store 內。

更根本的是**只存 URL 不構成 provenance**。實測：`sites.stat.sinica.edu.tw/cheng/` 與 `www.stat.sinica.edu.tw/cheng/` 回傳位元組相同的內容（同一 SHA-256）；`staff.` 版本則是 404。兩個不同的 URL、同一個東西——URL 是通往內容的路徑，不是內容本身。URL 失效時，主張所依賴的東西就再也取不回來（同批實測：Wayback 對這類低流量學術頁 5 個死站只有 1 個有快照，且是活著的首頁而非死掉的子頁）。

## What Changes

新增一個 provenance 機制，記錄同時保留兩件事：

1. **指涉的內容本身**——擷取當下的位元組，以 SHA-256 內容定址存放。這是主張真正依賴的東西，URL 死了它還在。
2. **取得的路徑**——URL 與擷取日期。這是審計軌跡；不同的路徑可以獨立驗證同一份內容（上述 `sites.` 與 `www.` 即互為佐證）。

存檔內容**只留 local，不進 git remote**，比照本專案既有的 raw 第三方逐字內容處置。理由：存檔的網頁是第三方的逐字內容，即使來源是公開發布的機構頁面。store 的 git remote 追蹤 provenance 的**指涉**（URL、hash、日期），不追蹤**被指涉的位元組**。

排除規則寫在 store 自己的版控忽略檔（store 是獨立的資料 repo，不是本 repo 的檔案），由 layout 建立時寫入並在寫檔前驗證生效——不依賴使用者記得設定。

存檔內容**不是 entity**，不進 `entities/`。理由不只是 entity-boundary 既有的形狀判準（網頁不決定記錄形狀、不讓 loader 分岔到不同 decoder），還有一個更強的：內容定址的位元組串改一個 byte 就是另一串，它沒有名字、沒有歷史、沒有生命週期，身分完全是外延的——這與「名稱改變後仍應被視為同一物」的 entity 判準正好相反。

## Non-Goals

- **不改既有的 `TemporalValue.source`**。目前 78 段 affiliation 各帶一個裸 URL，本次不遷移、不升級成指涉形式。兩者並存，遷移另案處理。
- **不做內容正規化後再 hash**。廣告、時間戳、session id 會讓內容變動而所指未變，但正規化本身是一種詮釋，牽涉 design-principles 第 16 節的規則遵循問題，需要獨立審議。
- **不自動擷取**。本變更定義 provenance 的形狀與存放，不含爬取或排程；擷取由呼叫端決定。
- **不把 provenance 加進 `export-tables`**。衍生層是否要能查 provenance 是獨立決定。
- **不做存檔內容的過期偵測或重新擷取**。

## Capabilities

### New Capabilities

- `provenance-reference`: 記錄一筆資料的來源，同時保留指涉路徑（URL 與擷取日期）與被指涉的內容（內容定址的存檔），並規定存檔內容不進版控遠端、不是 entity。

### Modified Capabilities

(none)

## Impact

- Affected specs: `provenance-reference`（新增）
- Affected code:
  - New:
    - `Sources/AkashicCore/Provenance.swift`
    - `Tests/AkashicKitTests/ProvenanceTests.swift`
  - Modified:
    - `Sources/AkashicCore/Models.swift`
    - `Sources/AkashicCore/Organization.swift`
    - `Sources/AkashicCore/YAML.swift`
    - `Sources/AkashicStoreIO/LibraryStore.swift`
    - `docs/store-format.md`
  - Removed: (none)
