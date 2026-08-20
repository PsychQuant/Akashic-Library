## Why

模型裡缺一個有名字的類別：**身分證**——由註冊機構指派、用來終結「這是哪一個」的識別碼（DOI／PMID／ISBN／ISSN／ORCID／ROR）。缺席的後果是可量測的：同一種東西目前有**三種待遇**——`Person.orcid` 是一等公民欄位、work 的 `doi`／`pmid`／`isbn`／`issn` 塞在自由字典 `Entry.fields`、venue（402 筆）與 organization（8 筆）**完全沒有識別碼欄位**。

兩個直接後果已在 store 內量到：

- **識別碼放在錯的實體上**：64 筆 work 帶著 `issn`，但 ISSN 是**期刊**的身分證——它住在 work 上，只因為 venue 沒有地方放它。
- **有值但沒有型別**：`0003-066x` 的 check digit 是小寫（ISSN 標準規定大寫 `X`）、`1467-8624(Electronic),0009-3920(Print)` 一個欄位塞兩個號。自由字典驗不出這些，因為它對值沒有任何主張。

此外，`.claude/rules/identity-is-judged-not-matched.md` 禁止「身分判定由字串謂詞單獨做出」，而 **DOI 相等就是一個字串謂詞**。缺少明文例外的話，日後有人會拿那條規則去否決「用 DOI 判定同一筆」——那是荒謬的，而規則本身沒有任何地方擋得住這個誤讀。

## What Changes

- 新增**識別碼**作為模型的一等公民類別：`Venue`／`Organization` 取得識別碼欄位、`Entry` 的 `doi`／`pmid`／`isbn` 自 `Entry.fields` 升格為結構化欄位、`Entry` 的 `issn` 移位到它所識別的 venue。
- 識別碼欄位的型別**不是** `String?`，而是帶形狀驗證與正規化的 value type。ISSN 驗 `NNNN-NNNN` 與 check digit 大寫、DOI 驗 `10.` 前綴形狀、ORCID 驗四段十六位與 check digit。
- 基數**逐種決定**：ORCID 每人一個（純量）；ISSN 每個 venue 可多個（print 與 electronic 是兩個真號，實測 `1554-351x` 與 `1554-3528`）；DOI 每筆 work 可多個（實測 37 組同題同年不同 DOI）。
- **BREAKING**：識別碼欄位加入 `references[].field` 白名單，使識別碼能攜帶來源。該白名單是 store 格式的 strict 層——舊 binary 讀到未知 field 是整檔 quarantine，故 store format 自 12 升至 13。三個獨立 binary（CLI／MCP server／原生 App）必須同步部署。
- 正規化只發生在**寫入面**；讀取面接受並保留非正規形，不因大小寫而 quarantine 既有記錄。遷移命令原子地同時改寫識別碼值與指向它的 provenance `value`。
- `.claude/rules/identity-is-judged-not-matched.md` 增列例外條款，**具名到六種識別碼**並明寫「封閉列舉，不得依性質相似類推」。`url`（281 筆）明確排除，理由具名為「locator 而非註冊指派」。

## Capabilities

### New Capabilities

- `entity-identifier`: 識別碼作為跨實體種類的一等公民——落位、型別、基數、正規化時機，以及它終結什麼（指涉）與不終結什麼（欄位值的正確性）。

### Modified Capabilities

- `provenance-reference`: 具名欄位的可附掛範圍擴及識別碼欄位；清單型識別碼的 reference 必須攜帶 `value` 指名支持哪一個值，與既有 `names` 的清單語意一致。

## Impact

- Affected specs: `entity-identifier`（新）、`provenance-reference`（修改）
- Affected code:
  - New:
    - `Sources/AkashicCore/Identifier.swift`
    - `Tests/AkashicKitTests/IdentifierTests.swift`
  - Modified:
    - `Sources/AkashicCore/Models.swift`
    - `Sources/AkashicCore/Venue.swift`
    - `Sources/AkashicCore/Organization.swift`
    - `Sources/AkashicCore/Provenance.swift`
    - `Sources/AkashicCore/YAML.swift`
    - `Sources/AkashicExport/BibExport.swift`
    - `Sources/akashic/CLI.swift`
    - `Sources/akashic/Commands.swift`
    - `Sources/akashic-mcp/Server.swift`
    - `Sources/AkashicMCPKit/AkashicService.swift`
    - `docs/store-format.md`
    - `.claude/rules/identity-is-judged-not-matched.md`
    - `.claude/rules/entity-backlink-completeness.md`
    - `.claude/rules/mcp-cli-parity.md`
  - Removed: （無）
