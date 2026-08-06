import XCTest
@testable import AkashicTestGuard

/// #124：守衛的指紋層自測（純函式，對假 root——絕不碰真實 home）。
/// observer 的 fatalError 路徑刻意不可測：那是 stop-the-world 的最後防線。
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
        let f = root.appendingPathComponent("index/main.sqlite")
        try FileManager.default.createDirectory(at: f.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try "v1".write(to: f, atomically: true, encoding: .utf8)
        let before = RealHomeSandboxGuard.fingerprint(root: root)
        try "v2-longer".write(to: f, atomically: true, encoding: .utf8)
        let after = RealHomeSandboxGuard.fingerprint(root: root)
        XCTAssertNotEqual(before, after, "檔案內容改變（size 變）必須反映在指紋")
        XCTAssertTrue(RealHomeSandboxGuard
            .describeDiff(baseline: before, current: after).contains("main.sqlite"),
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

    func testAbsentRootIsLegalBaselineAndAppearanceIsDetected() throws {
        let ghost = root.appendingPathComponent("never-created")
        let before = RealHomeSandboxGuard.fingerprint(root: ghost)
        XCTAssertTrue(before.isEmpty, "不存在的 home（CI runner）是合法基線")
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        try "x".write(to: ghost.appendingPathComponent("a.yaml"),
                      atomically: true, encoding: .utf8)
        XCTAssertNotEqual(RealHomeSandboxGuard.fingerprint(root: ghost), before,
                          "測試期間長出 home ＝逃逸，必須偵測得到")
    }

    func testQuickProbeDetectsIndexTouch() throws {
        let idx = root.appendingPathComponent("index")
        try FileManager.default.createDirectory(at: idx, withIntermediateDirectories: true)
        let before = RealHomeSandboxGuard.quickProbe(root: root)
        try "db".write(to: idx.appendingPathComponent("main.sqlite"),
                       atomically: true, encoding: .utf8)
        let after = RealHomeSandboxGuard.quickProbe(root: root)
        XCTAssertNotEqual(before, after, "index 被寫入必須被輕量探針抓到（#101 的靶心路徑）")
    }
}
