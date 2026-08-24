## 1. 先驗探針：正規化只在寫入面發生，讀取面寬容保留既有值（此裁決的前提待實測）

- [x] 1.1 確認「provenance reference 的 `value` 不在該欄位現值清單內」時讀取面的實際行為：造一筆帶清單欄位 reference 的暫時記錄，把該值改成不同字串後讀回。驗證目標——新測試斷言實際結果（拒讀並具名孤兒 value，或載入成功），並在 design.md 的 Open Questions 記下實測結論。**若實測顯示不拒讀，設計裁決「正規化只在寫入面發生，讀取面寬容保留既有值」須重做，後續任務暫停等重新裁決。**

## 2. 識別碼欄位的型別是帶驗證的 value type，不是可選字串

交付 spec requirement「An identifier value SHALL be typed」。

- [x] 2.1 [P] 交付 spec requirement「An identifier value SHALL be typed」。先寫失敗測試：`ISSN` 對 `0003-066X` 接受、對 `0003-066x` 正規化為大寫、對 `12345` 與 `1467-8624(Electronic),0009-3920(Print)` 拒絕。驗證目標——`swift test --filter IdentifierTests` 由紅轉綠。
- [x] 2.2 [P] 交付設計裁決「identity-is-judged-not-matched 的例外條款具名到六種識別碼」，即 spec requirement「An identifier SHALL settle reference, not description」與「Identifier equality SHALL be admissible as an identity judgement」：在 `.claude/rules/identity-is-judged-not-matched.md` 新增例外節，具名 DOI／PMID／ISBN／ISSN／ORCID／ROR 六種並明寫「封閉列舉，不得依性質相似類推」，同節說明識別碼終結指涉但不終結欄位值，並具名排除 `url`（locator 非註冊指派）。驗證目標——內容複審確認條款未寫成性質判準，且六種識別碼逐一列出。
- [x] 2.3 在 `Sources/AkashicCore/Identifier.swift` 實作六個 value type，各自帶 failable 或 throwing 建構器、形狀驗證與正規形輸出。驗證目標——2.1 的測試全綠，且新增 DOI／ORCID／ROR／PMID／ISBN 各自的合法／非法／非正規三類案例。

## 3. 識別碼放記錄頂層的具名欄位，不做泛型容器

交付 spec requirement「An identifier SHALL live on the entity it identifies」。

- [x] 3.1 [P] 交付 spec requirement「An identifier SHALL live on the entity it identifies」。`Venue` 取得 `issn: [ISSN]`、`Organization` 取得 `ror: ROR?`，且 `Venue` 型別 doc comment 內逐一列舉欄位的那段同步更新。驗證目標——新測試以反射斷言兩型別的欄位集合含新欄位，且 `Venue` 的 doc 列舉與實際欄位一致。
- [x] 3.2 [P] `Entry` 取得 `doi: [DOI]`／`pmid: [PMID]`／`isbn: [ISBN]` 結構化欄位，與既有 `Entry.fields` 並存（本任務不移除 `fields` 內的舊值，移除由遷移負責）。驗證目標——新測試斷言同時持有結構化值與 `fields` 殘留時，結構化值為正典。
- [x] 3.3 `Person.orcid` 的型別自 `String?` 改為 `ORCID?`，並逐一更新讀取它的五個消費面（App 審議面、MCP 的 update-person、CLI 命令、關聯匯出、divergence 解析）。驗證目標——`swift build -Xswiftc -warnings-as-errors` 通過且既有 person 相關測試全綠。

## 4. YAML 編解碼：正規化只在寫入面發生，讀取面寬容保留既有值

交付 spec requirement「Normalization SHALL occur on the write path only」。

- [x] 4.1 交付 spec requirement「Normalization SHALL occur on the write path only」。先寫失敗測試：讀取一筆 `issn` 值為 `0003-066x` 的 venue 記錄時記錄成功載入且值原樣保留；寫入同一筆時值變為 `0003-066X`。驗證目標——測試由紅轉綠。
- [x] 4.2 實作識別碼欄位的序列化與反序列化：頂層鍵、清單欄位為序列、純量欄位為純量、空清單不序列化（既有記錄零 diff）、讀取路徑**不因非正規形而拒讀**（形狀不合法仍拒讀——2026-08-24 裁決，見 design.md Failure modes）。驗證目標——4.1 全綠，且 round-trip 測試斷言未知欄位仍被 tolerant-preserve 保留。
- [x] 4.3 `akashic validate` 對非正規形的識別碼值輸出一則具名該記錄與該值的 diagnostic（surfaced，不靜默）。驗證目標——對含 `0003-066x` 的暫時 store 執行 validate，斷言輸出含該值。

## 5. 基數逐種決定，且基數決定 provenance 走哪條驗證分支

交付 spec requirement「Identifier cardinality SHALL be decided per kind」與「A reference to a list-valued identifier SHALL name which value it supports」。

- [x] 5.1 交付 spec requirement「Identifier cardinality SHALL be decided per kind」與「A reference to a list-valued identifier SHALL name which value it supports」。先寫失敗測試：清單型識別碼欄位的 reference 缺 `value` 時被拒；純量型識別碼欄位的 reference 帶 `value` 時被拒；`value` 不在清單內時整筆拒讀並具名孤兒值。驗證目標——測試由紅轉綠。
- [x] 5.2 依基數把清單型識別碼導向 `names` 既有的清單驗證分支、純量型導向 `orcid` 既有的純量分支；`ORCID` 與 `ROR` 宣告為純量，`ISSN`／`DOI`／`PMID`／`ISBN` 宣告為清單。驗證目標——5.1 全綠。

## 6. 識別碼進 provenance 欄位白名單，store format 自 12 升至 13

交付 spec requirement「An identifier field SHALL be attachable」。

- [x] 6.1 交付 spec requirement「An identifier field SHALL be attachable」。在 `ProvenanceReference` 的欄位白名單新增 `doi`／`pmid`／`isbn`／`issn`／`ror`，使識別碼能攜帶來源。驗證目標——新測試斷言一筆帶 `field: issn` reference 的 venue 記錄可載入，且該 reference 出現在讀回的記錄上。
- [x] 6.2 `docs/store-format.md` 的版本對照表新增 format 13 一列，寫明「`references[].field` 白名單是 strict → 舊 binary 整檔 quarantine」的升版理由；`StoreVersion` 的支援版本同步。驗證目標——對 format 13 的 store 用未升級路徑讀取的測試斷言拒讀並指路。

## 7. 匯出面：結構化值勝過自由字典殘留

- [x] 7.1 `BibExport` 在自由字典逐鍵轉出的迴圈**之後**寫出結構化識別碼，使結構化值勝過 `fields` 內的同名殘留，形狀比照既有的學位論文欄位處理。驗證目標——新測試斷言同時持有兩者時 `.bib` 取結構化值；並對現行 store 執行 export 與升格前輸出逐位元比對，`DOI`／`ISBN`／`PMID` 欄位無差異。

## 8. 遷移

- [x] 8.1 新增 CLI 命令 `migrate-identifiers`：預設乾跑列出每一筆將改動的值、`--apply` 才寫入、要求 store 工作樹乾淨、**不自動 bump format**。驗證目標——乾跑對現行 store 輸出 825 個識別碼的處置清單且 store 無變動。
- [x] 8.2 遷移對 ISSN 的多值處理：先正規化再去重，去重後仍 >1 者保留為多值；乾跑報告把「去重後合併」與「保留多值」分開列出。驗證目標——對 8 個收到多值的 venue，斷言 `american-psychologist` 的 `0003-066x` 與 `0003-066X 1935-990X` 合併為兩個相異值，而 `behavior-research-methods` 的 `1554-351x` 與 `1554-3528` 保留為兩個。
- [x] 8.3 遷移原子地同時改寫識別碼值與指向舊值的 provenance `value`；無法解析的識別碼字串略過該筆並在報告具名，不猜測不丟棄。驗證目標——測試斷言改寫後無任何 reference 指向不存在的值，且略過項出現在報告中。

## 9. 兩面對等與收尾裁決

- [ ] 9.1 [P] `.claude/rules/mcp-cli-parity.md` 的三張裁決表對本 change 新增的每一個面各加一列（`migrate-identifiers` 落 CLI-only 表並具名維運例外理由；識別碼參數在 MCP 面的有無各自裁決）。驗證目標——依該規則的四步機械稽核程序執行，確認枚舉輸出與表零差集。
- [ ] 9.2 [P] `.claude/rules/zero-instance-guards.md` 的裁決表新增一列，裁決 `Organization.ror` 這個當下零實例欄位要不要寫，並在同列寫出該列自己的理由。驗證目標——內容複審確認理由未沿用既有四列任一列的理由。
- [ ] 9.3 收尾驗收：遷移後帶 `issn` 的 work 數為 0、帶 `issn` 的 venue 數為 39、`akashic validate` 零新增 diagnostic、`swift test` 全綠。驗證目標——逐項執行並記錄實測數字。
