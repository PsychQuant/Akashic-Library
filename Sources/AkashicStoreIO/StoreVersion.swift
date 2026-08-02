import Foundation

/// Store format version 標記與 refuse-if-newer 防線（#24）。
///
/// **分工邊界（與 #23 的 tolerant-preserve）**：
///
/// | 變更種類 | 由誰處理 | bump `format`？ |
/// |---|---|---|
/// | **additive**（新增欄位）| #23 的 unknown-key 容忍 + round-trip 保留 | **否** |
/// | **non-additive**（欄位語意變更、刪除、結構重排）| 本機制 refuse-if-newer | **是** |
///
/// 兩者不重疊：additive 變更下舊 binary 讀新資料是**安全的**（未知欄位原樣保留），
/// 所以不該 bump——bump 會讓每個 additive 演化都逼所有 binary 同步升級，等於白做 #23。
/// non-additive 下舊 binary 會**按舊語意解讀新格式**，靜默產生錯誤行為——那比 quarantine
/// 更糟，必須在開 store 的當下就整體拒絕，而不是在個別檔案 decode 現場丟難解的錯。
///
/// **為什麼現在做**（原 issue 標 P3/YAGNI「等第一個真實 non-additive 需求」）：#35 要把
/// `entries/<citekey>.yaml` 改成 `entities/<uuid>.yaml`——那是結構重排。沒有這道防線的話，
/// 舊 binary 會看到空的 `entries/` 而回報「0 entries」：一個**看起來成功的錯誤答案**，
/// 比拒絕開啟糟得多。
public enum StoreVersion {

    /// 本 binary 支援的最高 store format。
    ///
    /// **1** ＝ v1.x 家族（`entries/<citekey>.yaml` + `people/<person-key>.yaml`；
    /// tolerant-preserve 於 v1.3 落地，屬 additive，故不 bump）。
    /// #35 的 `entities/<uuid>.yaml` 落地時 bump 為 2。
    public static let supported = 1

    /// 標記檔名。放 **store root** 而非 `.akashic/`：version 是 canonical 事實
    /// （「這份資料是什麼格式」），不是衍生物。`.akashic/` 是可全刪重建的衍生層，
    /// 把 canonical 事實放進去，語意錯且會隨 index 一起被清掉。
    public static let fileName = "store.yaml"

    public static func url(in root: URL) -> URL {
        root.appendingPathComponent(fileName)
    }

    /// 讀 store 的 format version。
    ///
    /// **缺檔 ＝ format 1**，不是錯誤：#24 之前寫的 store 都沒有這個檔，而它們就是
    /// v1.x。把缺檔當錯誤會讓這道防線一落地就打死所有既有 store。
    public static func read(root: URL) throws -> Int {
        let u = url(in: root)
        guard FileManager.default.fileExists(atPath: u.path) else { return 1 }
        let text = try String(contentsOf: u, encoding: .utf8)
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard line.hasPrefix("format:") else { continue }
            let v = line.dropFirst("format:".count)
                .trimmingCharacters(in: .whitespaces)
            // 註解可以跟在值後面（`format: 1  # v1.x`）
            let numeric = v.prefix { $0.isNumber }
            guard let n = Int(numeric), n >= 1 else {
                throw StoreVersionError.malformed(path: u.path, line: line)
            }
            return n
        }
        // 檔案存在但沒有 format: 行——不猜，明說。
        throw StoreVersionError.malformed(path: u.path, line: "(檔案內找不到 format: 行)")
    }

    /// 開 store 前的防線。version 超過本 binary 支援上限 → 整體拒絕。
    public static func check(root: URL) throws {
        let found = try read(root: root)
        guard found <= supported else {
            throw StoreVersionError.tooNew(found: found, supported: supported)
        }
    }

    /// 建立標記檔（若不存在）。**不覆寫既有檔**——那可能是較新版本寫的，
    /// 覆寫等於把 refuse-if-newer 的依據自己抹掉。
    public static func writeIfAbsent(root: URL) throws {
        let u = url(in: root)
        guard !FileManager.default.fileExists(atPath: u.path) else { return }
        let body = """
            # Akashic store format（#24）。只有 **non-additive** 變更才 bump——
            # 新增欄位由 tolerant-preserve 涵蓋（#23），不 bump。
            # 舊 binary 讀到比自己新的 format 會整體拒絕開啟，而不是按舊語意誤讀。
            format: \(supported)

            """
        try body.write(to: u, atomically: true, encoding: .utf8)
    }
}

public enum StoreVersionError: Error, LocalizedError, Equatable {
    case tooNew(found: Int, supported: Int)
    case malformed(path: String, line: String)

    public var errorDescription: String? {
        switch self {
        case let .tooNew(found, supported):
            return """
                此 library 由較新版本寫入（store format \(found)），本 binary 支援至 \(supported)。
                請升級 CLI（akashic）/ akashic-mcp / App —— 三者是各自獨立的 binary，
                只升級其中一個仍會撞到同一道防線。
                （降級路徑：若確定要用舊 binary，須先把 store 轉回舊格式；直接改 \
                \(StoreVersion.fileName) 的數字**不會**讓資料變回舊格式，只會讓舊 binary \
                按舊語意誤讀新結構——那正是這道防線要擋的事。）
                """
        case let .malformed(path, line):
            return "store format 標記無法解析：\(path)（\(line)）"
        }
    }
}
