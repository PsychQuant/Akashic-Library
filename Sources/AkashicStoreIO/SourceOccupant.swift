import Foundation
import Darwin
import AkashicCore

/// 一個 digest 的位址上是什麼（#703 R2 verify 第 4、5、6、15 則）。**這四個讀者共用這一個分類**：`writeBlob`（位址上已經有東西時）、
/// `checkStoredBlob`、`sourcePresence`、`auditSourceIndex` 都讀它。**另有兩個讀者仍各自判斷、與它不完全一致**（b26 F6 INFO 33，記錄、未改）：
/// `missingSourceDigests`（`validate` 的「本機缺承重存檔」）用 `fileExists`——位址上是目錄算「在場」、懸空 symlink 算「缺席」；
/// `abstracts-to-proposals --source sha256:…` 以自己的 `fstat` 讀（目錄與懸空 symlink 都回「存檔不存在」，指向合法 blob 的 symlink 會被跟隨讀穿）。
/// R2 之前四處各自判，`writeBlob` 對任何佔用都說「已經在了」、
/// 回條照樣成功並寫 index，而同一個狀態 `copy-zotero-attachments` 說判不出來、`doctor` 什麼都不說。
public extension LibraryStore {

    /// 位址上的東西（`lstat` 語意，不跟隨 symlink）。
    enum SourceOccupant: Equatable {
        /// 沒有東西。
        case absent
        /// 普通檔；值是它的大小。
        case regular(bytes: Int)
        /// 有東西、但不是普通檔（值是給人看的種類名：目錄、symlink、特殊檔案）。`sources/` 由本工具寫成普通檔，位置上出現別的東西就是
        /// 有人動過；內容讀不到。
        case notRegularFile(String)
        /// 判不出來：分片目錄存在但列不出來，或 `lstat` 以「不存在」以外的原因失敗（讀不到不等於缺席，#265）。
        case unreadable
    }

    /// 位址上的東西。形狀不合法的 digest 由呼叫端先擋（`sourceURL` 回 nil）。
    internal func sourceOccupant(at url: URL) -> SourceOccupant {
        var st = stat()
        if lstat(url.path, &st) == 0 {
            switch st.st_mode & S_IFMT {
            case S_IFREG: return .regular(bytes: Int(st.st_size))
            case S_IFDIR: return .notRegularFile("目錄")
            case S_IFLNK: return .notRegularFile("symlink")
            default: return .notRegularFile("特殊檔案")
            }
        }
        let code = errno
        // ENOTDIR：分片那一段是個檔——位址上不可能有東西（先前 `attributesOfItem` 失敗後 `fileExists(isDirectory:)` 也判成缺席）
        guard code == ENOENT || code == ENOTDIR else { return .unreadable }
        let shardDir = url.deletingLastPathComponent()
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: shardDir.path, isDirectory: &isDir), isDir.boolValue,
           (try? FileManager.default.contentsOfDirectory(atPath: shardDir.path)) == nil {
            return .unreadable
        }
        return .absent
    }

    /// `sources/<xx>/<其餘>`：給人看的位址（只有 hex，印出安全）。
    static func sourceRelativePath(digest: String) -> String {
        let hex = digest.dropFirst("sha256:".count)
        return "sources/\(hex.prefix(2))/\(hex.dropFirst(2))"
    }

    /// 存一份內容時位址上已有東西、而那不是這份內容（#703 R2 verify 第 4、5、6 則）：具名拒絕——不覆寫、不寫 index、回條不成立。
    /// 大小相同而內容不同的普通檔看不出來（比對內容要整份再讀一遍；`copy-zotero-attachments` 的 `checkStoredBlob` 會讀，`store-source` 不讀）。
    internal static func occupiedAddressError(_ occupant: SourceOccupant, digest: String, bytes: Int) -> StoreIOError {
        let path = sourceRelativePath(digest: digest)
        let tail = "——這份內容沒有存，也沒有記進 index.jsonl。把 \(path) 移走後重存；akashic doctor 的 sources 一致性會列出位址上的佔用"
        let why: String
        switch occupant {
        case .notRegularFile(let kind):
            why = "\(path) 的位置上是\(kind)、不是普通檔" + tail
        case .regular(let stored):
            why = "\(path) 已有一份 \(stored) bytes 的檔，而這份內容是 \(bytes) bytes——那一份大小不是這個 digest 的內容的大小（被截短、接長或換掉），不覆寫" + tail
        case .unreadable:
            why = "判不出 \(path) 的位置上有沒有東西（分片目錄列不出來，或 lstat 失敗）——沒有存；先查 sources/ 的權限"
        case .absent:
            why = "\(path) 的位置剛剛還有東西、現在不見了——沒有存；重跑"
        }
        return StoreIOError.invalidInput(what: "sources/ 存檔", why: why)   // display-safe-exempt: path 只含 hex；kind 是本檔的三個固定字串；stored、bytes 是 Int
    }

    /// 本機 `sources/` 裡這個 digest 的那一份，內容是否真的是這個 digest（#703）。
    enum StoredBlobCheck: Equatable {
        /// 位置上沒有東西。
        case absent
        /// 內容的 digest 就是位址。
        case matches
        /// 內容不是這個 digest（被截短、被換掉）。`bytes` 是那一份的實際大小；`digest` 是它內容的 digest——大小與 `expectedBytes`
        /// 不同時不必讀就知道不符，是 nil。
        case mismatch(bytes: Int, digest: String?)
        /// 位置上有東西、但不是普通檔（值是給人看的種類名）。
        case notRegularFile(String)
        /// 分片目錄列不出來、或那一份打不開／讀不完——判不出來（讀不到不等於缺席，#265）。
        case unreadable
    }

    /// 比對本機存檔與它的位址（#703：`copy-zotero-attachments` 補存時「已連過」不再只看在不在）。**逐塊**算 digest（不設上限——既有的
    /// 存檔可能早於上限；每塊經 `pump` 讀完即釋放）；`expectedBytes` 給了而大小不同就直接判不符、不讀。不改任何東西。
    func checkStoredBlob(digest: String, expectedBytes: Int?) throws -> StoredBlobCheck {
        guard let url = sourceURL(digest: digest) else {
            throw StoreIOError.invalidInput(
                what: "source digest",
                why: "digest 形狀必須是 sha256: + 64 個小寫 hex，實得「\(displaySafeInvisible(digest, max: 120))」")
        }
        let size: Int
        switch sourceOccupant(at: url) {
        case .absent: return .absent
        case .unreadable: return .unreadable
        case .notRegularFile(let kind): return .notRegularFile(kind)
        case .regular(let n): size = n
        }
        if let expectedBytes, size != expectedBytes { return .mismatch(bytes: size, digest: nil) }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { return .unreadable }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        guard let streamed = try? Self.contentDigest(reading: handle, limit: .max),
              case .digest(let actual, let n) = streamed else { return .unreadable }
        return actual == digest ? .matches : .mismatch(bytes: n, digest: actual)
    }

    /// `auditSourceIndex` 的一則位址問題（#703 R2 verify 第 5、6、15 則）：位址上不是普通檔，或那一份的大小與 index 記的不同。
    /// **只報不刪**——那可能是一個人正在處理的東西。
    struct SourceOccupantProblem: Equatable {
        public enum Kind: Equatable {
            /// 位址上是目錄、symlink 或特殊檔案（值是種類名）。
            case notRegularFile(String)
            /// 普通檔，但大小與 `index.jsonl` 那一列的 `bytes` 不同（被截短、被換掉、或中斷的複製留下的半截）。
            case sizeMismatch(stored: Int, indexed: Int)
        }
        public let digest: String
        /// `sources/<xx>/<其餘>`（只有 hex）。
        public let path: String
        public let kind: Kind
    }

    // MARK: audit 的報告型別（#224；R2 起從 `SourceStore.swift` 搬來——那個檔加上 #703 R2 會超過 800 行）

    /// #224：blob ↔ index 一致性報告。三類都要 loud——audit sidecar 的腐爛
    /// 全靠這份報告變得可見。
    struct SourceIndexAudit {
        /// 有 blob、無 index 條目（digest 形式，排序）
        public let orphanBlobs: [String]
        /// 有 index 條目、無 blob（digest 形式，排序）
        public let danglingEntries: [String]
        /// 非 JSON 物件、或 `content` 缺席／形狀不合法的行（1-based 實際檔案行號）
        public let malformedLines: [Int]
        /// 存在但列不出來的 shard 目錄（權限、半截同步）——讀不到 ≠ 不存在，
        /// 其 blob 不參與兩向比對（verify reg F2）
        public let unreadableShards: [String]
        /// 分片目錄裡 `temporaryBlobName` 形狀的檔（#703 R1 verify 第 13、18、22、23 則）：存檔在複製途中被殺掉（SIGKILL、斷電、
        /// 逾時）時 `writeBlob` 的清理不會跑，一份可以到上限那麼大，而先前沒有任何面報它。**只報不刪**——同一時間正在進行的存檔
        /// 也長這樣；每一個附上最後修改時間（R2 verify 第 28 則），讓人與呼叫端分得出「一秒前還在寫」與「三天前被殺掉」。依路徑排序。
        public let strayTemporaryFiles: [StrayTemporaryFile]
        /// 位址上不是普通檔、或普通檔的大小與 index 記的不同（#703 R2 verify 第 5、6、15 則）。先前 audit 只比檔名，位址被目錄或懸空
        /// symlink 佔住、blob 被截短都看不到。不是普通檔的不算孤兒 blob、index 指向它的也不算懸空（只在這一族報一次）。依路徑排序。
        public let occupantProblems: [SourceOccupantProblem]

        /// 有沒有任何一則（doctor 三個面「sources 一致性」出不出現、`hasFindings` 的一半——殘留暫存檔另以年齡判，見 `StoreHealth`）。
        public var isEmpty: Bool {
            orphanBlobs.isEmpty && danglingEntries.isEmpty && malformedLines.isEmpty && unreadableShards.isEmpty
                && strayTemporaryFiles.isEmpty && occupantProblems.isEmpty
        }
    }

    /// 一個殘留的暫存檔：`sources/<xx>/<檔名>`、大小與最後修改時間（lstat；讀不到屬性時大小記 0、時間是 nil）。
    struct StrayTemporaryFile: Equatable {
        public let path: String
        public let bytes: Int
        public let modified: Date?

        /// 最後修改到 `now` 過了幾秒。**時間讀不到是 nil；時間在未來、超過容忍（`LibraryStore.strayTemporaryClockSkewSeconds`）也是 nil**
        /// （b26 F6：時鐘被往回撥、備份還原、跨時區的 FAT 卷——FAT 沒有時區——都會讓檔案的修改時間在未來，先前夾成 0 秒前、算成
        /// 「一小時內還在動」，永遠不算殘留、`hasFindings` 與 App 的計數都不亮）。容忍範圍內的未來時間算 0。
        public func ageSeconds(now: Date = Date()) -> Int? {
            guard let modified else { return nil }
            let age = Int(now.timeIntervalSince(modified))
            if age >= 0 { return age }
            return age >= -LibraryStore.strayTemporaryClockSkewSeconds ? 0 : nil
        }

        /// 修改時間在未來、超過容忍（`ageSeconds` 是 nil 的兩種原因之一）：給人看的訊息要分得出它與「時間讀不到」。
        public func modifiedInTheFuture(now: Date = Date()) -> Bool {
            guard let modified else { return false }
            return Int(now.timeIntervalSince(modified)) < -LibraryStore.strayTemporaryClockSkewSeconds
        }

        /// 夠舊、不像是正在進行的存檔（#703 R2 verify 第 22 則）：最後修改超過 `LibraryStore.strayTemporaryQuietSeconds`。
        /// 時間讀不到、或在未來超過容忍的算舊（寧可多要人看一眼）。只影響 `hasFindings` 與 App 的計數；CLI／MCP 的 doctor 全部列出、附年齡。
        public func isStale(now: Date = Date()) -> Bool { (ageSeconds(now: now) ?? .max) >= LibraryStore.strayTemporaryQuietSeconds }

        /// 可能是正在進行的存檔（不要刪）：一小時內還在動，**或時間不可信**（`ageSeconds` 是 nil：讀不到、或在未來超過容忍）。
        /// 與 `isStale` 不是互補（b29 V5 LOW 10、15）：時間不可信時兩者都是 true——`isStale` 管「要不要人看一眼」（疑問往亮的方向），
        /// 這個管「可不可以刪」（疑問往不刪的方向）。先前 MCP 的 `possiblyInProgress` 是 `!isStale()`，未來的時間被讀成「可以刪」。
        public func possiblyInProgress(now: Date = Date()) -> Bool {
            guard let age = ageSeconds(now: now) else { return true }
            return age < LibraryStore.strayTemporaryQuietSeconds
        }
    }

    /// 殘留暫存檔多久沒動才算進 `hasFindings`（#703 R2 verify 第 22 則）：3,600 秒。暫存檔每寫一塊就更新修改時間，一份上限大小的檔在慢磁碟上
    /// 也是幾分鐘的事；一小時沒動的幾乎一定是中斷留下的。**這不是刪除的判準**——doctor 仍然只報不刪（第 73 列：以年齡斷定一定是殘留是猜）。
    static let strayTemporaryQuietSeconds = 3_600

    /// 修改時間在未來多少秒以內仍當成「剛剛」（時鐘小幅誤差、FAT 的兩秒解析度）：300 秒。超過就不信那個時間（`StrayTemporaryFile.ageSeconds` 回 nil、算舊）。
    static let strayTemporaryClockSkewSeconds = 300

    // MARK: 讀回

    /// 讀回存檔。**缺席（nil）與格式錯（throw）是兩個條件**（task 4.5）：
    /// 存檔不進 remote，clone 後必然缺席——那是預期狀態不是損毀；
    /// 形狀錯的 digest 才是真正的格式錯誤。
    ///
    /// 回的是整份 `Data`（呼叫端要的就是內容），所以**有界**而不是逐塊（#703 R2 verify 第 12、23 則：先前是無上限的
    /// `Data(contentsOf:)`，早於上限的舊 blob 可以任意大）：大小超過 `limit`（預設 `maxSourceBytes`）以 `lstat` 判、不讀、具名擲出；
    /// 讀的時候長過上限也擲出。位址上不是普通檔、判不出來也擲出（先前 `fileExists` 對目錄回 true，再由 `Data(contentsOf:)` 擲出不具名的錯）。
    func sourceContent(digest: String, limit: Int = LibraryStore.maxSourceBytes) throws -> Data? {
        guard let url = sourceURL(digest: digest) else {
            throw StoreIOError.invalidInput(
                what: "source digest",
                why: "digest 形狀必須是 sha256: + 64 個小寫 hex，實得「\(displaySafeInvisible(digest, max: 120))」")
        }
        let path = Self.sourceRelativePath(digest: digest)
        func refuse(_ why: String) -> StoreIOError {
            StoreIOError.invalidInput(what: "sources/ 存檔", why: "\(path)：\(why)")   // display-safe-exempt: path 只含 hex；why 是本函式的固定句與 Int
        }
        switch sourceOccupant(at: url) {
        case .absent: return nil
        case .unreadable: throw refuse("判不出位置上有沒有東西（分片目錄列不出來，或 lstat 失敗）")
        case .notRegularFile(let kind): throw refuse("位置上是\(kind)、不是普通檔")
        case .regular(let n) where n > limit:
            throw refuse("\(n) bytes，超過讀回的上限 \(Self.sourceCapDescription(limit))——不讀")
        case .regular: break
        }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw refuse("打不開（errno \(errno)）") }
        var chunks = HandleChunks(handle: FileHandle(fileDescriptor: fd, closeOnDealloc: true))
        var data = Data()
        switch try Self.pump(&chunks, limit: limit, { data.append($0) }) {
        case .complete: return data
        case .exceeded(let n): throw refuse("讀的時候長到 \(n) bytes 以上，超過讀回的上限 \(Self.sourceCapDescription(limit))")
        }
    }
}
