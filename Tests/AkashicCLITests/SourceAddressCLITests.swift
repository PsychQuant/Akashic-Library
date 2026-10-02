import XCTest
import Foundation
import CryptoKit
@testable import AkashicCore
@testable import AkashicStoreIO

/// #703 R2 verify 第 4、5、6、15 則，以真 binary 重現：位址被懸空 symlink、目錄佔住，或 blob 被截短時——
///
/// - R2 之前 `store-source` 回 rc=0、印「✓ 已建立 index 條目」、寫一列 index，位元組沒有存（#703 之前的 binary 會以真檔取代懸空 symlink，
///   這是 R1 引入的回歸）；`update-entry --add-source` 把截短的 blob 照連；`doctor` 什麼都不說。
/// - 現在：`store-source` 具名拒絕（rc=1）、不寫 index；`--add-source` 以大小不符拒絕；`doctor` 在 sources 一致性列出位址上的佔用與大小不符。
///
/// scratch store（`--library` 與 `AKASHIC_HOME` 都指 scratch）。
final class SourceAddressCLITests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var home: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-srcaddr-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try store.writeEntry(Entry(id: UUID(), citekey: "x2026y", type: .periodicalArticle, title: "T"))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: ["AKASHIC_HOME": home.path])
    }
    private func storeSource(_ file: URL) throws -> (status: Int32, output: String) {
        try cli(["store-source", file.path, "--media-type", "application/pdf", "--retrieved", "2026-10-01",
                 "--origin", "https://example.org/x.pdf", "--acquisition", "browser-download"])
    }
    private func file(_ data: Data) throws -> URL {
        let url = base.appendingPathComponent("in-\(UUID().uuidString).pdf")
        try data.write(to: url)
        return url
    }
    private func digest(_ data: Data) -> String { "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func address(_ d: String) -> URL {
        let hex = String(d.dropFirst("sha256:".count))
        return root.appendingPathComponent("sources/\(hex.prefix(2))/\(hex.dropFirst(2))")
    }
    private func indexLines() -> Int {
        let text = (try? String(contentsOf: root.appendingPathComponent("sources/index.jsonl"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").count
    }

    /// 第 5、6 則：懸空 symlink 佔住位址。
    func testADanglingSymlinkAtTheAddressIsRefusedAndDoctorListsIt() throws {
        let data = Data("%PDF-1.7 dangling".utf8)
        let url = address(digest(data))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: "/nonexistent-\(UUID().uuidString)")
        let r = try storeSource(try file(data))
        XCTAssertEqual(r.status, 1, r.output)
        XCTAssertTrue(r.output.contains("symlink") && r.output.contains("沒有記進 index"), r.output)
        XCTAssertFalse(r.output.contains("已建立 index 條目"), r.output)
        XCTAssertEqual(indexLines(), 0, "拒絕時不寫 index")
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: url.path), "位置不動")
        let doctor = try cli(["doctor"])
        XCTAssertTrue(doctor.output.contains("位址上不是普通檔（symlink"), doctor.output)
    }

    /// 第 5、6 則：目錄佔住位址。
    func testADirectoryAtTheAddressIsRefusedAndDoctorListsIt() throws {
        let data = Data("%PDF-1.7 directory".utf8)
        try FileManager.default.createDirectory(at: address(digest(data)), withIntermediateDirectories: true)
        let r = try storeSource(try file(data))
        XCTAssertEqual(r.status, 1, r.output)
        XCTAssertTrue(r.output.contains("目錄"), r.output)
        XCTAssertEqual(indexLines(), 0)
        let doctor = try cli(["doctor"])
        XCTAssertTrue(doctor.output.contains("位址上不是普通檔（目錄"), doctor.output)
        XCTAssertFalse(doctor.output.contains("孤兒 blob"), "目錄不是孤兒 blob：\(doctor.output)")
    }

    /// 第 4 則：blob 被截短。`store-source` 先說清楚這一次有沒有寫位元組；截短之後重存具名拒絕、`--add-source` 拒絕、doctor 報大小不符。
    func testATruncatedBlobIsRefusedByStoreSourceAndAddSourceAndReportedByDoctor() throws {
        let data = Data(repeating: 0x25, count: 4_096)
        let input = try file(data)
        let first = try storeSource(input)
        XCTAssertEqual(first.status, 0, first.output)
        XCTAssertTrue(first.output.contains("✓ 已存入位元組"), first.output)
        let again = try storeSource(input)
        XCTAssertEqual(again.status, 0, again.output)
        XCTAssertTrue(again.output.contains("位元組早已在 sources/"), again.output)
        let json = try cli(["store-source", input.path, "--media-type", "application/pdf", "--retrieved", "2026-10-01",
                            "--origin", "x", "--acquisition", "y", "--json"])
        XCTAssertTrue(json.output.contains("\"bytesWritten\" : false"), json.output)

        try Data(repeating: 0x25, count: 100).write(to: address(digest(data)))
        let refused = try storeSource(input)
        XCTAssertEqual(refused.status, 1, refused.output)
        XCTAssertTrue(refused.output.contains("100 bytes") && refused.output.contains("不覆寫"), refused.output)
        XCTAssertEqual(try Data(contentsOf: address(digest(data))).count, 100, "不覆寫")

        let link = try cli(["update-entry", "x2026y", "--add-source", digest(data), "--apply"])
        XCTAssertNotEqual(link.status, 0, link.output)
        XCTAssertTrue(link.output.contains("100 bytes") && link.output.contains("4096 bytes"), link.output)
        let store = LibraryStore(root: root, key: nil, environment: [:])
        XCTAssertEqual(try store.load().entries.first?.akashic.sources, [], "截短的 blob 不連")

        let doctor = try cli(["doctor"])
        XCTAssertTrue(doctor.output.contains("存檔大小與 index 不符（存檔 100 bytes、index 記 4096 bytes"), doctor.output)
        // b26 F6 LOW 10／15：補救辦法要兩邊都說——錯的也可能是 index 那一列（重存不會改既有的列）
        for text in [link.output, doctor.output] {
            XCTAssertTrue(text.contains("index 那一列的 bytes 記錯") && text.contains("重存不會改既有的列") && text.contains("手改"), text)
        }
    }
}
