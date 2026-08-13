## Context

消解判定要在零 format bump 的約束下持久化（#247 擋住任何新序列化形狀），並讓「校準」成為衍生值（#221：存哪一側的判準——判定是關於配對的事實，計數是判定的集合，存計數即第二份 canonical state）。載體選既有 `ProvenanceReference` 是 discuss 定案；本文件記載其餘結構決定與邊界。

## Goals / Non-Goals

**In scope**
- verdict 欄位對的驗證規則（Provenance.swift 封閉表擴充）與 value 編碼慣例
- `ResolutionLedger` 的介面與深度（讀寫兩端的唯一封裝點）
- resolver 跳過語意、reject/apply 的寫入路徑、resolve 面的回應形狀
- person 與 organization 兩族（同 ledger；#44 教訓：family-wide 一次涵蓋）

**Out of scope**
- 比率／貝氏合成／自動降權；來源×類別粒度；person 檢視與 doctor 呈現；org 的 MCP 工具；任何 store format 變更（proposal Non-Goals 為準）

## Decisions

### D1

**verdict 住 `field`，不住 statement 文法。**

`resolution-confirmed`／`resolution-rejected` 是**封閉欄位對**（僅此二值，不得類推第三個）。放 field 而非 statement 前綴的理由：statement 內嵌文法是會漂移的散文（common-spec-prose-enumeration 的失敗形狀）；field 是既有的結構槽，計數只需 switch 兩個 case。

### D2

**value 編碼配對：`<kind>:<key> :: <literal>`（verify 修訂——kind token 必填、兩族統一）。**

判定的對象是「literal 所在記錄的某個 literal ↔ 被判定的 person/org」配對。value slot 承載單一文法 `<kind>:<key> :: <literal>`，kind ∈ `work`（entry citekey，person 族）／`person`／`org`（org 族的 literal 持有者）。原設計（`<citekey> :: <literal>`，無 kind）在 verify 被推翻兩處：(a) person 與 org 的 key 可合法同名（#166），無 kind 時一筆 org 側否決會連帶抑制同名 person 的配對（C-3/S-3 實測）；(b) 兩族兩套文法靠「掛在哪種記錄」的脈絡區辨，是 D3 自認過的 grammar-in-string 漂移再開一個（DA (b)）。分隔一律取第一個 ` :: `、holder token 取第一個 `:`；key 是 StoreKey 字元集（無空白無冒號），literal 任意可 round-trip。解析器住 `ProvenanceReference.VerdictPairingValue`（AkashicCore）——store 閘與 `ResolutionLedger` 共用同一個實作。

### D3

**證據類別記在 statement 尾註 `[rule: <name>]`。**

今日恰一類 `author-name-exact`。tolerant parse：尾註缺席時計入 `author-name-exact`（今日唯一合法值）。這是 v1 的妥協——typed slot 需要序列化變更，被 #247 擋住；格式解封後遷移為 typed 欄位（明記於 spec 的 Residue）。

### D4

**`ResolutionLedger` 是唯一的讀寫封裝點。**

```
ResolutionLedger（AkashicEntity）
  ├─ record(verdict:pairing:rule:statement:) → ProvenanceReference   ← 寫端唯一產生器
  ├─ verdicts(for: Person|Organization) → [Verdict]                  ← 讀端唯一解析器
  ├─ rejectedPairings(people:) → Set<Pairing>                        ← resolver 消費
  └─ counts(people:candidates:) → 三態計數（per rule）                ← 呈現面消費
```

深度：value 編碼、field 對、rule 尾註的 encode/decode 全部藏在這裡；resolver 與 service 只見型別。刪除測試：沒有它 → 重複提名回歸 + 計數無來源 + 慣例散落三處。

### D5

**跳過語意：只跳「同配對」，不跳「同 literal」。**

resolver 排除的是**被否決的 (citekey, literal, personKey) 三元組**——同 literal 在另一個 entry 上仍會被提名（那是另一次觀察）。過寬的跳過會把一次否決放大成全庫封殺，重演「自我強化迴圈」。

### D6

**reject 是顯式人為動作，與 apply 對稱。**

`resolvePeople(apply:reject:)`：reject 收 rowID 陣列（複合鍵同 apply，#236 R4 慣例）。reject 寫 `resolution-rejected` reference 到該候選 person；apply 在改寫 entry 的同一動作內寫 `resolution-confirmed`。兩者都經 `writePerson`（既有寫入閘）。無任何自動 reject 路徑。**apply 與 reject 不可同一次呼叫**（verify A，4/4 席 + DA 確認）：兩腿寫同一批 person 檔，曾以 stale 快照互相蓋寫——reject 剛寫的 verdict 被 confirm 的整檔改寫抹掉、回應照樣宣稱成功；組合語意需要按腿回報部分失敗的回應形狀，是它自己的設計題，v1 禁止。rowID 去重（保序）＋ `appendIfAbsent` 寫入邊界冪等——store 永不持有重複 verdict，計數就能誠實地數原始 refs（DA (d)）。

### D7

**呈現形狀（verify 修訂——已否決獨立成段）。**

候選物件增 `counts: {confirmed, rejected, pending}`（該候選所屬 rule 的計數）。已否決配對**獨立為頂層 `rejected` 陣列**（排在 candidates 之後閱讀；帶 `verdict: "rejected"`、無 id）——原設計「沉底附在 candidates 內」在 verify 被推翻：列數超過文件宣稱的上限（實測 317 列）、`candidateTotal` 小於陣列長度、沉底列缺 id/reason 使消費端無條件讀取即炸（C-7/S-7/REG-6），且共用預算讓「記載人類決定的那段」最先被擠掉（DA (c)）。獨立段有自己的 50 列上限、48 KB 預算、`rejectedTotal` 與 `rejectedRowsDropped`。頂層 `pendingTotal`（未處理量可見——censoring 不可隱藏）；`verdictMalformed` 僅在偵測到解析不了的 verdict 時出現。**無比率欄位**——形狀上就不給。

### D8

**verdict 的 judgement 允許空 restsOn（僅限封閉欄位對）。** 實作揭露的修正：既有規則「judgement SHALL name digests」在 init 層強制非空，但 verdict 是**一階人為裁決**——「查過了，不是他」常沒有可指的 store 內 digest（看的是外部 PDF／記憶）。強制附 digest 會讓 reject 不可用，分母問題原地復發。例外綁同一封閉欄位對、有證據時 SHOULD 附。

## Risks / Trade-offs

- **statement 尾註是文法-in-string**（D3 自認）：以封閉值域（今日一值）+ tolerant 預設 + 測試釘住；風險上限是計數歸錯類，不是資料損失。
- **value 分隔符碰撞**：literal 含 ` :: ` 時 round-trip 破——decode 以「第一個 ` :: 」切分 + 測試涵蓋含空白/冒號的 literal；碰撞真發生時 verdict 定位失敗 → 該筆進 ledger 的 malformed 回報（loud），不靜默錯配。
- **references 增長**：每次判定一筆 reference，長期累積。可接受——判定史正是本 change 的目的；未見上限需求（doctor 的 payload 上限既有機制涵蓋）。

## Migration Plan

無資料遷移（新欄位對只出現在新寫入的 references；既有記錄不動）。程式遷移：`validateReferenceAttachment` 兩個封閉表各加一個 case。

**（verify 修訂——原「可接受的 quarantine 降級」被推翻，NEW-2/NEW-3）**：原設計主張「不 bump format，舊 binary quarantine 該筆是 loud 且可接受」。verify 實測整條毀損鏈推翻了它：舊 binary quarantine 整筆 person → 該記錄不在 load.people → 例行 `bootstrap-people --apply` 對同 key 提名 → 決定性 UUID 落同檔名 → **安靜覆寫、判定史全滅、exit ✓**。且 `docs/store-format.md` §5.0 對同型情況（v6 `ended`）已有 normative 裁決：「refuse-if-newer 的一句『請升級』遠比 per-file quarantine 誠實」。修法照 v6/v7 既有 gate 範式：**format 8** + `writePerson`／`writeOrganization` 對 format < 8 拒寫含 verdict 的記錄（拒絕而非自動 bump、訊息指路）；bootstrap 對既有目的檔一律跳過並報告（覆寫防護獨立成立）；`rename` 遷移 `work:` verdict value（NEW-1——外鍵完整性）。實際 bump 真實 store 的 marker 走 #247 的程序（先同步 distribution）。這不與「無新序列化形狀」矛盾——8 只是「此 store 可持有 verdict」的宣告。

## Open Questions

(none——決策點已於 discuss 與本文件收斂；殘餘的「格式解封後遷移 typed rule slot」記在 spec Residue)
