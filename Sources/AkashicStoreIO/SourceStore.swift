import Foundation
import CryptoKit
import AkashicCore

/// 擷取內容的存檔（#66 task 4.x）：`sources/<前2字元>/<其餘>`、內容定址、無副檔名。
///
/// **存檔不進 remote**（spec：Stored content SHALL NOT be tracked by the
/// version-control remote）——它是第三方逐字位元組，與本專案對 raw 逐字稿的處置
/// 相同。排除是 **fail-closed 的驗證**不是文件慣例（D5）：寫入前以 git 自身的
/// 忽略判定確認，未生效拒寫——外流不可逆，不能押在「使用者記得設定」上。
///
/// **存檔不是 entity**（spec 兩個獨立理由，任一充分）：網頁不決定記錄形狀、
/// 不讓 loader 分岔；且內容定址的身分被位元組窮盡——改一個 byte 就是另一串，
/// 沒有名字、沒有歷史、沒有生命週期，與 entity「改名後仍是同一物」正好相反。
public extension LibraryStore {

    var sourcesDir: URL { root.appendingPathComponent("sources") }

    /// `sources/` 單份內容的大小上限（#703，使用者 2026-09-30 裁決「三件都做，上限 256 MB」）：**268,435,456 bytes（256 MiB）**。
    /// 裁決的「256 MB」照原話引用；數值是 2^28，給人看的寫法一律是 MiB（R1 verify 第 30 則：以 10⁶ 讀，268,000,000 bytes 的檔會被收）。
    ///
    /// 超過的內容**不截斷、不存**、具名拒絕：`store-source`（CLI／MCP）整個呼叫拒絕、零寫入；`copy-zotero-attachments` 逐檔略過並印出
    /// 路徑與大小，其餘照跑。錨點是 2026-09-30 的本機實測：Zotero storage 最大單檔 5,499,190 bytes（全部 2,817 個檔、磁碟用量 66 MB），上限是它的 48.8 倍——
    /// 量法見 `docs/zero-instance-measurements.md` 第 72 列（`zero-instance-guards` 第 72 列的量測）。
    ///
    /// **只有這一份**（`no-compat-fallback` §同一件事只能有一份描述）：`storeSource`、`ZoteroStorageFile` 的定位與開檔、`store-source` 的入口
    /// 都讀這個常數；各函式的 `limit` 參數只是測試接縫，預設值就是它。要調整回 #703 重新裁決。
    static let maxSourceBytes = 268_435_456

    /// 上限給人看的寫法（錯誤訊息、報告共用）：整除 1 MiB 時附上 MiB 數。
    static func sourceCapDescription(_ limit: Int) -> String {
        limit > 0 && limit % (1 << 20) == 0 ? "\(limit) bytes（\(limit >> 20) MiB）" : "\(limit) bytes"
    }

    /// 寫入的回條：digest 之外**記錄排除驗證是否真的跑了**（D5：store 非 git repo
    /// 時跳過驗證，但跳過的事實不沉默——呼叫端可轉發給使用者）。
    struct SourceReceipt: Equatable {
        public let digest: String
        public let exclusionVerified: Bool
        /// #224：這次呼叫有沒有**新增** index 條目。false = 同 digest 條目已存在
        /// （冪等重存），不重複 append——呼叫端要能分辨「記了」與「早就記過」。
        public let indexEntryCreated: Bool
        /// #224 verify D2（lossless-intake「丟棄必須可見」）：冪等早退時，呼叫端
        /// 這次交來、但**沒有被寫入**的 provenance（既有條目以先到為準）。
        /// nil = 沒有丟棄任何東西。
        public let discardedProvenance: SourceProvenance?
        /// 這次呼叫有沒有**寫出** blob（false＝同 digest 的 blob 已經在 `sources/`）。與 `indexEntryCreated` 是兩件事：
        /// index 有條目而 blob 被清過時，這次寫出位元組、卻不新增條目（#606 R2 verify：呼叫端要能分辨「位元組早就在」與「這次才存」）。
        public let bytesWritten: Bool
    }

    /// #224：存 source 時**必須**一起提供的 provenance——blob 本身只是位元組，
    /// 沒有這些欄位它什麼都不證明。欄位形狀以既有 `sources/index.jsonl` 的
    /// 7 條手工條目為事實來源。
    struct SourceProvenance: Equatable {
        public let mediaType: String
        public let retrieved: String
        public let origin: String
        public let acquisition: String
        public let note: String?

        public init(mediaType: String, retrieved: String, origin: String,
                    acquisition: String, note: String? = nil) {
            self.mediaType = mediaType
            self.retrieved = retrieved
            self.origin = origin
            self.acquisition = acquisition
            self.note = note
        }
    }

    /// digest → 存檔路徑。形狀錯回 nil（呼叫端決定 throw 與否）。
    ///
    /// **位址層只看形狀**（`isWellFormedDigest`，#654）：空內容的 digest 不可被引用，但它是一個合法的位址——
    /// live store 有一個空 blob 住在那裡（#546 之前留下的）。
    internal func sourceURL(digest: String) -> URL? {
        guard ProvenanceReference.isWellFormedDigest(digest) else { return nil }
        let hex = String(digest.dropFirst("sha256:".count))
        return sourcesDir.appendingPathComponent(String(hex.prefix(2)))
            .appendingPathComponent(String(hex.dropFirst(2)))
    }

    /// 存檔在 `sources/` 的路徑（#629：階段 B 摘要轉換要讀存檔的位元組，而分片慣例只能有一份描述——就是上面那個 `sourceURL`）。
    /// digest 形狀不合法回 nil；不檢查檔案存在與否。
    func sourceBlobURL(digest: String) -> URL? { sourceURL(digest: digest) }

    /// 內容的 digest（`sha256:` + 小寫十六進位，算在原始位元組上）。`storeSource` 落地的位址就是它；只有這一份公式（#606：多筆操作要在寫入之前
    /// 算出 digest 做預演與去重，再自己算一遍就是兩份會分岔的位址規格）。#703 起檔案走逐塊的 `contentDigest(reading:)`，兩個入口共用 `digestText`。
    static func contentDigest(of data: Data) -> String {
        digestText(SHA256.hash(data: data))
    }

    /// 兩個入口（整份與逐塊）共用的 digest 文字形——`sha256:` + 64 個小寫十六進位。
    internal static func digestText(_ digest: SHA256.Digest) -> String {
        "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 串流存檔的結果（#703）。內容層面的拒絕是**正常輸出**，不是擲出的錯：批次呼叫端（`copy-zotero-attachments`）逐檔略過並具名、
    /// 其餘照跑；單檔呼叫端（`store-source`）把它轉成說出路徑的錯誤。store 層面的問題（index 腐壞、版控排除沒生效、I/O）照舊擲出。
    enum SourceIntake: Equatable {
        case stored(SourceReceipt)
        case refused(SourceContentRefusal)
    }

    /// 內容層面的拒絕（#703）。封閉列舉，每一種都是零寫入：不留 blob、不留暫存檔、不寫 index。
    enum SourceContentRefusal: Equatable {
        /// 0 byte（#546）：空內容的 digest 對所有空輸入都相同，不指認任何一份存檔。
        case empty
        /// 超過上限（`maxSourceBytes`）。值是實際大小（stat 的大小；讀的時候長大時是讀到的量與當下大小取大者）。
        case tooLarge(bytes: Int)
        /// 內容與預期不同：呼叫端給的 `expectedDigest` 對不上，或算 digest 那一遍與複製那一遍之間內容變了。值是實際讀到的 digest。
        case changed(actual: String)
    }

    /// #224 verify（Codex #4）：sidecar 已腐壞時不可宣稱冪等——malformed 行讓重複檢查不可靠（同 digest 可能藏在解析不出的行裡）。
    /// `storeSource` 與 `preflightStoreSource` 共用這一句。
    private func assertIndexHasNoMalformedLines(_ malformedLines: [Int]) throws {
        guard malformedLines.isEmpty else {
            throw StoreIOError.invalidInput(
                what: "sources/index.jsonl",
                why: "有 \(malformedLines.count) 行無法解析（行號 \(malformedLines.map(String.init).joined(separator: ", "))）。"   // display-safe-exempt: malformedLines.map(String.init).joined(separator: ", ")：行號 Int 清單（scanIndex 產出的 1-based 行號）
                    + "index 腐壞時不可判定冪等——先修復（akashic doctor 會列出），再存新 source")
        }
    }

    /// #606：`storeSource` 在**任何磁碟寫入之前**會擋的閘（index 有壞行、這個 digest 的 blob 路徑、暫存檔路徑與 index 路徑沒被版控排除、
    /// git 不可用），不寫任何東西。多筆操作（`copy-zotero-attachments`）在第一次寫入之前對每個要存的 digest 預演它：乾跑說「可以」時，實跑不會在第一個
    /// `storeSource` 才被拒；被拒時零寫入、不留孤兒 blob。排除驗證問的是**這個 digest 的實際路徑**（#145：寫死的探測路徑會 fail-open），
    /// 所以每個 digest 各問一次。
    ///
    /// **例外一格（#703 b29 V5；b31 W5 LOW 4、6 補寫在這裡）**：磁碟區**沒有回報**能力旗標時，預演不探測（探測要建檔，乾跑不寫）——
    /// 乾跑說「可以」，實跑由 `writeBlob` 的 `assertDirectoryCanPlace` 在每一筆複製之前實際放一次，做不到就逐筆具名拒絕（每筆進 `writeFailed`，
    /// 不是單一的整批拒絕）；被拒的那一筆零寫入（探測檔刪掉、這一步建的分片目錄收回），已存的前幾筆不受影響。旗標說做不到時與 `storeSource` 同一道閘、整批拒絕。
    ///
    /// `temporaryToken`（#703 R1）：實跑要用的暫存檔名的 token——呼叫端把同一個交給 `storeSource(contentsOf:…temporaryToken:)`，
    /// 預演問的就是實跑會建立的那條路徑。位址上已經有東西時實跑不建暫存檔，預演仍然問（偏嚴，不偏鬆）。
    func preflightStoreSource(digest: String, temporaryToken: String = UUID().uuidString) throws {
        try preflightStoreSource(digest: digest, temporaryToken: temporaryToken, placement: .system)
    }

    /// `preflightStoreSource` 的接縫版：多問一件事——`sources/` 所在的磁碟區做不做得到不覆寫的原子放置（b26 F6：旗標說做不到就整批拒絕、零寫入，
    /// 與 `storeSource` 的第一步同一道閘；旗標讀不到時這裡不擋，見上面的例外一格）。
    internal func preflightStoreSource(digest: String, temporaryToken: String, placement: BlobPlacement) throws {
        try assertSourcesVolumeCanPlace(placement)
        guard ProvenanceReference.isWellFormedDigest(digest) else {
            throw StoreIOError.invalidInput(
                what: "source digest",
                why: "digest 形狀必須是 sha256: + 64 個小寫 hex，實得「\(displaySafeInvisible(digest, max: 120))」")
        }
        try Self.checkTemporaryToken(temporaryToken)
        try assertIndexHasNoMalformedLines(try scanIndex().malformedLines)
        let hex = String(digest.dropFirst("sha256:".count))
        try assertSourcesExcluded(relativePath: "sources/\(hex.prefix(2))/\(hex.dropFirst(2))")
        try assertSourcesExcluded(relativePath: "sources/\(hex.prefix(2))/\(Self.temporaryBlobName(digest: digest, token: temporaryToken))")
        try assertSourcesExcluded(relativePath: "sources/index.jsonl")
    }

    /// #224：存 source 的**唯一**公開動作——blob 與它的 provenance 條目一起落地。
    ///
    /// 序：先 blob（含 fail-closed 排除驗證）、成功後 append index 條目。部分失敗
    /// （blob 成功、append 失敗）throw 且留下的孤兒由 `auditSourceIndex` 兜底可見。
    /// 同 digest 已有條目 → 不重複 append，`indexEntryCreated: false`（provenance
    /// 以先到的為準；重存不覆寫既有敘述——append-only，index 永不重寫既有行）。
    ///
    /// 沒有「只存 blob、不記 provenance」的入口（no-compat-fallback：那條 default
    /// 路徑正是 index 腐爛的來源——本 issue 之前的 7 個 blob 全靠手工補記）。
    ///
    /// 這是已經在記憶體裡的內容的入口；檔案走 `storeSource(contentsOf:)`（#703：逐塊，不整份讀進記憶體）。兩個入口同一條路徑
    /// （`storeSource(chunks:)`），內容層面的拒絕在這裡轉成具名的錯誤：0 byte（#546）與超過上限（#703）都是整個拒絕、零寫入。
    @discardableResult
    func storeSource(_ data: Data, provenance: SourceProvenance, limit: Int = LibraryStore.maxSourceBytes) throws -> SourceReceipt {
        var chunks = DataChunks(data: data)
        switch try storeSource(chunks: &chunks, provenance: provenance, expectedDigest: nil, limit: limit) {
        case .stored(let receipt):
            return receipt
        case .refused(.empty):
            // #546：下界。空字串的 digest 是常數，任何空輸入都得到它——它不指認任何一份內容，
            // 而兩次不同的失敗抓取會折成同一筆、被去重讀成「早已存過」。與 #519 的上界同型：
            // 整個拒絕、零寫入、具名。
            throw StoreIOError.invalidInput(
                what: "source 內容",
                why: "0 byte——空內容的 digest 對所有空輸入都相同，不指認任何一份存檔。"
                    + "這通常是一次失敗的抓取留下的空檔；重新取得內容再存")
        case .refused(.tooLarge(let bytes)):
            throw StoreIOError.invalidInput(
                what: "source 內容",
                why: "\(bytes) bytes，超過 sources/ 的單份上限 \(Self.sourceCapDescription(limit))——不截斷、不存（#703）")   // display-safe-exempt: bytes、limit 是 Int；Self.sourceCapDescription 只回數字與固定字
        case .refused(.changed(let actual)):
            // 記憶體裡的內容兩遍讀到的不會不同；留著這一格是因為列舉是封閉的，不是因為它走得到
            throw StoreIOError.invalidInput(
                what: "source 內容",
                why: "兩遍讀到的內容不同（\(actual)）——沒有存")   // display-safe-exempt: actual 是本函式算的 SHA-256 十六進位
        }
    }

    /// 從檔案存 source（#703）：**逐塊**——第一遍算 digest（不寫任何東西），第二遍複製進 `sources/` 並再算一次、兩遍相同才落地。
    /// 每塊經 `pump` 讀完即釋放，記憶體不隨檔案大小成長（R1 起；`SourceIntakeMemoryCLITests` 釘住）；handle 要是普通檔（可以回到開頭讀第二遍）。
    ///
    /// - 大小先以 `fstat` 判：0 byte 與超過 `limit` 在讀任何一個位元組之前就拒絕（`.refused`，零寫入）。
    /// - `expectedDigest`：呼叫端先算過的 digest（`copy-zotero-attachments` 計畫時算的）；對不上就 `.refused(.changed)`、什麼都不寫。
    /// - 同 digest 的位置上已有大小相同的普通檔就不寫（內容定址，不覆寫）；其他佔用具名擲出、不寫 index（`writeBlob`，#703 R2）。內容對不對是 `checkStoredBlob` 另外比的事。
    /// - `temporaryToken`：`preflightStoreSource` 預演過的暫存檔名 token（#703 R1）；nil＝這一次現產一個。
    func storeSource(contentsOf handle: FileHandle, provenance: SourceProvenance, expectedDigest: String? = nil,
                     limit: Int = LibraryStore.maxSourceBytes, temporaryToken: String? = nil) throws -> SourceIntake {
        var chunks = HandleChunks(handle: handle)
        return try storeSource(chunks: &chunks, provenance: provenance, expectedDigest: expectedDigest, limit: limit,
                               temporaryToken: temporaryToken)
    }

    /// 兩個入口共用的路徑（#703）。順序：大小（不讀）→ index 腐壞（任何寫入之前）→ 第一遍算 digest（不寫）→ blob（排除驗證 → 第二遍複製）→ index。
    ///
    /// **誠實邊界**（#703 R2 verify 第 16、47 則）：「index 已記過了嗎」是在寫 blob 之前掃的快照，append 在之後；同一份內容的幾個存檔並行時，
    /// 每一個都看到「還沒記」、各 append 一列（實測 6 個並行 6 列）。#703 之前同樣如此（沒有 store 層的鎖），不是本張引入的；讀的一方以第一列為準。
    /// `placement` 是放上位址那一步的測試接縫（#703 R1：模擬不支援 `RENAME_EXCL` 的檔案系統；b26 F6：模擬磁碟區回報做不到不覆寫的原子放置）。
    internal func storeSource<C: SourceChunks>(chunks source: inout C, provenance: SourceProvenance,
                                                expectedDigest: String?, limit: Int, temporaryToken: String? = nil,
                                                placement: BlobPlacement = .system) throws -> SourceIntake {
        if let temporaryToken { try Self.checkTemporaryToken(temporaryToken) }
        // 磁碟區做不到不覆寫的原子放置（exFAT、FAT32）：每一次存檔都具名拒絕，一個位元組都不讀、不寫（b26 F6，使用者 2026-10-02 裁決）
        try assertSourcesVolumeCanPlace(placement)
        // 看得到大小的來源先比上下界——一個位元組都不讀、不寫
        if let size = source.currentSize() {
            if size == 0 { return .refused(.empty) }
            if size > limit { return .refused(.tooLarge(bytes: size)) }
        }
        // #224 verify（Codex #4）：sidecar 已腐壞時不可宣稱冪等——malformed 行讓
        // 重複檢查不可靠（同 digest 可能藏在解析不出的行裡）。fail-closed：先修再寫。
        // 這個檢查在**任何**磁碟寫入之前——拒寫時不留孤兒 blob。
        let scan = try scanIndex()
        try assertIndexHasNoMalformedLines(scan.malformedLines)
        // 第一遍：只算 digest，不寫任何東西（寫入路徑要等 digest 知道了、排除驗證過了才決定）
        try source.rewind()
        let digest: String
        let bytes: Int
        switch try Self.streamDigest(&source, limit: limit) {
        case .overLimit(let n): return .refused(.tooLarge(bytes: n))
        case .digest(let d, let n): (digest, bytes) = (d, n)
        }
        guard bytes > 0 else { return .refused(.empty) }
        if let expectedDigest, expectedDigest != digest { return .refused(.changed(actual: digest)) }
        let blob: (exclusionVerified: Bool, bytesWritten: Bool)
        switch try writeBlob(&source, digest: digest, bytes: bytes, limit: limit,
                             token: temporaryToken ?? UUID().uuidString, placement: placement) {
        case .refused(let why): return .refused(why)
        case .done(let verified, let wrote): blob = (verified, wrote)
        }
        if scan.digests.contains(digest) {
            // 冪等早退。丟棄了呼叫端的 provenance——這必須**可見**（verify D2 /
            // lossless-intake「丟棄必須可見」）：receipt 帶 discardedProvenance，
            // 呼叫端能分辨「早已記過」與「你這份敘述沒被寫入」。
            return .stored(SourceReceipt(digest: digest,
                                         exclusionVerified: blob.exclusionVerified,
                                         indexEntryCreated: false,
                                         discardedProvenance: provenance,
                                         bytesWritten: blob.bytesWritten))
        }
        try appendIndexEntry(digest: digest, bytes: bytes, provenance: provenance)
        return .stored(SourceReceipt(digest: digest,
                                     exclusionVerified: blob.exclusionVerified,
                                     indexEntryCreated: true,
                                     discardedProvenance: nil,
                                     bytesWritten: blob.bytesWritten))
    }

    var sourceIndexURL: URL { sourcesDir.appendingPathComponent("index.jsonl") }

    /// JSON 字串字面量（含引號）。用 JSONEncoder 逃逸，不手寫 escape 表；
    /// `.withoutEscapingSlashes` 讓輸出與 7 筆手工條目同形（不把 `/` 寫成 `\/`）。
    private func jsonLiteral(_ s: String) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = .withoutEscapingSlashes
        guard let arr = String(data: try enc.encode([s]), encoding: .utf8) else {
            throw StoreIOError.invalidInput(what: "provenance 欄位",
                                            why: "無法編碼為 JSON 字串")
        }
        return String(arr.dropFirst().dropLast())
    }

    /// append 一行 index 條目。欄位序固定（content→bytes→media-type→retrieved→
    /// origin→acquisition→note），與既有手工條目同形；只 append、永不重寫既有行。
    ///
    /// 三道防線（#224 verify 整合）：
    /// - **index 路徑自己過 fail-closed 閘**（security HIGH-1：blob 的探測路徑不能
    ///   代替 index 的——#145 教訓同形；`sources/*/` 這種窄規則會放 blob 擋 index）
    /// - **結尾換行守衛**（logic HIGH-2：檔尾無 `\n` 時直接 append 會把新行黏進
    ///   既有行、毀掉它的可解析性——`SourcesIgnoreBlock.swift` 的附加用同一個守衛）
    /// - **O_APPEND**（logic HIGH-1：`FileHandle(forWritingTo:)` 是 O_WRONLY，
    ///   seekToEnd+write 之間無互斥，併發寫者會互相覆寫）
    private func appendIndexEntry(digest: String, bytes: Int,
                                  provenance p: SourceProvenance) throws {
        try assertSourcesExcluded(relativePath: "sources/index.jsonl")
        var line = "{\"content\": \(try jsonLiteral(digest)), \"bytes\": \(bytes), "
            + "\"media-type\": \(try jsonLiteral(p.mediaType)), "
            + "\"retrieved\": \(try jsonLiteral(p.retrieved)), "
            + "\"origin\": \(try jsonLiteral(p.origin)), "
            + "\"acquisition\": \(try jsonLiteral(p.acquisition))"
        if let note = p.note { line += ", \"note\": \(try jsonLiteral(note))" }
        line += "}\n"
        let url = sourceIndexURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // 結尾換行守衛：非空且末位元組不是 \n → 先補一個（不動既有行的位元組）
        var payload = Data(line.utf8)
        if let existing = try? FileHandle(forReadingFrom: url) {
            defer { try? existing.close() }
            if let end = try? existing.seekToEnd(), end > 0 {
                try existing.seek(toOffset: end - 1)
                if let last = try existing.read(upToCount: 1), last != Data("\n".utf8) {
                    payload = Data("\n".utf8) + payload
                }
            }
        }
        // O_APPEND：kernel 層的 append 定位，單一 write() 落整行
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else {
            throw StoreIOError.invalidInput(
                what: "sources/index.jsonl",
                why: "無法開啟寫入（errno \(errno)）；digest \(displaySafeInvisible(digest, max: 120)) 的 blob 已落地，"
                    + "條目未記——akashic doctor 會將其列為孤兒 blob")
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.write(contentsOf: payload)
        try handle.close()
    }

    /// index 的單次掃描：digest 集合 + malformed 行號（兩個消費端共用一份解析，
    /// 重複檢查與 audit 不得對同一份檔案給出不同讀法）。
    ///
    /// - **行號是實際檔案行號**（1-based，含空行——verify req F2：跳過空行再編號
    ///   會在有空行時指錯行）。空行本身不算 malformed（手工編輯的常態）。
    /// - **非法 UTF-8 不 throw**（verify reg F1／sec HIGH-2：診斷工具不得被
    ///   sidecar 的腐爛殺死）：lossy 解碼，壞位元組落在哪一行、那一行就 malformed。
    /// `entries`：每個 digest **第一列**的字串欄位（`bytes` 之類的非字串欄位不收）——provenance 以先到的為準
    /// （`storeSource` 的冪等語意），所以讀回來也取第一列（#614：宣告副本時讓人認得出這份內容是什麼）。
    /// `bytes`：同一列的 `bytes`（整數才收；#703 R2 verify 第 4 則：宣告副本與 audit 拿它比對位址上那一份的大小）。
    private func scanIndex() throws -> (digests: Set<String>, malformedLines: [Int], entries: [String: [String: String]],
                                        bytes: [String: Int]) {
        guard FileManager.default.fileExists(atPath: sourceIndexURL.path) else {
            return ([], [], [:], [:])
        }
        // 讀不到要**具名**（b11c R1 verify 第 20 列）：裸的 Foundation 錯誤只說「The file … couldn't be opened」，不說是 index、也不說
        // 後果。`fileExists` 對目錄也回 true，所以「位置被目錄佔了」與權限問題都落在這裡。三個消費端（存檔、audit、宣告副本）共用。
        let raw: Data
        do {
            raw = try Data(contentsOf: sourceIndexURL)
        } catch {
            throw StoreIOError.invalidInput(
                what: "sources/index.jsonl",
                why: "讀不到（錯誤碼 \((error as NSError).code)）——檢查它的權限，以及那個位置是不是被目錄之類的東西佔了。"   // display-safe-exempt: error 只取 NSError 的 code（Int），不迴送訊息文字
                    + "index 是取得記錄的唯一帳，讀不到時不能判定任何 digest 有沒有取得記錄")
        }
        let text = String(decoding: raw, as: UTF8.self)   // lossy——絕不 throw
        var digests = Set<String>()
        var malformed: [Int] = []
        var entries: [String: [String: String]] = [:]
        var sizes: [String: Int] = [:]
        for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               let content = obj["content"] as? String,
               ProvenanceReference.isWellFormedDigest(content) {   // #654：index 的文法只看形狀——指向空 blob 的那一列（#546 之前）不是無法解析的行
                digests.insert(content)
                if entries[content] == nil {
                    entries[content] = obj.compactMapValues { $0 as? String }
                    // 只收整數（JSON 的 true／1.5 不是大小）：NSNumber 的 objCType 要是整數型別
                    if let n = obj["bytes"] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue == Double(n.intValue) {
                        sizes[content] = n.intValue
                    }
                }
            } else {
                malformed.append(i + 1)
            }
        }
        return (digests, malformed, entries, sizes)
    }

    /// 一個 digest 在本機 `sources/` 的狀態（#614）：把內容宣告為某篇 work 的副本（`akashic.sources`）之前，
    /// 要確認位元組真的在這台機器上、而且有取得記錄。
    enum SourcePresence: Equatable {
        /// blob 在、index 有它的條目；值是那一列的字串欄位（media-type／retrieved／origin／acquisition／note）
        case stored([String: String])
        /// blob 不在本機——從未存過，或這台機器沒同步 `sources/`（它不進 git）
        case absent
        /// blob 在、index 沒有它：孤兒 blob，沒有取得記錄（`auditSourceIndex` 的 `orphanBlobs`）
        case unindexed
        /// shard 目錄存在但列不出來——讀不到不等於缺席（#265 的同一條）
        case unreadable
        /// blob 的位置上有東西、但不是普通檔（目錄、symlink、其他特殊檔案；值是給人看的種類名）——`fileExists(atPath:)` 對目錄也回 true，
        /// 於是「已存的 blob 被換成同名目錄」會被判成 `.stored`（b11c R1 verify 第 3 列）。`sources/` 由本工具寫成普通檔，位置上出現
        /// 別的東西就是有人動過；內容讀不到，不能宣告為副本。
        case notRegularFile(String)
        /// blob 在、index 有它的條目，但那一份的大小與條目記的 `bytes` 不同（#703 R2 verify 第 4 則：被截短、被換掉，或中斷的複製留下的半截）
        /// ——那一份不是條目說的內容，不能宣告為副本。大小相同而內容不同的看不出來（要整份讀才知道）。
        /// 值多帶 index 那一列的字串欄位（取得記錄）：`update-entry --remove-source` 要靠它讓人認得出被收回的是哪一份內容（b26 F6 LOW 7）。
        case sizeMismatch(stored: Int, indexed: Int, entry: [String: String])

        /// index 那一列的字串欄位（media-type／retrieved／origin／acquisition／note）：有條目的兩種狀態（`.stored`、`.sizeMismatch`）才有。
        public var indexEntry: [String: String]? {
            switch self {
            case .stored(let e): return e
            case .sizeMismatch(_, _, let e): return e
            default: return nil
            }
        }
    }

    /// 逐個 digest 回報 `SourcePresence`。index 只掃一次（與 `storeSource`／`auditSourceIndex` 共用 `scanIndex`，
    /// 同一份檔案不得給出兩種讀法）。**index 有無法解析的行、而這個 digest 的 blob 在卻不在可解析的行裡**時擲錯：
    /// 它的條目可能就藏在壞掉的那一行，判不出「沒有取得記錄」（`storeSource` 對同一情形 fail-closed 的同一條理由）。
    /// 形狀不合法的 digest 也擲錯——呼叫端應先以 `ProvenanceReference.isValidDigest` 驗過。
    func sourcePresence(digests: [String]) throws -> [String: SourcePresence] {
        let scan = try scanIndex()
        var out: [String: SourcePresence] = [:]
        for d in digests {
            guard let url = sourceURL(digest: d) else {
                throw StoreIOError.invalidInput(
                    what: "source digest",
                    why: "digest 形狀必須是 sha256: + 64 個小寫 hex，實得「\(displaySafeInvisible(d, max: 120))」")
            }
            // 位址上的東西只有一個分類（`sourceOccupant`，#703 R2）：`lstat` 語意，種類要是普通檔
            switch sourceOccupant(at: url) {
            case .absent: out[d] = .absent
            case .unreadable: out[d] = .unreadable
            case .notRegularFile(let kind): out[d] = .notRegularFile(kind)
            case .regular(let size):
                if let entry = scan.entries[d] {
                    if let indexed = scan.bytes[d], indexed != size {
                        out[d] = .sizeMismatch(stored: size, indexed: indexed, entry: entry)
                    } else {
                        out[d] = .stored(entry)
                    }
                } else if !scan.malformedLines.isEmpty {
                    throw StoreIOError.invalidInput(
                        what: "sources/index.jsonl",
                        why: "有 \(scan.malformedLines.count) 行無法解析（行號 \(scan.malformedLines.map(String.init).joined(separator: ", "))）——"
                            + "\(displaySafeInvisible(d, max: 120)) 的取得記錄可能就在那幾行裡，判不出它有沒有條目；先修好 index（akashic doctor 會列出）")
                } else {
                    out[d] = .unindexed
                }
            }
        }
        return out
    }

    /// #224：blob ↔ index 的兩向一致性 + malformed 行回報。
    ///
    /// 讀不到 ≠ 不存在（verify reg F2）：shard 目錄存在但列不出來（權限、半截同步）
    /// 時**不得**把它的 blob 當缺席——那會把好好的條目捏造成「懸空」。讀失敗的
    /// shard 進 `unreadableShards`，其 blob 不參與兩向比對。
    /// （同型缺陷存在於既有 `missingSourceDigests` 的 `fileExists`——本 change 不動
    /// 既有語意，追蹤歸 follow-up issue。）
    func auditSourceIndex() throws -> SourceIndexAudit {
        let fm = FileManager.default
        var diskDigests = Set<String>()       // 位址上有任何東西的 digest（index 指向它的不算懸空）
        var regularSizes: [String: Int] = [:] // 其中是普通檔的，與它的大小
        var unreadable: [String] = []
        var stray: [StrayTemporaryFile] = []
        var problems: [SourceOccupantProblem] = []
        // 只認 2-hex 目錄 / 62-hex 檔名的正規形，外加 `writeBlob` 的暫存檔形狀（#703 R1：中斷的存檔留下的，只報不刪）；
        // 其餘非正規形檔案**不在本 audit 範圍**（layoutResidue 也刻意不掃 sources/——那裡沒有任何機制報它們，這是已知
        // 缺口，見 verify logic MED-2 的更正，不在此假稱有人接住）
        if let shards = try? fm.contentsOfDirectory(atPath: sourcesDir.path) {
            for shard in shards where shard.count == 2 && shard.allSatisfy({ "0123456789abcdef".contains($0) }) {
                let dir = sourcesDir.appendingPathComponent(shard)
                guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else {
                    unreadable.append("sources/\(shard)/")
                    continue
                }
                for f in files {
                    if f.count == 62 && f.allSatisfy({ "0123456789abcdef".contains($0) }) {
                        let digest = "sha256:\(shard)\(f)"
                        // #703 R2 verify 第 5、6、15 則：位址上是什麼（先前只比名字，目錄、懸空 symlink 都被當成在場的 blob）
                        switch sourceOccupant(at: dir.appendingPathComponent(f)) {
                        case .regular(let n):
                            diskDigests.insert(digest)
                            regularSizes[digest] = n
                        case .notRegularFile(let kind):
                            diskDigests.insert(digest)
                            problems.append(SourceOccupantProblem(digest: digest, path: "sources/\(shard)/\(f)", kind: .notRegularFile(kind)))
                        case .unreadable:
                            // 列得出名字、lstat 不了（分片目錄有讀權限、沒有搜尋權限）：與列不出來同一類
                            if !unreadable.contains("sources/\(shard)/") { unreadable.append("sources/\(shard)/") }
                        case .absent:
                            continue   // 列出之後被刪了
                        }
                    } else if Self.isTemporaryBlobName(f) {
                        // lstat 的大小與修改時間（暫存檔由 `O_CREAT | O_EXCL` 建立，是普通檔）；讀不到屬性時大小記 0、時間 nil，路徑照樣報
                        let attrs = try? fm.attributesOfItem(atPath: dir.appendingPathComponent(f).path)
                        stray.append(StrayTemporaryFile(path: "sources/\(shard)/\(f)",
                                                        bytes: (attrs?[.size] as? NSNumber)?.intValue ?? 0,
                                                        modified: attrs?[.modificationDate] as? Date))
                    }
                }
            }
        }
        let scan = try scanIndex()
        // 普通檔的大小與 index 那一列的 `bytes` 比（#703 R2 verify 第 4 則）；條目沒有 `bytes` 的不比
        for (digest, size) in regularSizes {
            if let indexed = scan.bytes[digest], indexed != size {
                problems.append(SourceOccupantProblem(digest: digest, path: Self.sourceRelativePath(digest: digest),
                                                      kind: .sizeMismatch(stored: size, indexed: indexed)))
            }
        }
        // 讀不到的 shard：它的 blob 看不見，對應 index 條目不得被判懸空
        let comparableIndexDigests = scan.digests.filter { d in
            let shard = String(d.dropFirst("sha256:".count).prefix(2))
            return !unreadable.contains("sources/\(shard)/")
        }
        return SourceIndexAudit(
            orphanBlobs: Set(regularSizes.keys).subtracting(scan.digests).sorted(),
            danglingEntries: comparableIndexDigests.subtracting(diskDigests).sorted(),
            malformedLines: scan.malformedLines,
            unreadableShards: unreadable.sorted(),
            strayTemporaryFiles: stray.sorted { $0.path < $1.path },
            occupantProblems: problems.sorted { $0.path < $1.path })
    }

    /// blob 原語的結果：寫了（或位置上已有東西、沒寫），或內容在兩遍之間變了／長過上限。
    private enum BlobWrite {
        case done(exclusionVerified: Bool, bytesWritten: Bool)
        case refused(SourceContentRefusal)
    }

    /// blob 原語（#224 起不再公開）：把一份已算過 digest 的內容存進 `sources/`。
    ///
    /// - digest 算在**原始位元組**上（D3）：不正規化、不轉碼——判準必須客觀。
    /// - 同 digest 冪等：位址上已有**大小相同的普通檔**就不寫——內容定址，**不覆寫**（#703：內容對不對由 `checkStoredBlob` 比）。
    ///   位址上是別的東西（目錄、symlink——含懸空的、特殊檔案）或大小不同的普通檔，**具名擲出**、不寫 index（#703 R2 verify 第 4、5、6 則：
    ///   R2 之前對任何佔用都回「沒寫、但成功」，`store-source` 接著寫 index 並印「✓ 已建立 index 條目」，位址上仍是懸空 symlink——
    ///   #703 之前的 `fileExists` 會用真檔取代懸空 symlink，這是 R1 引入的回歸）。大小相同而內容不同的看不出來（不整份再讀一遍）。
    /// - 寫入前驗證版控排除（見 `assertSourcesExcluded`）；驗證先於**任何**磁碟寫入——拒寫時不留內容。
    /// - #703：**逐塊**複製進同一個分片目錄裡的暫存檔（`O_EXCL` 建立，檔名是 `temporaryBlobName`），邊寫邊再算一次 digest；兩遍相同、
    ///   同步到裝置（R2 verify 第 21 則）之後才放到位址上（`placeTemporaryBlob`：`RENAME_EXCL`，檔案系統不支援時退到 `link(2)`；兩個都不行就
    ///   具名拒絕——b26 F6：拿掉了第三條「排他建立目的檔後逐塊複製」；同時有別人放進來就不覆寫、丟掉暫存）。位址上的名字只經那兩個原子動作
    ///   出現，所以**名字出現的那一刻就是寫完、同步過的完整內容**——下面 `existing` 的「大小相同就算已經在了」不會讀到進行中的半截檔。
    ///   暫存檔的路徑**也**過排除驗證——只排除 blob 名、不排除暫存名的規則會 fail-open。
    ///   可捕捉的失敗都刪掉暫存檔；`SIGINT`／`SIGTERM`／`SIGHUP` 由 `InFlightSourceFiles` 刪（R2 verify 第 27 則）；行程被殺掉（`SIGKILL`、
    ///   斷電）時刪不到，`auditSourceIndex` 的 `strayTemporaryFiles` 報它（#703 R1）。
    private func writeBlob<C: SourceChunks>(_ source: inout C, digest: String, bytes: Int, limit: Int,
                                            token: String, placement: BlobPlacement) throws -> BlobWrite {
        let hex = String(digest.dropFirst("sha256:".count))
        // 排除驗證問的必須是**即將寫入的那條路徑**（#145 verify F1）：曾用寫死的
        // 探測路徑 `sources/00/probe`——任何碰巧命中它的無關規則（basename
        // `probe`、窄的 `sources/00/`、使用者全域 gitignore 的一行）都會讓驗證
        // 回「已排除」而實際寫入路徑根本沒被排除——fail-open 還回報假的
        // exclusionVerified: true。順帶收穫：check-ignore 對**已被追蹤**的路徑
        // 回「未忽略」，所以先前被 add -f 進 index 的存檔也會被擋（F4）。
        let relative = "sources/\(hex.prefix(2))/\(hex.dropFirst(2))"
        let verified = try assertSourcesExcluded(relativePath: relative)
        // sourceURL 對剛算出的合法 digest 不可能回 nil
        let url = sourceURL(digest: digest)!
        // 任何分支之前（含下面「位址上已經有同一份」那一支）：這個分片目錄做不做得到不覆寫的原子放置。旗標讀不到時實際放一次（b29 V5 MEDIUM 0：
        // 先前「已經在了」那一支不經任何放置呼叫就回成功、缺條目時還補 index，「每一次存檔都拒絕」在旗標讀不到的磁碟區上不成立）
        try assertDirectoryCanPlace(url.deletingLastPathComponent(), digest: digest, placement: placement)
        /// 位址上已經有東西：大小相同的普通檔才算「已經在了」，其餘具名擲出（不寫 index）。**這裡不會讀到進行中的存檔**（b26 F6）：
        /// 位址上的名字只經 `renamex_np(RENAME_EXCL)` 或 `link(2)` 出現（原子），那一刻內容已經寫完、同步過；失敗與訊號的清理刪的只有暫存名，
        /// 從不刪位址上的檔——所以「別人看到大小相同就回成功」之後，那個檔不會被收回。（R2 的第三條路在最終檔名下逐塊複製，這個窗曾經存在。）
        func existing(_ occupant: SourceOccupant) throws -> BlobWrite {
            if case .regular(let n) = occupant, n == bytes { return .done(exclusionVerified: verified, bytesWritten: false) }
            throw Self.occupiedAddressError(occupant, digest: digest, bytes: bytes)
        }
        let occupant = sourceOccupant(at: url)
        if occupant != .absent { return try existing(occupant) }
        let tmpName = Self.temporaryBlobName(digest: digest, token: token)
        try assertSourcesExcluded(relativePath: "sources/\(hex.prefix(2))/\(tmpName)")
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.deletingLastPathComponent().appendingPathComponent(tmpName)
        // 建立與登記在同一把鎖裡（`InFlightSourceFiles.create`，R2 verify 第 27 則）：訊號在建立之後、登記之前送到也清得掉
        let (fd, flight) = InFlightSourceFiles.create(path: tmp.path) {
            let fd = open(tmp.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
            return fd >= 0 ? fd : -errno
        }
        guard fd >= 0 else {
            throw StoreIOError.invalidInput(
                what: "sources/ 暫存檔",
                why: "無法建立（errno \(-fd)）——digest \(digest) 沒有存")   // display-safe-exempt: fd 是 Int32（負的 errno）；digest 是本函式的呼叫端算的 SHA-256 十六進位
        }
        var placed = false
        defer {
            if !placed { unlink(tmp.path) }
            if let flight { InFlightSourceFiles.unregister(flight) }
        }
        let out = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var hasher = SHA256()
        try source.rewind()
        let copied = try Self.pump(&source, limit: limit) { chunk in
            hasher.update(data: chunk)
            try out.write(contentsOf: chunk)
        }
        switch copied {
        case .exceeded(let n):
            try out.close()
            return .refused(.tooLarge(bytes: max(n, source.currentSize() ?? n)))
        case .complete(let n):
            let second = Self.digestText(hasher.finalize())
            // 兩遍之間內容變了：存下來的會不是 digest 說的那一份——不落地
            guard n == bytes, second == digest else {
                try out.close()
                return .refused(.changed(actual: second))
            }
        }
        // 放上位址之前同步到裝置（R2 verify 第 21 則）：之後的崩潰或斷電不會在合法的位址下留一份被撕裂的內容
        let synced = placement.sync(fd)
        try out.close()
        guard synced == 0 else {
            throw StoreIOError.invalidInput(
                what: "sources/ 暫存檔",
                why: "同步到裝置失敗（\(Self.errnoText(synced))）——digest \(digest) 沒有存")   // display-safe-exempt: Self.errnoText 只回 errno 數字與系統的固定英文說明（synced 是 Int32）；digest 是本函式的呼叫端算的 SHA-256 十六進位
        }
        switch try placeTemporaryBlob(tmp.path, at: url.path, digest: digest, placement: placement) {
        case .alreadyThere:
            // 同時有別人放進來了：不覆寫（暫存由 defer 刪掉）；放進來的是什麼，與一開始就在的同一個判法
            return try existing(sourceOccupant(at: url))
        case .placed:
            placed = true
            return .done(exclusionVerified: verified, bytesWritten: true)
        }
    }

    /// 全庫 references 指名、但本機沒有存檔的 digest（排序去重）。
    /// 「回報缺席」的可用面——doctor/CLI 接線屬後續 issue（Out of scope）。
    ///
    /// **讀不到 ≠ 缺席**（#265，同 auditSourceIndex 的 verify reg F2）：digest 所屬
    /// shard 目錄存在但列不出來（權限、半截同步）→ 該 digest **不判缺席**、shard
    /// 進 `unreadableShards`——fileExists 對讀不到的父目錄同樣回 false，直接信它
    /// 會把好好的存檔捏造成「缺席」。
    ///
    /// **divergence 的 `judgement.restsOn` 在掃描範圍**（#251，第 12 條邊）——
    /// 先前只掃 people/organizations 的 references，報告對消歧證據鏈全盲。
    /// 逐 holder 的缺席報告（#453）：每一筆是「哪一筆記錄的哪個槽位指向一個本機沒有的存檔」。
    /// `missing` 維持既有語意（distinct digest、排序）；`holders` 是 per-record 事實——
    /// `danglingSourceIssues(in:)` 據此組出 `perRecordIssues` 的 warning（#464 死 verdict 的同一形）。
    struct MissingSourceReport {
        struct Holder: Equatable {
            /// 持有記錄的 key（entry 為 citekey、divergence 為 id）。
            let owner: String
            /// `entry`／`person`／`organization`／`venue`／`divergence`——與 `StoreHealth.OwnedIssue.kind` 同詞彙。
            let kind: String
            /// 指向該存檔的槽位：reference 的 `field`、`judgement.restsOn`、或 `akashic.sources`。
            let slot: String
            let digest: String
            /// `false` ＝ 值根本不是 `sha256:` 形（`sourceURL` 解不出路徑）——無從在本機查找，
            /// 與「合法但本機沒有」是兩件事（live store 2026-09-04 實測一筆 divergence 的
            /// `judgement.restsOn` 裝的是 URL）。兩者都算進 `missing`（既有語意），訊息分開說。
            /// **#507 起對已載入的記錄不可達**：三條路徑（`akashic.sources`、`ProvenanceReference.restsOn`、
            /// divergence 的 rests-on）都在 decode 期擋不合法的值。留著這個分支是防禦，
            /// `DanglingSourceScanTests.testMalformedDigestIsUnreachableForLoadedRecords` 釘住它為什麼是零。
            let wellFormed: Bool
        }
        let holders: [Holder]
        let unreadableShards: [String]
        /// 既有介面：distinct digest、排序。
        var missing: [String] { Array(Set(holders.map(\.digest))).sorted() }
    }

    func missingSourceDigests(_ load: LibraryLoad) -> MissingSourceReport {
        typealias Claim = (owner: String, kind: String, slot: String, digest: String)
        var claims: [Claim] = []
        func collect(_ refs: [ProvenanceReference], owner: String, kind: String) {
            for r in refs {
                switch r.kind {
                case .retrieval(_, _, _, _, let content):
                    claims.append((owner, kind, r.field, content))
                case .judgement(_, let restsOn):
                    for d in restsOn { claims.append((owner, kind, r.field, d)) }
                }
            }
        }
        for p in load.people { collect(p.references, owner: p.key, kind: "person") }
        for o in load.organizations { collect(o.references, owner: o.key, kind: "organization") }
        // #453：venue 的 references——#406 起承重證據（`paginated` 判定的 rests-on）第一次住在 venue 上，
        // 而這裡先前不掃它（第 11 條邊的 venue 形，#304 隨形狀新增時沒跟著補）。
        for v in load.venues { collect(v.references, owner: v.key, kind: "venue") }
        for d in load.divergences {   // #251：judgement 的依據也是指名的存檔
            guard let j = d.judgement else { continue }
            for digest in j.restsOn {
                claims.append((d.id.uuidString, "divergence", "judgement.restsOn", digest))
            }
        }
        for e in load.entries {
            // 記錄側副本引用（#223）：關係項與欄位層級 references 不同，但**指向同一個
            // 內容儲存區**，所以缺席語意共用這一條路徑——不新增第二套判定。
            for digest in e.akashic.sources { claims.append((e.citekey, "entry", "akashic.sources", digest)) }
            // #453：`Entry.references`（第 15 條邊，#394 §5）——識別碼的來源存檔，先前不掃。
            collect(e.references, owner: e.citekey, kind: "entry")
        }
        let fm = FileManager.default
        var absent = Set<String>()
        var malformed = Set<String>()
        var unreadable = Set<String>()
        for d in Set(claims.map(\.digest)).sorted() {
            guard let url = sourceURL(digest: d) else { absent.insert(d); malformed.insert(d); continue }
            if fm.fileExists(atPath: url.path) { continue }
            // 判缺席前先確認 shard 可列——列不出來是「讀不到」，不是「缺席」（#265）
            let shardDir = url.deletingLastPathComponent()
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: shardDir.path, isDirectory: &isDir), isDir.boolValue,
               (try? fm.contentsOfDirectory(atPath: shardDir.path)) == nil {
                unreadable.insert("sources/\(shardDir.lastPathComponent)/")
                continue
            }
            absent.insert(d)
        }
        let holders = claims.filter { absent.contains($0.digest) }.map {
            MissingSourceReport.Holder(owner: $0.owner, kind: $0.kind, slot: $0.slot, digest: $0.digest,
                                       wellFormed: !malformed.contains($0.digest))
        }
        return MissingSourceReport(holders: holders, unreadableShards: unreadable.sorted())
    }

    /// 版控排除的 fail-closed 驗證（D5）。
    ///
    /// - store 是 git repo：`git check-ignore` 對 `sources/` 內的探測路徑必須回
    ///   「被忽略」——用 git **自己的**判定，不是自己 parse .gitignore（更外層的
    ///   全域設定、`.git/info/exclude` 都會影響結果，只有 git 知道總和）。
    ///   未生效 → throw，錯誤說明如何修。回 true。
    /// - 非 git repo：跳過，回 false——事實進 `SourceReceipt`，不沉默。
    @discardableResult
    internal func assertSourcesExcluded(relativePath: String) throws -> Bool {
        guard Self.isInsideVersionedWorkTree(root) else { return false }

        // **這道閘的失效方向是 fail-open（#239）**，與 `filesNotSafelyRecoverable`
        // 相反：若 git 被導向另一個 repo，而**那個 repo 的 `.git/info/exclude` 或
        // `core.excludesfile`** 涵蓋該相對路徑，`check-ignore` 回 0、閘放行，第三方
        // 逐字位元組就寫進一個真實 repo 並**不**排除它的 store，隨下次 commit 外流。
        // （另一個 repo 的 `.gitignore` **不是**向量——那讀自工作樹，而工作樹跟著 cwd。）
        //
        // 防線在 `Self.git` 的環境剝除。曾試圖在此加一道 runtime containment 斷言，
        // **失敗且已移除**：`rev-parse --show-toplevel` 跟著 cwd 走，`GIT_DIR` 被覆寫
        // 時它照樣回本地路徑——**恰好在攻擊成功時通過**，比沒有更糟；改用
        // `--absolute-git-dir` 雖看得見覆寫，卻無法與合法的 `git worktree` 區分
        // （worktree 的 git dir 本來就在主 repo 底下、不是 store 的祖先）。
        //
        // 第二層改由**架構測試**承擔（見 `GitSpawnHygieneTests`）：確保 Sources/ 底下
        // 每一處 spawn git 都經過剝除環境的 helper。真正的復發風險是「新增呼叫點時
        // 忘記剝除」，那是靜態可驗的；runtime 再驗一次同一件事只是同語反覆。
        guard let r = Self.git(["check-ignore", "-q", "--", relativePath], in: root) else {
            // git 執行不起來時 fail-closed——「不知道有沒有排除」不等於「排除了」
            throw StoreIOError.invalidInput(
                what: "sources 版控排除",
                why: "無法執行 git 確認 sources/ 的忽略狀態——排除驗證是寫入前提"
                    + "（外流不可逆），git 不可用時拒絕寫入")
        }
        guard r.status == 0 else {
            throw StoreIOError.invalidInput(
                what: "sources 版控排除",
                why: "sources/ 未被版控忽略——存檔是第三方逐字內容，不得進 remote。"
                    + "在 store 的 .gitignore 加上「sources/」（akashic doctor 會在沒有標記區塊時附加一段；"
                    + ".gitignore 讀不懂、是 symlink 或硬連結、唯讀時它不改，改印要自己加的那段），"
                    + "或確認沒有其他規則反向 un-ignore 它，再重試")
        }
        return true
    }
}
