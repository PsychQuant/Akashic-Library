## 1. 載體與驗證（provenance-reference 修改）

- [ ] 1.1 實作 spec「A reference SHALL be attachable to a named field」的 verdict 例外（design D1——verdict 住 field、不住 statement 文法）：Provenance.swift 的 `validateReferenceAttachment()`（person 與 organization 兩處）各加封閉 case `resolution-confirmed`／`resolution-rejected`——合法、value 必填（缺 value 拒收，訊息說明「verdict 沒有配對即無錨」）、不做集合成員檢查。驗證：`testVerdictFieldsAcceptedWithValue`、`testVerdictFieldWithoutValueRejected`（兩型別各一組）紅→綠；既有 validateReferenceAttachment 測試全綠不動。
- [ ] 1.2 實作 spec「A resolution verdict SHALL be recorded as a provenance reference on the judged record」的 round-trip 半邊：帶兩種 verdict reference 的 person／organization 經 encode→decode→encode 位元組穩定、store format 標記不變（`testVerdictReferencesRoundTripByteStable`）。

## 2. ResolutionLedger（design D4——唯一的讀寫封裝點）

- [ ] 2.1 新增 Sources/AkashicEntity/ResolutionLedger.swift：`Pairing`（citekey/literal/recordKey）、`Verdict`、`record(verdict:pairing:rule:statement:) -> ProvenanceReference`——value 依 design D2 編碼 `<citekey> :: <literal>`、statement 依 design D3 帶尾註 `[rule: <name>]`；`verdicts(references:)` tolerant 解析（尾註缺席計入 author-name-exact；value 以第一個 ` :: ` 切分；解析失敗 loud 回報 malformed 不靜默）。這同時是 spec「A resolution verdict SHALL be recorded as a provenance reference on the judged record」的產生端。驗證：ResolutionLedgerTests——encode/decode 對稱、含空白與冒號的 literal round-trip、malformed 回報（紅→綠）。
- [ ] 2.2 實作 spec「Calibration counts SHALL be derived, never stored」與 spec「Rejection SHALL be distinct from absence」：`rejectedPairings(people:)` 與 `counts(...)`（per rule 三態；pending＝現有候選中無 verdict 者——「還沒查」與「查過了不是他」由 verdict 存在與否區分）。驗證：計數測試——加一筆 verdict 後重算即反映、全樹無任何 stored counter；三態區分測試（rejected 配對 vs 無 verdict 配對）。

## 3. Resolver 跳過（design D5——只跳同配對；兩族 family-wide）

- [ ] 3.1 實作 spec「The resolver SHALL NOT re-propose a rejected pairing」於 person 族：PersonResolver.resolve 增收 rejected pairings（呼叫端傳入，resolver 保持純函式），候選生成排除**恰為**該 (citekey, literal, personKey) 三元組；同 literal 他 entry 照提。驗證：`testRejectedPairingIsNotReproposed`、`testRejectionDoesNotBanLiteralGlobally`（紅→綠）。
- [ ] 3.2 spec「The resolver SHALL NOT re-propose a rejected pairing」的 organization 族：OrgResolver 同語意、同兩個測試（#44 教訓——family 一次涵蓋，不留 sibling）。

## 4. Service 面（design D6 reject 顯式動作 + design D7 呈現形狀）

- [ ] 4.1 實作 spec「A verdict SHALL require explicit human invocation」：`AkashicService.resolvePeople(apply:reject:)`——reject 收 rowID 陣列（複合鍵同 apply），寫 `resolution-rejected` reference 到候選 person（經既有 writePerson 閘）；apply 同動作內寫 `resolution-confirmed`（design D6 對稱）；無任何自動 verdict 路徑。驗證：MCP 面測試——reject 後重跑 resolve 該候選消失、person YAML 出現 verdict reference；apply 後 person 帶 confirmed reference；無 rowID 不發生任何寫入。
- [ ] 4.2 實作 spec「Presentation SHALL use counts, order without hiding, and keep pending visible」（design D7）：resolvePeople 回應候選增 `counts{confirmed,rejected,pending}` 與已否決標記、已否決沉底排序不隱藏、頂層 `pendingTotal`；**形狀上不存在比率欄位**。payload 三軸上限沿 #236 慣例。驗證：回應形狀測試（含「無任何 ratio/percentage 鍵」斷言）+ 排序測試。
- [ ] 4.3 CLI `resolve-people` 增 `--reject <rowID>`（可多值）與三態計數渲染；`resolve-organizations` 同資訊形（org 族 reject 經其既有路徑寫 organization verdict reference）——兩面與 service 同一實作路徑（mcp-cli-parity）。驗證：CLITestHarness 測試——reject 經真 binary 落 YAML、人可讀輸出含三態計數。
- [ ] 4.4 Server.swift `akashic_resolve_people` schema 增 `reject` 參數、description 同步（含「計數不報比率」語意）。驗證：MCP schema 測試（payload-key coverage 守衛慣例）。

## 5. 收尾

- [ ] 5.1 全套件綠（swift test）；`spectra validate resolution-judgement-ledger` 通過。
- [ ] 5.2 docs/store-format.md 的 provenance 節補 verdict 欄位對一段（封閉對、value 慣例 design D2、舊 binary quarantine 降級的明記——design Migration Plan）。
