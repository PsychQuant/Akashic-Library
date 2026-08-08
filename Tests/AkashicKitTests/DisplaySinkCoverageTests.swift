import XCTest
@testable import AkashicSQLite
import Foundation
@testable import AkashicCore

/// #28：**sink coverage 的機械守衛**。
///
/// 為什麼是掃原始碼而不是跑功能：`displaySafe` 的問題從來不是它本身有 bug，而是
/// **有人新增了一條沒接上它的輸出路徑**。#23 的 R11 → R12 → R13 三輪都在憑記憶補
/// sink、三輪都漏——漏的還一次比一次常用（第三輪漏的是 `akashic query`）。記憶枚舉
/// 贏不了「每次改動都可能新增一條路徑」，所以判準必須機械化。
///
/// 判準：CLI / MCP 的原始碼裡，任何把 **store 衍生字串**插值進輸出的位置，該表達式
/// 必須含 `displaySafe(`。要例外就在同一行寫 `// display-safe-exempt: <理由>`——
/// 逼人講出理由，而不是安靜跳過。
///
/// ## 守衛的涵蓋邊界（#141——誠實記錄「行級文字掃描」照不到的形狀）
///
/// 這是**行級的文字啟發式**，不是型別感知的資料流分析。以下形狀結構性地在它的
/// 視野外，靠人工 + 功能測試釘住，不是它的失效：
///
/// - **bare 變數名**（含 `$0` 的 `.map { }`。#156 verify 156-3：原本這裡寫「最大宗」，
///   但四類的相對量**從來沒有人量過**——盲點依定義是守衛看不到的東西，數不出來。
///   宣稱已撤下，不改成另一個同樣沒支撐的排序）。
///
///   **這個盲區在 #141 的量測中造成了一次真實的洩漏**：`AkashicService.swift` 的
///   `["literal": literal, …]`——`literal` 是 Zotero 匯入的作者原字串（第三方最直接
///   的來源），裸送進 MCP 回應。守衛看不到，因為 token 是 `.literal`（帶點）而這裡
///   是裸變數名；同一個回應裡上面兩行的 `person_key` 卻有消毒。**它是人工比對發現
///   的，不是守衛抓到的，而且修好之後守衛依然看不見**（拔掉 displaySafe 仍全綠）。
///   這條記在這裡，是為了讓「守衛全綠」永遠不被讀成「這一面已經安全」。
///
///   **第二次同型**（#156 verify 156-15）：`summaryDict` 的 `journal` 裸送進 MCP
///   回應，而同一個檔案的 `entryDict` 註解自己寫著「fields 值是 biblatex 第三方
///   內容（journal、booktitle…）——**與 title 同源**」並在那裡消毒了。同樣是裸
///   變數名（`journal` 不含任何 token），同樣是人工比對發現的。兩次都是「同一份
///   資料在同一個檔案裡兩種待遇」——那個不一致本身比守衛更早發現問題。
///
///   `load.residue.map { $0 }` 的 `$0` 不含
///   任何 tainted token，token 判準對它結構性失效。
///
///   **「差額多是這一類」已撤下**（#156 verify R2 實測推翻）：全掃描面 210 個含
///   `displaySafe(` 的行裡守衛只認 67（recall 31%），143 條未見行的分類是——
///   **沒被認成 sink 行 82**（其中 70 條是真的輸出行，多為多行字串串接的續行）、
///   bare-`$0` **32**、其他 token 未命中 23、`case ` 豁免 2、exempt 標記 4。
///   也就是說最大宗是 **sink 辨識失敗（≈49%）**，不是 bare-`$0`（22%）。
///   （單檔基準：`AkashicService` 的 `grep -c 'displaySafe('` = 75、守衛認 38，
///   2026-08-07 自量。）補 bare-`$0` 需要
///   element-type 或 receiver 上下文（`.map` 的來源是誰），不是另一條行級 regex。
/// - **key-family accessor**（`$0.key`/`p.key`/`lib.key`/`$0.path`）：`key` 不在
///   `taintedTokens`（只有 `citekey`/`personKey`/`libraryKey`）——因為 `key` 也是
///   大量 registry/config 常量 key 的名字，無腦入清單會誤中一片。
/// - **跨行 throw**：`throw StoreYAMLError.invalidField(` 在 N 行、payload 內插在
///   N+1 行——行級掃描看不到 N+1 行的 sink。約 50 個 StoreYAMLError 站點屬此，
///   靠輸出端 sink 兜底（#149 verify F5）。
/// - **switch `case` 短變數值**：`case .literal(let s): return ["literal": s]` 的
///   `s` 是短名、不含 token——那類站點靠人工消毒 + 功能測試。
///
/// ### 試過並撤回：dict 內部一致性判準（#164 第四方向）
///
/// 三次真洩漏是同一形狀——同一個 dict、相鄰位置、一個包了一個沒包（`literal` vs
/// `person_key`／`journal` vs `title`／`tags` vs `citekey`）。看起來是一條不需要
/// taint 分析的好判準：「同一組值裡若有人消毒了，其餘字串值都必須有」。
///
/// **實作並量測後撤回**，兩種範圍都不行：
///
/// | 範圍 | 命中 | 真的 | 對三次歷史洩漏的 recall |
/// |---|---|---|---|
/// | 行內（同一行的 dict 值） | 4 | 1 | **0/3** |
/// | 函式內（跨行、跨 `append`） | 47 | ~3（6%） | 3/3 |
///
/// **行內版的致命傷不是低 recall，是它的偵測依賴排版**：它唯一抓到的那條
/// （`summaryDict` 的 `s.type`），在我為它加註解而把兩個 dict entry 拆成不同行之後
/// **就再也抓不到了**。一個「偵測力取決於兩個 entry 恰好在同一行」的守衛不是守衛
/// ——那正是 #162 記載的「消毒分佈跟著行寬走」的反面。
///
/// **函式版的 94% 誤中**則重演 156-14 的教訓：為了提高 recall 而放寬形狀規則，換來
/// 一批需要 exempt 的誤中，而反射性加 exempt 比沒有守衛更糟。
///
/// **但函式版當一次性稽核工具有用**：那 47 條裡我挑出 3 個真的
/// （`QueryCommands` 的 `summary.type`、`root.path` ×2）。
///
/// **那個「3 個」是錯的**（#171 verify 171-5）：獨立的一輪把同一批重過一遍，另外
/// 找到 4 條——`Provenance.zoteroKey`、`Relations.cites/related`（兩個吐出點）、
/// `addPerson` 回吐的 `names`、`ImportReport.droppedFields` 的 key，前三條有行為
/// 證明（raw U+202E 抵達 tool result）。全部已修。
///
/// 這個更正本身是本段最重要的內容：**「稽核跑過了」不等於「稽核跑完了」**，而
/// 寫下的量測數字會被日後的人讀成「這一輪已經清乾淨」。誰都可以漏——包括剛剛
/// 論證完這種漏法長什麼樣的人。這是「掃出來人工過一遍」的價值，不是 CI gate 的
/// 價值；兩者不該混淆，而人工那一遍的 recall 也不該被寫成確定數字。
///
/// **`testGuardCatchesStrippedSanitisation`（#141）是對這個侷限的補償**：它不宣稱
/// 守衛涵蓋每條路徑，而是量測「守衛確實在看真實的消毒站點」——拔光 displaySafe
/// 後守衛必須報大量違規（實測 78）。守衛退化成空洞會讓那個下限失守。完整的
/// 型別感知覆蓋屬另案（需要 SwiftSyntax 級的分析，非本測試的體量）。
final class DisplaySinkCoverageTests: XCTestCase {

    /// store 衍生（＝可能來自別的 binary / 別人 / Zotero 匯入的第三方內容）的識別字。
    /// `authors` 在列：entries 來自 `import-zotero`，而 Zotero 的資料來自出版商與網頁
    /// ——那不是使用者自撰內容。
    private let taintedTokens = [
        "citekey", ".title", ".name", ".reason", ".file",
        ".literal", "personKey", "libraryKey", "authors",
        // #76：divergence 的未信任內容（#133 起可由 LLM 經 MCP 寫入——來源面擴大）
        ".question", ".judgement", ".statement", "restsOn",
        // #141 第 3 項（「key 該不該入清單」）**實測後入列**。issue 當時擔心
        // 「`key` 全下會誤中大量 registry/config key」——那個顧慮對**裸** `key`
        // 成立，對 `.key` 不成立：加了點之後 `d["some-key"]` 這種常量不會命中。
        // **正常掃描**只新增 4 條（3 條 dict 查找 + 1 條 MCP 回應的真不一致，
        // 後者已於 `bcd46d4` 修掉）；strip-all 面則 +11（78→89）。兩個量差 3.5 倍，
        // 所以要說清楚是哪一種掃描（#156 verify R3 的精確化建議）。
        //
        // 那 3 條 dict 查找**用具名 exempt 處理，不用形狀規則**（#156 verify 156-14）：
        // 我曾加過 `if expr.contains("[") && expr.contains("] ?? ") { continue }`，
        // 席位實測它是個洞——判準取的是**查找的形狀**，而風險在**值的型別**，形狀
        // 決定不了型別。守衛沒有型別資訊，分不出 `?? 0` 與 `?? entry.title`：
        //
        //     放過  titles[lib.key] ?? entry.title      ← fallback 就是 store 內容
        //     放過  names[personKey] ?? "(無)"           ← 值型別是字串
        //     放過  entry.title.isEmpty ? alt[0] ?? "" : entry.title   ← **共現洞**：
        //           整條只要「某處」含 `[…] ?? ` 就整條豁免，即使 tainted 的部分
        //           與那個查找毫無關係
        //
        // 而且它正是 156-7 標記的那一類（為降 false positive 加的形狀規則），逐軸
        // 計數偵測不到——加了它總數只掉 3，四軸全在 floor 上。用 3 條具名 exempt
        // 換掉：理由進 git、可稽核、零洞。
        ".key",
    ]

    /// 掃描範圍是**封閉列舉**（見 `scannedDirs` 與下方兩個個別加入的路徑），不是
    /// 「使用者看得到輸出的各層」——那個說法在 #158 第一版寫過，是**假的**，這裡
    /// 記著避免再寫回去。
    ///
    /// **含 `AkashicAppKit`**（#155）：App 的 error 型別（Adjudication／AppState／
    /// FileWatcher）同樣 echo store 衍生值，威脅模型比 MCP-直達-LLM 弱（顯示在
    /// SwiftUI 而非灌進 context），但同 bug class。
    ///
    /// **不含 `AkashicApp/Sources/`——那才是真正的使用者顯示層，而且有 10 處裸綁**
    /// （#158 verify 158-1 實測）。它是 XcodeGen 專案、不是 SwiftPM target
    /// （`Package.swift` 對它零引用，`swift build` 從不編譯它）。把它加進掃描清單
    /// **也照樣零違規**——因為 `isSink` 只認 `print(` / `jsonString(` / `d["` /
    /// `result["` / `": ` / `return "` / `FileHandle.standard`，SwiftUI 的 `Text(` /
    /// `Label(` / `Button(` / `.alert(` 一個都不在裡面。加目錄不等於加保護。
    ///
    /// 舊註解說 App 層「走型別投影（`displayFile` 等）由 `AkashicAppKit` 的
    /// `public extension` 保證」——**那也是假的**：`ResolutionCandidate` 根本沒有
    /// `displayLiteral` / `displayPersonKey`，`AdjudicationViews.swift:20` 就裸綁著
    /// 這兩個（而 21 行用的是消毒過的 `displayCitekey`）。兩個版本的說法都不成立，
    /// 差別只在錯的方向。真正的處置是 follow-up issue，不是換一句好聽的註解。
    ///
    /// **App target 未編不影響本守衛**——它掃的是原始碼文字，不需要能執行 App。
    /// **掃描面用「枚舉 `Sources/` + 顯式 opt-out」，不是手寫白名單**
    /// （#158 verify 158-3b）。
    ///
    /// 手寫清單有三個靜默失效路徑，實測全部成立：
    ///
    /// | 洞 | 手寫清單 | 枚舉 + opt-out |
    /// |---|---|---|
    /// | 打錯字（`AkashicAppKitTYPO`）| `try?` 貢獻 0 檔、不報錯 | 目錄還在 `Sources/` → 自動掃回來 |
    /// | **刪掉一項** | 清單與斷言讀同一份常數，一起縮，測試無感 | 同上 |
    /// | 新模組沒人加進清單 | 完全開放 | 自動被掃 |
    ///
    /// 第二項是 R2 席位的實測：刪掉 `Sources/AkashicAppKit` **並且**同時放回一條
    /// 真的未消毒輸出 → 全套仍綠。第一版的逐項非空斷言只 pin「宣稱掃的目錄都
    /// 存在」，membership 軸還是 tautology——入口從 typo 換成 deletion。
    ///
    /// 要排除必須寫進 `optOut` **並給理由**，跟 `display-safe-exempt` 同一個哲學：
    /// 逼人講出理由，而不是安靜跳過。
    /// **理由必須是可否證的陳述，而且量詞要附上能驗它的 grep**（#158 verify R3／R4）。
    ///
    /// R3 把「讀起來合理但沒人能檢查」的理由換成可否證的；R4 證明**可否證性起作用了**
    /// ——席位用 `grep` 就把新寫的三條全部打臉，而**三條全部栽在量詞上**（「唯二」
    /// 講的是別的模組、「同上」繼承了對自己為假的字面、「6 條」實際是 4 行）。
    ///
    /// 兩個教訓：
    /// 1. **「同上」繼承的是字面、不是意圖**——兩條 import 模組的理由改成各自為真。
    /// 2. **理由裡出現量詞（零／唯一／唯二／全部／只有）時，要給「跑什麼會看到
    ///    什麼」**——不只是行號。R4 的三次打臉都只需要一行 `grep -c`；而 R4 之後
    ///    席位又指出：WoS 那條的「唯二」當時只給了行號、**沒給能證明只有兩條的
    ///    指令**。行號證明「這兩條存在」，證明不了「沒有第三條」。
    ///
    /// R4 另外收回了「opt-out 模組不得含 `LocalizedError`」這個機械檢查的提案——
    /// 它是**用形式當性質的 proxy**（正是 `common-spec-prose-enumeration` 要防的）：
    /// 它會因為 `SQLiteError` 存在而擋下 `AkashicSQLite`，但擋的理由是錯的，真正的
    /// 問題是 `bindFailed` 的 caller payload 與跨模組 SQL 不變式——兩個都不是
    /// 「有沒有 LocalizedError」看得出來的。用錯的 proxy 擋對的東西，下次 proxy
    /// 不成立時就靜默放行。
    ///
    /// **（歷史）R3 的三條假理由**——「無使用者可見輸出面」這種
    /// 讀起來合理但沒人能檢查的句子不算。R3 席位實測：第一版 7 條裡 **3 條是假的**，
    /// 而且錯的兩條正是我自己心虛、特地請席位攻擊的那兩條：
    ///
    /// - `AkashicExport`「不是終端輸出；跳脫由 biblatex 層負責」——**兩個子句都假**。
    ///   `akashic export-bib` 預設印到 stdout、MCP `akashic_export` 把 .bib 全文當
    ///   tool result 回 LLM（最強威脅模型）；而 biblatex 跳脫的是 TeX specials
    ///   （`{}`／`\`／`%`／`&`），**不是** C0／bidi／LS-PS。席位探針實測：raw ESC
    ///   與 U+202E 都原樣通過。已移出 opt-out，leak 另開 issue。
    /// - `AkashicIndex`「只寫 SQLite」——假。`IndexError.rootNotALibrary` 是
    ///   `LocalizedError` 且**它自己就包了 `displaySafe`**（寫的人知道那是輸出面）。
    ///   opt-out 把那條的回歸保護整個拆掉（席位 mutation 實測綠）。已移出。
    /// - `AkashicSQLite`「無使用者可見輸出面」——結論對、**理由錯**。它有 4 個
    ///   `SQLiteError` case、6 條 caseReturn。正確理由是 #155 issue 自己寫的那句。
    ///   差別不是措辭：「無輸出面」＝以後沒人需要回來看；「有輸出面但目前不含
    ///   caller payload」＝以後有人往裡面塞 `citekey` 時理由當場失效、會被發現。
    /// SwiftUI 的輸出面（#161）。
    ///
    /// **這是封閉列舉，不得依性質相似類推。** 判準是「這個 API 會把字串**畫到
    /// 螢幕上**」，而不是「它是 SwiftUI 的 API」——`.onChange(`、`.task(`、
    /// `.id(` 收字串但不顯示，加進來只會製造誤中。
    ///
    /// 為什麼守衛先前對 App 層**結構上全盲**：`isSink` 只認 `print(` /
    /// `jsonString(` / `d["` / `": ` / `return "` / `FileHandle.standard`，
    /// 上面一個都不在。#158 verify 實測：把 `AkashicApp/Sources` 加進掃描目錄
    /// → 三條全綠。**加目錄不等於加保護**，判準要一起改。
    ///
    /// 對照組同時證明目錄讀得到：同目錄插一條 `return "probe \(citekey)"`
    /// 立刻被報出來——所以綠不是 `try?` 吞掉，是判準看不見那些形狀。
    /// 一行是不是**顯示 sink**。
    ///
    /// **抽成函式而不是留在掃描迴圈裡**（#161）：留在迴圈裡就只能靠「掃真實
    /// 原始碼有沒有報東西」間接驗，而修好之後那個訊號恆為零——mutation 實測
    /// 拿掉 SwiftUI 那條 disjunct，六條全綠。**綠證明不了偵測有在看。**
    /// 抽出來之後可以直接餵合成的行進去，那才咬得住。
    static func isDisplaySink(_ l: String) -> Bool {
        l.contains("print(") || l.contains("jsonString(")
            || l.contains("d[\"") || l.contains("result[\"") || l.contains("\": ")
            || l.contains("return \"") || l.contains("FileHandle.standard")
            || swiftUISinks.contains(where: { l.contains($0) })
    }

    /// 一行是不是 **error sink**（payload 最終進 `errorDescription` → 使用者可見）。
    ///
    /// 與 `isDisplaySink` 分開，因為**後續處理不同**：error sink 跳過 token 清單
    /// （payload 常是 `k` / `w.key` 這種短的局部變數名，清單抓不到），普通 sink 不跳。
    /// 續行必須繼承正確的那一種——第一版把續行一律當普通 sink，實測**零命中**，
    /// 而 #162 量到 56 個。判準對了種類錯了，症狀與判準沒改一模一樣。
    /// **型別感知**（#162）。三種 error 型別有三種**明寫的**政策，先前守衛對三者
    /// 一視同仁，於是對其中兩種要求了架構明確拒絕的東西：
    ///
    /// | 型別 | `errorDescription` 消毒 payload？ | throw 站點要消毒？ |
    /// |---|---|---|
    /// | `StoreIOError` | ✅ 是（`invalidInput` 對 what/why 都包） | ❌ **不要**——會雙重跳脫 |
    /// | `StoreYAMLError` | ❌ 否（自帶 exempt 註解說明策略是 sink-side） | ❌ 由輸出端 sink |
    /// | `ServiceError` | ❌ `.invalid` 直接回 `why` | ✅ 要 |
    /// | `StoreVersionError` | ❌ 否（`path`／`line` 原樣內插） | ✅ 要 |
    ///
    /// **這不是放寬，是修正歸屬。** 先前的守衛只看得見單行 throw，於是它對
    /// `StoreYAMLError` 的要求落在「訊息短到放得下一行」這個與威脅無關的子集上——
    /// `YAML.swift` 相鄰兩個 `if` 對同一個變數 `k` 做出兩個不同決定就是證據。
    /// 加上續行偵測之後那個要求會擴張到約 90 個站點，而它們的策略本來就是 sink-side。
    ///
    /// **真正缺的是 sink，不是那 90 個站點的消毒**：`akashic-mcp/Server.swift` 的
    /// per-tool 錯誤出口先前**沒有**消毒（CLI 早就有單一出口了，MCP 從沒拿到同樣
    /// 處置），於是那 90 個站點的 payload 逐字進 LLM context。本 change 補上它。
    static func isErrorSinkLine(_ l: String) -> Bool {
        // `StoreYAMLError` / `StoreIOError` **不列入**——見上表。
        //
        // **`StoreVersionError` 要列入**（#162 verify 182-2）：它的
        // `errorDescription` 把 `path` 與 `line` **原樣內插、不消毒**，真正保護它
        // 的是 throw 站點的 `displaySafe`——政策與 `ServiceError` 同一列。第一版
        // 把四種縮成一種時把它一起丟了，席位用合成 throw 站點證明：本 PR 版**漏掉**、
        // 加回來**抓到**。縮小丟掉的不是現存站點，是對**新**站點的防護。
        l.contains("throw ServiceError") || l.contains("throw StoreVersionError")
    }

    enum SinkKind { case display, error }

    static func parenBalance(_ l: String) -> Int {
        l.filter { $0 == "(" }.count - l.filter { $0 == ")" }.count
    }
    static func opensMoreThanCloses(_ l: String) -> Bool { parenBalance(l) > 0 }

    /// 每一行是不是某個**尚未收尾的 sink** 的續行，是的話屬哪一種（#162）。
    ///
    /// sink 標記在 N 行、payload 內插在 N+1 行時，行級掃描完全看不到。實測掃描面上
    /// 有 56 個這樣的位置，而且**消毒的分佈跟著行寬走、不跟著威脅走**——`YAML.swift`
    /// 相鄰兩個 `if` 對同一個變數 `k` 做了兩個不同決定：訊息長要折行的那個沒包、
    /// 單行放得下的那個包了。同一個作者、相鄰兩行。
    ///
    /// 修法是**擴充判準**，不是遷就判準把程式碼改成單行——後者把判準的實作細節變成
    /// 全 repo 的 coding rule，而它沒有 enforcement、違反時靜默（#155 對 `FileWatcher`
    /// 就是那樣處置的，不可規模化）。
    ///
    /// **前向追蹤括號深度，不是回看一行**：一層回看漏掉 payload 在第三行以上的形狀
    /// （`Provenance.swift` 的 `\(v)` 就是——`throw` 在 N、`\(r.field)` 在 N+1、
    /// `\(v)` 在 N+2）。
    ///
    /// **誠實邊界**：字串字面量裡的括號會混淆深度計算。誤判成續行只是多掃幾行
    /// （多出來的誤中要寫 exempt），誤判成非續行才會漏——偏誤在安全的一邊。
    ///
    /// **實測誤判 0/15006**（#162 verify）：把每一行的字串字面量整段抹掉後重跑
    /// 分類器，**0 行分類改變**。134 行被判為續行，其中 16 行含插值；最長的續行
    /// run 是 3 段 ≥ 6 行，全部落在真正的多行 `jsonString(` 內。這比抽象的警語有用
    /// ——那句誠實邊界在原理上對，在這份 codebase 上目前無影響。
    static func continuationKinds(_ lines: [String]) -> [SinkKind?] {
        var out = [SinkKind?](repeating: nil, count: lines.count)
        var open: SinkKind? = nil
        var depth = 0
        for (i, raw) in lines.enumerated() {
            let l = raw.trimmingCharacters(in: .whitespaces)
            if l.hasPrefix("//") { continue }
            if open != nil {
                out[i] = open
                depth += parenBalance(raw)
                if depth <= 0 { open = nil; depth = 0 }
                continue
            }
            let kind: SinkKind? = isErrorSinkLine(raw) ? .error
                : (isDisplaySink(raw) ? .display : nil)
            if let kind, parenBalance(raw) > 0 {
                open = kind
                depth = parenBalance(raw)
            }
        }
        return out
    }
    static let swiftUISinks = [
        "Text(", "Label(", "LabeledContent(", "Button(",
        "ContentUnavailableView(", ".navigationTitle(", ".alert(",
        ".help(", ".confirmationDialog(",
    ]

    static let optOut: [String: String] = [
        "AkashicTestGuard": "test-only target（Package.swift 只被 .testTarget 依賴），不進 release binary",
        "AkashicTestGuardLoader": "同上：test-only target，不進 release binary",
        // #158 verify R4：**理由裡的量詞是最容易被打臉的部分**，所以附上能驗它的
        // grep。上一版寫「全模組零 print(／return \"／throw；唯二的 return \" 是
        // dedup key 構造」——前半對 Zotero 為真，但那「唯二」講的是 **WoS** 的程式碼，
        // 而 WoS 的「同上」因此繼承了一句對它為假的陳述。「同上」繼承的是**字面**、
        // 不是**意圖**，兩條都改成對自己為真。
        "AkashicZoteroImport":
            "零輸出面：`grep -c 'print(\\|return \"\\|throw ' Sources/AkashicZoteroImport/*.swift` = 0",
        "AkashicWoSImport":
            "`grep -c 'return \"' Sources/AkashicWoSImport/*.swift` = 2，兩條都是 dedup key "
            + "構造（`\"doi:…\"` 與 `\"ty:…\"`，回傳值只進 identity(_:) 的 Dictionary 鍵、"
            + "不進輸出）；`grep -c 'print(\\|throw '` = 0",
    ]

    /// **不得 opt-out、且必須真的在掃描面裡**的模組。兩個條件用同一份清單
    /// （#158 verify R3-4——分成兩份時差集會靜默漏掉）。
    static let mustScan = ["AkashicCore", "AkashicStoreIO", "AkashicEntity",
                           "akashic", "akashic-mcp", "AkashicMCPKit",
                           "AkashicQuery", "AkashicGraph", "AkashicAppKit",
                           "AkashicExport", "AkashicIndex", "AkashicSQLite"]

    /// 實際被掃的模組目錄 = `Sources/` 底下全部，減去 `optOut`。
    ///
    /// **只掃各模組頂層**（#158 verify R3 的 158-5 升級）：`contentsOfDirectory` 非
    /// 遞迴，`Sources/AkashicCore/Sub/Probe.swift` 這種巢狀檔案**掃不到**（席位實測
    /// 放一條未消毒輸出進去 → 全綠）。SwiftPM 完全支援巢狀 source 目錄，所以
    /// 「= `Sources/` 底下全部」這句在**檔案**層級是假的——寫在這裡以免被誤讀。
    /// 改用 `enumerator(at:)` 屬另案（#162 家族）。
    static func scannedDirs(repoRoot: URL) -> [String] {
        let sources = repoRoot.appendingPathComponent("Sources")
        let all = (try? FileManager.default.contentsOfDirectory(
            at: sources, includingPropertiesForKeys: [.isDirectoryKey]))?
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map(\.lastPathComponent).sorted() ?? []
        // **`AkashicApp/Sources` 明列在此**（#161）：它不在 `Sources/` 底下
        // （XcodeGen 專案，`Package.swift` 對它零引用、`swift build` 從不編譯），
        // 所以枚舉 `Sources/` 永遠掃不到它。而它正是**真正的 SwiftUI 顯示層**——
        // `Sources/AkashicAppKit` 只差三個字，是 error 型別所在的 library。
        //
        // 明列的代價是它回到「手寫清單」的失效模式（目錄改名 → 靜默不掃）。
        // 由 `testAppSourcesAreActuallyScanned` 釘住：那個目錄必須存在且有 .swift。
        return all.filter { optOut[$0] == nil }.map { "Sources/\($0)" } + ["AkashicApp/Sources"]
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AkashicKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    private var scannedFiles: [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for dir in Self.scannedDirs(repoRoot: repoRoot) {
            let d = repoRoot.appendingPathComponent(dir)
            if let files = try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil) {
                out += files.filter { $0.pathExtension == "swift" }
            }
        }
        return out
    }

    /// 抓出一行裡所有 `\( … )` 插值的內容（括號配對，處理巢狀）。
    private func interpolations(in line: String) -> [String] {
        var out: [String] = []
        let chars = Array(line)
        var i = 0
        while i < chars.count - 1 {
            if chars[i] == "\\" && chars[i + 1] == "(" {
                var depth = 0
                var j = i + 1
                var buf = ""
                while j < chars.count {
                    if chars[j] == "(" { depth += 1; if depth == 1 { j += 1; continue } }
                    if chars[j] == ")" { depth -= 1; if depth == 0 { break } }
                    buf.append(chars[j])
                    j += 1
                }
                out.append(buf)
                i = j
            }
            i += 1
        }
        return out
    }

    /// 抓出一行裡所有 `"key": <value>` 字典值表達式（#138 verify F2）。
    ///
    /// **插值不是唯一的 sink 形狀。** MCP 面的輸出走 JSON dict——值是裸表達式、
    /// 不經 `\( … )`，只掃插值的守衛對它整面全盲（mutation 實測：拔掉
    /// `displaySafe` 後 U+202E 逐字回流 LLM）。值的邊界用括號深度感知的逗號
    /// 切分——`displaySafe($0.file, max: 300)` 內部的逗號不是邊界。
    ///
    /// `AkashicApp/Sources` 是**明列**進掃描面的（它不在 `Sources/` 底下），
    /// 所以它回到手寫清單的失效模式：目錄改名或搬走 → `try?` 貢獻 0 檔、靜默不掃。
    ///
    /// 這條把那個洞釘住——**兩件事都要驗**：目錄有 .swift 檔（不然掃了等於沒掃），
    /// 以及**判準真的看得見那裡的形狀**（#161 的教訓：#158 曾把目錄加進去而三條
    /// 全綠，因為 `isSink` 認不得 `Text(` / `Label(`。**加目錄不等於加保護**）。
    func testAppSourcesAreActuallyScannedAndSwiftUIShapesAreVisible() throws {
        let appDir = repoRoot.appendingPathComponent("AkashicApp/Sources")
        let files = (try? FileManager.default.contentsOfDirectory(at: appDir,
                                                                  includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "swift" } ?? []
        XCTAssertFalse(files.isEmpty,
                       "AkashicApp/Sources 沒有 .swift——目錄改名了？掃描面靜默失效")
        XCTAssertTrue(Self.scannedDirs(repoRoot: repoRoot).contains("AkashicApp/Sources"),
                      "App 顯示層必須在掃描面內")

        // **判準要直接餵行進去驗**，不能靠「掃真實原始碼有沒有報東西」——修好
        // 之後那個訊號恆為零（mutation 實測：拿掉 SwiftUI 判準六條全綠）。
        for sink in Self.swiftUISinks {
            XCTAssertTrue(Self.isDisplaySink("            \(sink)entry.title)"),
                          "SwiftUI sink「\(sink)」認不得——那條路徑上的裸綁會全部漏掉")
        }
        // 反面：收字串但**不顯示**的 API 不得誤中（那會製造一批需要 exempt 的
        // 誤中，而反射性加 exempt 比沒有守衛更糟）
        for notSink in [".onChange(of: entry.title)", ".task { load(entry.citekey) }",
                        ".id(entry.citekey)", "let t = entry.title"] {
            XCTAssertFalse(Self.isDisplaySink(notSink),
                           "「\(notSink)」不畫到螢幕上，不該被當 sink")
        }
    }

    /// 續行偵測本身（#162）。
    ///
    /// **必須直接餵合成的行**：把 6 個真站點修好之後，「掃真實原始碼有沒有報東西」
    /// 恆為零——mutation 拿掉整個續行偵測，六條全綠。同 #161 的教訓，第二次遇到：
    /// **守衛的偵測能力不能靠語料的乾淨程度來驗。**
    func testContinuationDetectionSeesFoldedSinks() {
        // 折行的 error sink：payload 在第二、第三行
        let folded = [
            "throw ServiceError.invalid(",
            "    \"欄位「\\(k)」不支援\")",
            "let x = 1",
        ]
        let kinds = Self.continuationKinds(folded)
        XCTAssertEqual(kinds[0], nil, "開頭那行自己就是 sink，不算續行")
        XCTAssertEqual(kinds[1], .error, "payload 行必須被認出是 error sink 的續行")
        XCTAssertEqual(kinds[2], nil, "括號收掉之後就結束")

        // 三層以上：一層回看會漏，前向追蹤不會
        let deep = [
            "throw ServiceError.invalid(",
            "    what: \"x\",",
            "    why: \"值「\\(v)」不合法\")",
            "return",
        ]
        XCTAssertEqual(Self.continuationKinds(deep)[2], .error,
                       "第三行也要看得到——`Provenance` 的 \\(v) 就是這個形狀")
        XCTAssertEqual(Self.continuationKinds(deep)[3], nil)

        // 顯示 sink 的續行要繼承 .display（種類不能混——error 才跳過 token 清單）
        let display = ["print(", "    \"\\(entry.title)\")", "x()"]
        XCTAssertEqual(Self.continuationKinds(display)[1], .display,
                       "普通 sink 的續行不得被當成 error sink")

        // 非 sink 的折行不得誤中
        let notSink = ["let a = foo(", "    bar, baz)", "x()"]
        XCTAssertEqual(Self.continuationKinds(notSink), [nil, nil, nil],
                       "不是 sink 的呼叫折行不該進來——誤中要寫 exempt，那比沒守衛更糟")

        // 註解行不開啟續行狀態
        let comment = ["// throw ServiceError.invalid(", "let x = \"\\(k)\"", ""]
        XCTAssertEqual(Self.continuationKinds(comment)[1], nil,
                       "註解裡的 sink 不是 sink")

        // **掃描迴圈真的用了它嗎。** 上面驗的是 `continuationKinds` 這個函式；
        // 這一段驗 `scanViolations` 有把它接上——mutation 只改用法（把
        // `continuations[idx] == .error` 換成 `false`）時，只測函式的斷言全綠。
        // 判準對、函式對、沒接上，症狀與沒做一模一樣。
        let corpus = """
            func f() throws {
                throw ServiceError.invalid(
                    "欄位「\\(k)」不支援")
            }
            """
        let found = scanViolations(name: "Synthetic.swift", text: corpus)
        XCTAssertEqual(found.count, 1, "折行的 ServiceError payload 必須被掃到：\(found)")
        XCTAssertTrue(found.first?.text.contains("k") == true, "要指出是哪個運算式：\(found)")

        // 同一段包了 displaySafe 就不該報——否則守衛在製造誤中
        let clean = corpus.replacingOccurrences(of: "\\(k)", with: "\\(displaySafe(k, max: 200))")
        XCTAssertEqual(scanViolations(name: "Synthetic.swift", text: clean).count, 0,
                       "包了就不該報")
    }
    /// **subscript 指派也是 dict 值**（#156 verify 156-16）：`isSink` 一直認得
    /// `d["` 與 `result["`——那正是 `d["key"] = value` 的形狀——但抽取器只認**字面量**
    /// `"key": value`，對 subscript 指派抽出**空陣列**。於是那兩條 disjunct 是
    /// **死碼**：守衛認得這個 sink，然後什麼都沒抽出來。
    ///
    /// 席位量到的怪事因此有了解釋：把 `d["` / `result["` 從 `isSink` 拿掉，總數
    /// 78→78 完全不動。而 `AkashicService.swift` 有一整批 `d["k"] = v` 的站點靠
    /// 這個缺口逃掉（含 156-15 那條真洩漏）。
    private func dictValues(in line: String) -> [String] {
        var out: [String] = []
        // subscript 指派：`d["key"] = <expr>` / `result["key"] = <expr>`。取 `] = `
        // 之後到行尾（Swift 的 subscript 指派本來就是一個完整敘述）。
        //
        // **已知限制**（實掃 66 個站點後記錄，#156 verify R3 的追問）：
        // - 每行只取**第一個** `"] = `——同行兩個 subscript 指派時第二個看不到（實掃
        //   無此形狀，但不是保證）。
        // - 值在**下一行**時抽到空字串（`d["k"] =` 換行接 expr）→ 落回續行盲區
        //   （#162），與整個判準的既有限制一致，不是這條新增的洞。
        // - 尾隨的 `}`（`if let x = … { d["k"] = x }`）會被含進表達式，對 token 比對
        //   無影響；`displaySafe(` 與 `{` 結尾的既有豁免照常生效。
        // - 字串**字面量**內含 `"] = ` 會誤中，但同行的真陽性仍會被攔下——是**報告
        //   雜訊**不是假紅（席位 R4 實測；掃描面上零命中）。
        // - **少報**四種形狀（皆不導出錯誤結論，記錄以免被誤讀成涵蓋）：
        //   `d["k"] += expr`（複合指派）、`d["k"] =expr`（無空格）、值在下一行
        //   （落回 #162）、`d[field] = expr`（key 非字面量）。
        if let r = line.range(of: "\"] = ") {
            var v = String(line[r.upperBound...])
            // **行尾註解必須切掉**（#156 verify 156-17）：取到行尾會讓註解文字整段
            // 參與後續**所有**豁免判斷。席位實測四種豁免都會被註解觸發：
            //
            //     d["name"] = c.name  // TODO: 之後包 displaySafe(...)   → 假綠
            //     d["name"] = c.name  // 只有 .count 會變                 → 假綠
            //     d["name"] = c.name  // 若 == nil 就跳過                 → 假綠
            //     d["name"] = c.name  // 見下面的 {                       → 假綠
            //
            // 形狀還特別自然——**TODO 註解正好提到要包 `displaySafe(...)` 的那一刻，
            // 守衛就閉嘴了**。這是本判準唯一會造成假綠的缺陷。
            //
            // 切在未被引號包住的 ` //`。URL 的 `https://` 前面沒有空格，不誤切。
            var depth = 0, inString = false, cut: String.Index?
            var idx = v.startIndex
            while idx < v.endIndex {
                let c = v[idx]
                if c == "\"" { inString.toggle() }
                if !inString, c == "/", idx > v.startIndex {
                    let prev = v.index(before: idx)
                    let next = v.index(after: idx)
                    if v[prev] == " ", next < v.endIndex, v[next] == "/" { cut = prev; break }
                }
                if !inString { if c == "(" { depth += 1 }; if c == ")" { depth -= 1 } }
                idx = v.index(after: idx)
            }
            _ = depth
            if let cut { v = String(v[v.startIndex..<cut]) }
            let trimmed = v.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { out.append(trimmed) }
        }
        let chars = Array(line)
        var i = 0
        while i < chars.count - 2 {
            if chars[i] == "\"" && chars[i + 1] == ":" {
                var j = i + 2
                while j < chars.count && chars[j] == " " { j += 1 }
                var depth = 0
                var buf = ""
                while j < chars.count {
                    let c = chars[j]
                    if c == "(" || c == "[" || c == "{" { depth += 1 }
                    if c == ")" || c == "]" || c == "}" {
                        if depth == 0 { break }
                        depth -= 1
                    }
                    if c == "," && depth == 0 { break }
                    buf.append(c)
                    j += 1
                }
                out.append(buf)
                i = j
            }
            i += 1
        }
        return out
    }

    /// 判準的四條**獨立軸**（#156 verify 156-1）。strip-all 自測按軸分別設下限，
    /// 因為總數下限**結構上**擋不住單軸失效——關掉 errorSink 總數只從 78 掉到 74、
    /// 關掉 caseReturn 只掉到 76（那些行多半同時被 token 路徑收走，classifier 死了
    /// 報告仍在）。逐軸計數才會歸零。理由與實測表見
    /// `testGuardCatchesStrippedSanitisation` 的 doc。
    enum Axis: String, CaseIterable {
        /// `print(` / dict 值 / `return "` 等一般輸出面
        case sink
        /// `throw XxxError` 行——payload 經 errorDescription 直達輸出
        case errorThrow
        /// `case …: return "…"`（含跨行）——#142 的雙重盲區
        case caseReturn
        /// 靠 `taintedTokens` 命中而入列（非 error sink 的那條路徑）
        case token
    }

    struct Violation {
        let text: String
        let axes: Set<Axis>
    }

    /// 對單一檔案的原始碼文字掃描違規（#141：抽成純函式，讓正常掃描與 strip-all
    /// 量測自測共用同一判準——meta-test 要能對「拔光 displaySafe 的 source」重跑）。
    func scanViolations(name: String, text: String) -> [Violation] {
        var violations: [Violation] = []
        do {
            let allLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            let continuations = Self.continuationKinds(allLines)
            for (idx, line) in allLines.enumerated() {
                let l = String(line)
                // 前一行是否為 `case …:` 結尾（ConfigError 的 case/return 跨兩行——
                // #149 verify F2）。**往回跳過註解與空行**（#149 R2 F4：case 與
                // return 之間常夾說明註解——愈認真解釋為什麼要消毒，愈把守衛的
                // 回看擋掉；StoreIOError.invalidKey 正是這樣漏掉的）。
                var prevIsCase = false
                var k = idx - 1
                while k >= 0 {
                    let prev = allLines[k].trimmingCharacters(in: .whitespaces)
                    if prev.isEmpty || prev.hasPrefix("//") { k -= 1; continue }
                    prevIsCase = prev.hasPrefix("case ") && prev.hasSuffix(":")
                    break
                }
                // 註解行不算輸出
                if l.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                if l.contains("display-safe-exempt:") { continue }
                // 只看真正的輸出面：print(…) 與 JSON dict 的字串值

                let isSink = Self.isDisplaySink(l) || continuations[idx] == .display
                // #78-7：error 構造點是**無條件** sink——payload 最終進 errorDescription
                // →使用者可見輸出，插值的任何內容（YAML 未知 key、原始值）都可疑，
                // 不看 token 清單（局部變數名抓不到）。安全的插值加 exempt 注記
                // #142：ServiceError/StoreIOError 的 throw 行同屬 error sink（caller
                // 輸入經 errorDescription 直達輸出）；errorDescription 的
                // `case … return "…"` 形狀也是——那正是 #142 的雙重盲區（不含
                // throw、又被 case 豁免跳過）。
                let caseReturn = (l.trimmingCharacters(in: .whitespaces).hasPrefix("case ")
                        && l.contains("return \""))
                    || (prevIsCase && l.trimmingCharacters(in: .whitespaces).hasPrefix("return \""))
                let isErrorSink = Self.isErrorSinkLine(l) || caseReturn
                    || continuations[idx] == .error
                guard isSink || isErrorSink else { continue }
                // switch 的 `case "x": stmt` 不是 dict 值——冒號後是語句（#138 F2）。
                // **誠實邊界**：這也豁免了 case 行內的真 dict（如
                // `case .literal(let s): return ["literal": s]`），且短變數名值
                // 本就不含可比對 token——那類站點靠人工 + 功能測試釘住。
                // error-sink 行不豁免——throw 行的插值無條件檢查優先於 case 形狀。
                if !isErrorSink,
                   l.trimmingCharacters(in: .whitespaces).hasPrefix("case ") { continue }

                for expr in interpolations(in: l) + dictValues(in: l) {
                    let tokenMatched = taintedTokens.contains(where: { expr.contains($0) })
                    guard isErrorSink || tokenMatched else { continue }
                    if expr.contains("displaySafe(") { continue }
                    // `.count` / `.isEmpty` 是數量不是內容；`!= nil` / `== nil` 是
                    // Bool 存在測試（如 hasJudgement）——都到不了內容本身
                    if expr.contains(".count") || expr.contains(".isEmpty") { continue }
                    if expr.contains("!= nil") || expr.contains("== nil") { continue }
                    // MCP tool schema 的描述文字（`str("citekey")` 等）：schema
                    // builder 的引數是程式字面量、不是 store 衍生內容——合併掃描面
                    //（#78-7 akashic-mcp）與 dict 值抽取（#138 F2）後的交叉誤中
                    if expr.hasPrefix("str(\"") || expr.hasPrefix("strArray(\"")
                        || expr.hasPrefix(".string(\"") { continue }
                    // 多行 closure 的開頭行（`… { author -> T in`）：實際輸出在
                    // 後續行——closure 體若是 `case` 行則落入上方 case 豁免的
                    // 誠實邊界，否則仍會被逐行掃到
                    if expr.hasSuffix(" in") || expr.hasSuffix("{") { continue }
                    var axes: Set<Axis> = []
                    if isSink { axes.insert(.sink) }
                    if isErrorSink && !caseReturn { axes.insert(.errorThrow) }
                    if caseReturn { axes.insert(.caseReturn) }
                    // `.token` 只在「不是靠 errorSink 免檢入列」時成立——那才證明
                    // token 清單真的有在做事（清空清單時這一軸歸零）
                    if !isErrorSink && tokenMatched { axes.insert(.token) }
                    violations.append(Violation(text: "\(name):\(idx + 1)  \(expr)", axes: axes))
                }

            }
        }
        return violations
    }

    func testNoUnsanitisedStoreStringReachesUserVisibleOutput() throws {
        var violations: [Violation] = []
        for url in scannedFiles {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                XCTFail("讀不到 \(url.lastPathComponent)——掃描範圍若失效，這個測試會變成空跑")
                continue
            }
            violations += scanViolations(name: url.lastPathComponent, text: text)
        }

        XCTAssertTrue(violations.isEmpty, """
            有 \(violations.count) 條把 store 衍生字串未消毒送進使用者可見輸出的路徑：

            \(violations.map(\.text).joined(separator: "\n            "))

            修法二選一：
              1. 包上 displaySafe(…)——資料面用 max: 800，識別字用 max: 200
              2. 確定安全 → 同一行加 `// display-safe-exempt: <理由>`，把理由寫出來
            """)
    }

    /// **opt-out 必須逐條有理由，且掃描面必須真的涵蓋核心模組**（#158 verify 158-3b）。
    ///
    /// 枚舉 + opt-out 把「刪掉一項」這個洞關掉了（模組還在 `Sources/` 就會被掃回來），
    /// 但留下一個新的入口：**把模組加進 `optOut`**。這條把它擋住——理由不得為空，
    /// 且幾個核心輸出面模組不得出現在 opt-out 裡（要移除必須先改這條測試，那是
    /// 顯式動作而非順手一改）。
    func testOptOutIsJustifiedAndCoreModulesAreScanned() throws {
        for (name, reason) in Self.optOut {
            XCTAssertFalse(reason.trimmingCharacters(in: .whitespaces).isEmpty,
                           "opt-out 的「\(name)」沒有理由——排除必須講出為什麼")
        }
        // **同一份清單**（#158 verify R3-4）：兩處各寫一份時差集是 `AkashicGraph`
        // 與 `AkashicQuery`——它們若目錄被改名／搬走，第一條檢查照過（不在 optOut）、
        // 第二條根本不看它們，只剩 `count >= 30` 兜底。
        let dirs = Self.scannedDirs(repoRoot: repoRoot)
        for core in Self.mustScan {
            XCTAssertNil(Self.optOut[core], "「\(core)」是使用者可見輸出面，不得 opt-out")
            XCTAssertTrue(dirs.contains("Sources/\(core)"),
                          "掃描面不含 Sources/\(core)：\(dirs)")
        }
        // 每個被掃的目錄都要真的有 .swift（目錄空了＝那個模組的覆蓋是假的）
        let fm = FileManager.default
        for dir in dirs {
            let files = (try? fm.contentsOfDirectory(
                at: repoRoot.appendingPathComponent(dir),
                includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "swift" } ?? []
            XCTAssertFalse(files.isEmpty, "掃描目錄「\(dir)」貢獻 0 個 .swift")
        }
    }

    /// #141：**量測式自測**——守衛非空洞不能靠「有一條壞樣式抓得到」單點證明
    /// （那被 verify 席多次質疑：拔一個真實站點守衛卻全綠）。這裡把 verify 席手動
    /// 做的 strip-all 量測內建：拔光全部 `displaySafe(`，重掃 shipped source，
    /// 守衛**必須**報大量違規。若守衛的判準退化成永遠不報（token 清單被清空、
    /// isSink 判斷失效…），strip-all 也不會報 → 這個測試紅。
    ///
    /// **逐軸下限**（#156 verify 156-1／156-4）。
    ///
    /// ### 更正紀錄：我先前在這裡寫的數字與因果都是錯的
    ///
    /// 第一版說「席位報的各軸數字全錯」，並列出本 tree 實測 59／74／76 當反證。
    /// **錯的是我。** 那三個數字來自 partial mutation——`let isSink = false && A || B || C`
    /// 只關掉第一個 disjunct（Swift 的 `&&` 綁定緊於 `||`）。我後來確實改用整條
    /// 包覆重跑並得到四軸全零，卻**沒有回頭更新這張表**，於是一份 partial 數字與
    /// 一份 correct 結論並存在同一段 doc 裡。R2 席位把兩種 mutation 都跑了：
    ///
    /// **席位在 `714d062` 量的**（`.key` 入 token 清單之前）：
    ///
    /// | mutation（**整條**關掉） | total | sink | errorThrow | caseReturn | token |
    /// |---|---|---|---|---|---|
    /// | baseline | 78 | 57 | 21 | 14 | 43 |
    /// | `isSink = false` | **35** | 0 | 21 | 14 | 0 |
    /// | `isErrorSink = false` | **43** | 43 | 0 | 0 | 43 |
    /// | `caseReturn = false` | **64** | 43 | 21 | 0 | 43 |
    /// | `taintedTokens = []` | **35** | 14 | 21 | 14 | 0 |
    /// | 只剩 `citekey` | **49** | 28 | 21 | 14 | 14 |
    ///
    /// 這五個數字與席位第一輪回報的**逐一相同**；partial mutation 則重現出我的
    /// 59／74／76，一個不差。決定性旁證：雙方唯一一致的是「只剩 citekey」的 **49**
    /// ——那是改陣列字面量、沒有布林運算式可誤括號的那一個。
    ///
    /// **當前 tree 自量**（`a15ed09` 之後，`.key` 已入清單）：baseline **89** =
    /// sink 68／errorThrow 21／caseReturn 14／token 54。sink 與 token 各 +11，就是
    /// `.key` 帶進來的量；errorThrow／caseReturn 不受影響（它們不看 token）。
    /// 四個 classifier mutation 在當前 tree 一樣把對應軸打到 **0**（自量，非採信）。
    /// 兩組數字都留著：一組是席位可複核的基準，一組是這個檔案現在的實況。
    ///
    /// **連帶更正兩件事**：
    ///
    /// 1. 我曾寫「那些行多半同時被 token 路徑收走」——**因果剛好相反**。`.token` 的
    ///    定義是 `!isErrorSink && tokenMatched`，與 error sink 依構造**互斥**：
    ///    78 − 43 = 35 = errorThrow 21 + caseReturn 14，被 token 接住的是**零**。
    /// 2. 我曾寫「總數 60 之下只有 isSink 會紅」——實際五分之四會紅（35／43／35／49
    ///    都低於 60），只漏 caseReturn 的 64。
    ///
    /// ### 為什麼仍然採用逐軸下限
    ///
    /// 上面的更正削弱了我原本的論證，但**沒有推翻結論**——R2 席位獨立確認逐軸下限
    /// 在正確 mutation 下五個全紅（`caseReturn` 那個總數下限抓不到）。理由改成誠實
    /// 的版本：逐軸計數在 classifier 整條失效時**歸零**，與消毒站點的多寡無關，
    /// 所以不隨正常增減漂移；總數下限則是唯一擋得住**掃描面萎縮**的東西
    /// （席位實測：drop 整個 `Sources/akashic` → 四軸全綠、只有總數接住），
    /// 兩者互補，不是主從。
    ///
    /// ### 誠實邊界（席位 156-7 實測，本判準看不到的東西）
    ///
    /// 逐軸下限只偵測 classifier **整條**失效。**部分**退化四軸都測不到：
    /// `isSink` 少掉 `return "`（sink 57→43，仍在 floor 上）、`isErrorSink` 少掉
    /// 某一個 error 型別、`taintedTokens` 少掉**任一**單一 token（13 個逐一測過，
    /// 最兇的 citekey 也只讓總數 78→64）、以及撤銷 #149-R2 的「回看跳過註解」修正
    /// （完全不動）。要抓這類需要 oracle-delta（把 oracle 在測試裡重新推導、斷言
    /// 差額為零），不是更多的 magic number——那屬另案。
    ///
    /// 下限取當前實測的一半上下，只釘「這一軸還活著」，不釘精確計數——所以 `.key`
    /// 這種讓數字整體上移的改動不需要動下限。
    func testGuardCatchesStrippedSanitisation() throws {
        var stripped: [Violation] = []
        for url in scannedFiles {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // 移除 `displaySafe(` ＝ 模擬「拔掉全部消毒」：`displaySafe(citekey, max:200)`
            // → `citekey, max:200)`，掃描抽出的 `citekey` 是 tainted 且不含 displaySafe
            let mutated = text.replacingOccurrences(of: "displaySafe(", with: "")
            stripped += scanViolations(name: url.lastPathComponent, text: mutated)
        }
        let byAxis = Dictionary(uniqueKeysWithValues: Axis.allCases.map { axis in
            (axis, stripped.filter { $0.axes.contains(axis) }.count)
        })
        let floors: [Axis: Int] = [.sink: 25, .errorThrow: 8, .caseReturn: 5, .token: 20]
        for axis in Axis.allCases {
            // **force-unwrap 是刻意的**（#171 verify 171-7）：`?? 0` 會讓「新增第五個
            // Axis 但忘了給下限」安靜通過——那正是本測試在防的「守衛退化成空洞」。
            // 實測：加一個無下限的 case，`?? 0` 版 passed、force-unwrap 版 crash。
            // 響亮地壞掉勝過安靜地失效。
            XCTAssertGreaterThanOrEqual(byAxis[axis] ?? 0, floors[axis]!, """
                strip-all 後 `\(axis.rawValue)` 軸只報 \(byAxis[axis] ?? 0) 條
                （下限 \(floors[axis]!)）——這一軸的判準可能已整條失效。
                全軸實測：\(Axis.allCases.map { "\($0.rawValue)=\(byAxis[$0] ?? 0)" }
                    .joined(separator: " "))（2026-08-07 baseline：68/21/14/54）。
                若是消毒站點正常減少造成的，重新校準下限並更新上方的量測時點。
                """)
        }
        XCTAssertGreaterThanOrEqual(stripped.count, 60, """
            拔光 displaySafe 後守衛只報 \(stripped.count) 條（總數下限 60、量測時
            baseline 78）。逐軸檢查是主判準，這條只是粗篩。
            """)
    }

    /// 守衛自身要可證偽：掃描範圍不得為空，判準不得永遠成立。
    func testGuardItselfIsNotVacuous() throws {
        // 4 太鬆——光 `Sources/akashic` 一個目錄就有 8 個檔，其餘五個全掉光也滿足
        //（#156 verify R2）。實際 38 個檔，取 30 留 ~21% 緩衝。
        XCTAssertGreaterThanOrEqual(scannedFiles.count, 30,
                                    "掃描範圍萎縮＝守衛失效（實際 38 檔）")
        // 判準對已知的壞樣式必須成立
        let bad = #"print("\(summary.citekey)\t\(summary.title)")"#
        let exprs = interpolations(in: bad)
        XCTAssertEqual(exprs.count, 2)
        XCTAssertTrue(exprs.allSatisfy { e in
            taintedTokens.contains { e.contains($0) } && !e.contains("displaySafe(")
        }, "判準抓不到已知的壞樣式")
        // dict-value 形狀（#138 verify F2 的 mutation 靶）：值是裸表達式、無插值
        let badDict = #""question": d.question,"#
        let vals = dictValues(in: badDict)
        XCTAssertEqual(vals, ["d.question"], "dict 值抽取失效：\(vals)")
        // 消毒後同形狀必須通過；內部逗號不得被當成值邊界
        let goodDict = #""question": displaySafe(d.question, max: 400),"#
        XCTAssertEqual(dictValues(in: goodDict), ["displaySafe(d.question, max: 400)"])
    }
}

/// #139 verify F2 的行為面 regression：contacts 的 mapping key 來自檔案，
/// 它進 errorDescription 前必須被消毒——掃描守衛管的是原始碼形狀，這條管行為。
extension DisplaySinkCoverageTests {
    func testContactsDirtyKeyDoesNotLeakRawBytesIntoError() {
        // 裸控制字元進不了 YAML（libyaml reader 先擋）——真正的注入路徑是
        // 雙引號的 \u escape，parser 在 reader 檢查**之後**解碼（#144 verify 同發現）
        let yaml = """
        person:
        id: 33333333-4444-5555-6666-777777777777
        key: dirty-contact
        names:
        - D
        profile:
          contacts:
            "email\\u001B[31mEVIL":
              value: not-a-sequence
        """
        XCTAssertThrowsError(try PersonYAML.decode(yaml)) { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertFalse(msg.contains("\u{1B}"),
                           "原始 ESC 不得進 errorDescription：\(msg.debugDescription)")
            XCTAssertTrue(msg.contains("u{001B}") || msg.contains("EVIL"),
                          "消毒後仍要可辨認：\(msg)")
        }
    }
}

/// #158 verify F1／LOW：`bindFailed` 的訊息內容。
///
/// 席位實測本 change 唯一的行為改動（補 `參數 #N`）**零測試覆蓋**——把它從訊息
/// 拿掉，全套仍全綠。而 F1（`type(of: value)` 永遠印 `Optional<Any>`）**就是靠
/// 「沒人跑過這條路徑」活下來的**：三處註解宣稱「收斂成型別名」，實際收斂成的是
/// 一個常量字串。
final class SQLiteBindMessageTests: XCTestCase {
    func testBindFailureNamesTheParameterIndexAndTheRealType() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("bindmsg-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDB(path: path, readOnly: false)
        try db.execute("CREATE TABLE t(a, b, c)")

        XCTAssertThrowsError(try db.execute("INSERT INTO t VALUES (?,?,?)",
                                            bind: [1, 2, Date()])) { err in
            let msg = (err as? LocalizedError)?.errorDescription ?? "\(err)"
            XCTAssertTrue(msg.contains("參數 #3"),
                          "要指出是第幾個參數——那是本 change 唯一有診斷價值的內容：\(msg)")
            XCTAssertTrue(msg.contains("Date"),
                          "要給**真的型別名**。`type(of: value)` 對 `Any?` 一律回 "
                          + "`Optional<Any>`，那是常量、零診斷價值（#158 verify F1）：\(msg)")
            XCTAssertFalse(msg.contains("Optional<Any>"), "沒 unwrap 就是這個症狀：\(msg)")
        }
    }
}
