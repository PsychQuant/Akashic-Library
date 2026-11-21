## Why

#824：`akashic store-source` 的 `--note` 寫進 `sources/index.jsonl` 之後，沒有受支援的路徑可以更正它。2026-11-20 存的五份全文裡，兩份的 note 寫了「no page range in the record」，實際上那兩筆條目有頁碼，是 `fulltext take` 當時沒帶 `--pages`；另外兩份寫「no page count check」，當時為真，事後頁數比對過了，也補不進去。對同一份位元組再跑一次 `store-source` 是冪等的：不建新列，新的敘述以 `discardedProvenance` 回報、不寫入。所以照 plugin 的規定（不手改 store 的檔），寫錯的那半句改不了；而連結說「這份就是這篇」，靠的正是 note 記得是誰、怎麼判的（`akashic-fetch-fulltext` 第 6 步）。

維護者 2026-11-21 17:05（+08:00）的答覆（#824 留言 7062309057）原文：

> when an old measurement row is corrected, **add a correction row and annotate the old row** (the old row stays, marked with what supersedes it). The other options offered were replacing the row in place, and keeping observations annotated while correcting wrong generalisations in place.

本 change 把其中的「old measurement row」讀成 `sources/index.jsonl` 裡記著那份存檔取得與驗證經過的那一列（#824 的例子就是 note 記下的量測：take 的結束碼、有沒有比對頁數）。這是協調者的讀法，答覆本身沒有點名 `index.jsonl`。

## Current behaviour

讀的是 `origin/main` 82c63451：

- **index 只增不改**：`appendIndexEntry` 以 `O_APPEND` 寫一整行，「只 append、永不重寫既有行」（`Sources/AkashicStoreIO/SourceStore.swift` 第 284–329 行）；`storeSource` 的說明「重存不覆寫既有敘述——append-only，index 永不重寫既有行」（同檔第 158–167 行）；`docs/store-format.md` 第 1478–1486 行同一條。`grep -rnE 'sourceIndexURL' Sources` 只有 `SourceStore.swift` 的四處（定義、append、兩處讀），沒有其他寫 index 的路徑（2026-11-21）。
- **同一個 digest 以第一列為準**：`scanIndex` 對每個 digest 只收第一列的字串欄位與 `bytes`（同檔第 338–340 行、第 362–378 行）。同一份內容並行存檔時會留下好幾列，讀的一方以第一列為準（同檔第 213–214 行）。
- **讀不懂的一行會擋住所有新存檔**：一行沒有合法的 `content` digest 就算無法解析；index 有無法解析的行時，`storeSource` 對任何新內容拒寫（同檔第 115–124 行、第 227–231 行），`sourcePresence` 對沒有可解析列的 digest 擲錯（同檔第 437–442 行）。
- **重存時新的敘述被丟棄、但看得見**：`SourceReceipt.discardedProvenance`（同檔第 40–46 行、第 252–261 行）；CLI 印出「要改既有條目的敘述，本命令做不到——那是另一個動作」（`Sources/akashic/StoreSourceCommand.swift` 第 87–96 行）。這一條在 `openspec/specs/provenance-reference/spec.md` 的〈Stored content SHALL be reachable through a user-facing entry point〉裡有 scenario（重存一份帶更正 note 的網頁、note 被回報為丟棄）。
- **把 index 列的 note 給人看的讀取面只有兩個**：`update-entry --add-source` 回應的 `sourcesAdded`（`Sources/AkashicMCPKit/EntryUpdate.swift` 第 376–386 行）與 `update-entry --remove-source` 回應的 `sourcesRemoved`（同檔第 628–641 行）。其餘讀 index 列的面只讀別的欄位：`fulltext text` 的 `chooseSource` 與作者列替換只讀 `media-type`（`Sources/AkashicSkillTools/FulltextReconcile.swift` 第 30–77 行、`Sources/AkashicMCPKit/AuthorListReplacement.swift` 第 246–257 行），`copy-zotero-attachments` 只讀 `origin`（`Sources/AkashicMCPKit/ZoteroAttachmentCopy.swift` 第 428–431 行）。
- **index 的文法不受 store format marker 管**：`docs/store-format.md` §5.0 的版本對照表（第 1813–1836 行，format 1–23）沒有任何一列提到 `index.jsonl`——`grep -n 'index.jsonl' docs/store-format.md` 的 23 個命中都在第 1642 行以前（2026-11-21）；舊 binary 讀到多出來的欄位或列時照第一列為準。
- **描述的真偽由寫的人負責**：`provenance-reference` 的〈The truthfulness of a provenance description SHALL rest with the writer, not with the audit〉——audit 只查形式。

## What Changes

- `provenance-reference` 新增四條 requirement：
  - 一份已存 source 的 note 可以用**追加一列更正**來更正；既有列一律不改寫。
  - 更正列的形狀：在今天的文法下可以解析（帶合法的 `content`），與並行存檔留下的重複列分得開，寫明它取代哪一列、新的 note、時間與理由。
  - 讀的一方以最新的更正為現在的 note，並把被取代的列標成「被哪一列取代」——標記由讀的一方算出，不寫進舊列（開放問題 Q1 的建議預設）。兩個讀取面（`sourcesAdded`、`sourcesRemoved`）回應現行的 note、標明它是更正過的，附上被取代的原文。
  - 讀的一方依檔案順序套用更正；指的不是當時現行列的更正（兩筆並行寫入時就會出現）不套用，由讀取面與 `doctor` 說出來。
  - 更正的入口：CLI 與 MCP 兩面；拒絕的情形是封閉列舉（六種），note 與現行相同時不寫、回報已是現行；`doctor` 報告指不到目標或沒有生效的更正列；更正不被說成驗證過。
- 重存時丟棄新敘述的既有 scenario 不變；CLI 那一句改成指向更正的入口。

## Non-Goals

- 不改既有的任何一列，也不提供刪列或改寫列的入口。
- 不更正 `note` 以外的欄位（Q2 的建議預設）。
- 不檢查更正內容的真偽：更正跟原本的 note 一樣，是寫的人的陳述。
- 不處理 #825 的匯出；但 #825 的 Q1（index 列的 `version` 欄位）要補到既有列上時，需要本 change 的更正能涵蓋那一欄，兩題要一起定（見 Q2）。

## Open questions for the maintainer

規格裡寫的是每一題的建議預設；選了別的，對應的 requirement 與 tasks 跟著改。

| # | 問題 | 建議預設 | 依據 |
|---|---|---|---|
| Q1 | 「annotate the old row」與 index 只增不改的衝突：要在舊列裡寫上標記，還是由讀的一方標 | 舊列的位元組不動；更正列寫明它取代哪一列，讀的一方把舊列顯示為「被第 N 列取代」。要真的改寫舊列，得同時改掉 `SourceStore.swift` 第 163、285 行與 `docs/store-format.md` 第 1481 行的只增不改，而 index 現在不進 git、沒有歷史（`docs/store-format.md` 第 1578–1581 行），改壞了救不回來 | 答覆說「the old row stays」；只增不改是現行的承重條件 |
| Q2 | 更正只涵蓋 `note`，還是也涵蓋其他欄位 | 只涵蓋 `note`。`media-type` 是三道閘讀的欄位（`chooseSource`、作者列替換、#825 的原版表），`bytes` 由位元組決定，`retrieved`／`origin`／`acquisition` 是取得當下的事實；要涵蓋哪一欄就逐欄加進封閉列舉。**例外要一起定**：#825 選了 Q1 的 `version` 欄位時，既有列要補 `version` 只有更正這條路，屆時把 `version` 加成第二個可更正的欄位 | #824 的例子全部是 note；Expected 寫的是「provenance」 |
| Q3 | 更正列本身寫錯了，能不能再更正 | 可以：新的更正取代當時現行的那一列（可能是前一次的更正），形成一條鏈；每一列都留著 | 與 Q1 同一個模型，不需要第二種列 |
| Q4 | 要不要升 store format | 要：更正的寫入要求 store format ≥ 下一號，舊 binary 整個拒開。舊 binary 照第一列為準，會把被取代的 note 當成現行的顯示——正是 #824 要防的那件事。`docs/store-format.md` 的先例是「語意不是語法」（版本表 18、21 兩列：頂層鍵本屬 additive，仍 bump） | 另一個選擇是不升：舊 binary 安靜地顯示舊 note |
| Q5 | 更正列怎麼指名它取代的那一列 | 以 `scanIndex` 的行號（1 起算、含空行）指名，寫入時要求那一行正是這個 digest 現行的那一列，不是就拒絕。index 只增不改，所以行號不會變；有人手改 index 時，`doctor` 會報指不到目標的更正列 | 行號已是 index 診斷的定位方式（`SourceStore.swift` 第 334–336 行） |

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `provenance-reference`：ADDED 四條 requirement（更正列、更正列的形狀、現行 note 與被取代列的呈現、更正的入口）。既有 requirement 的字句不變。

## Impact

- Affected specs: provenance-reference
- Affected code（實作時）：
  - Modified: Sources/AkashicStoreIO/SourceStore.swift, Sources/AkashicMCPKit/AkashicService.swift, Sources/AkashicMCPKit/EntryUpdate.swift, Sources/akashic/StoreSourceCommand.swift, Sources/akashic/Commands.swift（doctor）, Sources/akashic/CLI.swift, Sources/akashic-mcp/Server.swift, Sources/akashic/WriteGateRulings.swift, Sources/AkashicStoreIO/StoreVersion.swift（若 Q4 照建議）, docs/store-format.md, docs/rulings/mcp-cli-parity.md, docs/rulings/two-kinds-of-edits.md, plugin/skills/akashic-fetch-fulltext/SKILL.md, plugin/skills/akashic-bootstrap/references/writing-to-the-store.md, plugin/CHANGELOG.md, .githooks/plugin-shell-versions.txt
  - New: Sources/akashic/CorrectSourceCommand.swift, Tests/AkashicKitTests/SourceProvenanceCorrectionTests.swift, Tests/AkashicCLITests/CorrectSourceCLITests.swift, changelog/<日期>-source-provenance-correction-824.md
