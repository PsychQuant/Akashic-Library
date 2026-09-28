# 2026-09-27 掛錯刊的 ISSN 拿得掉了，也看得見（#588）

ISSN 的 mod-11 檢查碼擋得住亂碼，擋不住**合法但屬於姊妹刊的號**。JRSS-A、B、C 在模糊搜尋下都會命中，而 #556 起 `akashic-verify-venue` 會把查到的 ISSN 寫進 venue。在此之前兩件事都做不到：

- 看出一個號掛在兩本刊上：沒有任何檢查。
- 把掛錯的號拿掉：`add_issn` 只能加；唯一的路是手改 YAML。

## 改了什麼

**移除面，兩面同契約**：CLI `update-venue --remove-issn <issn>=理由`，MCP `akashic_update_venue` 的 `remove_issn`，同走 `updateVenue`。

- 理由必填，只進報告（`issnRemoved`），不寫進 store。這是使用者 2026-09-27 對三個移除面（#572／#586／#588）的裁決（原話「只進報告與 git 歷史」）。git 保存的是**移除前的檔**；理由要留在 git，得由操作者寫進後續的 commit message，工具不代寫——R1 verify 指出這一行初稿寫成「理由進 git 歷史」是過度宣稱。
- 被移除的號（以及 R1 起一併刪除的 `field: issn` provenance）只剩 git 裡移除前的那一份副本，所以移除前要求那筆 venue 檔已 commit、沒有未提交修改；理由不在那份副本裡（見上一條）。這道閘沿用 #573 的 `assertRetiredVerdictsRecoverable`，一般化成 `assertRecordsRecoverable`（#573 的呼叫改為呼叫它，行為不變）。
- 整批拒絕、零寫入的情形：缺 `=`、號不合法、理由空白或超過 4,096 位元組、同一個號在一次呼叫裡重複、這本刊沒有這個號、同一個號同時在 `add_issn` 與 `remove_issn`。
- 逆操作是 `--add-issn` 加回來。

**守衛**：`validate` 對同一個 ISSN 掛在 2 個以上 venue 報 warning（`crossRecordIssues`，以正規形比對，與 `add_issn` 的去重同一條規則）。訊息兩個出口都說：其中一筆記成了姊妹刊的號，就用 `--remove-issn`；兩筆是同一本刊，就用 record-divergence 記下、resolve-divergence 合併。

## 裁決

`zero-instance-guards` 加第 36 列。2026-09-27 實測 live store：venue 485 筆、ISSN 值 59 個、distinct 59、掛在 2 個以上 venue 的 0 個。

`two-kinds-of-edits` 加一列：移除是判定（號本身合法，錯的是它屬於哪本刊）。store 內「留 verdict」這一格有記錄地不兌現，兌現它的是 git。

`mcp-cli-parity` 的 `akashic_update_venue` 列補上兩面契約。

## 測試

`ISSNRemovalTests`：

- 移除並回報理由、其餘的號保留、理由不進 store；
- venue 檔有未提交修改時整批拒絕、零寫入；
- 六種輸入錯整批拒絕；
- 同一個 ISSN 掛在兩本刊上是 warning，兩個 key 都點名；只有一本刊的號不報。

負控三組：

1. 拿掉 git 副本的閘：紅。
2. 重號門檻改成 99：紅。
3. 拿掉「同時加與移除」的檢查：紅。

真 binary 驗證：用 scratch store（有 git）走完整流程。`validate` 印出重號 warning；檔案未 commit 時移除被拒、錯誤訊息點名原因；commit 之後移除成功，`issnRemoved` 帶理由，store 裡查不到理由字串；再跑 `validate`，warning 消失。

## 附帶

同一輪 push 被 `SanitizationBoundaryTests` 擋下。原因是 #647 兩處的豁免註記沒有寫出插值的第一個識別字（`Self`），補上後以獨立 commit 修掉。本輪新寫的註記依同一條規則寫。
