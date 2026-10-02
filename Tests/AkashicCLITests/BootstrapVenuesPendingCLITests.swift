import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #548：`bootstrap-venues` 的「與既有 venue 寬鬆共鍵」段**真的被印出來**。
///
/// **為什麼要 CLI 測試而不只是單元測試**：#547 的 BLOCKING finding 就是這個形狀——
/// model 端加了 `pendingMutual` 桶、單元測試全綠，而 `--apply` 的成功路徑從不呼叫
/// 印它的那個函式，於是 253 組／591 個寫法被靜默扣住。桶存在的唯一理由是「使用者
/// 要看得到」，所以判準必須落在 CLI 輸出上（`OrgBootstrapCLITests` 檔頭的同一論證）。
///
/// 用真 binary（非直接呼叫 `run()`）：#101/#112 的沙箱紀律。
final class BootstrapVenuesPendingCLITests: XCTestCase {
    private var root: URL!

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: [:])
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-bvp-\(UUID().uuidString)")
        let store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()

        // 既有 venue：帶冒號的 JRSS-B 全名。
        _ = try store.writeVenue(Venue(
            key: "jrss-b", type: .periodical,
            names: Timeline([TemporalValue(
                value: "Journal of the Royal Statistical Society Series B: Statistical Methodology")])))

        // 一筆 work 的刊名只差標點——括號形。
        var e = Entry(id: UUID(), citekey: "a2020punct", type: .periodicalArticle,
                      title: "T", authors: [.literal("A, A.")], date: "2020")
        e.fields = ["journaltitle":
            "Journal of the Royal Statistical Society Series B (Statistical Methodology)"]
        try store.writeEntry(e)

        // 另一筆是真的新刊——確保候選段不是空的（空清單什麼都證明不了）。
        var f = Entry(id: UUID(), citekey: "b2021new", type: .periodicalArticle,
                      title: "T", authors: [.literal("B, B.")], date: "2021")
        f.fields = ["journaltitle": "Journal of Educational Psychology"]
        try store.writeEntry(f)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// **乾跑要印出那一段，而且被扣住的不得出現在候選段。**
    func testDryRunPrintsThePendingSectionAndWithholdsTheCandidate() throws {
        let r = try cli(["bootstrap-venues"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("先消歧再說"),
                      "共鍵段沒有被印出來：\n\(r.output)")
        XCTAssertTrue(r.output.contains("jrss-b"),
                      "要說出撞的是哪一筆既有 venue：\n\(r.output)")
        XCTAssertTrue(r.output.contains("Journal of Educational Psychology"),
                      "無關的新刊仍要照常成為候選：\n\(r.output)")
        // 候選段的行帶 `[periodical ← journaltitle]`；被扣住的那一筆不該有這種行。
        let candidateLines = r.output.split(separator: "\n").filter { $0.contains("← journaltitle") }
        XCTAssertFalse(candidateLines.contains { $0.contains("Royal Statistical") },
                       "被扣住的刊名出現在候選段：\n\(candidateLines.joined(separator: "\n"))")
    }

    /// **`--apply` 也要印，而且真的不寫那一筆。**
    ///
    /// 乾跑印了不代表 apply 印——#547 的 BLOCKING 正是兩條路徑分岔。
    func testApplyAlsoReportsAndDoesNotWriteTheWithheldVenue() throws {
        let r = try cli(["bootstrap-venues", "--apply"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("先消歧再說"),
                      "--apply 沒有說出它扣住了什麼：\n\(r.output)")

        let venues = try LibraryStore(root: root, key: nil, environment: [:]).load().venues
        let keys = Set(venues.map(\.key))
        XCTAssertTrue(keys.contains("journal-of-educational-psychology"),
                      "無關的新刊要照常建檔：\(keys.sorted())")
        XCTAssertEqual(venues.filter { $0.names.entries.contains { $0.value.contains("Royal Statistical") } }
                             .map(\.key),
                       ["jrss-b"],
                       "JRSS-B 只能有一筆——被扣住的那個寫法不得建成第二筆：\(keys.sorted())")
    }

    /// **#563：`--apply` 建出來的 venue `authorized` 是空的**（真 binary、讀回磁碟）。「哪個寫法對外」是判定，
    /// 門檻建檔不做判定——同 `add-venue` 的 #227。顯示名退到 names 的第一段，所以顯示不變。
    func testApplyLeavesAuthorizedEmpty() throws {
        // 乾跑先跑（有候選時才說「建出來的 venue」）——放在 --apply 之後，候選已經沒了（#563 R2 verify 第 17／23 列）
        let dry = try cli(["bootstrap-venues"])
        XCTAssertTrue(dry.output.contains("authorized 留空"), "乾跑也說：\(dry.output)")
        let r = try cli(["bootstrap-venues", "--apply"])
        XCTAssertEqual(r.status, 0, r.output)
        let venues = try LibraryStore(root: root, key: nil, environment: [:]).load().venues
        let made = try XCTUnwrap(venues.first { $0.key == "journal-of-educational-psychology" },
                                 "新刊沒有被建出來：\(venues.map(\.key))")
        XCTAssertEqual(made.authorized, [], "bootstrap 不得替人指定對外形（#563）")
        XCTAssertEqual(made.displayName, "Journal of Educational Psychology")
        let file = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("entities"),
                                                               includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "yaml" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .first { $0.contains("key: journal-of-educational-psychology") }
        XCTAssertFalse(try XCTUnwrap(file).contains("authorized:"), "磁碟上不得出現 authorized 鍵：\(file ?? "")")
        // 輸出要告訴操作者：新建的 venue 不指定對外形、指定走哪個命令、doctor 不會報它（R1 verify 第 15 列）——
        // 命令要照抄跑得通：#564 起 --authorize 必附 --judgement（R2 verify 第 0／4 列）
        XCTAssertTrue(r.output.contains("update-venue") && r.output.contains("--authorize") && r.output.contains("doctor"), r.output)
        let hint = try XCTUnwrap(r.output.split(separator: "\n").first { $0.contains("--authorize") }, r.output)
        XCTAssertTrue(hint.contains("--judgement"), "指定的命令要帶 --judgement：\(hint)")
        // 待消歧那一段的 --add-variant 也一樣
        let pendingHint = try XCTUnwrap(r.output.split(separator: "\n").first { $0.contains("--add-variant") }, r.output)
        XCTAssertTrue(pendingHint.contains("--judgement"), "--add-variant 的命令要帶 --judgement：\(pendingHint)")
        // 沒有新建任何 venue 時不說「新建的 venue」（R2 verify 第 17／23 列）
        let again = try cli(["bootstrap-venues", "--apply"])
        XCTAssertEqual(again.status, 0, again.output)
        XCTAssertTrue(again.output.contains("已建立 0 筆"), again.output)
        XCTAssertFalse(again.output.contains("新建的 venue"), "沒有建任何 venue：\(again.output)")
        XCTAssertFalse(try cli(["bootstrap-venues"]).output.contains("authorized 留空"), "沒有候選時乾跑不說")
    }
}
