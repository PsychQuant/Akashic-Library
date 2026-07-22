# Akashic-Library Phase 3 — 原生 App（AkashicApp）設計

- 日期：2026-07-22
- 狀態：已與鄭澈逐節確認（brainstorming session）
- 前置：Phase 1（store+AkashicKit+CLI）、Phase 2（akashic-mcp + marketplace）已完結；實庫 536 entries
- 實作紀律：動 SwiftUI 前先載入 `apple-xcode-skills:swiftui-specialist`（CLAUDE.md CRITICAL 規則）

## 1. 決策記錄

| # | 決策 | 選擇 |
|---|------|------|
| 1 | App 定位 | **管理工作台優先**：人工裁決 UI（resolve-people／orphan／quarantine）+ 互動關係圖 + 基本瀏覽。查詢/標註日常已由 Claude+MCP 覆蓋，App 做 CLI/MCP 難做的事 |
| 2 | 互動圖技術 | **原生 SwiftUI Canvas**（自實 force-directed；符合「原生」命題、零 web 依賴） |
| 3 | Backlog | **只併 #4 citekey rename**（工作台自然功能，Kit 層 API 作前置）；#5 CLI 面／#6／#7 留 backlog |
| 4 | 打包形態 | **Xcode project + SPM 邏輯層**：真 .app bundle；view models 在可測的 `AkashicAppKit`，Xcode 只裝視圖薄殼 |
| 5 | 發布 | local build 為主；Developer ID sign 留 optional（不在本 phase 驗收內） |

Out of scope：閱讀中樞（PDF 檢視）、Zotero 擷取/斷奶、App Store、XCUITest、#5 CLI 面／#6／#7。

## 2. 架構

```
Akashic-Library repo
├── AkashicApp/                      ← Xcode project（SwiftUI 視圖薄殼 + .app bundle）
├── Sources/AkashicAppKit/           ← 新 SPM target：AppState / 裁決台 view models /
│                                       ForceLayout / FileWatcher（全部可 swift test）
├── Sources/AkashicStoreIO/          ← #4 前置：renameEntry API
└── Sources/akashic/                 ← CLI 加 rename 指令
```

- macOS 14+、SwiftUI、`@Observable`。
- App 讀寫走 AkashicKit typed API（QueryEngine／LibraryStore／PersonResolver／GraphBuilder），不繞 MCP JSON 層。
- Library 解析：`LibraryLocator`（與 CLI/MCP 同一套）。

## 3. #4 前置：citekey rename

`LibraryStore.renameEntry(from:to:)`：

1. 驗證新 key（`StoreKey.isValid` + 目的檔不存在——含 quarantined／大小寫別名）
2. 改 `entry.citekey`（UUID 不動）→ 原子寫新檔、刪舊檔
3. **全庫掃 relations**：他檔 `akashic.relations.cites`/`related` 引用舊 citekey → 改新（UUID 引用不動）
4. reindex

CLI 同步：`akashic rename <old> <new>`（#4 原 scope 完整兌現）。App 的 rename 按鈕走同一 API。

## 4. App 功能（v1 管理工作台）

| 區塊 | 內容 |
|---|---|
| **Sidebar** | Library 健康總覽（entries／unresolved literals／orphans／quarantined 計數＝doctor 視覺版）+ 搜尋 + filter（type/tag/journal/year） |
| **列表＋詳情** | 中欄列表（citekey/title/authors/year）；右欄詳情：biblatex 面向唯讀、**衍生層可編**（status 下拉、tags chips、relations 增刪）、rename 按鈕 |
| **裁決台①People** | resolve 候選逐一 accept／skip（#5 的 App 面）＋新增 person 表單 |
| **裁決台②Orphans** | 每筆三選：等待（預設）／刪檔（進垃圾桶）／轉純 Akashic entry（抹 provenance） |
| **裁決台③Quarantine** | 錯誤原因展示、在 Finder 開啟、重新驗證按鈕 |
| **Graph** | 原生 Canvas force-directed：focus 切換、depth 滑桿、拖節點（pin）、縮放、單擊選取同步詳情、雙擊增量展開鄰域 |

寫入邊界與 MCP 相同（**只碰衍生層**）＋兩個 App 專屬人工裁決：rename、orphan 刪檔（皆確認對話框；刪檔走 `NSWorkspace.recycle` 進垃圾桶可救回）。

## 5. Canvas graph 實作

- 資料：`GraphBuilder.neighborhood`（既有）。
- `ForceLayout`（AkashicAppKit，純函數）：反平方斥力＋邊彈簧＋中心引力；固定種子初始位置 → 佈局決定論可測；節點數由 depth 控制，個人庫規模 60fps 無壓。
- 視圖：`Canvas` 繪製（entry 方形／person 圓形／venue 六角，沿 DOT 形狀慣例）＋ `TimelineView` 驅動；手勢如上表。

## 6. 錯誤與併發

- 沿用生態契約：atomic write、last-wins、quarantined 檔永不被 App 覆寫；App 寫後即時 reindex。
- **FileWatcher**（DispatchSource 監看 `entries/`、`people/`）：外部變更（CLI/MCP/git）→ debounce 重載刷新；編輯中偵測同檔外部變更 → 衝突提示，不靜默覆蓋。
- 危險動作（rename／orphan 刪檔）確認對話框。

## 7. 測試

- `AkashicAppKit` XCTest：AppState（載入/篩選/衍生層編輯流）、裁決台 view models（accept/skip/orphan 三選）、ForceLayout（收斂＋決定論）、FileWatcher（debounce）。
- rename API 在 AkashicKitTests：搬檔、relations 遷移、quarantine/撞名拒絕、UUID 不變。
- UI：`xcodebuild build` 進驗證流程；**手動驗收清單**（spec 附錄 A）跑過即驗收；XCUITest 留 backlog。
- 全套件零回歸（Phase 2 的 143 tests）。

## 8. 交付物

1. #4 前置：`renameEntry` + relations 遷移 + `akashic rename` CLI（→ #4 可關）
2. `AkashicAppKit` + 測試
3. `AkashicApp/` Xcode project（Sidebar／列表詳情／裁決台×3／Graph）
4. 附錄 A 手動驗收清單全項通過（實庫操作）
5. README App 段

## 附錄 A — 手動驗收清單

- [ ] App 啟動載入實庫（536 entries，計數與 `akashic doctor` 一致）
- [ ] 搜尋/filter 結果與 `akashic query` 一致（抽查 3 組）
- [ ] 詳情頁編輯 status/tags/relations → 檔案落地 + CLI 可見；biblatex 面向不可編
- [ ] rename 一筆有被引用的 entry → 引用端 relations 跟著改、UUID 不變、graph 不斷鏈
- [ ] People 裁決：accept 一個候選 → entry 轉 key 形式；skip 不動
- [ ] Orphan 裁決三選各跑一次（刪檔那筆到垃圾桶可救回）
- [ ] Quarantine：放一個壞檔 → 顯示原因；修好後重新驗證消失
- [ ] Graph：拖拉/縮放/雙擊展開流暢；點擊節點詳情同步
- [ ] CLI 在 App 開著時 import → file watcher 自動刷新
- [ ] 外部改 App 正在編輯的檔 → 衝突提示出現
