import Foundation
import CYaml

/// Event-level 的 alias 展開預算（#36 / #27）。
///
/// ## 為什麼是 event level
///
/// 文字層掃描在這個 repo **失敗了五次**（R5 / R6 / R10 / R11 / PR #42），每次都是兩個
/// 方向同時錯：擋不住真攻擊，又誤殺真資料。共同形態是**用手寫的逐字元狀態機重現 YAML
/// 詞法**——引號跨行、flow collection、block scalar 標頭、CRLF、註解起始條件，每一個
/// 細節都是一個獨立的破口。排除清單見 `docs/store-format.md` §5。
///
/// `yaml_parser_parse` **不展開 alias**：每個 alias 就是一個 `YAML_ALIAS_EVENT`，
/// 成本與**輸入大小**成正比，與展開後的大小無關。所以掃完整份輸入的成本是 O(n)，
/// 而它給的是 parser 自己的判斷，不是我對 parser 的猜測。
///
/// **這裡不需要重現任何 YAML 詞法**——那正是前五次失敗的來源。
///
/// ## 判準
///
/// 估計展開後的節點數：把 anchor 定義的子樹大小記下來，alias 引用時加上它。這是
/// **實際的放大量**，不是「anchor 數 × alias 數」那種代理指標（PR #42 的判準，被真實
/// corpus 推翻——有檔案已經坐在門檻上）。
///
/// 單一 anchor 被引用 N 次是 (N+1)× 而非 2×——那是 PR #42 的另一個錯誤宣稱，
/// 這裡的累加自然涵蓋它。
public enum AliasEventBudget {

    /// 估計展開後的節點數上限。
    ///
    /// **由真實資料的最壞情形校準，不是由現況校準**——這個區別是本次調整的重點：
    ///
    /// | 輸入 | 估計節點數 |
    /// |---|---|
    /// | 真實 corpus 最大檔（536 檔實測） | **180** |
    /// | 45 位作者 + 40 個大欄位的 entry | 230 |
    /// | **#20 的 temporal person，1400 段時間軸** | **15,457** |
    /// | fanout 2 × 12 層（**compose 僅 0.01 s，不痛**） | 110,611 |
    /// | **真正會痛的**：fanout 9 × 7 層（357 B、compose **4.8 s**） | **超過門檻** |
    ///
    /// 第三列是**合法資料**（`#20` 明說「全部維度都要記錄歷史」，而 ISS 有 77 位 PI、
    /// 六個維度加聯絡資訊）。以 20,000 為門檻的話餘裕只有 1.3×——**誤殺會讓一筆合法
    /// 記錄永久寫不回**（encode canary 也走這道守衛），那正是 R11 的死法。
    ///
    /// **門檻由實際 compose 成本校準**（不是憑節點數猜）：實測 fanout 9 的痛點在
    /// lv=7（4.8 s），而 lv=5 就已超過 200,000——**門檻擋在痛點之前**。合法最壞情形
    /// 有 **12×** 餘裕。**兩邊都留餘裕**，
    /// 而不是只顧一邊。
    ///
    /// PR #42 的教訓是**不要用代理指標**（anchor 數 × alias 數）：那種門檻與真實資料的
    /// 距離無法量測。這裡是**同一個量綱**的直接比較，兩邊的餘裕都看得見。
    public static let maxExpandedNodes = 200_000

    /// 輸入大小上限（bytes）。
    public static let maxBytes = 8 * 1024 * 1024

    /// **展開後**的 bytes 上限。節點數擋不住這一類（verify 實測）：
    /// 19,000 次引用一個 5 KB scalar 只算 38,003 節點（過關），但展開後是 **95 MB**。
    /// 節點是**計數**，bytes 是**重量**——兩個軸都要。
    public static let maxExpandedBytes = 64 * 1024 * 1024

    /// **展開後**的樹深上限。
    ///
    /// **必須是展開深度，不是語法深度**——這是 PR #49 被 DA 打回的原因（第 6 次失敗）。
    /// 這個構造在語法上完全是平的（每行深度 1），展開後卻是 8000 層：
    ///
    ///     root: &a0 x
    ///     k1: &a1 [*a0]
    ///     k2: &a2 [*a1]
    ///     …8000 層…
    ///     ? *a8000
    ///     : 1
    ///
    /// 180 KB、估計 24,005 節點（遠低於門檻）、**語法深度 2**——舊版守衛完全放行，
    /// 而 `akashic validate` 直接 **SIGSEGV（exit 139）**。libyaml 自己的
    /// `MAX_NESTING_LEVEL` 也不觸發，因為它同樣只管語法巢狀。
    ///
    /// **SIGSEGV 比它要防的 DoS 更嚴重**：DoS 會 timeout 然後 quarantine，
    /// 而 SIGSEGV 是 Swift 的 `catch` 抓不到的——沒有 quarantine 路徑，那個檔案會讓
    /// CLI / MCP / App 每次載入都直接死，永久且無法跳過。
    ///
    /// 512：實測 500 層的 `[[[…]]]` 仍能被 Yams 正常 compose，**上限設在合法可解析
    /// 範圍之內就是誤殺**。真實書目資料是個位數。
    public static let maxDepth = 512

    public struct Estimate: Equatable {
        /// 估計展開後的節點數。
        public let expandedNodes: Int
        /// 估計展開後的 bytes（scalar 的實際長度累加）。
        public let expandedBytes: Int
        /// 展開後的最大樹深（不是語法巢狀深度）。
        public let maxDepthSeen: Int
        /// 實際的 event 數（≈ 未展開的節點數）。
        public let rawEvents: Int
        public let aliases: Int
        public let anchors: Int
    }

    /// 掃描一份 YAML，估計展開成本。**不建 document tree、不展開 alias。**
    public static func estimate(_ text: String,
                                nodeLimit: Int = maxExpandedNodes) throws -> Estimate {
        var parser = yaml_parser_t()
        guard yaml_parser_initialize(&parser) == 1 else {
            throw AliasBudgetError.parserUnavailable
        }
        defer { yaml_parser_delete(&parser) }

        let bytes = Array(text.utf8)
        var expanded = 0, raw = 0, aliases = 0, anchors = 0
        var expandedBytes = 0, maxDepthSeen = 0
        var error: AliasBudgetError?

        bytes.withUnsafeBufferPointer { buf in
            yaml_parser_set_input_string(&parser, buf.baseAddress, buf.count)

            // anchor 名 → (子樹節點數, 子樹 bytes, **展開後的子樹深度**)
            var anchorSize: [String: (nodes: Int, bytes: Int, depth: Int)] = [:]
            // 開啟中的 collection：(anchor 名或 nil, 進入時的 expanded 值)
            // 每個開啟中的 collection 另記「子節點的最大展開深度」——
            // collection 自己的展開深度 = 1 + 子節點的最大值。
            var openStack: [(anchor: String?, startNodes: Int, startBytes: Int,
                             maxChildDepth: Int)] = []

            /// 一個節點完成時把它的展開深度往上冒泡，並在有 anchor 時記錄。
            func settle(depth d: Int) {
                maxDepthSeen = max(maxDepthSeen, d + openStack.count)
                if !openStack.isEmpty {
                    openStack[openStack.count - 1].maxChildDepth =
                        max(openStack[openStack.count - 1].maxChildDepth, d)
                }
            }

            loop: while true {
                var event = yaml_event_t()
                guard yaml_parser_parse(&parser, &event) == 1 else {
                    // parse 錯誤在這裡不是我們的事——`Yams.compose` 走**同一個 parser**，
                    // 所以任何在這裡失敗的輸入在那裡也會失敗，由 decode 的正常路徑
                    // quarantine 並報出真正的原因。這一關只管資源。
                    //
                    // **這不是靜默漏洞**（verify 提出的疑慮）：不存在「這裡 parse 失敗
                    // 但 compose 成功」的輸入，因為兩者是同一份 libyaml。實測 60,000 層
                    // 巢狀：兩邊都擲錯。
                    break loop
                }
                defer { yaml_event_delete(&event) }
                raw += 1

                switch event.type {
                case YAML_ALIAS_EVENT:
                    aliases += 1
                    let name = event.data.alias.anchor.map { String(cString: $0) } ?? ""
                    // 未定義的 anchor 算 1（parser 之後會自己報錯）
                    let sz = anchorSize[name] ?? (1, 0, 1)
                    expanded += sz.nodes
                    expandedBytes += sz.bytes
                    // **alias 的展開深度 = 它指向的子樹深度**——這是語法深度看不到的
                    settle(depth: sz.depth)

                case YAML_SCALAR_EVENT:
                    expanded += 1
                    let len = event.data.scalar.length
                    expandedBytes += len
                    settle(depth: 1)
                    if let a = event.data.scalar.anchor {
                        anchors += 1
                        anchorSize[String(cString: a)] = (1, len, 1)
                    }

                case YAML_SEQUENCE_START_EVENT:
                    expanded += 1
                    let a = event.data.sequence_start.anchor.map { String(cString: $0) }
                    if a != nil { anchors += 1 }
                    // `expanded - 1`：START 事件已經把 collection 自己算進去了，起點要退回去，
                    // 否則記錄的子樹大小**不含 collection 本身**。單看是差一，但鏈起來會
                    // 累積——verify 實測 500 層的鏈估 1,505、真實 126,755（差 84 倍）。
                    openStack.append((a, expanded - 1, expandedBytes, 0))

                case YAML_MAPPING_START_EVENT:
                    expanded += 1
                    let a = event.data.mapping_start.anchor.map { String(cString: $0) }
                    if a != nil { anchors += 1 }
                    // `expanded - 1`：START 事件已經把 collection 自己算進去了，起點要退回去，
                    // 否則記錄的子樹大小**不含 collection 本身**。單看是差一，但鏈起來會
                    // 累積——verify 實測 500 層的鏈估 1,505、真實 126,755（差 84 倍）。
                    openStack.append((a, expanded - 1, expandedBytes, 0))

                case YAML_SEQUENCE_END_EVENT, YAML_MAPPING_END_EVENT:
                    if let top = openStack.popLast() {
                        let myDepth = 1 + top.maxChildDepth
                        if let anchor = top.anchor {
                            anchorSize[anchor] = (max(1, expanded - top.startNodes),
                                                  max(0, expandedBytes - top.startBytes),
                                                  myDepth)
                        }
                        settle(depth: myDepth)
                    }

                case YAML_STREAM_END_EVENT:
                    break loop

                default:
                    break
                }

                // 邊掃邊擋——不必等掃完。三個軸各自獨立：計數、重量、深度。
                // **節點軸只對有 alias 的輸入有意義**（verify HIGH）：alias-free 的檔案
                // `expanded == rawEvents`，放大**定義上不可能**，成本由 `maxBytes` 已經
                // 界住（實測 alias-free 的 compose 對輸入線性：7.4 MB → 1.8 s）。
                // 不 gate 的話，一個 1.2 MB 的正常大檔會被擋下並告知「這是攻擊的形狀」。
                if aliases > 0, expanded > nodeLimit {
                    error = .expansionTooLarge(estimated: expanded, limit: nodeLimit)
                    break loop
                }
                if expandedBytes > maxExpandedBytes {
                    error = .expandedBytesTooLarge(estimated: expandedBytes,
                                                   limit: maxExpandedBytes)
                    break loop
                }
                if maxDepthSeen > maxDepth {
                    error = .tooDeep(depth: maxDepthSeen, limit: maxDepth)
                    break loop
                }
            }
        }

        if let error { throw error }
        return Estimate(expandedNodes: expanded, expandedBytes: expandedBytes,
                        maxDepthSeen: maxDepthSeen, rawEvents: raw,
                        aliases: aliases, anchors: anchors)
    }

    /// **write path 的放寬倍數**（verify HIGH，沿用 R9 的既有先例）。
    ///
    /// encode canary 走同一道守衛，若讀寫用**完全相同**的門檻就沒有遲滯：一筆
    /// 199,999 節點的記錄讀得進來，但下一次編輯只要多一個節點就**永遠寫不回**，
    /// 而使用者的修改被丟掉。YAML.swift 的 R9 註解逐字寫過這個危害
    /// （「放寬為 2×，避免『讀得到但永遠寫不回』的邊界檔」）——同一個道理。
    public static let writePathMultiplier = 2

    /// compose **之前**的守衛。
    ///
    /// `isWritePath` 為 true 時門檻放寬 `writePathMultiplier` 倍（見上）。
    public static func check(_ text: String, context: String,
                             isWritePath: Bool = false) throws {
        let mult = isWritePath ? writePathMultiplier : 1
        let byteCount = text.utf8.count
        guard byteCount <= maxBytes * mult else {
            throw AliasBudgetError.fileTooLarge(bytes: byteCount, limit: maxBytes * mult)
        }
        do { _ = try estimate(text, nodeLimit: maxExpandedNodes * mult) }
        catch let e as AliasBudgetError { throw e.withContext(context) }
    }
}

public enum AliasBudgetError: Error, LocalizedError, Equatable {
    case expansionTooLarge(estimated: Int, limit: Int)
    case expandedBytesTooLarge(estimated: Int, limit: Int)
    case tooDeep(depth: Int, limit: Int)
    case fileTooLarge(bytes: Int, limit: Int)
    case parserUnavailable
    case contextual(String, AliasBudgetErrorKind)

    public func withContext(_ context: String) -> AliasBudgetError {
        switch self {
        case let .expansionTooLarge(e, l): return .contextual(context, .expansion(e, l))
        case let .expandedBytesTooLarge(e, l): return .contextual(context, .bytes(e, l))
        case let .tooDeep(d, l): return .contextual(context, .depth(d, l))
        case let .fileTooLarge(b, l):      return .contextual(context, .size(b, l))
        case .parserUnavailable:           return .contextual(context, .parser)
        case .contextual:                  return self
        }
    }

    public var errorDescription: String? {
        // **單行**：quarantine reason 會過 displaySafe，真換行會被逸出成 \u{000A}。
        switch self {
        case let .contextual(ctx, kind): return "\(ctx)：" + kind.text
        case let .expansionTooLarge(e, l): return AliasBudgetErrorKind.expansion(e, l).text
        case let .expandedBytesTooLarge(e, l): return AliasBudgetErrorKind.bytes(e, l).text
        case let .tooDeep(d, l): return AliasBudgetErrorKind.depth(d, l).text
        case let .fileTooLarge(b, l): return AliasBudgetErrorKind.size(b, l).text
        case .parserUnavailable: return AliasBudgetErrorKind.parser.text
        }
    }
}

public enum AliasBudgetErrorKind: Equatable {
    case expansion(Int, Int)
    case bytes(Int, Int)
    case depth(Int, Int)
    case size(Int, Int)
    case parser

    var text: String {
        switch self {
        case let .expansion(e, l):
            return "alias 展開後估計超過 \(l) 個節點（已數到 \(e)）——這是展開放大攻擊的形狀。"
                 + "估計在 parser 的 event 層完成，**不展開** alias，所以掃描本身的成本與檔案大小成正比。"
                 + "store 的寫入端從不產生 anchor/alias；若這是手寫的檔案，請把 alias 展開後再存。"
        case let .bytes(e, l):
            return "alias 展開後估計 \(e) bytes 超過上限 \(l)——節點數擋不住這一類："
                 + "少量 alias 引用一個大 scalar，計數過關但重量爆炸。"
        case let .depth(d, l):
            return "**展開後**的樹深 \(d) 超過上限 \(l)——深度可以由 alias 展開產生而"
                 + "語法上完全是平的（`k1: &a1 [*a0]` 每行都是深度 1），節點數也看不到它。"
                 + "過深會讓下游遞迴打爆堆疊而 **SIGSEGV**（catch 不到、無法 quarantine）。"
                 + "真實書目資料的深度是個位數。"
        case let .size(b, l):
            return "檔案 \(b) bytes 超過上限 \(l)——單一超大節點同樣會讓 parser 耗盡記憶體。"
        case .parser:
            return "YAML parser 初始化失敗（記憶體不足）。"
        }
    }
}
