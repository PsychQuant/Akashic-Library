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
        /// 非 JSON 物件、或 `content` 缺席／形狀不合法的行（1-based 行號）
        public let malformedLines: [Int]
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
        let blob = try writeBlob(data)
        if try indexedDigests().contains(blob.digest) {
            return SourceReceipt(digest: blob.digest,
                                 exclusionVerified: blob.exclusionVerified,
                                 indexEntryCreated: false)
        }
        try appendIndexEntry(digest: blob.digest, bytes: data.count, provenance: provenance)
        return SourceReceipt(digest: blob.digest,
                             exclusionVerified: blob.exclusionVerified,
                             indexEntryCreated: true)
    }

    var sourceIndexURL: URL { sourcesDir.appendingPathComponent("index.jsonl") }

    /// JSON 字串字面量（含引號）。用 JSONEncoder 逃逸，不手寫 escape 表。
    private func jsonLiteral(_ s: String) throws -> String {
        let arr = String(data: try JSONEncoder().encode([s]), encoding: .utf8) ?? "[\"\"]"
        return String(arr.dropFirst().dropLast())
    }

    /// append 一行 index 條目。欄位序固定（content→bytes→media-type→retrieved→
    /// origin→acquisition→note），與既有手工條目同形；只 append、永不重寫既有行。
    private func appendIndexEntry(digest: String, bytes: Int,
                                  provenance p: SourceProvenance) throws {
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
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } else {
            try Data(line.utf8).write(to: url, options: .atomic)
        }
    }

    /// index 內既有條目的 digest 集合（寬鬆讀：只取 `content` 欄；malformed 行在
    /// 這裡跳過——它們的**回報**歸 `auditSourceIndex`，重複檢查不需要為它們失敗）。
    private func indexedDigests() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: sourceIndexURL.path) else { return [] }
        let text = try String(contentsOf: sourceIndexURL, encoding: .utf8)
        var digests = Set<String>()
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               let content = obj["content"] as? String,
               ProvenanceReference.isValidDigest(content) {
                digests.insert(content)
            }
        }
        return digests
    }

    /// #224：blob ↔ index 的兩向一致性 + malformed 行回報。
    func auditSourceIndex() throws -> SourceIndexAudit {
        let fm = FileManager.default
        // 磁碟上的 blob（只認 2-hex 目錄 / 62-hex 檔名的正規形；其他殘留歸 layoutResidue）
        var diskDigests = Set<String>()
        if let shards = try? fm.contentsOfDirectory(atPath: sourcesDir.path) {
            for shard in shards where shard.count == 2 && shard.allSatisfy({ "0123456789abcdef".contains($0) }) {
                let dir = sourcesDir.appendingPathComponent(shard)
                for f in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
                where f.count == 62 && f.allSatisfy({ "0123456789abcdef".contains($0) }) {
                    diskDigests.insert("sha256:\(shard)\(f)")
                }
            }
        }
        // index 條目 + malformed 行
        var indexDigests = Set<String>()
        var malformed: [Int] = []
        if fm.fileExists(atPath: sourceIndexURL.path) {
            let text = try String(contentsOf: sourceIndexURL, encoding: .utf8)
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
                if let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                   let content = obj["content"] as? String,
                   ProvenanceReference.isValidDigest(content) {
                    indexDigests.insert(content)
                } else {
                    malformed.append(i + 1)
                }
            }
        }
        return SourceIndexAudit(
            orphanBlobs: diskDigests.subtracting(indexDigests).sorted(),
            danglingEntries: indexDigests.subtracting(diskDigests).sorted(),
            malformedLines: malformed)
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
                             indexEntryCreated: false)
    }

    /// 讀回存檔。**缺席（nil）與格式錯（throw）是兩個條件**（task 4.5）：
    /// 存檔不進 remote，clone 後必然缺席——那是預期狀態不是損毀；
    /// 形狀錯的 digest 才是真正的格式錯誤。
    func sourceContent(digest: String) throws -> Data? {
        guard let url = sourceURL(digest: digest) else {
            throw StoreIOError.invalidInput(
                what: "source digest",
                why: "digest 形狀必須是 sha256: + 64 個小寫 hex，實得「\(displaySafe(digest, max: 120))」")
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    /// 全庫 references 指名、但本機沒有存檔的 digest（排序去重）。
    /// 「回報缺席」的可用面——doctor/CLI 接線屬後續 issue（Out of scope）。
    func missingSourceDigests(_ load: LibraryLoad) -> [String] {
        var digests = Set<String>()
        func collect(_ refs: [ProvenanceReference]) {
            for r in refs {
                switch r.kind {
                case .retrieval(_, _, _, _, let content): digests.insert(content)
                case .judgement(_, let restsOn): digests.formUnion(restsOn)
                }
            }
        }
        for p in load.people { collect(p.references) }
        for o in load.organizations { collect(o.references) }
        return digests.filter { d in
            guard let url = sourceURL(digest: d) else { return true }
            return !FileManager.default.fileExists(atPath: url.path)
        }.sorted()
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
