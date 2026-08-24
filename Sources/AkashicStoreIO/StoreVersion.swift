import Foundation
import AkashicCore

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
    /// - **1** ＝ v1.x 家族（`entries/<citekey>.yaml` + `people/<person-key>.yaml`；
    ///   tolerant-preserve 於 v1.3 落地，屬 additive，故不 bump）。
    /// - **2** ＝ `entities/<uuid>.yaml`（#35）。這是**結構重排**——舊 binary 會看到空的
    ///   `entries/` 而回報「0 entries」，一個**看起來成功的錯誤答案**。refuse-if-newer
    ///   存在的直接理由就是這一次。
    /// - **3** ＝ 記錄的**形狀由裸標籤標示**（頂層一個無值的鍵），不再由 `type:` 的值標示。
    ///   這是 non-additive：舊 binary 讀新的 person 檔會看不到 `type: person`，走它的
    ///   全稱後備判成 work、decode 失敗，並回報與真正原因無關的 per-file 錯誤。
    ///   refuse-if-newer 把它變成一句「請升級」。
    /// - **4** ＝ 新增 organization 形狀，且 person 的隸屬值由字串升成**指涉或字面**。
    ///   兩者都是 non-additive：舊 binary 讀到 `organization:` 標籤會判定「不認得的形狀」，
    ///   讀到 `{key: …}` 形式的隸屬值會 decode 失敗。
    /// - **5** ＝ 廢除「`names` 的第一個是顯示名」（#81）。對外可稱呼的名字改由顯式的
    ///   `authorized` 欄位指定（`names` 的子集，每個書寫系統至多一個）。這是**欄位語意
    ///   變更**：`authorized` 本身對舊 binary 是未知欄位、會被 tolerant-preserve 保留，
    ///   但保留不等於遵守——舊 binary 仍會把 `names[0]` 當顯示名，並在一次
    ///   read-modify-write 裡重排 `names` 而不自知。bump 是唯一能擋住那條路的機制。
    /// - **6** ＝ 時間軸段新增 `ended`（「已結束、時點未知」，#63）。**看似 additive
    ///   其實不是**：tolerant-preserve 的開放演化層只涵蓋記錄「頂層」與 `akashic`
    ///   namespace——時間軸**段內**的鍵是 strict（`rejectUnknownKeys`），舊 binary
    ///   讀到 `ended:` 是**整檔 quarantine**（人檔在舊 binary 消失），不是保留。
    ///   refuse-if-newer 的一句「請升級」遠比 per-file quarantine 誠實。
    /// - **7** ＝ 時間軸段新增 `attested`（觀測點列表——「某時點成立、起訖皆不明」，
    ///   #70）。與 6 同型：段內鍵 strict → non-additive，write gate 對 format < 7
    ///   拒寫含 attested 的記錄。
    /// - **8** ＝ `references[].field` 白名單新增消解判定欄位對
    ///   `resolution-confirmed`／`resolution-rejected`（#232）。與 6/7 同型的
    ///   「看似 additive 其實不是」：field 白名單是 strict（未列拒收）→ 舊 binary
    ///   讀到 verdict reference 是**整檔 quarantine（人檔／org 檔消失）**，且該檔
    ///   隨後可被 bootstrap 的決定性 UUID 安靜覆寫、判定史全滅（#232 verify
    ///   NEW-2/NEW-3 實測整條鏈）。write gate 對 format < 8 拒寫含 verdict 的記錄；
    ///   refuse-if-newer 的「請升級」取代 per-file quarantine。序列化形狀不變——
    ///   8 只是「這個 store 可以持有 verdict」的宣告。
    /// - **9** ＝ 附件鍵域收窄為只剩 `zotero`（移除 `pool`），並新增記錄側的副本
    ///   引用 `akashic.sources`（#223）。**提升依據是鍵域的嚴格性，不是資料量**：
    ///   `attachments` 元素鍵走 strict 驗證，未知種類導致**整檔 quarantine** 而非
    ///   保留，所以縮減鍵域是 non-additive——一份帶 `pool` 附件的記錄被新 binary
    ///   讀到會整檔消失。實際受影響資料為 0 筆，但那是**當下的巧合**，不是契約；
    ///   把它當死碼移除而不 bump，會讓 refuse-if-newer 這道防線在下一次真的有
    ///   資料時失效。write gate 對 format < 9 拒寫含 `akashic.sources` 的記錄。
    ///   （原設計佔 8；rebase 時 8 已被 #232 佔用，順延為 9。）
    /// - **10** ＝ person 的 `names` 巢狀化為 `authorized`／`variant` 兩個分割，
    ///   頂層 `authorized` 欄位移除；`id` 改為獨立 v4（#227／#241）。**兩者都是
    ///   non-additive**：巢狀 names 對 v9 binary 是 known 欄位形狀不符 → 整檔
    ///   quarantine（人檔消失）；v10 binary 對平坦 names 與頂層 authorized 同樣
    ///   fail-closed（舊形狀只能經 migrate-person-identity，decoder 不順便相容）。
    ///   write gate 對 format < 10 拒寫含 names 的 person。organization 不變
    ///   （其 names 是時間軸，巢狀化是另一個設計題——刻意的不對稱）。
    ///   （原設計佔 8；實作時 8/9 已被 #232／#223 佔用，順延為 10。）
    /// - **11** ＝ 新一級形狀 `venue:`（期刊／會議／出版社，#304）＋ entry 的
    ///   `venues:` 二態 ref 邊。**non-additive，實測依據**（2026-08-16，format-10
    ///   binary 對含 `venue:` 檔的 store）：未知頂層形狀 → **整檔 quarantine**
    ///   （「頂層的無值鍵 『venue』 不是已知形狀」——記錄從計數與查詢中消失，
    ///   與 format 6 的 ended 前例同型）；entry 的 `venues:` 鍵雖落在
    ///   tolerant-preserve 層（舊 binary 保留不解讀），但「保留而不解讀」對
    ///   ref 邊即反向查詢靜默漏資料。write gate 對 format < 11 拒寫 venue 記錄
    ///   與含 `venues` 的 entry。
    /// - **12** ＝ `Author` 三態（#323，新增 `organization:` 鍵）＋ `VenueType` 的
    ///   APA7 值域（#324，`journal` → `periodical` 並加四值）。**non-additive，實測
    ///   依據**（2026-08-19）：
    ///   - **#323**：format-11 binary 讀含 `authors: [{organization: …}]` 的 entry →
    ///     `rejectUnknownKeys` 擲錯，被上層轉成**整檔 quarantine**。實測
    ///     `akashic query` 回 **rc=0 且該筆整個消失、無任何訊息**；只有主動跑
    ///     `doctor` 才看得到 `quarantined: 1`。與 format 11 的 venue 前例同型。
    ///   - **#324**：`VenueType` 的 decode 對未知值**整檔拒讀**（該型別的 doc 明載），
    ///     舊 binary 讀到 `type: periodical` 直接拒絕整個檔案。
    ///   write gate 對 format < 12 拒寫「含 organization 作者的 entry」與「type 不在
    ///   format 11 值域內的 venue」。
    ///
    ///   **`Entry.type` 的封閉列舉（#325）刻意不在此列**：`type` 是自由 `String` 且
    ///   decode 不驗，舊 binary 讀到新值會照 tolerant-preserve 原樣保留——那是
    ///   **additive**，依本檔頂部的判準表不該 bump（「bump 會讓每個 additive 演化都逼
    ///   所有 binary 同步升級，等於白做 #23」）。
    public static let supported = 13

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
    ///
    /// **Grammar（#117 定案；normative 見 store-format.md §5.0）**——合法 marker：
    ///
    /// ```
    /// marker      = *( comment / blank ) format-line *( comment / blank )
    /// format-line = "format:" SP* 1*DIGIT [ SP* comment ]    ；必須頂格
    /// comment     = *WS "#" anything                          ；註解可縮排
    /// 換行        = 任何 Unicode 換行（\n、\r\n、\r、LS、PS）
    /// ```
    ///
    /// 其餘一律 malformed（fail-loud）：
    /// - **未知頂層行**（含 `meta: {`）——#112 修掉縮排類 fail-silent 之後，flow
    ///   mapping 第 0 欄的鍵是僅存的繞法（毒化 marker 靜默降版）；grammar 不再
    ///   「跳過不認識的行」，繞法整類關閉。additive key 未來要加，得連解析器一起設計
    /// - **縮排的非註解行**——marker 裡沒有巢狀結構
    /// - **第二個 `format:` 行**——歧義不猜（同 #121 duplicateRegistration 的哲學）
    ///
    /// 換行用 `isNewline` 分割：CRLF 檔曾整檔被當一行（`\r\n` 是單一 Character、
    /// `split(separator: "\n")` 完全不分行）——換行符變體不是語意歧義。
    public static func read(root: URL) throws -> Int {
        let u = url(in: root)
        guard FileManager.default.fileExists(atPath: u.path) else {
            return try read(data: nil, path: u.path)
        }
        return try read(data: Data(contentsOf: u), path: u.path)
    }

    /// 與 filesystem API 共用的 bytes parser。snapshot 接受 capture 後只能走這條，
    /// 不得為了解析 marker 再回頭讀磁碟。
    static func read(data: Data?, path: String) throws -> Int {
        guard let data else { return 1 }
        guard let text = String(data: data, encoding: .utf8) else {
            throw StoreVersionError.malformed(path: path, line: "(標記檔不是 UTF-8)")
        }
        var found: Int?
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            // 有內容的行必須頂格（守衛字元集與上面 trim 的一致：Unicode Zs ∪ tab）。
            // 縮排 case 的 payload 用**原始行**（#127 verify F3）：trim 過的版本看起來
            // 完全合法（縮排正是被拒的原因，卻被 trim 掉了）。
            // 全部 payload 過 displaySafe（#127 verify M2）：這裡的 line 是攻擊者可控
            // 的檔案原文——ESC/bidi/超長行不得原樣進 error（StoreIOError 同模式；
            // CLI 頂層的 choke point 是 #114 的另一層，兩者互補不互代）。
            guard let first = raw.unicodeScalars.first,
                  !CharacterSet.whitespaces.contains(first) else {
                throw StoreVersionError.malformed(path: path, line: displaySafe(String(raw)))
            }
            guard line.hasPrefix("format:") else {
                throw StoreVersionError.malformed(path: path, line: displaySafe(line))
            }
            guard found == nil else {
                throw StoreVersionError.malformed(path: path, line: "(第二個 format: 行——歧義)")
            }
            let v = line.dropFirst("format:".count)
                .trimmingCharacters(in: .whitespaces)
            let numeric = v.prefix { $0.isNumber }
            guard let n = Int(numeric), n >= 1 else {
                throw StoreVersionError.malformed(path: path, line: displaySafe(line))
            }
            // 值後面只能是註解（`format: 1  # v1.x`）——`format: 2 garbage` 與
            // `format: 2.5` 都不是「帶註解的整數」，不得取前綴當真
            let rest = v.dropFirst(numeric.count).trimmingCharacters(in: .whitespaces)
            guard rest.isEmpty || rest.hasPrefix("#") else {
                throw StoreVersionError.malformed(path: path, line: displaySafe(line))
            }
            found = n
        }
        guard let found else {
            // 檔案存在但沒有 format: 行——不猜，明說。
            throw StoreVersionError.malformed(path: path, line: "(檔案內找不到 format: 行)")
        }
        return found
    }

    /// 開 store 前的防線。version 超過本 binary 支援上限 → 整體拒絕。
    public static func check(root: URL) throws {
        let found = try read(root: root)
        guard found <= supported else {
            throw StoreVersionError.tooNew(found: found, supported: supported)
        }
    }

    /// 寫入指定 format。**只給遷移用**——一般流程不得改動既有 store 的 format。
    public static func write(root: URL, format: Int) throws {
        let body = """
            # Akashic store format（#24）。只有 **non-additive** 變更才 bump——
            # 那條規則講的是**記錄層**（entities/ 底下的 YAML）：那裡未知欄位由
            # tolerant-preserve 涵蓋（#23），加欄位不 bump。
            #
            # **本檔案本身不在那個涵蓋範圍內。** 這裡的 parser 對任何非 `format:`
            # 的有內容行直接 throw——加一行進來，所有既有 binary 會拒絕開啟整個
            # store，不是忽略它。要加 store 級的欄位請另開檔案（#130 的
            # `incarnation` 就是這樣做的：根目錄獨立檔，舊 binary 完全容忍）。
            #
            # 舊 binary 讀到比自己新的 format 會整體拒絕開啟，而不是按舊語意誤讀。
            format: \(format)

            """
        try body.write(to: url(in: root), atomically: true, encoding: .utf8)
    }

    /// 建立標記檔（若不存在）。**不覆寫既有檔**——那可能是較新版本寫的，
    /// 覆寫等於把 refuse-if-newer 的依據自己抹掉。
    public static func writeIfAbsent(root: URL) throws {
        let u = url(in: root)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: u.path) else { return }

        // **#35 的關鍵安全點**：沒有 marker 的 store 可能是 #24 之前建的 **legacy** store。
        // 若無條件寫 `supported`（現在是 2），它會被誤標成 entities 佈局——而它的檔案
        // 全在 `entries/` 與 `people/`。之後的寫入會往 `entities/` 去，讀取端則同時看到
        // 兩個佈局，**而且沒有任何訊號說出哪裡不對**。
        //
        // 所以：有 legacy 內容 → 標 1（它就是 format 1）；全新的空 store → 標 supported。
        func hasFiles(_ dir: URL) -> Bool {
            ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? [])
                .contains { $0.lowercased().hasSuffix(".yaml") }
        }
        let legacy = hasFiles(root.appendingPathComponent("entries"))
            || hasFiles(root.appendingPathComponent("people"))
        let format = legacy ? 1 : supported
        try write(root: root, format: format)
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
            // 指路（#118）：對照 tooNew 的「請升級」，malformed 也要有出口——
            // 修復入口（doctor）對它第一步就拒絕，使用者被正確地擋下之後
            // 不能不知道往哪走。**不提供自動修復**：marker 是 canonical 事實，
            // 自動改寫它與 writeIfAbsent 的「不覆寫既有檔」哲學衝突（#106 的
            // 整個教訓是「對壞 marker 不猜」）——人工修檔 + 清楚指引已足夠。
            return """
                store format 標記無法解析：\(path)（\(line)）
                合法形狀：檔內只有註解行與**一個**頂格的 `format: <正整數>` 行\
                （規格見 docs/store-format.md §5.0）。修復方式：
                1. 手動修檔——把 \(StoreVersion.fileName) 改回上述形狀\
                （不確定原值時看 git 歷史或備份）
                2. 確定這是 #24 之前建的 v1.x store 被外力加料——可刪除 \(StoreVersion.fileName)\
                 重跑 doctor（**只對真的是 v1.x 的 store 安全**：不是 v1.x 的 store 會被\
                重標成 format \(StoreVersion.supported)——較新的被按舊語意誤讀、較舊的\
                （format 2–\(StoreVersion.supported - 1)）被按新語意誤讀（如整庫 quarantine）。\
                怎麼判斷：磁碟上有 entries/＋people/ 的 yaml → v1.x；有 entities/ → ≥2）
                """
        }
    }
}
