import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #683：可回溯閘的外層 wrapper 與理由上限只有一份，住在 StoreIO（`LibraryStore.recordRecoverability`／`LibraryStore.maxStatementBytes`）。
///
/// 先前 App 的移除面（#609）自己寫了一份外層（路徑解析＋自己的訊息＋自己的 `4_096`），與 `AkashicService.assertRecordsRecoverable`、
/// `AkashicService.maxStatementBytes` 是同一件事——而 AppKit 與 MCPKit 互不能 import，所以只能各寫一次。這裡釘：
/// (1) 共用函式本身的行為（回溯、找不到、legacy 佈局、路徑取自磁碟）；(2) service 那一層就是它的薄包裝，措辭逐字相同；
/// (3) 常數只有一個定義，service 的名字是它的別名。App 那一半的釘在 `AkashicAppKitTests/OrphanedAdditionalSourceTests`。
final class RecordRecoverabilityTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-recoverable-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    // MARK: - git fixture（`StoreGitCommit`：剝除 GIT_* 的 helper，已登記在 GitSpawnHygieneTests）

    private func git(_ args: [String]) { StoreGitCommit.run(args, in: root) }
    private func commitAll() { StoreGitCommit.commitAll(root) }

    private func seedEntry(_ citekey: String = "alpha2020") throws -> Entry {
        let e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: "Alpha")
        try store.writeEntry(e)
        return e
    }

    private func check(_ e: Entry, legacy: [UUID: String] = [:]) -> LibraryStore.RecordRecoverability {
        LibraryStore.recordRecoverability(root: root, items: [(e.id, "work「\(e.citekey)」")], legacyPaths: legacy,
                                          action: "這次會刪掉一筆", issue: "#683")
    }

    // MARK: - 共用函式本身

    func testNothingToCheckIsAllClear() {
        let r = LibraryStore.recordRecoverability(root: root, items: [], action: "a", issue: "#683")
        XCTAssertNil(r.refusal)
        XCTAssertTrue(r.paths.isEmpty)
    }

    func testRefusesOutsideAGitWorkTree() throws {
        let e = try seedEntry()
        let refusal = try XCTUnwrap(check(e).refusal)
        XCTAssertTrue(refusal.contains("不在 git 工作樹裡") && refusal.contains("整批拒絕、零寫入") && refusal.contains("#683"), refusal)
    }

    func testRefusesAnUncommittedOrDirtyRecord() throws {
        let e = try seedEntry()
        git(["init", "-q"])   // 在工作樹裡，但檔案還沒被追蹤
        XCTAssertNotNil(check(e).refusal, "未追蹤")
        commitAll()
        XCTAssertNil(check(e).refusal, "已 commit、乾淨")
        var dirty = e; dirty.title = "Edited, not committed"
        try store.writeEntry(dirty)
        let refusal = try XCTUnwrap(check(e).refusal)
        XCTAssertTrue(refusal.contains("work「alpha2020」"), "拒絕要點名那一筆：\(refusal)")
    }

    /// 找不到記錄檔＝拒絕，不放行（共用的 `filesNotSafelyRecoverable` 對不存在的路徑是略過，那是刪檔的語意）。
    func testAMissingRecordFileIsRefusedNotWaved() throws {
        commitAll()
        let ghost = Entry(id: UUID(), citekey: "ghost2020", type: .periodicalArticle, title: "G")
        let refusal = try XCTUnwrap(check(ghost).refusal)
        XCTAssertTrue(refusal.contains("找不到記錄檔") && refusal.contains("work「ghost2020」"), refusal)
    }

    /// 路徑取自磁碟上的實際檔名，不由 id 拼（#573 R1）：小寫 UUID 檔名的記錄也能被驗到，回傳的路徑就是那個小寫檔名。
    func testThePathComesFromTheFileOnDiskNotFromTheID() throws {
        let e = try seedEntry()
        let upper = root.appendingPathComponent("entities/\(e.id.uuidString).yaml")
        let lower = root.appendingPathComponent("entities/\(e.id.uuidString.lowercased()).yaml")
        try FileManager.default.moveItem(at: upper, to: lower)
        commitAll()
        let r = check(e)
        XCTAssertNil(r.refusal, r.refusal ?? "")
        XCTAssertEqual(r.paths[e.id], "entities/\(e.id.uuidString.lowercased()).yaml")
    }

    /// legacy 佈局（format < 2）：記錄檔是 `entries/<citekey>.yaml`。只有呼叫端給了 `legacyPaths` 才走，且磁碟上要真的有那個檔。
    func testLegacyPathIsUsedOnlyWhenGivenAndPresent() throws {
        let e = Entry(id: UUID(), citekey: "old2020", type: .periodicalArticle, title: "Old")
        let dir = root.appendingPathComponent("entries")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try EntryYAML.encode(e).write(to: dir.appendingPathComponent("old2020.yaml"), atomically: true, encoding: .utf8)
        commitAll()
        XCTAssertTrue(try XCTUnwrap(check(e).refusal).contains("找不到記錄檔"), "沒給 legacyPaths：只認 entities/")
        let r = check(e, legacy: [e.id: "entries/old2020.yaml"])
        XCTAssertNil(r.refusal, r.refusal ?? "")
        XCTAssertEqual(r.paths[e.id], "entries/old2020.yaml")
        XCTAssertTrue(try XCTUnwrap(check(e, legacy: [e.id: "entries/nope.yaml"]).refusal).contains("找不到記錄檔"),
                      "給了路徑但磁碟上沒有那個檔：仍是找不到")
    }

    // MARK: - service 是它的薄包裝

    /// `assertRecordsRecoverable` 丟的句子與共用函式的拒絕**逐字相同**（service 只把它包成 `ServiceError.invalid`）；通過時回傳同一份路徑。
    func testServiceWrapperSaysTheSameSentenceAndReturnsTheSamePaths() throws {
        let e = try seedEntry()
        let service = AkashicService(root: root)
        let items: [(id: UUID, label: String)] = [(e.id, "work「alpha2020」")]
        let shared = try XCTUnwrap(LibraryStore.recordRecoverability(root: root, items: items, action: "這次會刪掉一筆", issue: "#683").refusal)
        XCTAssertThrowsError(try service.assertRecordsRecoverable(items, action: "這次會刪掉一筆", issue: "#683")) { error in
            guard case ServiceError.invalid(let why) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(why, shared)
        }
        commitAll()
        let viaService = try service.assertRecordsRecoverable(items, action: "這次會刪掉一筆", issue: "#683")
        XCTAssertEqual(viaService, LibraryStore.recordRecoverability(root: root, items: items, action: "x", issue: "#683").paths)
        XCTAssertEqual(viaService[e.id].map { $0.hasPrefix("entities/") }, true)
    }

    // MARK: - 常數只有一個定義

    func testTheStatementLimitHasOneDefinitionAndTheServiceNameIsAnAlias() throws {
        XCTAssertEqual(LibraryStore.maxStatementBytes, 4_096)
        XCTAssertEqual(AkashicService.maxStatementBytes, LibraryStore.maxStatementBytes)
        var u = URL(fileURLWithPath: #filePath)
        while u.lastPathComponent != "Tests" { u.deleteLastPathComponent() }
        let sources = u.deletingLastPathComponent().appendingPathComponent("Sources")
        var definitions: [String] = []
        let e = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in e where url.pathExtension == "swift" {
            for (n, line) in try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
                // 「字面量」的定義：`maxStatementBytes = 4_096`；別名（`= LibraryStore.maxStatementBytes`）不算第二個定義
                if code.range(of: #"maxStatementBytes\s*(:\s*\w+\s*)?=\s*[0-9_]+"#, options: .regularExpression) != nil {
                    definitions.append("\(url.lastPathComponent):\(n + 1)")
                }
            }
        }
        XCTAssertEqual(definitions.count, 1, "理由上限的字面量定義只能有一處：\(definitions)")
        XCTAssertTrue(definitions.first?.hasPrefix("RecoverabilityGate.swift:") == true, "而且它在 StoreIO：\(definitions)")
    }
}
