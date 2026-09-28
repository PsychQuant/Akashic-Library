# 2026-09-28 每一個 CLI 寫入面都要有閘的裁決；`--drop-author` 與 Zotero 匯入過閘（#658）

#653 的 Expected 有兩半：逐格裁決閘不閘，以及把稽核擴成會抓到新的未閘寫入命令。`82de4255` 做了前半（只閘 `resolve-divergence`、`rename`、`migrate`、`migrate-provenance`），後半沒有做。舊稽核（`DestructiveTargetGateTests`）只認布林的 `--apply`／`--reject` 宣告：預設就寫的命令與逐 id 的寫入腿長出來時它不會紅。#653 R1 verify 另外指出兩個不閘的寫入腿同樣不可逆，裁決時沒有被點名。

## 裁決（使用者 2026-09-28）

- **`resolve-people --drop-author` 與 `import-zotero` 過閘。** 前者沒有具名逆操作：移除記錄留著被移除的字串，但不留位置（#457）。後者整份替換 `fields`、覆寫未歸戶的 literal 作者（`fieldsRemovedByPull`／`authorsOverwritten`），而且沒有乾跑。兩者寫到錯的 store 上，都要靠 git 收拾。
- **稽核改成一張封閉的裁決表**：CLI 的每一個葉命令一格，`resolve-people`／`resolve-venues`／`resolve-organizations` 的每一條腿再各一格。每一格是過閘、不閘（寫出這一格自己的理由）或不寫 store 三者之一。

## 改了什麼

**兩個新閘**（只擋 CLI；MCP 面不閘，理由同 `mcp-cli-parity` 橫切選項表的 `--yes` 列）：

- `import-zotero`：無條件閘。它沒有乾跑，也沒有寫入旗標可以不帶，所以拒絕訊息說「這個命令沒有 dry-run，也沒有只列候選的模式」。閘在 `openOrCreateStore` 之前——被擋的呼叫不得在錯的地方長出一個 store。命令的 abstract 補一句說明。
- `resolve-people --drop-author`：閘在參數組合檢查之後、開 store 之前（先報呼叫端的矛盾）。拒絕訊息點名 `resolve-people --drop-author`，說這個寫入沒有 dry-run。

**裁決表**：新檔 `Sources/akashic/WriteGateRulings.swift`。

- `WriteGateRuling` 四個值：`.gated`、`.notGated(理由)`、`.readOnly(說明)`、`.perLeg`（只用在命令層，表示逐腿裁決）。
- `commandRulings` 56 格：過閘 15、逐腿 3、不閘 18、不寫 20。與 #575 同批整合時補上 `repair-venue-names`（過閘：乾跑預設、`--apply` 才寫，同 `migrate` 族），成為 57 格、過閘 16——那個命令在本 change 之外寫成，由守衛在整合時指名。`legRulings`：`resolve-people` 14 條腿、`resolve-venues` 7 條、`resolve-organizations` 7 條（收窄條件與伴隨參數也各記一格，裁決為不自己寫入）。
- `DestructiveTargetGate.destructiveCommands` 改由表現算，不再手寫。
- `--yes` 的說明改由表產生。先前那一句手寫的清單在 #653、#572 各漂過一次。

**表寫下來時順手更正的兩處**：

- `migrate-venue-variants` 在舊的手寫清單裡列為過閘，卻從未呼叫閘。它的 `--apply` 自 #554 R15 起一律拒絕，裁決改為不寫 store。
- 測試裡的第二份手寫清單漏了 `migrate-identifiers`、`enrich`、`enrich-from-zotero`，所以「成員真的呼叫閘」對這三個從沒驗過。`DestructiveTargetGateTests.enumerated` 現在由表現算。

## 測試

`WriteGateRulingsTests` 8 支：

- 表與命令樹雙向相等。列舉走執行期的命令樹（ArgumentParser 的 dump-help，在 process 內呼叫），不做文字掃描。多一個命令、表裡留著已退場的名字，都會紅。
- 三個逐腿命令的每個 `@Option`／`@Flag`（`LibraryOptions` 的橫切選項除外）都有一格。
- 不閘與不寫的格，理由非空。
- `destructiveCommands` 由表現算，並含 #658 的兩格。
- 原始碼裡每一個閘的呼叫點都在過閘的集合裡，反之亦然。
- 逐腿的裁決對真 binary 成立。過閘的腿在未指名目標時被擋，拒絕訊息點名那條腿。不閘的腿不被擋，而且樣本要走過參數檢查（輸出不帶 `Usage:`）。在參數檢查就被擋下的樣本，證不到那條腿沒有閘。
- `import-zotero` 被擋時不建佈局；指名之後照常往下走。
- `--drop-author` 被擋時作者位不動；指名之後照常移除。

結果：`WriteGateRulingsTests`、`DestructiveTargetGateTests` 共 15 支，0 failures。`SanitizationBoundaryTests`、`PackageManifestTests` 全綠。

**負控兩組**，都以反向編輯還原，並用 `cmp` 對備份確認逐位元組相同：

1. 只改裁決表，六處：拿掉 `fmt`、加一個不存在的命令、`validate` 的說明改成空白、拿掉 `--rows`、`enrich` 改成不閘、`resolve-people --judge` 改成過閘。紅 8 則，分布在 6 支測試：命令樹比對 2 則、腿比對 1 則、理由非空 1 則、呼叫點 1 則、真 binary 2 則（缺樣本、`--judge` 沒被擋）、`DestructiveTargetGateTests` 的 `--apply` 稽核 1 則。
2. 改程式與測試樣本，三處：`--drop-author` 的閘改成不可達、`import-zotero` 的閘移到建佈局之後、`--judge` 的樣本加上一個會被參數檢查擋下的旗標。重建 binary 後，`WriteGateRulingsTests` 紅 3 支：`--drop-author` 那支、`import-zotero` 那支，以及真 binary 那支（`--drop-author` 沒被擋、`--judge` 樣本走不到閘）。`DestructiveTargetGateTests` 7 支全綠——文字掃描看不出這三種錯，只有真 binary 的測試看得出來。

## 規則與文件

- `mcp-cli-parity`：
  - 橫切選項表的 `--yes` 列補上 #658 的裁決，並寫明裁決表是 `destructiveCommands` 的來源。
  - `akashic_import_zotero` 列補上 CLI 的閘與面不對稱。
  - `--drop-author` 那段補一句 CLI 另過閘。
- `zero-instance-guards` 第 37 列、`各列共通的東西` 的 bullet，以及量測區塊：`swift test --filter WriteGateRulingsTests` 印出的 `WriteGateRulings：` 四行。
- `two-kinds-of-edits` 不動：閘不改變一個寫入面是 AI 編輯還是程式編輯。
- README 的閘那一段改寫：指向裁決表，不再列命令，也不寫個數。舊的那一段列了十個命令、寫「在 `--apply` 時」，MCP 不對稱的理由也是 #580 就已失效的那一句。
- `DestructiveTargetGate` 的 doc 改寫成指向裁決表。

## 誠實邊界

- **逐腿只做三個命令。** `update-venue`、`update-person`、`library` 也有多個寫入旗標，但以命令為單位裁決。它們新長一個寫入旗標時，這張表看不到。
- **理由是人寫的。** 測試只驗每一格都在、理由非空、過閘的格與閘的呼叫點一致、逐腿對真 binary 成立，驗不了理由對不對。裁決為不寫 store 的命令，測試只驗它不呼叫閘，不驗磁碟。
- **不閘的格不都可逆。** #653 的判準是「只閘不可逆的」，而「可逆」的界線沒有一句可機械判定的判準：`resolve-people --judge`／`--attribute-org` 沒有把作者位退回 literal 的工具面；`update-person` 提及的欄位整個替換；新增記錄沒有刪除面。各格的理由只寫出自己的事實，不宣稱可逆。界線待裁。
- **`dismiss-divergence` 不閘的理由在 #298 的事故形狀下不完全成立。** 它的理由是「以 UUID 定位，指錯 store 只會找不到那筆記錄」。但歧異記錄的 UUID 由候選 key 決定（`DeterministicUUID.forDivergence`），真 store 的副本裡同一筆記錄有同一個 UUID。它刪除前要求記錄檔已 commit，所以誤刪仍救得回來。本輪照 #586 的裁決不閘，只記在這裡。
- **`akashic --experimental-dump-help` 不能用來重算這張表。** CLI 頂層對輸出逐行截 400 字元、總行數截 200 行：2026-09-28 實測 dump-help 7,062 行被截成 200 行，zsh 補全腳本 1,083 行被截成 200 行。這是既有行為，不是本輪造成的。`--yes` 的說明變長後，它在 dump-help 裡也是一行超過 400 字元的字串。
