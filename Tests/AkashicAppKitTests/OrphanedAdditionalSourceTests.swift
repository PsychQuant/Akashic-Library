import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicAppKit

/// #609：App 裁決台看得到附加來源已刪除的 entry，並能拿掉那些來源；「只有附加來源、全部已刪除」的 entry
/// 當成整筆 orphan，可以脫鉤或丟垃圾桶。
final class OrphanedAdditionalSourceTests: XCTestCase {
    var root: URL!
    var state: AppState!
    private let gone = Date(timeIntervalSince1970: 1_753_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-orphadd-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        var partial = Entry(id: UUID(), citekey: "partial2020", type: .periodicalArticle, title: "Partial")
        partial.provenance = Provenance(zoteroKey: "K1", zoteroVersion: 1, libraryID: 1)
        partial.additionalProvenance = [
            Provenance(zoteroKey: "K2", zoteroVersion: 1, libraryID: 5, orphanedAt: gone),
            Provenance(zoteroKey: "K3", zoteroVersion: 1, libraryID: 7),
        ]
        try store.writeEntry(partial)
        var allGone = Entry(id: UUID(), citekey: "allgone2020", type: .periodicalArticle, title: "All gone")
        allGone.additionalProvenance = [Provenance(zoteroKey: "K4", zoteroVersion: 1, libraryID: 5, orphanedAt: gone)]
        try store.writeEntry(allGone)
        var alive = Entry(id: UUID(), citekey: "alive2020", type: .periodicalArticle, title: "Alive")
        alive.provenance = Provenance(zoteroKey: "K5", zoteroVersion: 1, libraryID: 1)
        try store.writeEntry(alive)
        state = AppState(root: root)
        try state.load()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func entry(_ citekey: String) throws -> Entry? {
        try LibraryStore(root: root).load().entries.first { $0.citekey == citekey }
    }

    // MARK: - git fixture（移除前要求記錄檔已 commit——移除面一族的使用者裁決，2026-09-27）

    /// 剝除 GIT_*（#234）：從 git hook 裡跑測試時，hook 環境帶著 GIT_DIR，`-C` 擋不住它。
    private static var scrubbedGitEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    }

    private func git(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path, "-c", "user.email=t@t", "-c", "user.name=t"] + args
        p.environment = Self.scrubbedGitEnvironment
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
    }

    private func commitAll() {
        if !FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path) { git(["init", "-q"]) }
        git(["add", "-A"])
        git(["commit", "-q", "--allow-empty", "-m", "fixture"])
    }

    // MARK: - 清單

    func testBothShapesAreListed() {
        let model = OrphanModel(state: state)
        XCTAssertEqual(model.orphans.map(\.citekey), ["allgone2020"], "只有附加來源、全部已刪除 → 整筆 orphan")
        XCTAssertEqual(model.orphanedAdditionalSourceEntries.map(\.citekey), ["partial2020"])
    }

    // MARK: - 整筆 orphan 的既有兩個動作，作用在「只有附加來源、全部已刪除」的 entry

    func testDetachWorksWhenEverySourceIsAdditionalAndGone() throws {
        try OrphanModel(state: state).resolve(citekey: "allgone2020", action: .detachFromZotero)
        let after = try XCTUnwrap(try entry("allgone2020"))
        XCTAssertNil(after.provenance)
        XCTAssertEqual(after.additionalProvenance, [], "已刪除的附加來源一併拿掉，轉純 Akashic entry")
    }

    func testTrashWorksWhenEverySourceIsAdditionalAndGone() throws {
        try OrphanModel(state: state).resolve(citekey: "allgone2020", action: .moveToTrash)
        XCTAssertNil(try entry("allgone2020"))
    }

    // MARK: - 拿掉已刪除的附加來源

    func testRemovalDropsOnlyTheOrphanedAdditionalSources() throws {
        commitAll()
        let before = try XCTUnwrap(try entry("partial2020"))
        let report = try OrphanModel(state: state)
            .removeOrphanedAdditionalSources(citekey: "partial2020", reason: "群組那份已刪、不再等")
        let after = try XCTUnwrap(try entry("partial2020"))
        XCTAssertEqual(after.provenance, before.provenance, "主來源不動")
        XCTAssertEqual(after.additionalProvenance.map(\.zoteroKey), ["K3"], "活著的附加來源不動")
        XCTAssertEqual(after.title, before.title)
        XCTAssertTrue(report.contains("5:K2"), report)
        XCTAssertTrue(report.contains("群組那份已刪、不再等"), "理由只進報告，要全文：\(report)")
        XCTAssertTrue(state.entriesWithOrphanedAdditionalSource.isEmpty, "寫後 reload")
    }

    func testRemovalRefusesWithoutAGitCopy() throws {
        let before = try XCTUnwrap(try entry("partial2020"))
        // 不在 git 工作樹
        XCTAssertThrowsError(try OrphanModel(state: state)
            .removeOrphanedAdditionalSources(citekey: "partial2020", reason: "r")) { err in
            XCTAssertTrue(err.localizedDescription.contains("git"), err.localizedDescription)
        }
        XCTAssertEqual(try entry("partial2020"), before, "零寫入")
        // 在 git 裡、但記錄檔有未提交修改
        commitAll()
        var dirty = before
        dirty.title = "Edited, not committed"
        try LibraryStore(root: root).writeEntry(dirty)
        try state.load()
        XCTAssertThrowsError(try OrphanModel(state: state)
            .removeOrphanedAdditionalSources(citekey: "partial2020", reason: "r"))
        XCTAssertEqual(try entry("partial2020")?.additionalProvenance.count, 2, "零寫入")
    }

    func testRemovalRequiresAReason() throws {
        commitAll()
        for r in ["", "   \n"] {
            XCTAssertThrowsError(try OrphanModel(state: state).removeOrphanedAdditionalSources(citekey: "partial2020", reason: r))
        }
        XCTAssertEqual(try entry("partial2020")?.additionalProvenance.count, 2, "零寫入")
    }

    /// 動作當下重新讀盤驗證（TOCTOU）：沒有已刪除附加來源的、整筆 orphan 的，都拒絕——後者要走脫鉤。
    func testRemovalRevalidatesTheShapeAtActionTime() throws {
        commitAll()
        let model = OrphanModel(state: state)
        XCTAssertThrowsError(try model.removeOrphanedAdditionalSources(citekey: "alive2020", reason: "r"))
        XCTAssertThrowsError(try model.removeOrphanedAdditionalSources(citekey: "allgone2020", reason: "r"))
        XCTAssertThrowsError(try model.removeOrphanedAdditionalSources(citekey: "ghost2000x", reason: "r"))
        // 清單開著的時候，外部把那個來源恢復了
        let store = LibraryStore(root: root)
        var restored = try XCTUnwrap(try entry("partial2020"))
        restored.additionalProvenance[0].orphanedAt = nil
        try store.writeEntry(restored)
        commitAll()
        XCTAssertThrowsError(try model.removeOrphanedAdditionalSources(citekey: "partial2020", reason: "r"))
        XCTAssertEqual(try entry("partial2020")?.additionalProvenance.count, 2)
    }
}
