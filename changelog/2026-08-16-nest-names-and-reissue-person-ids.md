# nest-names-and-reissue-person-ids（#227 + #241，store format 10）

Branch `idd/227-241-nest-names-reissue-ids`。單一 Spectra change 合併兩個 issue
（使用者 2026-08-12 裁決：同一批 867 筆記錄、一次不可逆遷移、一次 format bump）。

## #227 — names 巢狀化

- 新型別 `PersonNames`：`authorized`／`variant` 兩個分割，聯集 `all` 為 computed。
  「authorized ⊆ 全部名字」由結構承擔；執行期只剩兩條**內容**約束（每書寫系統
  至多一個、兩分割互斥——後者為 verify R1 補）。
- YAML codec 走巢狀形狀；平坦 `names` 陣列與舊頂層 `authorized` 一律 fail-closed
  指路遷移（舊形狀只能經遷移，decoder 不順便相容）。
- `writePerson` 對 format < 10 拒寫含 names 的 person（`invalidInput` 訊息形）。
- MCP `akashic_update_person` 的 `names` 改收 `{authorized, variant}` object。
- Organization 刻意**不**巢狀化（names 是時間軸）；其子集檢查留在執行期。

## #241 — id 獨立 v4 + 一次性遷移

- `Person.init` 預設 `UUID()`（單一產生事件）；decode 對缺 `id:` fail-closed；
  `DeterministicUUID.forPerson` 退場（零生產呼叫端）。
- `migrate-person-identity`（預設 dry-run）：涵蓋封閉列舉見
  `docs/store-format.md` v10 列——entities 裸標籤／format-2 `type: person`／
  legacy `people/` 就地遷移／缺 id 補發（先補再試 decoder）／簡單 flow-style。
  key 級收斂（同 key 殘留點名交人、永不發第三個 id）、per-file git 追蹤前置、
  error 級記錄不落盤。
- key 配發後永不重算（由結構滿足、測試釘住；撞名後綴不帶判斷權重）。

## 驗證

6-AI cluster verify 四輪（R1: 4×opus lens + DA；R2–R4: sonnet + Codex
gpt-5.6-sol）；1707 tests；mutation 12/12；真 store 複本演練 867/867 冪等。
R3/R4 補強：盲區 key 裁決（解不開的檔參與收斂、取不到 key 即保守抑制全部
重發）、byte-exact 檔案身分（NFC/NFD 雙生）、目錄列舉誠實、keeper 交叉點名、
next-step 以零失敗為唯一判準、name 查找面的 quarantine 可見性、
migrate CLI 回顯目標 store（防 registry 解析誤傷——2026-08-16 事故的即時緩解）。
Follow-ups：#294–#297、#298（LibraryLocator CWD 零感知 + 破壞性 apply 無確認）。
