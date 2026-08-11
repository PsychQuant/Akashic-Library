## Context

Akashic-Library 已有一份規範性設計哲學文件與多篇維根斯坦解說，但目前只引用少數《邏輯哲學論》命題，無法機械回答「是否每個正文句段都有翻譯、解讀與誠實的專案關係」。新能力是文件語料與建置工具，不是 Akashic canonical store 的新 entity，也不改 store format。

使用者已決定：範圍為維根斯坦序言與編號命題 1–7；德文、Ogden／Ramsey 1922、Pears／McGuinness 與臺灣正體中文採並排呈現；中文是本專案工作譯文；每條命題都要有專案關係，且允許明載不適用或刻意不遵循；`main` 是現況正典，其他 branch、commit 與 issue 只作歷史脈絡。

此語料會超過數百筆命題與更多句段，必須能分卷校訂、決定性產生文件、在 CI 離線驗證，並避免因追求「完整對照」而把工程類比冒充哲學同一。

## Goals / Non-Goals

**Goals:**

- 以 YAML 保存全部在範圍內的原文單位、跨版本句段對齊、中文工作譯文與中文哲學解讀。
- 對每個命題保存至少一筆可證偽的 Akashic 專案關係，區分實作、部分實作、願景、類比、拒絕、不適用與刻意不遵循。
- 驗證來源版本、命題樹、跨版本涵蓋、中文欄位、現況證據與歷史參照。
- 由同一份 YAML 決定性產生四欄並排 Markdown，讓 YAML 是唯一可編輯正典。
- 讓本機與 CI 使用相同 Swift 指令完成驗證與 generated-file drift 檢查。

**Non-Goals:**

- 不把《邏輯哲學論》命題放進 `entities/`，不新增 Akashic entity 形狀或 store format。
- 不宣稱 Akashic 完整實作 Tractatus；`not_applicable`、`analogy_only` 與 `intentional_nonconformance` 是必要的一級結果。
- 不收錄 Russell 導論與索引；獻詞與題辭只作來源 metadata，不要求逐句專案對照。
- 不新增 CLI／MCP 查詢 Akashic store 中哲學命題的執行期功能。
- 不在缺少相容授權時重製 Pears／McGuinness 全文。

## Decisions

### 正典邊界與來源版本

`docs/tractatus/sources.yaml` 記錄語料 scope、版本角色、來源 URL、擷取日期、上游 revision、著作權狀態與是否允許 inline。允許 inline 的公開領域來源另保存離線 snapshot，並以 SHA-256 鎖定實際下載內容，驗證器會對 snapshot 重算 digest；原文公式圖保存在 `source-assets/` 並由 `SHA256SUMS` 鎖定，CI 不依賴網路。

manifest inventory 不能自行定義何謂「完整」：驗證器另以固定指紋鎖住依印刷順序排列的序言八段與 526 條命題、獻詞與題辭 metadata，並要求三個固定版本 ID、角色、語言與 inclusion mode 皆唯一且順序正確。這避免同時縮短 manifest 與 corpus 後仍得到假綠燈。

德文是 `original`；Ogden／Ramsey 1922 與 Pears／McGuinness 是 `translation`，不得稱為第二份德文原典。德文與 1922 英譯可 inline。Pears／McGuinness 預設為 `external_reference`：產生文件仍保留固定欄位、版本資訊、命題編號與來源連結；只有 `sources.yaml` 出現可稽核的相容授權記錄時，才允許全文進入 YAML。替代方案「直接從公開網頁複製」被否決，因為網頁可讀不等於可重製。

若 inline 版本標為 `licensed`，必須另有絕對 HTTP(S) `license_evidence_url`，不能只寫任意非空 `rights_note`。所有版本共同檢查 bibliography、HTTP(S) URL、ISO 日期、revision 與 rights note；只有 inline edition 必須提供 64 位 SHA-256。External-reference edition 沒有本機重製內容，因此改由 bibliography、URL、revision 與 rights note 稽核，並必須省略 `sha256`，不能用全零值或其他假 digest 暗示不存在的內容校驗。validator 會把 corpus 各命題文字回組後直接比對固定 snapshot；digest 正確但 snapshot 結構無法解析或 corpus 文字漂移時仍 fail-closed 回報 `source-mismatch`。

### 分卷 YAML 與命題／句段雙層模型

語料依 `preface.yaml` 與 `1.yaml` 至 `7.yaml` 分卷。單一巨型檔會放大 merge conflict；一命題一檔則會產生數百檔案與難以導覽的目錄，兩者均否決。

每卷包含有序 `propositions`。編號命題用原編號作穩定 ID；序言段落用 `preface.<paragraph>`，句段再加 `.a`、`.b`。每個 inline edition 的 `texts` 是有序來源單位陣列；`segments[].alignment` 用索引陣列做多對多對齊。每個來源索引在該命題內必須恰好被引用一次，故不同譯本可以一對多或多對一，不必假裝標點切句完全相同。

逐句解讀是內容契約，不只是覆蓋率。允許的 segment 對齊形狀只有 1↔1，或為容納德英版本句界差異而使用 2↔1／1↔2。2↔2 與任一版本三個以上來源單位都代表可再拆的多句聚合，驗證回報 `alignment-granularity`。替代方案「只檢查每個索引被覆蓋一次」被否決，因為一個 mega-segment 就能讓整段形式上通過、實際上沒有逐句解毒。

來源單位邊界本身也不可信。若 1↔1 兩側都在單一字串內出現明顯的完整句終與下一句起首，驗證回報 `source-unit-granularity`；2↔1／1↔2 的單一側不得藏入多個完整句子，多單位側也必須有可信的標點切點。每個版本的 alignment 索引攤平後還必須嚴格依序，否則回報 `alignment-order`。縮寫、公式與真實版本句界差異仍由人工稽核保留。

每個句段必填 `translation_zh_tw` 與 `interpretation_zh_tw`。工作譯文表達原文內容；哲學解讀表達讀法、術語選擇與限制，兩者不得合併。以「建立論證起點／推進到／收束命題」包住譯文片段的語料建構樣板，不算哲學解讀，驗證器回報 `generic-interpretation`；`TODO：命題號` 等裝飾過的佔位文字仍視為缺漏。命題層可另有 `synthesis_zh_tw`，但它不能取代任何句段解讀。

### 雙軸專案關係與證據

每個命題至少有一筆 `project_relations`。`status` 是目前符合程度：

- `implemented`
- `partial`
- `aspirational`
- `analogy_only`
- `rejected`
- `not_applicable`
- `intentional_nonconformance`

`mode` 是關係如何存在：

- `instance`
- `structural_invariant`
- `semantic_operation`
- `formal_derivation`
- `refusal`
- `shown_constraint`
- `meta_elucidation`
- `declared_nonconformance`

每筆關係必填 `claim_zh_tw` 與 `rationale_zh_tw`。理由必須針對該命題的具體哲學內容撰寫；不同命題若在空白正規化後共用完全相同的理由，驗證器回報 `duplicate-rationale`，避免大量 `not_applicable` 樣板在形式上冒充逐條判斷。除 `not_applicable` 外至少要有一筆現況 `evidence`；`not_applicable` 仍必須有具體理由。證據可指向 project-root-relative path，加上穩定 symbol、規格 requirement 名稱、測試名稱或文件 heading；行號只能作顯示資訊，不能作唯一定位。

替代方案「每條命題都硬找一個實作」被否決，因為它會使完整性要求反而製造哲學過度宣稱。

### `main` 現況與歷史脈絡分層

`project_relations` 只描述目前 `main`。`history` 保存 branch、commit 或 issue，並以 `retained`、`revised`、`rejected` 標出它對現況的地位。驗證器對 current path 與 Git commit 做本機可驗證的存在檢查；issue URL 只做格式檢查，不在 CI 連網。

同一個 branch 不等於 possible world，merge commit 也不等於某個世界成真。歷史欄位只保存專案理解的演變。

current evidence 的 `kind` 不是裝飾欄位：heading 必須解析為完整 Markdown heading，test 必須是 `Tests/` 下的具名測試函式，requirement 必須位於 `openspec/` requirement heading，symbol 必須是 Swift 識別字。路徑先解析 `./`、`..` 與 symlink 再套用政策；canonical corpus、snapshot 與 generated 文件不得循環證成自身 relation。

### 單一深介面：`TractatusDocs`

新增 `TractatusDocs` library target，唯一負責 Yams node 到 typed corpus 的轉換、跨卷驗證與 Markdown rendering；`tractatus-doc` executable 只解析參數並呼叫此 library，不堆疊第二套薄 wrapper。刪除 library 會使 schema 驗證、完整性檢查與產生器全部失效，故此 seam 有實際深度。

使用既有 Yams dependency 與 Swift/XCTest，不新增 PyYAML。診斷輸出重用 `AkashicCore.displaySafe`，在唯一格式化邊界跳脫控制字元、雙向文字標記與反斜線，避免任意 YAML 值偽造 CLI 診斷行；schema error 自身的 `LocalizedError` 也套用同一層保護。Python 方案起步較快，但會建立第二套依賴與型別邊界，且現有 CI 已以 SwiftPM 為中心，因此否決。

### Fail-closed 完整性與來源誠信驗證

驗證分四層：

1. 單檔 schema：必填欄位、封閉 enum、ID 文法、edition key、來源 metadata 格式。
2. 跨檔結構：唯一 ID、父節點存在、自然數字順序、檔名與 `volume` 一致、scope 恰為序言與 1–7、來源 manifest 所列命題無遺漏也無多餘。
3. 句段與來源：inline edition 每個來源單位恰好被一次 alignment 引用；對齊形狀與切點合法；中文翻譯與解讀非佔位；snapshot 可解析且能回組；離線圖資存在且 digest 相符；external edition 不得含未授權全文。
4. 專案證據：正規化後的 current path 存在，指定 symbol／heading／test name 可在檔內定位，commit 可由 Git object database 解析；generated path 不得被當作現況承重證據。

驗證器收集全部錯誤後一次列出，依 path、record ID、error code 排序；任一錯誤 exit non-zero。輸出前以專案既有 `displaySafe` 處理所有診斷欄位，再跳脫欄位分隔符號；未知 YAML key 一律拒絕，避免 typo 靜默失效。

### 決定性四欄 Markdown

`render` 固定依序輸出德文、Ogden／Ramsey、Pears／McGuinness、臺灣正體中文四欄。輸出使用 GitHub-flavored Markdown 內嵌 HTML table，保留段落、公式與換行，並把 snapshot-relative 圖片改寫成指向版控內離線資產的 HTML image；每個句段後附中文哲學解讀，每個命題後附 project relation、現況證據與歷史脈絡。

相同 YAML bytes 與工具版本必須產生相同 Markdown bytes：不得含現在時間、絕對路徑或環境相關資料。輸出首段標示 generated，不接受直接編輯。`render --check` 在記憶體產生內容並與版控檔逐位元組比較，drift 時 exit non-zero。

### 分階段建構，最後啟用全書閘門

先完成 typed model、validator、renderer 與代表性 fixture；再依序完成序言與命題 1–7。建構期間可用 `--allow-incomplete` 顯示缺項清單，但 CI 與最後驗收只執行 strict mode。strict mode 不接受 placeholder、空字串、`<unfinished>`、`<unreviewed>` 或缺少關係的命題。

替代方案「先放數百筆空 skeleton 讓檔案看起來完整」被否決；空 skeleton 會讓檔案數量冒充內容完成度。

## Implementation Contract

### Observable commands

- `swift run tractatus-doc validate --root docs/tractatus`：離線載入全部來源 metadata 與 corpus，strict 驗證成功時印出命題、來源單位、句段與專案關係計數並 exit 0。
- `swift run tractatus-doc validate --root docs/tractatus --allow-incomplete`：只供建構期使用；結構與誠信錯誤仍失敗，缺卷／缺命題以明確清單輸出。
- `swift run tractatus-doc render --root docs/tractatus --output docs/tractatus/generated/tractatus-project-map.md`：先 strict validate，再原子寫入決定性 Markdown。
- `swift run tractatus-doc render --root docs/tractatus --output docs/tractatus/generated/tractatus-project-map.md --check`：不寫檔；內容相同 exit 0，不同則列出 drift 並 exit non-zero。

### Error contract

每個錯誤使用 `path:record-id:error-code: message`，不印絕對路徑；同次執行的錯誤依上述三個鍵排序。至少定義：`unknown-key`、`invalid-id`、`invalid-scope`、`invalid-source`、`volume-file-mismatch`、`duplicate-id`、`missing-parent`、`missing-proposition`、`extra-proposition`、`source-mismatch`、`digest-mismatch`、`alignment-gap`、`alignment-duplicate`、`alignment-order`、`alignment-granularity`、`source-unit-granularity`、`missing-translation`、`missing-interpretation`、`generic-interpretation`、`invalid-relation`、`duplicate-rationale`、`missing-evidence`、`invalid-evidence`、`broken-path`、`missing-symbol`、`unknown-commit`、`license-violation`、`generated-drift`。

### Acceptance criteria

- XCTest 以 fixture 覆蓋每個 error code、many-to-many alignment、數字命題排序、external-reference edition、決定性 rendering 與 generated drift。
- 正式語料 strict validate 成功，且來源 manifest 的序言／命題 inventory 與 corpus 完全相等。
- 正式語料中每個 inline source unit 恰好被一個句段涵蓋，且對齊形狀限 1↔1、2↔1 或 1↔2；每個句段都有非 placeholder 的中文工作譯文與哲學解讀；每個命題至少有一筆合法專案關係。
- 所有 current evidence 通過本機 path／symbol 驗證；所有 commit history ref 可解析。
- 連續 render 兩次產生相同 SHA-256；`render --check` 對版控產物成功。
- `.github/workflows/ci.yml` 在 Swift test 後執行 strict validate 與 render check。

### Scope boundaries

本變更只建立文件語料、文件工具與 CI 閘門。它不修改 Akashic store decoder、entity model、MCP schema、CLI store 指令或 App 行為。語料中標為 `aspirational` 的內容不授權順便實作相應執行期功能。

## Risks / Trade-offs

- [Risk] Pears／McGuinness 全文受著作權保護 → 預設 external reference；只有可稽核授權允許 inline，驗證器阻擋未授權全文。
- [Risk] AI 工作譯文或解讀可能錯誤 → 每句保留德文與公開領域英譯對齊、翻譯與解讀分欄、來源 digest 與逐卷 review 邊界。
- [Risk] 覆蓋率通過但多句共用一段泛化解讀 → `alignment-granularity` 只允許 1↔1 與句界差異所需的 2↔1／1↔2，正式來源回組測試再確認沒有遺漏原文。
- [Risk] 編者先把多句吞進單一 `texts[]`，再用 1↔1 繞過索引數限制 → `source-unit-granularity` 偵測雙版本明顯內部句界，逐卷人工稽核處理縮寫、公式與版本差異。
- [Risk] 編者任意切字，再用 2↔1／1↔2 冒充版本句界差異 → 單一側不得含內部完整句界，多單位側必須有可信標點切點。
- [Risk] snapshot digest 正確但 corpus 文字漂移，或 alignment 交叉錯欄 → production validator 直接回組 snapshot 並要求各版本索引嚴格依序。
- [Risk] 公式圖只留相對連結而成為壞圖，或圖檔被替換 → 版控保存離線資產並以 `SHA256SUMS` 驗證，renderer 改寫為可解析路徑。
- [Risk] 每句都有 interpretation 欄位，但內容只是自動產生的論證進度樣板 → `generic-interpretation` 阻擋已知建構樣板，逐卷代表命題審閱再檢查哲學內容。
- [Risk] 每個命題都有 relation，但大量命題共用泛化理由 → `duplicate-rationale` 阻擋跨命題完全相同的理由，逐卷稽核再確認理由確實回應各命題內容。
- [Risk] 「完整」被誤解為「全部已實作」 → status／mode 雙軸與 `not_applicable`、`analogy_only`、`intentional_nonconformance` 強制理由。
- [Risk] 數百筆資料造成巨大 review → 依序言與 1–7 分卷，內容任務再按命題子樹分批，strict gate 最後才開。
- [Risk] path 或 symbol 因重構失效，或用 `./` 繞過禁止路徑 → CI 先正規化再驗證 current evidence；歷史 commit 與現況 path 分欄。
- [Risk] Markdown table 對公式與多段文字支援不一 → 使用受控 HTML table 片段與 escaping 測試，YAML 永遠是正典。

## Migration Plan

1. 新增 Swift targets、fixture 與 `--allow-incomplete` 工具，不修改既有產品行為。
2. 加入來源 manifest、離線 snapshots 與分卷 corpus，逐卷通過局部驗證。
3. 全部序言與命題 1–7 完成後產生正式 Markdown。
4. CI 接上 strict validate 與 render check；此時不再允許 incomplete corpus。
5. 回滾時可移除新 targets、文件目錄與 CI 兩道命令；Akashic store 無資料遷移。

## Open Questions

無。Pears／McGuinness 是否能 inline 由 `sources.yaml` 的可稽核授權記錄決定；缺少授權時的行為已定義為 external reference，並以 bibliography、URL、revision 與 rights note 稽核而不虛構內容 digest，不阻擋其餘完整語料。
