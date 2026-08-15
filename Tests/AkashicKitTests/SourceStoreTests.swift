import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #66 task 4.x：擷取內容的存檔——內容定址、版控排除的 fail-closed 驗證、
/// digest 缺席的預期化回報。
///
/// 沙箱鐵律：全部在 temp store，不碰真實 `~/.akashic`。
final class SourceStoreTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-src-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    // MARK: - #224 存 source 是一個動作（blob + index 條目一起落地）

    private var indexURL: URL {
        root.appendingPathComponent("sources").appendingPathComponent("index.jsonl")
    }

    private func prov(note: String? = "測試條目") -> LibraryStore.SourceProvenance {
        LibraryStore.SourceProvenance(mediaType: "application/json", retrieved: "2026-08-13",
                         origin: "unit-test", acquisition: "file", note: note)
    }

    private func indexLines() throws -> [String] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        return try String(contentsOf: indexURL, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    func testStoreSourceWritesBlobAndIndexEntryTogether() throws {
        let receipt = try store.storeSource(Data("one action".utf8), provenance: prov())
        XCTAssertTrue(receipt.indexEntryCreated)
        // blob 落地
        let hex = String(receipt.digest.dropFirst("sha256:".count))
        let blob = root.appendingPathComponent("sources")
            .appendingPathComponent(String(hex.prefix(2)))
            .appendingPathComponent(String(hex.dropFirst(2)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: blob.path))
        // index 條目同時落地，欄位齊備
        let lines = try indexLines()
        XCTAssertEqual(lines.count, 1)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(lines[0].utf8)) as? [String: Any])
        XCTAssertEqual(obj["content"] as? String, receipt.digest)
        XCTAssertEqual(obj["bytes"] as? Int, "one action".utf8.count)
        XCTAssertEqual(obj["media-type"] as? String, "application/json")
        XCTAssertEqual(obj["retrieved"] as? String, "2026-08-13")
        XCTAssertEqual(obj["origin"] as? String, "unit-test")
        XCTAssertEqual(obj["acquisition"] as? String, "file")
        XCTAssertEqual(obj["note"] as? String, "測試條目")
    }

    func testDuplicateDigestDoesNotAppendSecondEntry() throws {
        let data = Data("same bytes".utf8)
        let r1 = try store.storeSource(data, provenance: prov())
        XCTAssertTrue(r1.indexEntryCreated)
        let r2 = try store.storeSource(data, provenance: prov(note: "第二次——不得落地"))
        XCTAssertFalse(r2.indexEntryCreated, "同 digest 不重複 append，receipt 要說出來")
        XCTAssertEqual(try indexLines().count, 1)
    }

    /// lossless：既有手工條目（含未知欄位、非標準空白）**逐字**不動——append-only 永不重寫。
    ///
    /// **fixture 刻意不帶結尾換行**（verify D1／logic HIGH-2：手工檔常見狀態；
    /// 無守衛時新行會黏進既有行、毀掉它的可解析性——這正是本測試要抓的）。
    func testExistingHandwrittenLinesAreNeverRewritten() throws {
        let handwritten = #"{"content": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "bytes": 1,  "custom-field": "手工",   "note": "奇怪空白也要保留"}"#
        try FileManager.default.createDirectory(
            at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try handwritten.write(to: indexURL, atomically: true, encoding: .utf8)   // 無結尾 \n

        _ = try store.storeSource(Data("new entry".utf8), provenance: prov())
        let lines = try indexLines()
        XCTAssertEqual(lines.count, 2, "新條目必須落在**新的一行**，不得黏進既有行")
        XCTAssertEqual(lines[0], handwritten, "既有行必須逐字保留（含未知欄位與空白）")
        // 兩行都必須各自可解析——吞併會讓其中一行變垃圾
        for l in lines {
            XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(l.utf8)),
                            "行必須可解析：\(l)")
        }
    }

    /// verify Codex #4：sidecar 腐壞時不可判定冪等——fail-closed 拒寫，且不留孤兒 blob。
    func testStoreSourceRefusesWhenIndexMalformed() throws {
        try FileManager.default.createDirectory(
            at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not json at all\n".write(to: indexURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.storeSource(Data("blocked".utf8), provenance: prov())) { e in
            let msg = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            XCTAssertTrue(msg.contains("修復") || msg.contains("doctor"), "錯誤要指路：\(msg)")
        }
        // 拒寫在任何磁碟寫入之前——不得留下新 blob
        let shards = ((try? FileManager.default.contentsOfDirectory(
            atPath: root.appendingPathComponent("sources").path)) ?? [])
            .filter { $0.count == 2 }
        XCTAssertTrue(shards.isEmpty, "拒寫時不得留孤兒 blob：\(shards)")
    }

    /// verify D2（lossless-intake「丟棄必須可見」）：冪等早退丟棄的 provenance 要在回條上。
    func testIdempotentStoreReportsDiscardedProvenance() throws {
        let data = Data("same".utf8)
        let r1 = try store.storeSource(data, provenance: prov())
        XCTAssertNil(r1.discardedProvenance)
        let r2 = try store.storeSource(data, provenance: prov(note: "被丟的敘述"))
        XCTAssertEqual(r2.discardedProvenance?.note, "被丟的敘述",
                       "呼叫端必須看得到自己這份 provenance 沒被寫入")
    }

    /// verify req F2：malformed 行號必須是**實際檔案行號**（空行不位移編號、也不算 malformed）。
    func testMalformedLineNumbersAccountForBlankLines() throws {
        try FileManager.default.createDirectory(
            at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let good = #"{"content": "sha256:\#(String(repeating: "e", count: 64))", "bytes": 1}"#
        try "\(good)\n\ngarbage line\n".write(to: indexURL, atomically: true, encoding: .utf8)
        let audit = try store.auditSourceIndex()
        XCTAssertEqual(audit.malformedLines, [3], "空行（第 2 行）不算 malformed、也不得讓編號位移")
    }

    /// verify reg F1／sec HIGH-2：非法 UTF-8 不得殺死 audit——壞位元組落進 malformed 通道。
    func testNonUTF8BytesFallIntoMalformedChannelNotThrow() throws {
        try FileManager.default.createDirectory(
            at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var bytes = Data("{\"content\": \"x".utf8)
        bytes.append(contentsOf: [0xFF, 0xFE])
        bytes.append(contentsOf: Data("\"}\n".utf8))
        try bytes.write(to: indexURL)
        let audit = try store.auditSourceIndex()   // 不得 throw
        XCTAssertEqual(audit.malformedLines, [1])
    }

    /// verify reg F2：shard 讀不到 ≠ blob 缺席——不得捏造懸空條目。
    func testUnreadableShardIsReportedNotFabricatedAsDangling() throws {
        let receipt = try store.storeSource(Data("perm test".utf8), provenance: prov())
        let shard = String(receipt.digest.dropFirst("sha256:".count).prefix(2))
        let shardDir = root.appendingPathComponent("sources").appendingPathComponent(shard)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: shardDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shardDir.path) }
        let audit = try store.auditSourceIndex()
        XCTAssertTrue(audit.danglingEntries.isEmpty,
                      "讀不到的 shard 不得把好條目報成懸空：\(audit.danglingEntries)")
        XCTAssertEqual(audit.unreadableShards, ["sources/\(shard)/"])
    }

    /// verify sec HIGH-1（#145 同形）：index.jsonl 自己的路徑必須過 fail-closed 閘——
    /// `sources/*/` 這種窄規則放得過 blob、放不過 index，必須拒寫。
    func testNarrowIgnoreRuleThatMissesIndexIsRefused() throws {
        GitFixture.initRepo(root)
        try store.ensureLayout()
        try "sources/*/\n".write(to: root.appendingPathComponent(".gitignore"),
                                 atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.storeSource(Data("half safe".utf8), provenance: prov()),
                             "blob 被排除、index 沒被排除——同一次呼叫一半安全一半外流，必須拒絕")
    }

    // MARK: - #224 blob ↔ index 一致性 audit

    func testAuditFindsOrphanBlob() throws {
        // 直接造一個沒有 index 條目的 blob（模擬手工/歷史遺留）
        let dir = root.appendingPathComponent("sources").appendingPathComponent("ab")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("orphan".utf8).write(to: dir.appendingPathComponent(String(repeating: "c", count: 62)))
        let audit = try store.auditSourceIndex()
        XCTAssertEqual(audit.orphanBlobs, ["sha256:ab" + String(repeating: "c", count: 62)])
        XCTAssertTrue(audit.danglingEntries.isEmpty)
    }

    func testAuditFindsDanglingEntry() throws {
        try FileManager.default.createDirectory(
            at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let missing = "sha256:" + String(repeating: "d", count: 64)
        try #"{"content": "\#(missing)", "bytes": 9}"#.appending("\n")
            .write(to: indexURL, atomically: true, encoding: .utf8)
        let audit = try store.auditSourceIndex()
        XCTAssertEqual(audit.danglingEntries, [missing])
        XCTAssertTrue(audit.orphanBlobs.isEmpty)
    }

    func testAuditReportsMalformedLinesLoudly() throws {
        try FileManager.default.createDirectory(
            at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not json at all\n{\"content\": \"sha256:bad-shape\"}\n"
            .write(to: indexURL, atomically: true, encoding: .utf8)
        let audit = try store.auditSourceIndex()
        XCTAssertEqual(audit.malformedLines.count, 2,
                       "非 JSON 行與 digest 形狀不合法的行都要 loud 回報，不得靜默跳過")
    }

    func testAuditCleanAfterStoreSource() throws {
        _ = try store.storeSource(Data("clean".utf8), provenance: prov())
        let audit = try store.auditSourceIndex()
        XCTAssertTrue(audit.orphanBlobs.isEmpty)
        XCTAssertTrue(audit.danglingEntries.isEmpty)
        XCTAssertTrue(audit.malformedLines.isEmpty)
    }

    // MARK: - 4.1/4.2 內容定址

    func testStorePathIsTwoCharShardedWithoutExtension() throws {
        let receipt = try store.storeSource(Data("hello provenance".utf8), provenance: prov())
        XCTAssertTrue(receipt.digest.hasPrefix("sha256:"))
        let hex = String(receipt.digest.dropFirst("sha256:".count))
        let expected = root.appendingPathComponent("sources")
            .appendingPathComponent(String(hex.prefix(2)))
            .appendingPathComponent(String(hex.dropFirst(2)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path),
                      "存檔必須住 sources/<前2>/<其餘>：\(expected.path)")
        XCTAssertTrue(expected.pathExtension.isEmpty, "無副檔名——位元組就是位元組")
    }

    func testSameBytesStoreOnceDifferentBytesTwice() throws {
        let a = Data("same".utf8)
        let r1 = try store.storeSource(a, provenance: prov())
        let r2 = try store.storeSource(a, provenance: prov())
        XCTAssertEqual(r1.digest, r2.digest)
        let files = try FileManager.default.subpathsOfDirectory(
            atPath: root.appendingPathComponent("sources").path)
            .filter { !$0.hasSuffix("/") && !$0.contains(".DS_Store")
                      && $0.contains("/") }
        XCTAssertEqual(files.count, 1, "同位元組只存一份：\(files)")

        _ = try store.storeSource(Data("different".utf8), provenance: prov())
        let after = try FileManager.default.subpathsOfDirectory(
            atPath: root.appendingPathComponent("sources").path)
            .filter { $0.contains("/") }
        XCTAssertEqual(after.count, 2, "位元組相異存兩份：\(after)")
    }

    /// D3：位元組原樣——CRLF 不正規化、非 UTF-8 不轉換。
    func testBytesPreservedVerbatim() throws {
        var data = Data("line1\r\nline2\r\n".utf8)
        data.append(contentsOf: [0xFF, 0xFE, 0x00, 0x9D])   // 非 UTF-8 位元組
        let receipt = try store.storeSource(data, provenance: prov())
        let back = try XCTUnwrap(store.sourceContent(digest: receipt.digest))
        XCTAssertEqual(back, data, "讀回位元組必須與寫入完全相同")
    }

    // MARK: - 4.3 ensureLayout 的忽略區塊（idempotent + 相容手工既有區塊）

    func testEnsureLayoutWritesIgnoreBlockOnce() throws {
        try store.ensureLayout()
        try store.ensureLayout()
        let ignore = try String(contentsOf: root.appendingPathComponent(".gitignore"),
                                encoding: .utf8)
        XCTAssertEqual(ignore.components(separatedBy: "# BEGIN akashic sources").count - 1, 1,
                       "重跑不重複寫入：\(ignore)")
        XCTAssertTrue(ignore.contains("sources/"), ignore)
    }

    /// 前提漂移（plan 修正）：真實 store 的區塊是**手工先寫的**——程式必須與
    /// 既有狀態相容：標記已在（即使內文與程式版不同）就不再寫、也不改寫。
    func testEnsureLayoutRespectsPreexistingHandWrittenBlock() throws {
        let hand = """
        # BEGIN akashic sources — 手工版本，內文與程式版不同
        sources/
        # END akashic sources
        """
        try hand.write(to: root.appendingPathComponent(".gitignore"),
                       atomically: true, encoding: .utf8)
        try store.ensureLayout()
        let ignore = try String(contentsOf: root.appendingPathComponent(".gitignore"),
                                encoding: .utf8)
        XCTAssertTrue(ignore.contains("手工版本"), "既有手工區塊不得被改寫：\(ignore)")
        XCTAssertEqual(ignore.components(separatedBy: "# BEGIN akashic sources").count - 1, 1)
    }

    // MARK: - 4.4 排除驗證（fail-closed）

    func testWriteRefusedWhenExclusionRemoved() throws {
        GitFixture.initRepo(root)
        try store.ensureLayout()
        // 使用者自行移除了忽略區塊
        try "".write(to: root.appendingPathComponent(".gitignore"),
                     atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.storeSource(Data("secret page".utf8), provenance: prov()),
                             "排除未生效必須拒寫——外流不可逆") { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("gitignore") || msg.contains("排除"),
                          "錯誤必須說明如何修復：\(msg)")
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("sources").path)
            && !((try? FileManager.default.contentsOfDirectory(
                atPath: root.appendingPathComponent("sources").path)) ?? []).isEmpty,
            "拒寫時不得留下內容")
    }

    func testWriteVerifiedWhenExclusionEffective() throws {
        GitFixture.initRepo(root)
        try store.ensureLayout()
        let receipt = try store.storeSource(Data("page".utf8), provenance: prov())
        XCTAssertTrue(receipt.exclusionVerified, "git repo 內排除生效 → 已驗證")
        // Acceptance：存檔目錄在版控狀態中不出現（git status 看不到 sources/）
        let status = LibraryStore.git(["status", "--porcelain"], in: root)
        XCTAssertNotNil(status)
        XCTAssertFalse(status!.out.contains("sources/"),
                       "存檔不得出現在版控狀態：\(status!.out)")
    }

    /// 契約 Behavior 第一條的 organization 側：既有記錄（無 references）零 diff。
    func testExistingOrganizationWithoutReferencesIsByteStable() throws {
        var org = Organization(key: "stat-sinica")
        org.names = TimelineOf([TemporalValue(value: "中央研究院統計科學研究所",
                                              range: DateRange(start: "1987"))])
        let canonical = try OrganizationYAML.encode(org)
        XCTAssertFalse(canonical.contains("references"),
                       "無 references 不寫出該鍵：\(canonical)")
        XCTAssertEqual(try OrganizationYAML.encode(try OrganizationYAML.decode(canonical)),
                       canonical, "decode→encode 位元組冪等")
    }

    func testWriteSkipsValidationOutsideGitRepoAndSaysSo() throws {
        try store.ensureLayout()   // 非 git repo
        let receipt = try store.storeSource(Data("page".utf8), provenance: prov())
        XCTAssertFalse(receipt.exclusionVerified,
                       "非 git repo 跳過驗證——事實記錄在 receipt，呼叫端可轉發")
    }

    /// #145 verify F1 的 regression：無關規則碰巧命中舊探測路徑（basename
    /// `probe`）不得騙過驗證——驗的必須是實際寫入路徑。
    func testUnrelatedIgnoreRuleDoesNotDefeatExclusionCheck() throws {
        GitFixture.initRepo(root)
        try store.ensureLayout()
        // 使用者移除了 sources 區塊；.gitignore 只剩一條與本案無關的規則
        try "probe\n".write(to: root.appendingPathComponent(".gitignore"),
                            atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.storeSource(Data("leak me".utf8), provenance: prov()),
                             "實際寫入路徑未被排除就必須拒寫——不管別的規則命中什麼")
        let sourcesPath = root.appendingPathComponent("sources").path
        let leftover = (try? FileManager.default.subpathsOfDirectory(atPath: sourcesPath))?
            .filter { $0.contains("/") } ?? []
        XCTAssertTrue(leftover.isEmpty, "拒寫不得留內容：\(leftover)")
    }

    // MARK: - 4.5 digest 缺席 ≠ 損毀

    func testAbsentDigestIsDistinctFromMalformed() throws {
        let absent = "sha256:" + String(repeating: "ee", count: 32)
        XCTAssertNil(try store.sourceContent(digest: absent),
                     "合法但缺席 → nil（clone 後的預期狀態）")
        XCTAssertThrowsError(try store.sourceContent(digest: "sha256:zzz"),
                             "形狀錯 → throw（真正的格式錯誤）——兩個條件必須可區分")
    }

    /// 載入照常成功 + 缺席可回報（record 引用缺席 digest 不是損毀）。
    func testRecordWithAbsentDigestLoadsAndReportsMissing() throws {
        let present = try store.storeSource(Data("kept".utf8), provenance: prov()).digest
        let absent = "sha256:" + String(repeating: "ee", count: 32)
        var p = Person(key: "chen-h-y")
        p.names = ["Chen, H-Y."]
        p.orcid = "0000-0003-4038-9439"
        p.references = [
            ProvenanceReference(field: "orcid", kind: .retrieval(
                url: "https://example.org/a", retrieved: "2026-08-03", status: 200,
                mediaType: nil, content: present)),
            ProvenanceReference(field: "names", value: "Chen, H-Y.", kind: .judgement(
                statement: "判定", restsOn: [absent])),
        ]
        try store.writePerson(p)
        let load = try store.load()
        XCTAssertEqual(load.people.count, 1, "缺席 digest 不阻擋載入")
        XCTAssertEqual(load.quarantined.count, 0)
        XCTAssertEqual(store.missingSourceDigests(load).missing, [absent],
                       "缺席清單只含真的不在本機的（present 不在列）")
    }

    /// 記錄側副本引用（`akashic.sources`）的缺席語意，與 person references 同一條
    /// 契約（#223）：digest 合法但本機無存檔＝**載入成功 + 可回報**，
    /// 與「記錄格式損毀」是兩種不同條件，不可混為一談。
    func testEntryWithAbsentCopyDigestLoadsAndReportsMissing() throws {
        let present = try store.storeSource(Data("copy".utf8), provenance: prov()).digest
        let absent = "sha256:" + String(repeating: "dd", count: 32)
        var e = Entry(id: UUID(), citekey: "a2020b", type: "article", title: "T")
        e.akashic.sources = [present, absent]
        _ = try store.writeEntry(e)
        let load = try store.load()
        XCTAssertEqual(load.entries.count, 1, "缺席 digest 不阻擋載入")
        XCTAssertEqual(load.quarantined.count, 0, "缺席不是損毀——不得進 quarantine")
        XCTAssertEqual(store.missingSourceDigests(load).missing, [absent],
                       "缺席清單只含真的不在本機的（present 不在列）")
    }

    /// 兩個關係項只在**內容**處相遇，不得因此被合併（#223）。
    /// work 記錄的副本引用（作品 ← 副本）與 person 記錄的欄位層級 provenance
    /// （值 ← 證據）指向同一份 digest 時，兩者各自保留、內容只存一份。
    ///
    /// 即使目前無需產品程式碼即通過，仍保留為回歸鎖：日後若有人「順手」把兩者
    /// 合併成一個欄位，這個測試會擋下來。
    func testCopyReferenceAndFieldReferenceCoexistOverSameContent() throws {
        let shared = try store.storeSource(Data("shared bytes".utf8), provenance: prov()).digest

        var work = Entry(id: UUID(), citekey: "a2020b", type: "article", title: "T")
        work.akashic.sources = [shared]
        _ = try store.writeEntry(work)

        var p = Person(key: "chen-h-y")
        p.names = ["Chen, H-Y."]
        p.orcid = "0000-0003-4038-9439"
        p.references = [
            ProvenanceReference(field: "orcid", kind: .retrieval(
                url: "https://example.org/a", retrieved: "2026-08-11", status: 200,
                mediaType: nil, content: shared)),
        ]
        try store.writePerson(p)

        let load = try store.load()
        XCTAssertEqual(load.entries.first?.akashic.sources, [shared],
                       "副本引用不得被改寫成欄位層級 reference")
        XCTAssertEqual(load.people.first?.references.count, 1,
                       "欄位層級 reference 不得被改寫成副本引用")
        XCTAssertEqual(load.people.first?.references.first?.field, "orcid",
                       "欄位層級 reference 仍綁在具名欄位上")
        XCTAssertEqual(store.missingSourceDigests(load).missing, [],
                       "共用的內容存在本機，兩邊都不該被回報為缺席")
        XCTAssertNotNil(try store.sourceContent(digest: shared),
                        "同位元組只存一份，兩個關係項共用它")
    }
}

// MARK: - #251／#265：missingSourceDigests 的掃描範圍與讀不到語意

extension SourceStoreTests {
    /// #251：divergence 的 judgement.restsOn（第 12 條邊）在掃描範圍——
    /// 消歧判斷的依據缺存檔時報告不得全盲。
    func testMissingScanCoversDivergenceRestsOn() throws {
        let absent = "sha256:" + String(repeating: "ee", count: 32)
        try store.writePerson(Person(key: "p-one", names: ["P"]))
        try store.writePerson(Person(key: "p-two", names: ["P2"]))
        var d = Divergence(id: UUID(), question: "q",
                           candidates: [DivergenceCandidate(key: "p-one", shape: .person),
                                        DivergenceCandidate(key: "p-two", shape: .person)])
        d.judgement = Judgement(statement: "s", restsOn: [absent])
        try store.writeDivergence(d)
        let load = try store.load()
        XCTAssertEqual(store.missingSourceDigests(load).missing, [absent],
                       "judgement 的依據缺存檔要被報出來——先前對這條邊全盲")
    }

    /// #265：shard 目錄存在但列不出來（權限）→ digest 不判缺席、shard 進
    /// unreadableShards——fileExists 對讀不到的父目錄回 false，直接信它是捏造缺席。
    func testUnreadableShardIsNotReportedAsMissing() throws {
        // 真的存一份（blob 落地），再把 shard 目錄鎖成不可讀
        let receipt = try store.storeSource(Data("locked".utf8), provenance: prov())
        var p = Person(key: "p-locked", names: ["L"])
        p.orcid = "0000-0002-1825-0097"   // reference 指名的欄位必須存在
        p.references = [ProvenanceReference(
            field: "orcid", value: nil,
            kind: .retrieval(url: "https://example.org", retrieved: "2026-08-15",
                             status: 200, mediaType: nil, content: receipt.digest))]
        try store.writePerson(p)
        let hex = String(receipt.digest.dropFirst("sha256:".count))
        let shardDir = root.appendingPathComponent("sources").appendingPathComponent(String(hex.prefix(2)))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: shardDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shardDir.path) }
        let load = try store.load()
        let out = store.missingSourceDigests(load)
        XCTAssertFalse(out.missing.contains(receipt.digest),
                       "讀不到不得判缺席（存檔明明在）：\(out.missing)")
        XCTAssertEqual(out.unreadableShards, ["sources/\(String(hex.prefix(2)))/"],
                       "讀不到要有自己的通道，不是靜默")
    }
}
