import Foundation
import CryptoKit
import AkashicCore

/// 階段 B 的摘要存檔（NDJSON）→ `akashic enrich --from` 的 `[Proposal]`（#516；#629 由
/// `ndjson-abstracts-to-proposals.py` 移植）。
///
/// # 為什麼原本住在 skill 而不是 CLI 子命令，以及為什麼現在是子命令
///
/// NDJSON 的形狀（每列 `{"doi","status","abstract","title","year","landing","page_title","retrieved"}`）是 `akashic-venue-works`
/// 階段 B 的 scrape 產物，不是 store 的契約；store 的公開面只有 `[Proposal]` JSON，而 `AddOnlyEnrichment.decodeProposals`
/// 是它唯一的解析器。#516 當時把私有形狀焊進 CLI 會要在 `mcp-cli-parity` 加一列，所以把 adapter 放在 skill 目錄。
/// #629（`swift-is-the-implementation-language`）把「新的程式一律是 Swift」成文後，skill 目錄裡不得有 Python 腳本，
/// 於是 adapter 成為 `akashic abstracts-to-proposals`：它仍**只是**一個 adapter（輸入是 skill 的私有產物、輸出是 core 的
/// 公開格式），不寫 store、不進 MCP（`mcp-cli-parity` CLI-only 表一列）。
///
/// # 三條紀律（舊腳本的 docstring 逐條保留）
///
/// 1. 只收 `status == "got"`、摘要非空、DOI 在場的列；其餘每一列在 stderr 逐筆具名
///    （`skip\t<reason>\t<doi>\tline <n>`）——丟棄必須可見（`lossless-intake` 執行細節 3）。
///    摘要是 Crossref「這個 DOI 沒有 metadata」的固定樣板（開頭 `This DOI is not currently attached to any metadata records`）時
///    同樣略過（`crossref-no-metadata`，#544）：那是錯誤頁文字，不是這篇的摘要。
///    **這道守衛不是那 21 筆進庫的路徑**：那 21 筆是 2026-09-01 的 #423 階段 A（OpenAlex `abstract_inverted_index` 還原 →
///    `create-entry`）建檔時帶進來的，OpenAlex 回傳的摘要本身就是這段樣板；本轉換 2026-09-07 才新增。它守的是另一件事：
///    `update-entry --remove-field` 把那 21 筆的摘要移除之後，它們沒有摘要、會被排回階段 B——若階段 B 對它們抓到同一個樣板，
///    這裡擋得住。核心層（`create-entry`／`enrich`／`validate`）不過濾，那是 #676 的裁決題。
///    **這個字串在程式裡只有一份**（`crossrefNoMetadata`），但 plugin 的 `akashic-venue-works/SKILL.md` 階段 A 另抄了一份——plugin 讀者
///    讀不到這個 private repo 的 Swift 檔，判準得寫在他們讀得到的地方（#629 R1 verify 第 48 則：先前這裡寫「只有一份」，與 SKILL.md 並存的
///    事實不符）。兩份之間由 `AbstractProposalsPythonJSONTests.testTheSkillsCopyOfTheNoMetadataTemplateEqualsTheConstant` 對帳，
///    改字串時那個測試會紅。
/// 2. `doi` **原樣透傳**：URL 前綴與大小寫由 core 的 `DOI` 正規化吸收，這裡**不**複製那條規則。轉換自己只有一條更弱的身分規則
///    ——逐位元相同的 DOI 字串——大小寫／前綴不同的近重複兩筆都輸出、留給 core（它會把第二筆報成 `skipped`，不會靜默）。
///    同 DOI 而摘要**不同**不是冗餘是衝突：理由印 `conflicting-duplicate`，與 `duplicate-doi` 分開具名（#516 verify）。
/// 3. 決定論、無網路：同一輸入輸出逐位元相同。`--source` 給 digest 時走 `sources/<前 2 hex>/<其餘 62>`（`SourceStore` 的分片
///    慣例，路徑由 `LibraryStore.sourceBlobURL` 給）並驗 sha256；給路徑時由位元組算出 `sourceDigest`。
///
/// skip 報告不可被資料偽造：`doi`／`status` 裡的控制字元跳脫、長度截斷（`displaySafe`），`doi` 含換行不得憑空多出一列（#516 verify）。
public enum AbstractProposals {

    /// Crossref 對沒有 metadata 的 DOI 回的固定樣板開頭（#544；live store 的 21 筆逐字以它開頭）。
    public static let crossrefNoMetadata = "This DOI is not currently attached to any metadata records"

    public struct Skip: Equatable {
        /// 略過的理由標籤（`no-doi`、`status:<值>`、`empty-abstract`……）。**欄位名不叫 `reason`**：`SanitizationBoundaryTests` 把 `reason` 當作「已消毒的載體」名字（`QuarantinedFile.reason` 等），
        /// 對它再跑 `displaySafe` 會被判成二次逃脫；這個標籤的內容含資料（`status:` 之後是來源給的值），要在輸出端消毒。
        public var cause: String
        public var doi: String
        public var line: Int
    }

    public struct Conversion {
        /// 每個提案是 `{"doi", "fields": {"abstract"}, "sourceDigest"}`（鍵已依字典序排好——輸出用 `sort_keys`）。
        public var proposals: [PyJSON]
        public var skips: [Skip]
        /// 非空白列數（rows 不算空行）。
        public var rows: Int
    }

    /// 兩個字串「逐 code point 相同」（Swift 的 `String ==` 是 canonical equivalence，NFC 與 NFD 會相等；Python 不會）。
    private static func sameBytes(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }

    /// 把 UTF-8 位元組解成文字：去掉開頭的 BOM（Python 的 `utf-8-sig`）；不是合法 UTF-8 回 nil 與第一個壞位元組的位置。
    static func decodeUTF8SIG(_ data: Data) -> (text: String?, badByte: Int) {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        if let s = String(data: bytes, encoding: .utf8) { return (s, 0) }
        var decoder = UTF8()
        var it = bytes.makeIterator()
        var offset = 0
        loop: while true {
            switch decoder.decode(&it) {
            case .scalarValue(let s): offset += UTF8.width(s)
            case .emptyInput: break loop
            case .error: return (nil, offset)
            }
        }
        return (nil, offset)
    }

    /// Python 的 `str(x)`（只涵蓋 JSON 值：`status:{status}` 這種理由字串要用）。
    private static func pyStr(_ any: Any?) -> String {
        switch any {
        case nil, is NSNull: return "None"
        case let s as String: return s
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "True" : "False" }
            return CFNumberIsFloatType(n) ? PyJSON.repr(n.doubleValue) : String(n.intValue)
        default: return PyJSONBridge.convert(any).dumps()
        }
    }

    /// 轉換。壞的輸入（非 UTF-8、某行不是合法 JSON 物件）整批拒絕、不輸出任何提案。
    public static func convert(_ data: Data, digest: String) throws -> Conversion {
        var proposals: [PyJSON] = []
        var skips: [Skip] = []
        var seen: [[UInt8]: String] = [:]   // doi 的位元組 → 已接受的摘要（判冗餘 vs 衝突）
        var rows = 0
        let decoded = decodeUTF8SIG(data)
        guard let text = decoded.text else {
            throw SkillToolError.failure("✗ 存檔不是 UTF-8（byte \(decoded.badByte)）——不輸出任何提案")   // display-safe-exempt: decoded：badByte 是 Int 位置
        }
        for (index, lineScalars) in PyText.splitLines(Scalars(text.unicodeScalars)).enumerated() {
            let n = index + 1
            let raw = PyText.string(lineScalars)
            if PyText.strip(lineScalars).isEmpty { continue }
            rows += 1
            let row: [String: Any]
            do {
                guard let obj = try PyJSONParser.parse(Data(raw.utf8)) as? [String: Any] else {
                    throw SkillToolError.failure("✗ 第 \(n) 行不是 JSON 物件")   // display-safe-exempt: n 是 Int 行號
                }
                row = obj
            } catch let e as SkillToolError {
                throw e
            } catch {
                throw SkillToolError.failure("✗ 第 \(n) 行不是合法 JSON：\(displaySafeErrorText(error))")   // display-safe-exempt: n 是 Int 行號
            }
            let doiValue = row["doi"] as? String
            let abstractValue = row["abstract"] as? String
            let statusValue = row["status"]
            let statusIsGot = (statusValue as? String) == "got"
            let trimmedDOI = doiValue.map { PyText.string(PyText.strip(Scalars($0.unicodeScalars))) } ?? ""
            let abstractTrimmed = abstractValue.map { PyText.string(PyText.strip(Scalars($0.unicodeScalars))) }
            var cause: String?
            if doiValue == nil || trimmedDOI.isEmpty {
                cause = "no-doi"
            } else if !statusIsGot {
                cause = "status:\(pyStr(statusValue))"
            } else if abstractTrimmed == nil || abstractTrimmed!.isEmpty {
                cause = "empty-abstract"
            } else if abstractTrimmed!.utf8.starts(with: crossrefNoMetadata.utf8) {
                cause = "crossref-no-metadata"
            } else if let earlier = seen[Array(doiValue!.utf8)] {
                cause = sameBytes(earlier, abstractTrimmed!) ? "duplicate-doi" : "conflicting-duplicate"
            }
            if let cause {
                skips.append(Skip(cause: cause, doi: (doiValue != nil && !trimmedDOI.isEmpty) ? doiValue! : "(no doi)", line: n))
                continue
            }
            let doi = doiValue!, abstract = abstractTrimmed!
            seen[Array(doi.utf8)] = abstract
            proposals.append(.object([
                ("doi", .string(doi)),
                ("fields", .object([("abstract", .string(abstract))])),
                ("sourceDigest", .string(digest)),
            ]))
        }
        return Conversion(proposals: proposals, skips: skips, rows: rows)
    }

    /// 輸出文字：`json.dumps(proposals, ensure_ascii=False, indent=2, sort_keys=True) + "\n"`。
    public static func render(_ proposals: [PyJSON]) -> String { PyJSON.array(proposals).dumps(indent: 2) + "\n" }

    /// stderr 的報告：逐筆 skip 行，再一行總結。**skip 行的每個欄位都消毒**——資料本身不能改寫報告的形狀。
    public static func reportLines(_ c: Conversion) -> [String] {
        var lines = c.skips.map { "skip\t\(displaySafeInvisible($0.cause, max: 60))\t\(displaySafeInvisible($0.doi))\tline \($0.line)" }
        var counts: [String: Int] = [:]
        for s in c.skips { counts[s.cause, default: 0] += 1 }
        let detail = counts.keys.sorted { Array($0.unicodeScalars.map(\.value)).lexicographicallyPrecedes(Array($1.unicodeScalars.map(\.value))) }
            .map { "\(displaySafeInvisible($0, max: 60))=\(counts[$0]!)" }.joined(separator: ", ")
        lines.append("rows=\(c.rows) proposals=\(c.proposals.count) skipped=\(c.skips.count)" + (detail.isEmpty ? "" : " (\(detail))"))
        return lines
    }

    // MARK: 來源

    /// `sha256:` 之後恰 64 個十六進位字元（不分大小寫）。
    static func digestHex(_ source: String) -> String? {
        guard source.hasPrefix("sha256:") else { return nil }
        let hex = source.dropFirst("sha256:".count)
        guard hex.utf8.count == 64, hex.utf8.allSatisfy({ ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x46) || ($0 >= 0x61 && $0 <= 0x66) }) else { return nil }
        return hex.lowercased()
    }

    /// 回 (位元組, digest)。digest 形（`sha256:` 開頭，不分大小寫判斷「是不是 digest 形」）走內容定址並驗雜湊；否則當路徑、由位元組算 digest。
    /// - Parameter blobURL: 由 digest 給存檔路徑的函式（`LibraryStore.sourceBlobURL`）；只有 digest 形會用到。擲出的錯誤原樣往上；回 nil＝digest 形狀不合法。
    public static func resolveSource(_ source: String, blobURL: (String) throws -> URL?) throws -> (data: Data, digest: String) {
        if source.lowercased().hasPrefix("sha256:") {
            guard let hex = digestHex(source) else {
                throw SkillToolError.failure("✗ 不是合法的 digest（sha256: 之後須恰 64 個 hex）：\(displaySafeInvisible(source, max: 90))")
            }
            let digest = "sha256:\(hex)"
            // store 解析失敗（沒有 --library、registry 沒有 current……）由 `blobURL` 擲出、原樣往上：第一版把它吞成 nil，於是報出
            // 「不是合法的 digest」——形狀合法的 digest 被說成形狀錯，診斷指錯方向（R1 verify 第 38 則）
            guard let url = try blobURL(digest) else { throw SkillToolError.failure("✗ 不是合法的 digest：\(displaySafeInvisible(source, max: 90))") }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
                throw SkillToolError.failure("✗ 存檔不存在：\(displaySafeInvisible(url.path, max: 400))（digest \(digest)）")   // display-safe-exempt: digest：由 digestHex 驗過的 `sha256:` 加 64 個十六進位字元
            }
            let data = try readFile(url)
            let actual = sha256Hex(data)
            guard actual == hex else {
                throw SkillToolError.failure("✗ 內容定址不符：\(displaySafeInvisible(url.path, max: 400)) 的 sha256 是 \(actual)，不是 \(hex)——不輸出任何提案")   // display-safe-exempt: actual、hex：SHA-256 的十六進位輸出與驗過形狀的 digest
            }
            return (data, digest)
        }
        let url = URL(fileURLWithPath: source)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            throw SkillToolError.failure("✗ 檔案不存在：\(displaySafeInvisible(source, max: 400))")
        }
        let data = try readFile(url)
        return (data, "sha256:" + sha256Hex(data))
    }

    private static func readFile(_ url: URL) throws -> Data {
        do { return try Data(contentsOf: url) } catch {
            throw SkillToolError.failure("✗ 讀不到 \(displaySafeInvisible(url.path, max: 400))：\(displaySafeErrorText(error))")
        }
    }

    static func sha256Hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    // MARK: `--out`

    /// `os.path.abspath(os.path.expanduser(p))`：展開開頭的 `~`、相對路徑接上 cwd、以**字面**正規化 `.` `..` 與重複斜線
    /// （**不**解 symlink——舊實作印的是它實際操作的那條路徑）。
    static func absolutePath(_ path: String) -> String {
        var p = (path as NSString).expandingTildeInPath
        if !p.hasPrefix("/") { p = FileManager.default.currentDirectoryPath + "/" + p }
        var parts: [Substring] = []
        for comp in p.split(separator: "/", omittingEmptySubsequences: true) {
            if comp == "." { continue }
            if comp == ".." { if !parts.isEmpty { parts.removeLast() }; continue }
            parts.append(comp)
        }
        return "/" + parts.joined(separator: "/")
    }

    /// `--out` 的寫入語意（#519 Expected 1 裁決）。三條，順序固定：
    ///
    /// 1. 目標存在且**不是普通檔**（symlink／目錄／FIFO／socket／device）→ 硬錯誤、具名、零寫入。
    /// 2. 否則同目錄開 temp、寫完 `rename()` 原子替換。
    /// 3. **無論成敗**，把解析後的絕對路徑交給 `announce`（呼叫端印到 stderr）。
    ///
    /// **為什麼拒絕 symlink 而不是「跟隨但原子替換」**：#516 verify 實測 `ln -sf victim.txt outlink.json` 之後
    /// `--out ./outlink.json` **改到了 victim.txt**——逃逸到另一條路徑。原子替換本身不會逃逸（`rename(2)` 作用在名字上、不跟隨
    /// symlink），但那會把使用者刻意建立的導向**默默換成實體檔**。拒絕是唯一不做假設的選項。
    ///
    /// **為什麼不加 `--force`**：本 repo 對 `--force` 有明文立場（`idd-close`）。重跑覆寫這個中間產物是**常態**動作，把常態放在旗標
    /// 後面訓練出來的正是那個反射。**為什麼印絕對路徑**：`--out ~/.akashic/store.yaml` 這種**指錯地方**，上面兩條都擋不住（它是
    /// 普通檔）；可見性才是對症的。
    ///
    /// **權限會變，而這是刻意的**：`mkstemp` 建的檔是 `0600`，`rename` 換的是 inode，所以覆寫一個既有的 `0644` 檔之後它會變成
    /// `0600`（舊實作同，實測）。`proposals.json` 裝的是第三方逐字摘要（含出版商版權聲明），`0600` 對這個內容更對。寫出來是因為它是
    /// **安靜的**行為改變。
    ///
    /// **`lstat` 只查最後一段——父目錄若是 symlink，寫入仍會穿透過去**。這不是漏掉的檢查，是刻意的範圍：第 1 條防的是「寫穿到另一個
    /// **檔**」，目錄層的重導向是檔案系統的正常語意。但它削弱第 3 條的可見性承諾（印出來的是未解析的路徑）。**不改成印 `realpath`**：
    /// macOS 的 `$TMPDIR` 本身就是 `/var → /private/var`，那會讓每一次正常執行都多印一行雜訊。
    ///
    /// **TOCTOU**：第 1 條與第 2 條之間有窗，但那個窗**不會造成逃逸**——`rename` 換的是名字，即使競爭者剛插入一個 symlink，被換掉的
    /// 也是那個 symlink 本身。第 1 條買到的是「拒絕」而不是「不逃逸」，兩者是不同的性質。
    public static func writeOut(path: String, text: String, announce: (String) -> Void) throws {
        let resolved = absolutePath(path)
        announce("→ --out 寫入 \(displaySafeInvisible(resolved, max: 400))")
        let shown = displaySafeInvisible(resolved, max: 400)

        var st = stat()
        if lstat(resolved, &st) == 0 {
            let mode = st.st_mode & S_IFMT
            if mode != S_IFREG {
                let kind: String
                switch mode {
                case S_IFLNK: kind = "symlink"
                case S_IFDIR: kind = "目錄"
                case S_IFIFO: kind = "FIFO"
                case S_IFSOCK: kind = "socket"
                case S_IFCHR: kind = "字元裝置"
                case S_IFBLK: kind = "區塊裝置"
                default: kind = "非普通檔"
                }
                // 括號裡那句**只對 symlink 為真**——對目錄／FIFO 講「跟隨它會改到另一條路徑上的檔」是假的。訊息按類別分。
                let why = mode == S_IFLNK
                    ? "跟隨它會改到另一條路徑上的檔（#516 verify 實測過），取代它則會默默拆掉你刻意建的導向"
                    : "本命令只寫普通檔"
                throw SkillToolError.failure("✗ --out \(shown) 已存在且是\(kind)，不是普通檔——拒絕寫入，零寫入。\n"
                    + "  \(why)。這個命令的產出是 $TMPDIR 裡的短命中間產物；要寫到別處請直接把那個路徑給 --out。")   // display-safe-exempt: shown 上面已 displaySafeInvisible；kind、why 是本函式的固定字串
            }
        } else if errno != ENOENT {
            throw SkillToolError.failure("✗ 無法檢查 --out \(shown)：\(displaySafeInvisible(String(cString: strerror(errno)), max: 200))")   // display-safe-exempt: shown 上面已 displaySafeInvisible
        }

        let dir = (resolved as NSString).deletingLastPathComponent
        let name = (resolved as NSString).lastPathComponent
        var template = Array("\(dir)/.\(name).XXXXXX.tmp".utf8CString)
        let fd = mkstemps(&template, 4)
        guard fd >= 0 else {
            throw SkillToolError.failure("✗ 無法寫入 --out \(shown)：\(displaySafeInvisible(String(cString: strerror(errno)), max: 200))")   // display-safe-exempt: shown 上面已 displaySafeInvisible
        }
        let tmp = String(cString: template)
        var failure: String?
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
        } catch {
            failure = displaySafeErrorText(error)
        }
        if failure == nil, rename(tmp, resolved) != 0 { failure = String(cString: strerror(errno)) }
        if let failure {
            unlink(tmp)
            throw SkillToolError.failure("✗ 無法寫入 --out \(shown)：\(displaySafeInvisible(failure, max: 300))")   // display-safe-exempt: shown 上面已 displaySafeInvisible
        }
    }
}
