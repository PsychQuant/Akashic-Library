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

    // MARK: - 4.1/4.2 內容定址

    func testStorePathIsTwoCharShardedWithoutExtension() throws {
        let receipt = try store.storeSourceContent(Data("hello provenance".utf8))
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
        let r1 = try store.storeSourceContent(a)
        let r2 = try store.storeSourceContent(a)
        XCTAssertEqual(r1.digest, r2.digest)
        let files = try FileManager.default.subpathsOfDirectory(
            atPath: root.appendingPathComponent("sources").path)
            .filter { !$0.hasSuffix("/") && !$0.contains(".DS_Store")
                      && $0.contains("/") }
        XCTAssertEqual(files.count, 1, "同位元組只存一份：\(files)")

        _ = try store.storeSourceContent(Data("different".utf8))
        let after = try FileManager.default.subpathsOfDirectory(
            atPath: root.appendingPathComponent("sources").path)
            .filter { $0.contains("/") }
        XCTAssertEqual(after.count, 2, "位元組相異存兩份：\(after)")
    }

    /// D3：位元組原樣——CRLF 不正規化、非 UTF-8 不轉換。
    func testBytesPreservedVerbatim() throws {
        var data = Data("line1\r\nline2\r\n".utf8)
        data.append(contentsOf: [0xFF, 0xFE, 0x00, 0x9D])   // 非 UTF-8 位元組
        let receipt = try store.storeSourceContent(data)
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
        XCTAssertThrowsError(try store.storeSourceContent(Data("secret page".utf8)),
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
        let receipt = try store.storeSourceContent(Data("page".utf8))
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
        let receipt = try store.storeSourceContent(Data("page".utf8))
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
        XCTAssertThrowsError(try store.storeSourceContent(Data("leak me".utf8)),
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
        let present = try store.storeSourceContent(Data("kept".utf8)).digest
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
        XCTAssertEqual(store.missingSourceDigests(load), [absent],
                       "缺席清單只含真的不在本機的（present 不在列）")
    }
}
