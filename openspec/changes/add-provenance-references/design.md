## Context

Store 目前唯一的結構化 provenance 是 `TemporalValue.source: String?`，掛在單一時間段上。`~/.akashic` 內 78 段 affiliation 各帶一個機構名冊頁 URL，運作良好——但它只覆蓋時間軸欄位，且只存 URL。

2026-08-03 的實測（Akashic-Library#64）暴露兩個缺口。

**其一，欄位層級的來源多樣性。** 同一個 person 記錄的 `profile.affiliations` 來自機構名冊頁、`orcid` 來自 ORCID public API 加人工判定、`names` 的某個別名來自人工判定。現況只能把判定推理塞進整筆記錄的 `note` 自由文字（`hsuan-yu-chen` 就是一例），或推出 store 之外（41 筆 ORCID 的判定依據存在另一個 repo 的 CSV）。

**其二，URL 不構成 provenance。** 實測：`sites.stat.sinica.edu.tw/cheng/` 與 `www.stat.sinica.edu.tw/cheng/` 回傳位元組相同的內容（SHA-256 皆為 `d1f446b3507bd24a…`），`staff.` 版本則是 404。兩個路徑、一個東西。URL 是通往內容的路徑，不是內容本身。同批實測另證實 Wayback 對這類低流量學術頁幾乎無快照（5 個死站僅 1 個有，且是活著的首頁而非死掉的子頁），所以「URL 死了再去 archive 撈」不是可依賴的退路。

約束：store 的資料 repo 有 GitHub remote，而本專案的既有規則是原始第三方逐字內容不進 remote。存檔的網頁屬於該類內容。

## Goals / Non-Goals

**Goals:**

- 一筆 provenance 同時保留取得路徑（URL、擷取日期、HTTP 狀態）與被取得的內容（SHA-256 定址的位元組）
- provenance 可指名它支持的是哪一個欄位
- 支援「判斷」型 provenance——不是單次擷取，而是對多份證據的推理
- 存檔內容的版控排除是**被驗證的性質**，不是使用者記得設定的慣例
- 既有記錄零改動載入

**Non-Goals:**

- 不遷移既有的 `TemporalValue.source`（78 段裸 URL 原樣保留，另案處理）
- 不做內容正規化後再 hash（正規化是詮釋，牽涉 design-principles 第 16 節，需獨立審議）
- 不含擷取行為（爬取、排程、重新驗證都由呼叫端決定）
- provenance 不進 `export-tables`
- 不做存檔內容的過期偵測

## Decisions

### D1：provenance 掛在欄位層，不是記錄層

考慮過三種形狀：(a) 頂層 `references:` 清單、(b) 每個純量欄位升級成「值 + 來源」、(c) 兩層並用（頂層定義來源、欄位層用 id 指涉）。

選 **(a) 的形式加上 `field:` 欄位**——清單住頂層，但每一筆自報它支持哪個欄位。

理由：(a) 純形式做不到欄位對應，一筆記錄五個來源時關係就丟了，而這正是要解的問題。(b) 對應精確但要改所有純量欄位的 codec、YAML 大幅變胖，代價與收益不成比例。(c) 表達力最強但引入 store 內的區域性 id，而 id 一旦存在就要處理重複、孤兒、跨檔引用——複雜度換來的表達力本案用不到。

清單住頂層還有一個好處：它不改任何既有欄位的形狀，所以既有 codec 不動，向後相容是結構上的而非測出來的。

### D2：collection 內的欄位用「值」定位，不用索引

`names` 是清單。要指名「`Chen, H-Y.` 這個別名的來源」時，用索引（`names[2]`）會在清單重排時失效。改用值本身：

```yaml
- field: names
  value: "Chen, H-Y."
```

值可能重複嗎？`names` 內重複的別名本來就該去重，所以不構成問題。代價是值改寫時 provenance 會變成孤兒——這由「reference 指名的欄位/值必須存在」的驗證擋下（見 spec 的對應 scenario）。

### D3：SHA-256 於原始位元組，不正規化

digest 算在**收到的位元組**上，不做任何轉換。這讓「同一個東西」的判準是客觀的：兩次擷取位元組相同就是同一個 referent，不需要人判斷。

代價誠實記錄：頁面的廣告、時間戳、session id 會讓內容變動而所指未變，於是同一份實質內容可能有多個 digest。正規化能解這個問題但本身是一種詮釋（要決定什麼算「無關差異」），列為 Non-Goal。

也因為不正規化，**錯誤頁面同樣有 digest**。實測中三個 `staff.` 的 404 共用同一個 digest——「死」本身也是內容。所以 reference 記錄 HTTP 狀態，讓消費者能區分「取得了一份 404」與「取得了想要的內容」。這比「HTTP 200 就是活著」可靠：實測另有一例是 200 但只有 122 bytes 的 meta-refresh，把已廢棄偽裝成正常回應。

### D4：存檔住 store 內的 `sources/`，two-char 分片

路徑形如 `sources/d1/f446b3507bd24a…`（digest 前兩字元當目錄）。分片沿用 git object store 的慣例，避免單一目錄累積上萬檔。

存檔**不帶副檔名**——位元組就是位元組，媒體型別記在 reference 的欄位裡。這讓內容定址保持純粹：檔名完全由 digest 決定，不受詮釋影響。

**不進 `entities/`**：兩個獨立的理由，任一充分。第一是 entity-boundary 既有的形狀判準——網頁不決定記錄形狀、不讓 loader 分岔到不同 decoder。第二是內容定址本身——entity 的判準之一是「名稱改變後仍應被視為同一物」，而內容定址的位元組串改一個 byte 就是另一串。它沒有名字、沒有歷史、沒有生命週期，身分完全是外延的。這與 entity 的判準正好相反，所以它在構造上不可能是 entity。

### D5：版控排除是 fail-closed 的驗證，不是文件慣例

`ensureLayout()` 建立 `sources/` 時，一併把排除規則寫進 store 的版控忽略檔（idempotent，有標記區塊，重跑不重複）。

但寫入不等於生效——使用者可能自行改回、或忽略規則被更外層的設定覆蓋。所以**寫入任何存檔內容之前，先驗證排除確實生效**（store 是 git repo 時，以 git 自己的忽略判定為準）。未生效就拒絕寫入並說明原因。

理由：這條規則保護的是第三方內容不外流，而外流是不可逆的。靠「使用者記得設定」等於把不可逆風險交給記憶。本 session 反覆出現的教訓正是這一類——靜默失敗比大聲失敗昂貴得多。

store 不是 git repo 時（可能的使用情境），跳過驗證但記錄跳過的事實。

### D6：判斷型 reference 是獨立的種類，不是缺欄位的擷取型

有些主張建立在對多份證據的推理上，而非單次擷取。實例：某位研究員的 ORCID 是靠「著作時間窗吻合任期 + 主題相符 + 一篇與同機構另一位確認成員的合著」判定的——ORCID 的機構欄只列現職，直接比對會判定為不符。

這種 reference 沒有自己的 URL、沒有自己的位元組，但它**指名所依據的 digest**。所以形狀上是：有 `judgement` 文字 + `rests-on` digest 清單，無 `url` / `content`。

刻意讓它與擷取型互斥（判斷型帶 `content` 就拒絕）：兩者的驗證條件不同，混在一起會讓「這筆 provenance 完不完整」無法機械判定。

### D7：既有 `TemporalValue.source` 不動

78 段 affiliation 的裸 URL 保留原樣、不轉成 reference、不被改寫。新舊並存。

理由：遷移是獨立的決定（要不要為 78 段各補一次擷取？補不到的怎麼辦？），與本變更的形狀設計無關。硬綁在一起會讓本變更無法在遷移策略定案前落地。

## Implementation Contract

### Behavior

- Person 與 Organization 記錄可攜帶 `references:` 頂層清單。既有記錄無此欄位，載入與寫回位元組不變。
- 每筆 reference 自報 `field:`（必要），指名它支持的欄位；欄位是 collection 時另帶 `value:` 定位。
- 擷取型 reference 必須有 `url` / `retrieved` / `content` / `status`；缺 `content` 拒收。
- 判斷型 reference 必須有 `judgement` 與 `rests-on`；帶 `content` 拒收。
- 存檔位元組寫入 `<store>/sources/<前2字元>/<其餘>`，無副檔名。
- 寫入存檔前驗證版控排除生效；未生效拒寫。
- reference 指名的 digest 若無對應存檔，載入照常成功，並以**與格式錯誤不同**的條件回報缺席。

### Interface / data shape

YAML 形狀（頂層，與 `key` / `names` / `profile` 同層）：

```yaml
references:
- field: orcid
  url: https://pub.orcid.org/v3.0/0000-0003-4038-9439
  retrieved: 2026-08-03
  status: 200
  media-type: application/json
  content: sha256:d1f446b3507bd24a...
- field: names
  value: "Chen, H-Y."
  judgement: 名冊內 Chen 姓且 given initials H-Y 唯一，與既有 pipeline 的縮寫配對一致
  rests-on:
  - sha256:9a23d701e4fe4888...
```

Swift 型別：新增 `ProvenanceReference`（於新檔），`Person` 與 `Organization` 各加 `references: [ProvenanceReference]`。編解碼沿用既有 `PersonYAML` / `OrganizationYAML` 的慣例：排序後輸出、未知欄位 tolerant-preserve、encode 後 canary 自檢。

`LibraryStore` 新增存檔的讀寫入口與排除驗證。

### Failure modes

| 情況 | 行為 |
|---|---|
| 擷取型缺 `content` | 拒絕載入，錯誤指名缺少的欄位 |
| 判斷型帶 `content` | 拒絕載入，錯誤說明判斷型無自身位元組 |
| `field` 指名記錄沒有的欄位 | 拒絕載入，錯誤指名該欄位 |
| `value` 在該 collection 內找不到 | 拒絕載入，錯誤同時指名欄位與值 |
| digest 無對應存檔 | **載入成功**，以獨立條件回報「內容未在本機」——這是預期狀態（存檔不進 remote，clone 後必然缺席），不是損毀 |
| 版控排除未生效 | 拒絕寫入存檔，錯誤說明排除未生效與如何修 |
| store 非 git repo | 跳過排除驗證，記錄跳過事實 |

刻意**不**沉默的：以上每一項都回報。刻意沉默的：無。

### Acceptance criteria

- 無 `references` 的既有記錄載入後寫回位元組相同
- 帶 `TemporalValue.source` 的記錄，該值原樣保留、未被轉成 reference
- 同一份位元組經兩次擷取，只有一份存檔、兩筆 reference 指向同一 digest
- 位元組相異的兩次擷取產生兩份存檔
- 上表七種失敗情況各有對應測試
- 存檔目錄在 store 的版控狀態中不出現
- 排除未生效時寫入被拒（以臨時 store 構造此情境測試）

### Scope boundaries

**In scope**：`ProvenanceReference` 型別與編解碼、`Person` / `Organization` 的欄位、存檔的讀寫與路徑規則、排除驗證、`ensureLayout()` 建立 `sources/` 與寫入排除規則、store-format 文件。

**Out of scope**：擷取行為本身、既有 `TemporalValue.source` 的遷移、`export-tables`、Entry（work）的 references、內容正規化、存檔的過期偵測與重新擷取、CLI 子命令。
