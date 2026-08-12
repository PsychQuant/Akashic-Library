## Why

完工稽核發現三個會讓機械驗證假綠的邊界：digest 正確但只含部分可解析 heading 的 inline snapshot，在零 corpus volume 的 construction mode 不會失敗；`history.kind: branch` 只檢查字元格式，不確認 Git ref 是否存在；不同的純英文 filler 也能冒充兩個臺灣正體中文欄位。初步修正後的獨立審查又確認，序言與正文的全域順序可能被 parser 正規化、任意 commit-ish 可能冒充 branch、粗略碼位範圍也可能漏收真正漢字或納入未指派 scalar。這使來源完整性、逐句中文內容與跨 branch 脈絡無法由目前的綠燈直接證明。

## What Changes

- inline snapshot 的結構解析結果必須依 heading 在原始 snapshot 的全域位置，與 manifest inventory 驗證完整、唯一且順序一致，即使 construction mode 尚未載入任何 corpus volume。
- 部分可解析、缺項、重複或順序錯置的 snapshot 必須 fail-closed，並產生可定位的 `source-mismatch`。
- branch history reference 必須在本機 Git object database 中解析為 `refs/heads/` 或 `refs/remotes/` 下的真實 branch；僅有合法字元的 SHA、tag、`HEAD` 或不存在名稱都必須回報 `unknown-branch`。
- `translation_zh_tw` 與 `interpretation_zh_tw` 必須各自包含已指派的 Unicode 漢字內容；不同的英文 filler 或未指派碼位不得只因非空且彼此不相同就冒充臺灣正體中文工作譯文與解讀。
- 新增針對上述假綠路徑的 red-green regression tests；保持正式 snapshots 與 source assets bytes 不變，只把正式 corpus 中 `5.101.l`、`5.101.m` 的公式型工作譯文補成含漢字的最小中文表述，並決定性重產 generated Markdown。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `tractatus-project-map`: 強化來源結構完整性與歷史 branch evidence 的 fail-closed 契約。

## Impact

- Affected specs: `openspec/specs/tractatus-project-map/spec.md`
- Affected code:
  - Modified: `Sources/TractatusDocs/SourceManifest.swift`
  - Modified: `Sources/TractatusDocs/Validation.swift`
  - Modified: `Tests/TractatusDocsTests/SourceManifestTests.swift`
  - Modified: `Tests/TractatusDocsTests/CorpusValidationTests.swift`
  - Modified: `docs/tractatus/corpus/5.yaml`
  - Modified: `docs/tractatus/generated/tractatus-project-map.md`
  - Modified: `openspec/specs/tractatus-project-map/spec.md`
  - New: `openspec/changes/close-tractatus-validation-audit-gaps/specs/tractatus-project-map/spec.md`
