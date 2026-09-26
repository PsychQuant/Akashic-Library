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

    /// 寫入的回條：digest 之外**記錄排除驗證是否真的跑了**（D5：store 非 git repo
    /// 時跳過驗證，但跳過的事實不沉默——呼叫端可轉發給使用者）。
    struct SourceReceipt {
        public let digest: String
        public let exclusionVerified: Bool
        /// #224：這次呼叫有沒有**新增** index 條目。false = 同 digest 條目已存在
        /// （冪等重存），不重複 append——呼叫端要能分辨「記了」與「早就記過」。
        public let indexEntryCreated: Bool
        /// #224 verify D2（lossless-intake「丟棄必須可見」）：冪等早退時，呼叫端
        /// 這次交來、但**沒有被寫入**的 provenance（既有條目以先到為準）。
        /// nil = 沒有丟棄任何東西。
        public let discardedProvenance: SourceProvenance?
    }

    /// #224：存 source 時**必須**一起提供的 provenance——blob 本身只是位元組，
    /// 沒有這些欄位它什麼都不證明。欄位形狀以既有 `sources/index.jsonl` 的
    /// 7 條手工條目為事實來源。
    struct SourceProvenance {
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
    }

    /// digest → 存檔路徑。形狀錯回 nil（呼叫端決定 throw 與否）。
    internal func sourceURL(digest: String) -> URL? {
        guard ProvenanceReference.isValidDigest(digest) else { return nil }
        let hex = String(digest.dropFirst("sha256:".count))
        return sourcesDir.appendingPathComponent(String(hex.prefix(2)))
            .appendingPathComponent(String(hex.dropFirst(2)))
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
    @discardableResult
    func storeSource(_ data: Data, provenance: SourceProvenance) throws -> SourceReceipt {
        // #546：下界。空字串的 digest 是常數，任何空輸入都得到它——它不指認任何一份內容，
        // 而兩次不同的失敗抓取會折成同一筆、被去重讀成「早已存過」。與 #519 的上界同型：
        // 整個拒絕、零寫入、具名。所以這一道放在任何磁碟寫入之前。
        guard !data.isEmpty else {
            throw StoreIOError.invalidInput(
                what: "source 內容",
                why: "0 byte——空內容的 digest 對所有空輸入都相同，不指認任何一份存檔。"
                    + "這通常是一次失敗的抓取留下的空檔；重新取得內容再存")
        }
        // #224 verify（Codex #4）：sidecar 已腐壞時不可宣稱冪等——malformed 行讓
        // 重複檢查不可靠（同 digest 可能藏在解析不出的行裡）。fail-closed：先修再寫。
        // 這個檢查在**任何**磁碟寫入之前——拒寫時不留孤兒 blob。
        let scan = try scanIndex()
        guard scan.malformedLines.isEmpty else {
            throw StoreIOError.invalidInput(
                what: "sources/index.jsonl",
                why: "有 \(scan.malformedLines.count) 行無法解析（行號 \(scan.malformedLines.map(String.init).joined(separator: ", "))）。"
                    + "index 腐壞時不可判定冪等——先修復（akashic doctor 會列出），再存新 source")
        }
        let blob = try writeBlob(data)
        if scan.digests.contains(blob.digest) {
            // 冪等早退。丟棄了呼叫端的 provenance——這必須**可見**（verify D2 /
            // lossless-intake「丟棄必須可見」）：receipt 帶 discardedProvenance，
            // 呼叫端能分辨「早已記過」與「你這份敘述沒被寫入」。
            return SourceReceipt(digest: blob.digest,
                                 exclusionVerified: blob.exclusionVerified,
                                 indexEntryCreated: false,
                                 discardedProvenance: provenance)
        }
        try appendIndexEntry(digest: blob.digest, bytes: data.count, provenance: provenance)
        return SourceReceipt(digest: blob.digest,
                             exclusionVerified: blob.exclusionVerified,
                             indexEntryCreated: true,
                             discardedProvenance: nil)
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
    ///   既有行、毀掉它的可解析性——照抄同檔 `ensureSourcesIgnoreBlock` 的兩條件寫法）
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
    private func scanIndex() throws -> (digests: Set<String>, malformedLines: [Int]) {
        guard FileManager.default.fileExists(atPath: sourceIndexURL.path) else {
            return ([], [])
        }
        let raw = try Data(contentsOf: sourceIndexURL)
        let text = String(decoding: raw, as: UTF8.self)   // lossy——絕不 throw
        var digests = Set<String>()
        var malformed: [Int] = []
        for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               let content = obj["content"] as? String,
               ProvenanceReference.isValidDigest(content) {
                digests.insert(content)
            } else {
                malformed.append(i + 1)
            }
        }
        return (digests, malformed)
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
        var diskDigests = Set<String>()
        var unreadable: [String] = []
        // 只認 2-hex 目錄 / 62-hex 檔名的正規形；非正規形檔案**不在本 audit 範圍**
        // （layoutResidue 也刻意不掃 sources/——那裡沒有任何機制報它們，這是已知
        // 缺口，見 verify logic MED-2 的更正，不在此假稱有人接住）
        if let shards = try? fm.contentsOfDirectory(atPath: sourcesDir.path) {
            for shard in shards where shard.count == 2 && shard.allSatisfy({ "0123456789abcdef".contains($0) }) {
                let dir = sourcesDir.appendingPathComponent(shard)
                guard let files = try? fm.contentsOfDirectory(atPath: dir.path) else {
                    unreadable.append("sources/\(shard)/")
                    continue
                }
                for f in files
                where f.count == 62 && f.allSatisfy({ "0123456789abcdef".contains($0) }) {
                    diskDigests.insert("sha256:\(shard)\(f)")
                }
            }
        }
        let scan = try scanIndex()
        // 讀不到的 shard：它的 blob 看不見，對應 index 條目不得被判懸空
        let comparableIndexDigests = scan.digests.filter { d in
            let shard = String(d.dropFirst("sha256:".count).prefix(2))
            return !unreadable.contains("sources/\(shard)/")
        }
        return SourceIndexAudit(
            orphanBlobs: diskDigests.subtracting(scan.digests).sorted(),
            danglingEntries: comparableIndexDigests.subtracting(diskDigests).sorted(),
            malformedLines: scan.malformedLines,
            unreadableShards: unreadable.sorted())
    }

    /// blob 原語（#224 起不再公開）：存入一份擷取內容，回 digest（`sha256:` 前綴）。
    ///
    /// - digest 算在**原始位元組**上（D3）：不正規化、不轉碼——判準必須客觀。
    /// - 同位元組冪等：已存在就不重寫（內容定址，兩份是不可能的）。
    /// - 寫入前驗證版控排除（見 `assertSourcesExcluded`）；驗證先於**任何**磁碟
    ///   寫入——拒寫時不留內容。
    private func writeBlob(_ data: Data) throws -> SourceReceipt {
        let hex = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let digest = "sha256:\(hex)"
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
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        return SourceReceipt(digest: digest, exclusionVerified: verified,
                             indexEntryCreated: false, discardedProvenance: nil)
    }

    /// 讀回存檔。**缺席（nil）與格式錯（throw）是兩個條件**（task 4.5）：
    /// 存檔不進 remote，clone 後必然缺席——那是預期狀態不是損毀；
    /// 形狀錯的 digest 才是真正的格式錯誤。
    func sourceContent(digest: String) throws -> Data? {
        guard let url = sourceURL(digest: digest) else {
            throw StoreIOError.invalidInput(
                what: "source digest",
                why: "digest 形狀必須是 sha256: + 64 個小寫 hex，實得「\(displaySafeInvisible(digest, max: 120))」")
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
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
                    + "在 store 的 .gitignore 加上「sources/」（ensureLayout 會寫入"
                    + "標記區塊），或確認沒有其他規則反向 un-ignore 它，再重試")
        }
        return true
    }

    /// `.gitignore` 的 sources 排除區塊（task 4.3）。**以標記為判準的 idempotent**：
    /// `# BEGIN akashic sources` 已在（即使內文是手工版本、與程式版不同）就不寫
    /// 也不改寫——真實 store 的區塊是手工先寫的（#66 落地前），程式必須與既有
    /// 狀態相容，改寫等於用程式版覆蓋使用者的措辭。
    internal func ensureSourcesIgnoreBlock() throws {
        let ignoreURL = root.appendingPathComponent(".gitignore")
        let existing = (try? String(contentsOf: ignoreURL, encoding: .utf8)) ?? ""
        guard !existing.contains("# BEGIN akashic sources") else { return }
        var out = existing
        if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
        out += """
        # BEGIN akashic sources — 存檔的來源內容（第三方逐字位元組）
        # 被指涉的內容本身不進 remote（Akashic-Library#66）；指涉紀錄（references:）照常追蹤。
        sources/
        # END akashic sources

        """
        try out.write(to: ignoreURL, atomically: true, encoding: .utf8)
    }
}
