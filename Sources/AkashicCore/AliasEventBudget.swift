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
    /// | 真實 corpus 最大檔（536 檔實測） | ~700 |
    /// | 45 位作者 + 40 個大欄位的 entry | 230 |
    /// | **#20 的 temporal person，1400 段時間軸** | **15,457** |
    /// | 已知最小 bomb（282 bytes、12 層 fanout 2） | 110,611 |
    ///
    /// 第三列是**合法資料**（`#20` 明說「全部維度都要記錄歷史」，而 ISS 有 77 位 PI、
    /// 六個維度加聯絡資訊）。以 20,000 為門檻的話餘裕只有 1.3×——**誤殺會讓一筆合法
    /// 記錄永久寫不回**（encode canary 也走這道守衛），那正是 R11 的死法。
    ///
    /// 200,000 讓合法最壞情形有 13× 餘裕、離 bomb 仍有 5.5× 距離。**兩邊都留餘裕**，
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

    /// 巢狀深度上限。
    ///
    /// **實測澄清（verify 提出、我實證）**：深度**不是** bypass——libyaml 自己有
    /// `MAX_NESTING_LEVEL`（1000），60,000 層時 `yaml_parser_parse` 直接擲錯，
    /// 而 `Yams.compose` 走同一個 parser 也擲錯，所以正常路徑會 quarantine。
    ///
    /// 但這道上限仍有價值：它讓深度問題在**這裡**被指名（「巢狀太深」），而不是留給
    /// decode 端報一個泛用的 parse error。設 512 而非 100——實測 500 層仍能被 Yams
    /// 正常 compose，**上限設在合法可解析範圍之內就是誤殺**。真實書目資料是個位數，
    /// 512 留了兩個數量級。
    public static let maxDepth = 512

    public struct Estimate: Equatable {
        /// 估計展開後的節點數。
        public let expandedNodes: Int
        /// 估計展開後的 bytes（scalar 的實際長度累加）。
        public let expandedBytes: Int
        /// 最大巢狀深度。
        public let maxDepthSeen: Int
        /// 實際的 event 數（≈ 未展開的節點數）。
        public let rawEvents: Int
        public let aliases: Int
        public let anchors: Int
    }

    /// 掃描一份 YAML，估計展開成本。**不建 document tree、不展開 alias。**
    public static func estimate(_ text: String) throws -> Estimate {
        var parser = yaml_parser_t()
        guard yaml_parser_initialize(&parser) == 1 else {
            throw AliasBudgetError.parserUnavailable
        }
        defer { yaml_parser_delete(&parser) }

        let bytes = Array(text.utf8)
        var expanded = 0, raw = 0, aliases = 0, anchors = 0
        var expandedBytes = 0, depth = 0, maxDepthSeen = 0
        var error: AliasBudgetError?

        bytes.withUnsafeBufferPointer { buf in
            yaml_parser_set_input_string(&parser, buf.baseAddress, buf.count)

            // anchor 名 → (子樹節點數, 子樹 bytes)
            var anchorSize: [String: (nodes: Int, bytes: Int)] = [:]
            // 開啟中的 collection：(anchor 名或 nil, 進入時的 expanded 值)
            var openStack: [(anchor: String?, startNodes: Int, startBytes: Int)] = []

            func close(_ anchor: String?, _ startNodes: Int, _ startBytes: Int) {
                guard let anchor else { return }
                anchorSize[anchor] = (max(1, expanded - startNodes),
                                      max(0, expandedBytes - startBytes))
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
                    let sz = anchorSize[name] ?? (1, 0)
                    expanded += sz.nodes
                    expandedBytes += sz.bytes

                case YAML_SCALAR_EVENT:
                    expanded += 1
                    let len = event.data.scalar.length
                    expandedBytes += len
                    if let a = event.data.scalar.anchor {
                        anchors += 1
                        anchorSize[String(cString: a)] = (1, len)
                    }

                case YAML_SEQUENCE_START_EVENT:
                    expanded += 1
                    depth += 1
                    maxDepthSeen = max(maxDepthSeen, depth)
                    let a = event.data.sequence_start.anchor.map { String(cString: $0) }
                    if a != nil { anchors += 1 }
                    openStack.append((a, expanded, expandedBytes))

                case YAML_MAPPING_START_EVENT:
                    expanded += 1
                    depth += 1
                    maxDepthSeen = max(maxDepthSeen, depth)
                    let a = event.data.mapping_start.anchor.map { String(cString: $0) }
                    if a != nil { anchors += 1 }
                    openStack.append((a, expanded, expandedBytes))

                case YAML_SEQUENCE_END_EVENT, YAML_MAPPING_END_EVENT:
                    depth -= 1
                    if let top = openStack.popLast() {
                        close(top.anchor, top.startNodes, top.startBytes)
                    }

                case YAML_STREAM_END_EVENT:
                    break loop

                default:
                    break
                }

                // 邊掃邊擋——不必等掃完。三個軸各自獨立：計數、重量、深度。
                if expanded > maxExpandedNodes {
                    error = .expansionTooLarge(estimated: expanded, limit: maxExpandedNodes)
                    break loop
                }
                if expandedBytes > maxExpandedBytes {
                    error = .expandedBytesTooLarge(estimated: expandedBytes,
                                                   limit: maxExpandedBytes)
                    break loop
                }
                if depth > maxDepth {
                    error = .tooDeep(depth: depth, limit: maxDepth)
                    break loop
                }
            }
        }

        if let error { throw error }
        return Estimate(expandedNodes: expanded, expandedBytes: expandedBytes,
                        maxDepthSeen: maxDepthSeen, rawEvents: raw,
                        aliases: aliases, anchors: anchors)
    }

    /// compose **之前**的守衛。
    public static func check(_ text: String, context: String) throws {
        let byteCount = text.utf8.count
        guard byteCount <= maxBytes else {
            throw AliasBudgetError.fileTooLarge(bytes: byteCount, limit: maxBytes)
        }
        do { _ = try estimate(text) }
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
            return "巢狀深度 \(d) 超過上限 \(l)——深度不影響節點數（`[[[[…]]]]` 只算幾個節點），"
                 + "但會打爆 parser 的解析堆疊。真實書目資料的巢狀深度是個位數。"
        case let .size(b, l):
            return "檔案 \(b) bytes 超過上限 \(l)——單一超大節點同樣會讓 parser 耗盡記憶體。"
        case .parser:
            return "YAML parser 初始化失敗（記憶體不足）。"
        }
    }
}
