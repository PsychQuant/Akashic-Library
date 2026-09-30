import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #703 R1 verify 第 2、8 則：「逐塊」要讓記憶體不隨檔案大小成長，這要量**真 binary 的尖峰 RSS** 才看得到。
///
/// 先前的證據只有 `SourceIntakeStreamingTests.testDigestAndCopyNeverAskForMoreThanOneChunk`——它證的是每次只要一塊，量不到留住了幾塊。
/// `FileHandle.read(upToCount:)` 回的是 autoreleased NSData，CLI 沒有外層 pool 排水，每一塊都留到行程結束：改動前的 binary 存 128 MiB
/// 的檔尖峰 284,557,312 bytes（2026-09-30 實測，約 2.1 倍——兩遍各留一份），`copy-zotero-attachments --apply` 跨檔累積。
///
/// **為什麼是子行程**：測試行程自己的 heap、先前的測試留下的常駐頁、XCTest 包在每支測試外的 autorelease pool 都會混進行程內的量測；
/// `/usr/bin/time -l` 報的是那一個子行程自己的 `ru_maxrss`。**為什麼減掉基準**：binary、dyld、Foundation 的常駐量（約 16 MB）與檔案大小無關，
/// 同一個命令存 1 MiB 的檔當基準，差值才是隨大小成長的那一段。門檻取檔案（或附件合計）大小的一半：改動前的差值是它的 2 倍以上，改動後是 MB 級。
///
/// 檔案是真的寫出來的位元組（不是 sparse——sparse 檔以 stat 判大小，而這裡要的是真的讀過每一塊）。
final class SourceIntakeMemoryCLITests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var home: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-srcmem-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try LibraryStore(root: root, key: nil, environment: [:]).ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    /// 寫一個 `mib` MiB 的檔，每 1 MiB 的內容不同（seed 讓兩個檔的 digest 不同）。一次只在記憶體裡放 1 MiB。
    private func writeFile(_ url: URL, mib: Int, seed: UInt8) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: nil))
        let h = try FileHandle(forWritingTo: url)
        defer { try? h.close() }
        var block = Data((0..<(1 << 20)).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) })
        for i in 0..<mib {
            block[0] = UInt8(truncatingIfNeeded: i)
            block[1] = seed
            try h.write(contentsOf: block)
        }
    }

    /// #239：hook 環境帶 `GIT_DIR`，`-C` 擋不住它——不剝的話 fixture 的 commit 會寫進使用者的 repo（同 `CopyZoteroAttachmentsCLITests`）。
    private var scrubbedGitEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    }

    private func git(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path, "-c", "user.email=t@t", "-c", "user.name=t"] + args
        p.environment = scrubbedGitEnvironment
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
    }

    private func storeSource(_ file: URL) throws -> (status: Int32, output: String, peakRSS: Int) {
        try CLITestHarness.runMeasuringPeakRSS(
            ["store-source", file.path, "--media-type", "application/octet-stream", "--retrieved", "2026-09-30",
             "--origin", "memory-test", "--acquisition", "file", "--library", root.path],
            env: ["AKASHIC_HOME": home.path])
    }

    func testStoreSourcePeakMemoryDoesNotGrowWithTheFileSize() throws {
        let small = base.appendingPathComponent("small.bin")
        let large = base.appendingPathComponent("large.bin")
        try writeFile(small, mib: 1, seed: 1)
        try writeFile(large, mib: 128, seed: 2)
        let baseline = try storeSource(small)
        XCTAssertEqual(baseline.status, 0, baseline.output)
        let big = try storeSource(large)
        XCTAssertEqual(big.status, 0, big.output)
        let grew = big.peakRSS - baseline.peakRSS
        print("SourceIntakeMemory store-source：1 MiB 尖峰 \(baseline.peakRSS) bytes、128 MiB 尖峰 \(big.peakRSS) bytes、差 \(grew)")
        XCTAssertLessThan(grew, 64 << 20,
                          "存 128 MiB 的檔，尖峰 RSS 比 1 MiB 的多 \(grew) bytes（基準 \(baseline.peakRSS)、大檔 \(big.peakRSS)）——"
                          + "每塊沒有在讀完之後釋放。改動前實測約多 2 倍檔案大小")
    }

    /// `copy-zotero-attachments --apply`：一趟讀很多檔（計畫一遍、複製兩遍），改動前每一塊都留到行程結束、跨檔累積。
    /// 三個 48 MiB 的附件（合計 144 MiB）；基準是同一個命令只複製一個 1 MiB 的附件。
    func testCopyZoteroAttachmentsPeakMemoryDoesNotAccumulateAcrossFiles() throws {
        let zdir = base.appendingPathComponent("zotero")
        try FileManager.default.createDirectory(at: zdir.appendingPathComponent("storage"), withIntermediateDirectories: true)
        try Data().write(to: zdir.appendingPathComponent("zotero.sqlite"))
        let store = LibraryStore(root: root, key: nil, environment: [:])
        func work(_ citekey: String, _ path: String) throws {
            _ = try store.writeEntry(Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: "T \(citekey)",
                                           attachments: [AttachmentRef(kind: .zotero, path: path)]))
        }
        try writeFile(zdir.appendingPathComponent("storage/SMALL001/s.pdf"), mib: 1, seed: 10)
        try work("s2025", "storage/SMALL001/s.pdf")
        for (i, key) in ["BIGKEY01", "BIGKEY02", "BIGKEY03"].enumerated() {
            try writeFile(zdir.appendingPathComponent("storage/\(key)/b.pdf"), mib: 48, seed: UInt8(20 + i))
            try work("b\(i)2025", "storage/\(key)/b.pdf")
        }
        git(["init", "-q"]); git(["add", "-A"]); git(["commit", "-q", "-m", "fixture"])
        func copy(_ citekeys: String) throws -> (status: Int32, output: String, peakRSS: Int) {
            try CLITestHarness.runMeasuringPeakRSS(
                ["copy-zotero-attachments", "--apply", "--citekeys", citekeys,
                 "--zotero-db", zdir.appendingPathComponent("zotero.sqlite").path, "--library", root.path],
                env: ["AKASHIC_HOME": home.path])
        }
        let baseline = try copy("s2025")
        XCTAssertEqual(baseline.status, 0, baseline.output)
        XCTAssertTrue(baseline.output.contains("已改寫 1 筆"), baseline.output)
        let big = try copy("b02025,b12025,b22025")
        XCTAssertEqual(big.status, 0, big.output)
        XCTAssertTrue(big.output.contains("已改寫 3 筆"), big.output)
        let grew = big.peakRSS - baseline.peakRSS
        print("SourceIntakeMemory copy-zotero-attachments：1 MiB 尖峰 \(baseline.peakRSS) bytes、3×48 MiB 尖峰 \(big.peakRSS) bytes、差 \(grew)")
        XCTAssertLessThan(grew, 72 << 20,
                          "三個 48 MiB 的附件，尖峰 RSS 比一個 1 MiB 的多 \(grew) bytes（基準 \(baseline.peakRSS)、三個大檔 \(big.peakRSS)）——"
                          + "讀過的塊跨檔累積")
    }
}
