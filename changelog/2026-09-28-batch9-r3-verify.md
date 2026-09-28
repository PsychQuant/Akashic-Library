# 2026-09-28 #569／#647 的 R3 verify 修正

R3 只審 R2 的修正 commit（`15fd2ba7`），六席回報 28 條：1 HIGH、4 MEDIUM，其餘 LOW／INFO。

## #647 否決比對的正規化（HIGH，DA 真 binary；logic 另一席同指）

organization 族的否決抑制原本以 `ResolutionPairing` 的合成 `Hashable` 比原始 literal，出現在三處：person 隸屬、上級機構、work 團體作者位。R2 為 judge 腿新加的略過也照抄了這種比法。合成 `Hashable` 只折 canonical equivalence，不折大小寫、空白、連字號家族、Cf。DA 的重現全程走工具，每一步都是合法操作：

1. 一筆 work 的作者位是 `{Sinica}` 與 `{SINICA}`。
2. `--reject` 寫入時以正規化鍵去重，只留下一筆 rejected。
3. `{SINICA}` 照樣被提名。
4. `--apply` 或 `--judge` 寫下 confirmed。
5. `validate` 報出矛盾對。

person 側的 `rejectedNorm`（R1-fix I1）與 venue 側（R12）早就以 `matchingKey` 比對，org 族是唯一的例外。現在 `OrgResolver.normalizedRejection` 把 literal 換成 `matchingKey`，三處抑制與 judge 腿的略過都用它，與矛盾掃描的 `verdictPairingKey` 同一套正規化。

這個缺陷早於本批（#304／#643 就有），R2 把它照抄進新的略過，所以一併修。

## #569 文件出口分成兩個集合（MEDIUM，security）

R2 扣掉 Zs、SHY、私用區的理由是「下游是 TeX／XML，`U+XXXX` 標記解不回來」。這個前提只對**檔案與終端**的出口成立。`documentSafe` 同時是 MCP `akashic_export`（bib）與 `akashic_graph` 的消毒，而它們回到 LLM context：LLM 讀得懂 `U+00AD`，SHY 與補充私用區在那裡卻是零寬或不渲染的隱藏通道。

現在分成兩個出口：
- `documentSafe(_:forLLM:)` 在 MCP 的兩個出口傳 `true`，改用 `escapesInLLMDocument`，也就是人可讀輸出的集合加上 noncharacter；
- CLI `export-bib`／`graph` 的 stdout 維持 `escapesInDocument`。

R2 把 R1 那支測試的 SHY 斷言翻成「保留」，當時就把這條路打開了；現在翻回「逃脫」，檔案出口的保留由 CLI 那支釘住。

## #569 變體選擇子在檔案出口保留（MEDIUM，regression）

VS1–16、VS17–256（含 CJK IVS 與蒙古文 FVS）是字形選擇，也是造字的標準化後繼。R2 扣掉了私用區卻不扣它們，說不通；現在 `escapesInDocument` 也扣掉它們。DA 量過：live store 沒有任何變體選擇子。

## 文件

- CLI `--judge` 的 help 補上 `verdictNotRecorded`、略過否決、整批先驗。R2 只改了 MCP 描述，兩面曾經分岔。
- `mcp-cli-parity` 的 resolve-organizations 列補上否決略過、`verdictNotRecorded` 與整批先驗。
- `escapingInvisibleScalars` 的 doc 補完（R2 只改了一半，仍寫 BRAILLE PATTERN BLANK）。
- `rendersBlank` 的 doc 裡「命中約 90 個」改成重量後的 82。
- README 的消毒器表寫明 MCP 出口用 `forLLM: true`、檔案出口扣掉哪幾類，以及 noncharacter 的加項。
- noncharacter 的註解更正：XML 1.0 只排除 U+FFFE／U+FFFF；其餘 noncharacter 是依 Unicode「不得交換」一併逃脫。
- R2 changelog 的字元計數把全庫合計寫成只在 work 裡：work 內是 NBSP ×6、SHY ×3，另外 3 筆 person 帶 NBSP ×6、SHY ×2。

## 測試

- 新增 `OrgJudgeLegTests.testRejectionSuppressesCaseVariantsOfTheSameLiteral`。
- `testDocumentExitsKeepTypographicContentAndStayValidXML` 改成斷言 MCP 出口會逃脫。
- CLI 那支改成釘住 IVS 與私用區逐位元組保留。
- `testDestinationChecksRunBeforeAnyWrite` 釘住拒絕來自目的檔檢查，不再接受任意 throw。

負控三組（否決比對改回原始 literal、MCP 出口改回檔案集合、拿掉變體選擇子的豁免）全紅。

## 記錄、不改

- `--reject` 對同一配對的兩個拼法報「否決 2 筆」，實際只寫一筆（寫入以正規化鍵去重）。報告的計數與寫入不一致，但沒有資料錯誤。
- `issnRemoved` 對一併刪除的 provenance 只給筆數，不逐筆列出內容。git 的移除前副本有全文。
- mermaid 的節點 id 可能帶 `U+XXXX` 標記（含 `+`，R1 起；security 席 LOW）。本輪沒有驗證它對 mermaid 解析的影響，記在這裡。
