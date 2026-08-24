## Context

store 對識別碼有三種並存待遇，且沒有任何一次裁決記錄說明為何不同：`Person` 的 `orcid` 與 `openalex` 是頂層具名欄位並登記在 `ProvenanceReference` 的欄位白名單裡；work 的 `doi`／`pmid`／`isbn`／`issn` 住在自由字典 `Entry.fields`；`Venue` 與 `Organization` 兩個型別完全沒有識別碼欄位。

全庫實測（937 筆 work、867 筆 person、402 筆 venue、8 筆 organization）：`fields` 內的識別碼是 4 種、825 個出現（`doi` 665、`pmid` 65、`issn` 64、`isbn` 31）；其中 64 筆 `issn` 全部帶在 work 上，而它識別的是 venue，那 64 筆對應的 venue 邊 **64/64 皆已歸戶**。39 個受影響的 venue 裡有 8 個會收到多於一個相異的 ISSN 字串，內容混了三類：真的兩個號（print 與 electronic）、同一個號的不同寫法、以及值本身錯誤（check digit 小寫）。

兩個現存約束限定了解法空間：

- `docs/store-format.md` 的 tolerant-preserve 開放演化層**只涵蓋記錄頂層與 `akashic` namespace**。時間軸段內與 `references` 元素內的鍵是 strict——舊 binary 讀到未知鍵是整檔 quarantine。format 6／7／8 三次升版全出自這個邊界。
- `ProvenanceReference` 的欄位白名單對純量欄位與清單欄位走**不同驗證分支**：純量欄位的 reference 不得攜帶 `value`；清單欄位（`names`）必須攜帶 `value` 指名支持哪一個值，且該值不在清單內時整筆記錄拒讀。

`docs/tractatus/` 的 3.325 工程類比（好的記法讓錯誤在其中寫不出來）與本設計同向：讓 `0003-066x` 這種值**在型別上寫不出來**，而不是寫得出來再靠檢查抓。

## Goals / Non-Goals

**Goals:**

- 識別碼成為跨四種實體的一等公民類別，落位、型別、基數、正規化時機四者各有顯式裁決。
- 識別碼能攜帶來源（provenance），與 `Person.orcid` 現有的待遇一致。
- `.claude/rules/identity-is-judged-not-matched.md` 取得明文例外，使「用 DOI 判定同一筆」不再與該規則衝突。
- ISSN 移位到它所識別的 venue，且遷移不丟失任何既有值。

**Non-Goals:**

- **不**引入泛型 `identifiers: [String: String]` 容器。那會複製 `Entry.fields` 的病——有值而無型別，正是本 change 要治的東西。
- **不**為識別碼引入時間軸（期刊改名換 ISSN 的歷史）。時間軸段內的鍵是 strict 層，而目前零實例支撐該需求；出現實例時另行裁決。
- **不**驗證識別碼指向的外部記錄是否存在（不打 API、不解析 DOI）。本 change 只管形狀與正規化。
- **不**處理 `url`（281 筆）。它是 locator 而非註冊指派，明確排除。
- **不**改變 `Entry.fields` 內其餘 34 個鍵的待遇。它們是正牌 biblatex 欄位，本來就該住自由字典。

## Decisions

### 識別碼放記錄頂層的具名欄位，不做泛型容器

`Venue` 取得 `issn`、`Organization` 取得 `ror`、`Entry` 取得 `doi`／`pmid`／`isbn`，皆為記錄頂層的具名欄位，形狀比照現有的 `Person.orcid`。

**替代方案：泛型 `identifiers` 字典。** 否決——它把「哪些種類合法」變成執行期問題，且對值不做任何主張，等於在頂層再造一個 `Entry.fields`。本 change 的動機正是那個字典驗不出 `0003-066x`。

**替代方案：識別碼獨立成一個 entity 種類。** 否決——識別碼不會被別的東西引用，也沒有自己的屬性；把它實體化成第三個東西正是 `entity-backlink-completeness` 記載的「把關係實體化成第三項」反模式。

### 識別碼欄位的型別是帶驗證的 value type，不是可選字串

每種識別碼是一個具名 struct（`ISSN`／`DOI`／`PMID`／`ISBN`／`ORCID`／`ROR`），住在新檔 `Sources/AkashicCore/Identifier.swift`。建構器是 throwing 或 failable，驗形狀並正規化。

**判準是介面深度**：若欄位型別是 `String?`，這個抽象什麼行為都沒藏，刪掉它今天不會壞任何東西——那樣的 seam 不該存在，而本 change 也就退化成「把字串從一個容器搬到另一個」。實測的 `0003-066x`（check digit 小寫）與 `1467-8624(Electronic),0009-3920(Print)`（一欄兩號）正是「有值無型別」的直接產物。

**替代方案：單一泛型 `Identifier<Kind>`。** 否決——各種識別碼的驗證規則差異大（ISSN 有 mod-11 check digit、DOI 只有前綴形狀、ORCID 有四段結構），泛型參數化後每個 case 仍要各自的驗證函式，抽象沒有換到共用。

**型別同時持有 `raw` 與 `normalized`（2026-08-24 補，實作時發現）。** 初版只留
`normalized`，於是「讀取面原樣保留」在**結構上做不到**——decode `0003-066x` 得到的
物件已經是 `0003-066X`，值在讀取當下就被改寫了。那正是下一條裁決要避免的事，而它與
本條裁決在字面上互不矛盾，所以初版沒有人看出衝突。

實測（以真的建構器當 oracle，非 regex 代理）：store 內 **43 個非正規值**落在這一格
——issn 10、isbn 18、doi 15。

分工逐字取自 task 4.1 的驗證目標：**讀取→`raw`、寫入→`normalized`**。
**相等由 `normalized` 決定**，不由 `raw`——否則遷移的去重（§8.2「先正規化再去重」）
永遠去不掉異寫法。這一條必須顯式寫在 protocol extension：加了 `raw` 之後 Swift 合成的
逐欄位 `==` 會把 `0003-066x` 與 `0003-066X` 判成兩個不同的識別碼（負控實測：移除自訂
`==` → 4 個斷言紅）。

### 基數逐種決定，且基數決定 provenance 走哪條驗證分支

`ORCID` 與 `ROR` 是純量（每人／每機構一個）；`ISSN`、`DOI`、`PMID`、`ISBN` 是清單。

這不是風格選擇：`ProvenanceReference` 對純量欄位要求 reference **不得**帶 `value`，對清單欄位要求**必須**帶 `value`。宣告錯邊會落到錯的驗證分支。實測支撐：print 與 electronic 是兩個真的 ISSN；37 組 work 同題同年但 DOI 不同；同一筆生醫論文同時有 DOI 與 PMID 是常態。

**替代方案：一律純量。** 否決——print/electronic 只能留一個，違反 `.claude/rules/lossless-intake.md`。

**替代方案：一律清單。** 否決——`Person.orcid` 既有的純量 provenance 路徑要改，那是對既有記錄的破壞性變更，且 ORCID 在定義上每人一個。

### 識別碼進 provenance 欄位白名單，store format 自 12 升至 13

識別碼欄位加入 `ProvenanceReference` 的欄位白名單，使它們能攜帶來源。該白名單是 store 格式的 strict 層，故本變更是 non-additive：舊 binary 讀到未知的 `field` 值是整檔 quarantine。format 自 12 升至 13。

**這是本 change 唯一的 bump 觸發點。** 頂層新增欄位本身是 additive（tolerant-preserve 覆蓋記錄頂層），若不進白名單則不需要升版——但那樣識別碼就只是「放在頂層的字串」，無法記錄它從哪裡來，不符合本 change 對「一等公民」的定義。使用者已裁定識別碼必須能記來源。

### 正規化只在寫入面發生，讀取面寬容保留既有值

寫入路徑一律正規化（大小寫、分隔符、去除括號標註）；讀取路徑接受非正規形並原樣保留，不因格式不合而拒讀。

**替代方案：讀取時正規化。** 否決——provenance reference 的 `value` 必須落在該欄位的現值清單內，讀取時改寫值會讓既有 reference 變成孤兒，於是整筆記錄拒讀。用整檔 quarantine 去修一個大小寫，代價不成比例。

**替代方案：讀取時拒讀非正規值（fail-closed）。** 否決——先有雞先有蛋：嚴格解碼器上線前跑不了遷移，遷移沒跑完不能上線嚴格解碼器。

**這不違反 `.claude/rules/no-compat-fallback.md`**：讀取面接受非正規形不是第二條讀法——正規化只在寫入面發生，遷移完成後 store 內只存在一種形式。這是「輸入寬容」而非「兩條讀法」。

### identity-is-judged-not-matched 的例外條款具名到六種識別碼

在該規則新增一節，明列 DOI／PMID／ISBN／ISSN／ORCID／ROR 六種識別碼的相等比對**可**單獨做出身分判定，並明寫「封閉列舉，不得依性質相似類推」。同節說明識別碼終結**指涉**但不終結**描述**（附帶欄位仍可能有誤）。

**替代方案：寫成性質判準（「凡註冊機構指派的識別碼」）。** 否決——該規則自身的失敗史就是總括判準在邊界上長出沒人同意的答案；全域 `common-spec-prose-enumeration` 明令能列舉的就列舉。寫成性質會讓下一個人把 `url`、`zotero_key`、`library_id` 推導進來。

## Implementation Contract

**Behavior（可觀察的結果）**

- `akashic venue <key>` 對帶 ISSN 的 venue 顯示其 ISSN 清單；`akashic person <key>` 顯示 ORCID（既有行為不變）。
- `akashic export-bib` 對升格後的 work 仍輸出 `DOI` / `ISBN` / `PMID` 欄位，內容與升格前逐字相同。
- 寫入一個非正規的識別碼（例如小寫 check digit）後讀回，得到正規形；寫入一個形狀不合法的值（例如 `12345`）被拒絕並具名原因。
- 舊記錄（識別碼仍在 `Entry.fields`、或值為非正規形）**仍可讀**，不 quarantine。

**Interface / data shape**

- 新型別住 `Sources/AkashicCore/Identifier.swift`：`ISSN`／`DOI`／`PMID`／`ISBN`／`ORCID`／`ROR`，各自 `Equatable`、各自有 failable 或 throwing 建構器與 `rawValue`-風格的正規形輸出。
- `Venue` 新增 `issn: [ISSN]`；`Organization` 新增 `ror: ROR?`；`Entry` 新增 `doi: [DOI]`／`pmid: [PMID]`／`isbn: [ISBN]`；`Person.orcid` 型別自 `String?` 改為 `ORCID?`。
- YAML 表示為記錄頂層的鍵：純量欄位是純量、清單欄位是序列。空清單不序列化（既有記錄零 diff）。
- `ProvenanceReference` 的欄位白名單新增上述欄位名；清單型者比照 `names` 要求 `value`，純量型者比照 `orcid` 拒收 `value`。
- 新增 CLI 遷移命令 `migrate-identifiers`，比照既有 `migrate-venues` 的形狀：預設乾跑、`--apply` 才寫入、需 store 工作樹乾淨、**不自動 bump format**（手動另行 bump）。

**Failure modes**

- 形狀不合法的識別碼在**寫入面**被拒絕，錯誤訊息具名該值與該種識別碼的預期形狀。
- **非正規形**的識別碼（例如小寫 check digit）在**讀取面**被接受並原樣保留，且 `akashic validate` 報一則 diagnostic 具名該記錄與該值（surfaced，不是靜默）。
- **形狀不合法**的識別碼（例如 `12345`）在**讀取面**仍然拒讀，整筆 quarantine 並具名該值與預期形狀。

  > **這一句在 2026-08-24 被裁決過一次，原本寫的是相反的行為。** 原文是「形狀不合法的
  > 識別碼在讀取面被接受並保留」，而它與兩處分岔：spec 的 scenario 寫的是 “does not match
  > **the normal form**”（只涵蓋非正規形），task 3.3 落地的 `Person.orcid` 對
  > `not-an-orcid` 是整筆 quarantine 且測試綠著。
  >
  > 使用者裁定取**窄**的那個讀法。理由不是「比較好做」，是 `id` 與 `issn` 的不對稱：
  > `id` 壞掉是**身分**壞掉（不知道這是哪一筆），`issn` 壞掉是**屬性**壞掉。但 quarantine
  > 是**看得見**的失敗（`doctor`／`validate` 報得出來），沒有違反 `lossless-intake` 的
  > 「靜默是最糟的形式」——而寬容版要新增一個機制（型別的 invalid 狀態或 per-field 殘留），
  > 那個成本要穿過相等、export、遷移、provenance 驗證四處，而觸發它的情形是**零實例**
  > （寫入面已拒絕、遷移對無法解析者略過，只有手改 YAML 到得了這一格）。
  >
  > 依 `.claude/rules/zero-instance-guards.md` 的立場，這一格要不要防是一列一列裁決的，
  > 而這一列的裁決是**現在不防**。真的出現手改壞值的實例時重新裁決。
- provenance reference 指向不在清單內的值時，維持既有行為（拒讀整筆並具名孤兒 value）——本 change 不放寬它。
- 遷移遇到無法解析的識別碼字串時**略過該筆並具名**，不猜測、不丟棄；乾跑報告列出全部略過項。

**Acceptance criteria**

- `swift test` 全綠，且新增測試涵蓋：六種識別碼各自的合法／非法／非正規輸入；清單與純量兩種 provenance 分支；round-trip 保留未知欄位。
- 對 store 跑 `akashic export-bib` 並與升格前的輸出逐位元比對，`DOI`／`ISBN`／`PMID` 欄位無差異。
- 遷移後 `akashic validate` 零新增 diagnostic；帶 `issn` 的 work 數自 64 降至 0，帶 `issn` 的 venue 數自 0 升至 39。
- `.claude/rules/mcp-cli-parity.md` 的三張裁決表對本 change 新增的每一個面各有一列。

**Scope boundaries**

- **In scope**：六種識別碼的型別、四個記錄型別的欄位、provenance 白名單、format 12→13、`migrate-identifiers`、export 補寫、三份規則檔的條款、MCP／CLI 兩面的參數裁決。
- **Out of scope**：外部 API 查證、識別碼的時間軸、`url` 與其餘 34 個 `fields` 鍵、#393 的候選 DOI 判定流程（那是如何**找到**識別碼，本 change 是識別碼**住哪裡**）。

## Risks / Trade-offs

- **[export 靜默少欄位]** 把 `doi` 搬出 `Entry.fields` 後，`BibExport` 對自由字典的逐鍵轉出不再輸出它，而 `.bib` 少一個欄位不會報錯 → **Mitigation**：照 #335 已建立的模板，在自由字典迴圈**之後**寫結構化值；驗收條件明列「與升格前逐位元比對」。
- **[format bump 打死三個 binary]** 未同步升級的 CLI／MCP server／App 會整份拒讀 store → **Mitigation**：遷移命令跑在舊解碼器上、format bump 是手動的獨立一步（沿用 `migrate-venues` 的既有部署形狀）；Migration Plan 明列順序。
- **[例外條款寫寬反噬]** `identity-is-judged-not-matched` 的例外若寫成性質判準，會讓字串謂詞重新合法化 → **Mitigation**：條款具名到六種識別碼並明寫封閉性；同一變更在該規則的「不主張什麼」段補一句。
- **[ISSN 多值的三種混合]** 8 個 venue 收到的多值混了真多號、異寫法、錯值三類，遷移若一律當成多值會把異寫法保留成假的多個 ISSN → **Mitigation**：遷移先正規化再去重；去重後仍 >1 者才是真多號。乾跑報告分開列出「去重後合併」與「保留多值」兩類供人審。
- **[`Person.orcid` 型別變更的擴散]** `orcid` 自 `String?` 改為 `ORCID?` 會觸及全部讀取它的面（App 的審議面、MCP 的 update-person、CLI、關聯匯出、divergence 解析） → **Mitigation**：先加 `ORCID` 型別與 `Person.orcid` 的轉換，再逐面改；此項單獨成一個任務，不與其他識別碼混做。

## Migration Plan

部署順序（沿用 `migrate-venues` 的既有形狀，每一步可獨立驗證）：

1. 發布新版三個 binary（含新型別、新欄位、寬容讀取、`migrate-identifiers`），此時 store 仍是 format 12，新欄位尚未使用。
2. 對 store 跑 `migrate-identifiers` 乾跑，人工審閱報告——特別是 ISSN 去重後仍多值的那些，以及無法解析而被略過的。
3. 跑 `migrate-identifiers --apply`：`Entry.fields` 的識別碼升格為結構化欄位、`issn` 移位至對應 venue、非正規值正規化，指向被改寫值的 provenance `value` 同一次寫入原子改寫。
4. 跑 `akashic validate` 與 `akashic export-bib`，確認零新增 diagnostic 且 `.bib` 的識別碼欄位與遷移前逐位元相同。
5. 手動把 `store.yaml` 的 `format` 自 12 改為 13。
6. 三個 binary 全部確認可讀新 store 後，才把識別碼欄位加入 provenance 白名單的寫入路徑啟用。

**Rollback**：步驟 5 之前，舊 binary 仍可讀（新欄位對它是 tolerant-preserve 的未知欄位）；步驟 3 的寫入以 git 為退路（遷移要求 store 工作樹乾淨，失敗時 `git restore` 即可）。步驟 5 之後回退需手動把 `format` 改回 12 並移除白名單欄位，成本較高——這是把 bump 排在最後一步的理由。

## Open Questions

- ~~**讀取面對非正規值的現行行為未經實測。**~~ **已實測確認（2026-08-21，Task 1.1 探針）。** 造一筆 `person` 記錄，其 `references` 帶 `field: names` 與一個 `value`：

  | 條件 | `akashic doctor` 結果 |
  | --- | --- |
  | `value` 在 `names` 清單內 | `people: 1`，零 quarantine |
  | `value` 不在清單內（其餘完全不動） | `people: 0`，`quarantined: 1` |

  拒讀訊息逐字：「欄位 person.references(field: names) 無效：value「…」不在 names 清單內——值被改寫後 provenance 成了孤兒，把 value 更新成現值或移除這筆 reference」。

  結論：「讀取時正規化會讓既有 reference 成為孤兒、於是整筆拒讀」為真，**裁決「正規化只在寫入面發生，讀取面寬容保留既有值」維持不變**，後續任務照原計畫進行。

  探針的兩個附帶發現（實作時會用到）：(a) `references` 元素的合法鍵是 `content`／`field`／`judgement`／`media-type`／`rests-on`／`retrieved`／`status`／`url`／`value`，**沒有 `source`**——本設計散文中的「來源」對應的鍵是 `url`；(b) `rests-on: []` 的空依據例外**只適用於 resolution verdict 欄位**，`names` 這類一般欄位的 judgement 型 reference 要求非空 `rests-on`（訊息：「沒有依據的斷言不是判斷」）。識別碼欄位屬於後者，其 provenance 必須帶依據。
- ~~**解析不出的識別碼字串要放哪裡。**~~ **已實測，不需要新形狀（2026-08-24）。**
  擔心的是 `[ISSN]` 這種型別裝不下 `0022-3506 1467-6494`，於是要為它發明一個二態欄位
  （比照 `Author` 的 `.key`／`.literal`）。實測推翻了這個需求：

  | 種類 | 解析不出 | 按空白切＋去括號註記後**全部** token 可解 | 真的壞掉 |
  | --- | --- | --- | --- |
  | issn | 25 | **25**（每筆恰好拆出 2 個合法 ISSN） | **0** |
  | isbn | 7 | 5（另 2 筆部分可解） | **0** |
  | doi | 3 | 1（另 2 筆部分可解，如 `DOI 10.1037/h0077149` 的 `DOI` 是標籤字） | **0** |

  **零筆是真的壞掉**——全部是「多值塞單欄」或帶標籤／註記，也就是 §8.2 遷移本來就要
  拆的東西。所以它們留在 `Entry.fields` 直到遷移拆開即可，不需要在型別層開第二態。
  部分可解的 4 筆依 §8.3「略過該筆並具名」交人工。

- **ISBN 的 10 碼與 13 碼是否視為同一個識別碼。** 同一本書的 ISBN-10 與 ISBN-13 可互相換算，是同一個身分的兩種編碼；但也可能一本書有多個真的不同 ISBN（不同版次／不同地區）。實測 31 筆 `isbn` 尚未按此切分。此問題只影響 ISBN 的去重規則，不影響其餘五種。
- **`Organization.ror` 目前零實例（8 筆 organization 皆無 ror）。** 依 `.claude/rules/zero-instance-guards.md`，新增一個當下零實例的欄位需要在該規則的裁決表加一列；該列的理由待定（傾向「寫」——落位一致性本身是價值，且成本是一個欄位）。
