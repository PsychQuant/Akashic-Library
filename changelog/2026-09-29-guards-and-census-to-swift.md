# 2026-09-29 守衛與普查的 shell／Python 移植成 Swift（#629 第一塊）

`swift-is-the-implementation-language` 把 repo 裡成文前已存在的 shell／Python 領域邏輯逐檔列成〈既有檔〉，#629 追蹤把它們移植掉。
本輪是第一塊：**守衛** `plugin-store-format-parity`、`rule-coverage`、`review-claim-audit`，**promote-literals 那組**
（`literal-census.sh` 與守它的三支測試、生成器、生成表），以及開發用的 `scan-yaml-profile.py`。fetch-fulltext、`crossref_match.py`、
兩支 `ndjson-abstracts-to-proposals.py` 不在本輪。

**這一輪的處置有三種，不只「移植」**：

| 舊檔 | 處置 | 新的去處 |
|---|---|---|
| `plugin/tests/plugin-store-format-parity.py` | 移植 | `akashic-guards plugin-store-format-parity`（`PluginStoreFormatParity.swift`） |
| `plugin/tests/rule-coverage.sh` | 移植 | `akashic-guards rule-coverage [plugin-root]`（`RuleCoverage.swift`，呼叫形狀不變） |
| `plugin/skills/akashic-promote-literals/scripts/literal-census.sh`（598 行，573 行是內嵌 Python） | 移植 | `akashic literal-census`（`AkashicStoreIO/LiteralCensus.swift` ＋ `LiteralCensusCommand.swift`） |
| `scripts/scan-yaml-profile.py` | 移植 | `akashic scan-yaml-profile`（`AkashicCore/YAMLProfileScan.swift` ＋ `ScanYAMLProfileCommand.swift`） |
| `tests/store-marker-parity.sh`、`tests/hash-table-drift.sh`、`tests/multiscalar-parity.swift`、`tests/derive-hash-extenders.swift`、`hash-merging-ranges.txt`、`marker-parity-mutations`（harness ＋ 資料檔） | **退場**（受測的分岔不存在了） | 46 格矩陣留成 `StoreMarkerMatrixTests` |
| `literal-scalar-parity`（守衛，從 census.sh 抽 Python 函數來 spawn） | **變成測試** | `LiteralCensusTests.testScalarDecoderAgreesWithYams`，oracle 是 Yams |
| `plugin/tests/review-claim-audit.sh` | **退場**（九條 finding 的受測物全部不存在） | 逐條處置見下 |

## 為什麼 census 那一組是「退場」而不是「移植」

那四支測試守的是同一個命題：**census 自己用 Python 重寫的 marker 解析，和讀端（`StoreVersion.read`）有沒有分岔**。#407 的 R6～R18 有一半的輪次
花在這上面——列舉 Foundation 的 19 個空白 scalar、由 Swift 生成「`#` 後接 grapheme extender」的表再測表會不會漂移、證明「逐 code point 的表夠用」、
再用一支負控 harness 證明 46 格矩陣真的會紅。

census 現在是讀端同一個 binary 裡的子命令，marker 直接呼叫 `StoreVersion.read(root:)`，支援上限直接讀 `StoreVersion.supported`。**分岔不是被守衛擋住，是沒有第二份東西可以分岔**。
所以生成表、生成器、漂移守衛、多 scalar 序列證明、parity 測試、它的負控，全部沒有東西可以守；留著它們是「一支守著不存在的東西的守衛」。

隨之消失的還有 shell 版三層「支援上限的來源」（問 binary／讀 checkout 的原始碼／未知）與兩個狀態（`undecidable`：判註解用的表讀不到；`ceiling-unknown`），以及環境變數 `AKASHIC_BIN`、`AKASHIC_REPO`。
SKILL.md 那張 venue 輸出表因此少了兩列。

**矩陣本身留下來**（`Tests/AkashicKitTests/StoreMarkerMatrixTests.swift`，46 格）：它從來就不只是 parity 測試——每格帶著**預期裁決**，所以同時是讀端 grammar 的可否證規格
（全形數字是 malformed、`#` 後緊跟 combining mark 該行不是註解、U+200B 被 Foundation 的空白集 trim 掉、BOM 被吃掉…）。這些行為取決於 Swift／Unicode 版本，
作業系統更新讓某一格變了，這裡會紅——以前由 hash-table-drift 守著「表過期是安靜的」，現在由這裡守。每格同時斷言讀端的裁決、普查歸到的態、兩者一致。

## `review-claim-audit` 的九條逐條處置

它逐條重建 #407 R10 審查者宣稱的失敗情境（「一條 finding 若重建不出它宣稱的失敗，那條就是未經量測的」）。census 移植後，每一條的受測物：

| finding | 受測物 | 處置 |
|---|---|---|
| #3 sed `;/./q` 在前置雜訊下拿不到值（兩個 verdict） | shell 探測寫法——census.sh 早在 R17 就改成 Python subprocess，這兩個 verdict 是**與 repo 內任何東西無關的 bash 行為示範** | 退場（不守任何 repo 內的東西） |
| #7 5000 前導零 fixture 依賴 `seq`（三個 verdict） | `store-marker-parity.sh` 的 fixture；前兩個是 printf／seq 行為示範 | 退場（受測檔已刪） |
| #4 parity workflow 的 paths 漏掉生成表（兩個 verdict） | 生成表與 hash-table-drift step | 退場（兩者都不存在；workflow 的 paths 現在由 `trigger-coverage` 逐對量） |
| #9 `derive-hash-extenders.swift` 的 `--check` 是假接口（兩個 verdict） | 生成器 | 退場（檔案已刪） |

**這是一個判斷，不是機械結果**：它讓守衛清單少了一支，而它有一半的內容是對 bash 行為的示範（移植成 Swift 就是在 Swift 裡 spawn bash／sed／seq 去示範一個不再存在的 shell 慣用法）。
若使用者要保留「重建 finding」這個模式本身，另開的形狀應該是「對 repo 內**現存**受測物的重建」，不是保留這一支。

## 行為比對的證據

**每一個移植都在移除舊實作之前，用同一組輸入對舊與新各跑一次。** 差分腳本放在 scratch，沒有進 repo（一次性量測）。

- **`rule-coverage`**：26 個情境（乾淨樹、拿掉連結、token 是 `.bak`／別的檔名、目錄錯、結尾多一個句點／全形句號、只在 note.md 提到、多一個沒引用的 skill、SKILL.md 不見、`rules/` 不見、根不存在、0 個 skill、`skills/` 不見、隱藏規則檔、規則名是目錄、backtick／雙引號／括號三種包法…）×
  舊 shell 與新子命令：**rc 與（正規化過的）stdout 25 格逐位元相同**。唯一的差異是「`rules/` 一條 `.md` 都沒有」——shell 版是意外變紅（glob 沒命中時字面的 `*.md` 被當成一條叫 `*` 的規則），
  Swift 版空迴圈會直接印綠燈，所以顯式報「沒有東西可檢查」rc=1。**兩版都紅，原因不同**（空集合不得冒充通過）。
- **`plugin-store-format-parity`**：15 個情境（乾淨、plugin.json／mcpb 各自 bump、兩份都錯、宣告消失、`Store format N` 少句點、檔案不見、marketplace 條目帶 description、marketplace 不見／不是 JSON／沒有 `plugins`、`supported` 改名／多空白／bump）：**rc 的類別全部一致**，訊息只有措辭差異
  （「DECLARERS」→「宣告來源清單」；來源檔不存在時 Python 是 traceback、Swift 是具名的 rc=1）。
- **`literal-census`**：83 個 fixture（四域各種寫法、引號／跳脫／尾註、續行、legacy／混合佈局、隱藏檔與大小寫、CRLF、孤立 CR、BOM、壞 UTF-8、NFC／NFD、`work:` 後接組合符號、glob 特殊字元路徑、
  46 格 marker 矩陣、`chmod 000`、marker 是目錄、venue 三分支、exit 2／3）× 舊 shell 與新子命令：**逐行相同**，差異只有兩處刻意改寫的措辭（探測到的 binary 路徑；marker 問題行的說明）。
  真實 store（`~/.akashic`，唯讀）：兩版四行輸出逐字相同。
- **`scan-yaml-profile`**：29 個 fixture（每種 profile 外語法、顯式 core tag 與自訂 tag、anchor 在 tag 前後、`&amp;`、CRLF／BOM／NEL／tab／VT、多文件、壞檔、非 `.yaml`）＋真實 store：輸出相同，**除了一處刻意的差異**——見下。

## 刻意的行為差異（都在報告裡，沒有靜默的）

1. **`rule-coverage`**：零條規則 → 顯式紅（上）；輸出裡的 SKILL.md 路徑印成 `skills/<name>/SKILL.md`（shell 版因為 glob 尾斜線印成 `skills/<name>//SKILL.md`）。
2. **`literal-census`**：
   - 支援上限與 marker 一律由讀端判（上）——「超過你的 binary 支援上限」是確定的話；
   - 某個記錄檔讀不進來（權限、是目錄）：Python 版 traceback（rc=1），現在是具名的 exit 3「拒絕輸出計數」——**少算一個檔的普查與「查完歸零」無法區分**；
   - `\UXXXXXXXX` 超出 U+10FFFF：Python 版整支中止（ValueError），現在解成 U+FFFD——一筆惡意 literal 不該讓量測儀器倒掉；
   - 預設 store 由 `--library`／`$AKASHIC_LIBRARY`／registry 解析（與其他命令同），舊腳本預設 `~/.akashic`；
   - **繼承的怪癖，刻意不修**（各有釘住的測試）：檔首 BOM 讓 `work:` 前綴不成立、該檔不進任何計數；`- organization:` 項目終止 authors 區塊；空的 `affiliations:` 緊接兄弟鍵時區塊會吃到兄弟鍵之後；`# ` 註解只認空格（tab 不算）。它們是對 emitter 輸出的結構掃描的邊界，改它是語意變更，要另案裁決。
3. **`scan-yaml-profile`**：**parser 層改用 libyaml 的 event 流（store 讀端 Yams 用的那個 parser），不再是 PyYAML**。兩者對 anchor 與顯式 tag 同義，但對「什麼算 parse 失敗」偶有不同——實測 `a:\t1`（冒號後接 tab）PyYAML 是 ScannerError、
   libyaml 接受。ground truth 以讀端為準；也不再需要另外安裝 PyYAML。`--inspect` 的輸出順序不同（依檔案順序，不是先 anchor 後 inline comment）。
4. **`rule-prose-guards` 的第 6 項移除**：它數的兩個「會長的數字」（parity 的 fixture 格數、mutation 的個數）都是已退場物件的計數，plugin 規則檔自我量測表相應改成**不寫格數**的一列（沒有會長的數字，就沒有東西會過期）。其餘五項的編號不動。

## 測試與負控

**新增**：`LiteralCensusTests` 39 支、`StoreMarkerMatrixTests` 2 支（46 格）、`LiteralCensusCLITests` 4 支（真 binary：四域輸出與 `~` 縮寫、拒開的 store 掛警告仍 exit 0、exit 2、唯讀）、`YAMLProfileScanTests` 12 支。
期望值取自**移植前舊實作的輸出**，不是新實作自己說的話；純量解碼的 oracle 是 Yams。

**負控**（反向編輯實作 → 測試轉紅 → 還原並 `cmp` 確認逐位元組相同）：

| 改壞什麼 | 紅的測試 |
|---|---|
| 雙引號跳脫表少 `\_` | `testEveryDoubleQuotedEscapeAgreesWithYams`、`testScalarDecoderAgreesWithYams` |
| 不做 CR→LF 正規化 | `testCRLFAndLoneCRCountLikeLF` |
| 前綴比對退回 grapheme 層 | `testShapePrefixIsCodePointLevelNotGraphemeLevel` |
| marker `malformed` 一律當 `read(1)` | `StoreMarkerMatrixTests`（多格） |
| marker `unreadable` 當 `malformed` | `StoreMarkerMatrixTests` |
| 「未部署」門檻 11 → 10 | `testVenueNotDeployedIsNotZero` |
| org parents 終止條件改成任何字元 | `testOrganizationParentsBlockEndsAtTheNextLowercaseTopLevelKey`（第一次寫的版本**沒有紅**——fixture 的結果與真行為碰巧相同；改寫成 PL2 落在 `Next:` 與 `note:` 之間才鑑別得出來） |
| authors 區塊不吃續行 | `testContinuationLinesBelongToTheirItemAndBlocksStopAtTheNextKey` |
| `~` 縮寫退回裸前綴 | `testTildeShrinksOnlyAtPathBoundaries` |
| tooNew 不算「讀端會拒開」 | `LiteralCensusCLITests.testTooNewStorePrintsCountsWithAWarningAndStillExitsZero` |
| profile 掃描：空白類換成 ICU 的 | `testInlineCommentUsesPythonWhitespaceSemantics` |
| profile 掃描：顯式 core tag 判準拿掉 | `testParserLayerSeparatesAnchorsCustomTagsAndExplicitCoreTags` |
| profile 掃描：tag 先於 anchor 的判定 | 同上 |
| profile 掃描：深度不除以 2 | `testNestingDepthIsMaxLeadingSpacesOverTwoPerFile` |

**守衛的負控 harness**（`*-mutations`）：

- `audit-guards-mutations` 56/56（46 須紅 ＋ 8 須綠 ＋ 2 後設檢查）：移除 12 個 case（hash-table-drift 3、review-claim-audit 4、multiscalar 3、literal-scalar 2），
  新增 6 個 `plugin-store-format-parity`（唯一來源 bump 而宣告沒跟上、mcpb 出貨物被改、`Store format N.` 被拿掉、宣告來源檔不見、marketplace 條目帶 description、marketplace 不見），
  `rule-coverage` 的三個 case 改以子命令為受測對象（`withCopy` 補複製 `mcpb/manifest.json`）。**注入不寫死版號**（寫死就是第三份副本）：在 `supported` 或宣告的數字前塞一個 `9`。
- `trigger-coverage-mutations` 37/37：七個「注入守衛自己讀取形狀」的 case 與大部分宣告形狀的 case 把宿主從 `plugin-store-format-parity.py`／`review-claim-audit.sh`／`rule-coverage.sh`
  換成 `PluginStoreFormatParity.swift`／`RuleCoverage.swift`（被測的是 `trigger-coverage` 對路徑字面、probe token、宣告樣式的**文字層**判斷，與宿主語言無關）。
  **兩個 case 的預期文字放寬**：「從守衛清單拿掉一支守衛」原本只會多一條 pre-push 的缺口（那支守衛另被 workflow 的獨立 step 直接執行）；現在所有守衛都只經 `run-guards.sh`，拿掉那一行兩邊都不跑，
  它讀的每個受保護檔多一條「不在任何 CI workflow 跑」——是同一個注入的後果，共同前綴是「守衛名 ＋ 不在」。
- `rule-prose-guards-mutations` 15/15、`plugin-roots-mutations` 11/11（`rule-coverage` 的呼叫改為子命令）、`oracle-precondition-control` 兩個自檢都乾淨降級。
- `migrated-guard-control`：「實際在跑」的抽取式**允許縮排**——`rule-coverage` 在 `run-guards.sh` 裡是迴圈內逐根呼叫，行首有縮排，只認行首的版本會讓它「實際在跑卻不在被檢查的名單裡」（這支守衛要防的正是那個形狀）；同一支守衛在多處被呼叫時去重再數。

## 受保護清單與棘輪

`.githooks/protected-ratchet.txt` 71 → 61：

- 移除 12：`plugin/tests/{plugin-store-format-parity.py,review-claim-audit.sh,rule-coverage.sh}`、promote-literals 的 `literal-census.sh`、`hash-merging-ranges.txt`、`tests/{derive-hash-extenders.swift,hash-table-drift.sh,multiscalar-parity.swift,store-marker-parity.sh}`、
  `Sources/akashic-guards/{LiteralScalarParity,MarkerParityMutations,MarkerParityMutationsData}.swift`。
- 新增 2：`Sources/akashic-guards/{PluginStoreFormatParity,RuleCoverage}.swift`（依檔名規則自動受保護；`main.swift` 的 dispatch 有對應 `case`）。
- `ProtectedInventory` 的 `GENERATORS` 集合（排除 `derive-hash-extenders.swift`）與三條 census 的 DATA 顯式條目一併移除。

## 規則與文件

- `swift-is-the-implementation-language`：〈既有檔〉shell 七個 → 二個、Python 十一個 → 九個，加一段「已移植」的處置說明；語言組成重量。
- `mcp-cli-parity`：CLI-only 表加兩列——`literal-census`（候補缺席：唯讀量測，唯一消費流程是 skill 在 shell 裡呼叫 CLI；與 `akashic_doctor` 口徑不同且要能對讀端拒開的 store 出數字）、
  `scan-yaml-profile`（有理由缺席：repo 開發者重測 #33 決策的證據工具）。`WriteGateRulings` 兩格（都是不寫 store）。
- `zero-instance-guards`：第 21 列同形先例那句註明 hash-table-drift 已退場；量測段補 2026-09-29 的重量（61／18／43）。
- plugin：`akashic-promote-literals/SKILL.md` census 步驟改呼叫 `akashic literal-census`、venue 輸出表少兩列；`plugin/rules/assertions-must-be-measured.md` 的自我量測表兩列 ↗ 改成一列不寫格數、
  實例修復史補「第四次」；`plugin/CHANGELOG.md` 加一則使用者可見的改變（`AKASHIC_BIN`／`AKASHIC_REPO` 不再有作用）。
- `census-parity.yml`：三個 parity step 與三條 census 路徑移除（名字是歷史的，檔頭寫明；改名牽動面太廣另案）；`ci.yml` 的「Plugin parity 守衛」step 移除。
- CLAUDE.md：pre-push 耗時段加一則更正（描述的 `marker-parity-mutations` 已退場，原文保留為當時的量測記錄）。
- `openspec/specs/plugin-root-guard-coverage/spec.md`：一句 SHALL 的主詞從腳本改成子命令。

## 誠實邊界

- **普查的計數仍是文字層的結構掃描**（不經 loader），沒有改成用 Yams 解整份檔——那是語意變更（壞檔的處理、legacy 佈局、`entries/` 無形狀前綴）。上面「繼承的怪癖」是這個選擇的代價，各有測試釘住。
- 純量解碼與真 YAML 的對照只涵蓋單行純量的列舉寫法（十五種＋雙引號跳脫表逐字元）；區塊／摺疊純量不在內，與舊守衛同。
- `TriggerCoverageMutationsData` 的三個 absence-probe case 刻意保留 Python 形狀（`os.path.exists(`、`).exists()` 後綴）——那兩個 token 仍在 `PROBE_PREFIXES`／後綴清單裡，樹裡還有 Python 守衛；最後一支 Python 守衛退場時要一起處理。
- **這一輪沒有重跑 fetch-fulltext 的校準數字**（own 22/28、wrong 0/808）——那是下一塊的範圍。
- 差分腳本沒有進 repo：它們是移植當下的一次性證據；要重現，行為的規格在上面的測試裡。
