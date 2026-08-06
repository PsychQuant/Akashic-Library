import XCTest
@testable import AkashicTestGuard

/// #124：守衛的指紋層自測（純函式，對假 root——絕不碰真實 home）。
/// fatalError 預設路徑不在此觸發；偵測能力與歸因訊息由下列測試釘住，
/// observer 糊接層由「全套 run + 守衛啟用零誤報」的整合證據涵蓋。
final class SandboxGuardTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-guard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testFingerprintDetectsContentChange() throws {
        let f = root.appendingPathComponent("index/somekey.sqlite")
        try FileManager.default.createDirectory(at: f.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "v1".write(to: f, atomically: true, encoding: .utf8)
        let before = RealHomeSandboxGuard.fingerprint(root: root)
        try "v2-longer".write(to: f, atomically: true, encoding: .utf8)
        let after = RealHomeSandboxGuard.fingerprint(root: root)
        XCTAssertNotEqual(before, after, "檔案內容改變（size 變）必須反映在指紋")
        XCTAssertTrue(RealHomeSandboxGuard
            .describeDiff(baseline: before, current: after).contains("somekey.sqlite"),
            "diff 描述要點名變動的檔案（歸因價值）")
    }

    func testFingerprintDetectsNewFile() throws {
        let before = RealHomeSandboxGuard.fingerprint(root: root)
        try "x".write(to: root.appendingPathComponent("ghost.yaml"),
                      atomically: true, encoding: .utf8)
        let after = RealHomeSandboxGuard.fingerprint(root: root)
        XCTAssertNotEqual(before, after)
        XCTAssertTrue(RealHomeSandboxGuard
            .describeDiff(baseline: before, current: after).contains("新增"))
    }

    /// 三態不混同（#128 verify Codex-6）：不存在／空目錄／有內容是三個不同指紋。
    /// 曾經三者都可塌縮成空表——「最後一個測試建出空的 home」就此隱形。
    func testAbsentEmptyAndPopulatedRootsAreDistinct() throws {
        let ghost = root.appendingPathComponent("never-created")
        let absent = RealHomeSandboxGuard.fingerprint(root: ghost)
        XCTAssertEqual(absent["/"], "absent", "不存在的 home（CI runner）是合法基線")

        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        let empty = RealHomeSandboxGuard.fingerprint(root: ghost)
        XCTAssertNotEqual(empty, absent, "空目錄長出來了＝異動，不得與「不存在」同指紋")

        try "x".write(to: ghost.appendingPathComponent("a.yaml"),
                      atomically: true, encoding: .utf8)
        XCTAssertNotEqual(RealHomeSandboxGuard.fingerprint(root: ghost), empty)
    }

    /// quickProbe 動態枚舉（#128 verify F3）：#101 的靶心是 index/<key>.sqlite，
    /// key 是什麼都要抓到——寫死 main.sqlite 只護得住恰好叫 main 的 store。
    func testQuickProbeDetectsInPlaceWriteToAnyKeyedIndex() throws {
        let idx = root.appendingPathComponent("index")
        try FileManager.default.createDirectory(at: idx, withIntermediateDirectories: true)
        let db = idx.appendingPathComponent("mylib.sqlite")
        try "db-v1".write(to: db, atomically: false, encoding: .utf8)
        let before = RealHomeSandboxGuard.quickProbe(root: root)
        Thread.sleep(forTimeInterval: 0.01)
        try "db-v2-longer".write(to: db, atomically: false, encoding: .utf8)   // in-place
        let after = RealHomeSandboxGuard.quickProbe(root: root)
        XCTAssertNotEqual(before, after,
                          "非 main 的 index 檔被 in-place 改寫必須被輕量探針抓到（#101 靶心）")
    }

    /// `.git/` 排除（#128 verify F2）：真實 home 是 live git repo，`git status`
    /// 都會動 `.git/index`——外部正常操作不得殺整輪測試。
    func testGitSubtreeIsExcludedFromBothLayers() throws {
        let gitDir = root.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "ref: main".write(to: gitDir.appendingPathComponent("HEAD"),
                              atomically: true, encoding: .utf8)
        let fBefore = RealHomeSandboxGuard.fingerprint(root: root)
        let qBefore = RealHomeSandboxGuard.quickProbe(root: root)
        try "ref: other".write(to: gitDir.appendingPathComponent("HEAD"),
                               atomically: true, encoding: .utf8)
        try "idx".write(to: gitDir.appendingPathComponent("index"),
                        atomically: true, encoding: .utf8)
        XCTAssertEqual(RealHomeSandboxGuard.fingerprint(root: root), fBefore,
                       ".git/ 內的變動不進全樹指紋")
        XCTAssertEqual(RealHomeSandboxGuard.quickProbe(root: root), qBefore,
                       ".git/ 不進輕量探針")
    }

    /// 偵測→歸因訊息的組合（#128 verify Codex-14 的可測部分）：
    /// index/ 淺層的異動要在 diff 描述裡點得出位置。
    func testProbeDiffAttributesIndexEscape() throws {
        let idx = root.appendingPathComponent("index")
        try FileManager.default.createDirectory(at: idx, withIntermediateDirectories: true)
        let before = RealHomeSandboxGuard.quickProbe(root: root)
        try "esc".write(to: idx.appendingPathComponent("victim.sqlite"),
                        atomically: true, encoding: .utf8)
        let after = RealHomeSandboxGuard.quickProbe(root: root)
        XCTAssertNotEqual(before, after)
        let diff = RealHomeSandboxGuard.describeDiff(baseline: before, current: after)
        XCTAssertTrue(diff.contains("victim.sqlite") || diff.contains("index"),
                      "違規訊息必須點得出變動位置，否則歸因價值歸零：\(diff)")
    }
}
