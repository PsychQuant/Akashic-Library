import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #564（Spectra change `name-classification-judgement`）的 CLI 面，走真 binary：`update-venue`、`update-organization`、`authorize-names`
/// 的 `--judgement`／`--rests-on`。旗標名、`validate()` 的用法錯誤（64，早於開 store）與 `run()` 的轉送都只有實際呼叫抓得到。
final class NameClassificationCLITests: XCTestCase {
    private var tmp: URL!
    private var root: URL!
    private let digest = "sha256:" + String(repeating: "ef", count: 32)

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-nccli-\(UUID().uuidString)")
        root = tmp.appendingPathComponent("store")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writeVenue(Venue(key: "some-journal", type: .periodical,
                                   names: Timeline([TemporalValue(value: "PSYCHOMETRIKA"), TemporalValue(value: "Psychometrika")])))
        try store.writeOrganization(Organization(key: "iss", names: Timeline([TemporalValue(value: "Institute of Statistical Science"),
                                                                             TemporalValue(value: "中央研究院統計科學研究所")]),
                                                 id: UUID()))
        try store.writePerson(Person(key: "guan-yongtao", names: ["Guan, Yongtao"]))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func run(_ args: [String], library: URL? = nil) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", (library ?? root).path], env: ["HOME": tmp.path, "AKASHIC_HOME": tmp.path])
    }
    private func venue() throws -> Venue { try XCTUnwrap(try LibraryStore(root: root).load().venues.first { $0.key == "some-journal" }) }
    private func org() throws -> Organization { try XCTUnwrap(try LibraryStore(root: root).load().organizations.first { $0.key == "iss" }) }
    private func person() throws -> Person { try XCTUnwrap(try LibraryStore(root: root).load().people.first { $0.key == "guan-yongtao" }) }
    private func statements(_ refs: [ProvenanceReference]) -> [String] {
        refs.filter(NameClassificationRecord.isRecord).map { r in
            guard case .judgement(let s, let restsOn) = r.kind else { return "" }
            return [r.field, r.value ?? "", s].joined(separator: "|") + (restsOn.isEmpty ? "" : "|" + restsOn.joined(separator: ","))
        }
    }

    // MARK: - venue 面

    func testVenueLegsNeedAReasonAndWriteRecords() throws {
        let nowhere = tmp.appendingPathComponent("no-such-store")
        for leg in [["--authorize", "Psychometrika"], ["--unauthorize", "Psychometrika"], ["--add-variant", "PSYCHOMETRIKA"]] {
            let missing = try run(["update-venue", "some-journal"] + leg, library: nowhere)
            XCTAssertEqual(missing.status, 64, "\(leg)：\(missing.output)")
            XCTAssertTrue(missing.output.contains("judgement"), "\(leg)：\(missing.output)")
        }
        XCTAssertTrue(try venue().references.isEmpty, "零寫入")

        let designated = try run(["update-venue", "some-journal", "--authorize", "Psychometrika", "--judgement", "期刊官網刊頭", "--rests-on", digest])
        XCTAssertEqual(designated.status, 0, designated.output)
        XCTAssertTrue(designated.output.contains("judgementsRecorded"), designated.output)
        XCTAssertEqual(try venue().authorized, ["Psychometrika"])
        XCTAssertEqual(statements(try venue().references), ["authorized|Psychometrika|指定：期刊官網刊頭|\(digest)"])

        let variant = try run(["update-venue", "some-journal", "--add-variant", "PSYCHOMETRIKA", "--judgement", "WoS 大寫形"])
        XCTAssertEqual(variant.status, 0, variant.output)
        let confirmed = try run(["update-venue", "some-journal", "--authorize", "Psychometrika", "--judgement", "再查一次"])
        XCTAssertEqual(confirmed.status, 0, confirmed.output)
        let withdrawn = try run(["update-venue", "some-journal", "--unauthorize", "Psychometrika", "--judgement", "官網已改名"])
        XCTAssertEqual(withdrawn.status, 0, withdrawn.output)
        XCTAssertEqual(statements(try venue().references), [
            "authorized|Psychometrika|指定：期刊官網刊頭|\(digest)",
            "variant|PSYCHOMETRIKA|指定：WoS 大寫形",
            "authorized|Psychometrika|確認：再查一次",
            "authorized|Psychometrika|撤回：官網已改名",
        ])
        XCTAssertEqual(try venue().authorized, [])
    }

    func testPaginatedAndClassificationCannotShareACall() throws {
        let both = try run(["update-venue", "some-journal", "--authorize", "Psychometrika", "--paginated", "true",
                            "--judgement", "r", "--rests-on", digest])
        XCTAssertEqual(both.status, 64, both.output)
        XCTAssertTrue(both.output.contains("不同一次呼叫"), both.output)
        XCTAssertTrue(try venue().references.isEmpty)
    }

    // MARK: - organization 面

    func testOrganizationLegsNeedAReasonAndWriteRecords() throws {
        let nowhere = tmp.appendingPathComponent("no-such-store")
        let missing = try run(["update-organization", "iss", "--authorize", "Institute of Statistical Science"], library: nowhere)
        XCTAssertEqual(missing.status, 64, missing.output)
        XCTAssertTrue(missing.output.contains("judgement"), missing.output)
        let alone = try run(["update-organization", "iss", "--judgement", "r"], library: nowhere)
        XCTAssertEqual(alone.status, 64, "理由單獨出現是用錯：\(alone.output)")

        let done = try run(["update-organization", "iss", "--authorize", "Institute of Statistical Science", "--judgement", "所方正式英文名稱"])
        XCTAssertEqual(done.status, 0, done.output)
        XCTAssertTrue(done.output.contains("judgementsRecorded"), done.output)
        // organization 沒有撤回腿（`--unauthorize` 已於 #557 R1 verify 之後拿掉，待裁）：旗標不存在、不是「存在但拒絕」，store 不動
        let gone = try run(["update-organization", "iss", "--unauthorize", "Institute of Statistical Science"])
        XCTAssertNotEqual(gone.status, 0, gone.output)
        XCTAssertEqual(statements(try org().references), ["authorized|Institute of Statistical Science|指定：所方正式英文名稱"],
                       "沒有新增記錄")
        XCTAssertEqual(try org().authorized, ["Institute of Statistical Science"], "零寫入")
    }

    // MARK: - authorize-names

    func testAuthorizeNamesApplyNeedsAReasonAndWritesRecords() throws {
        let nowhere = tmp.appendingPathComponent("no-such-store")
        let missing = try run(["authorize-names", "--apply"], library: nowhere)
        XCTAssertEqual(missing.status, 64, "用法錯誤早於開 store：\(missing.output)")
        XCTAssertTrue(missing.output.contains("--judgement"), missing.output)

        let dry = try run(["authorize-names"])
        XCTAssertEqual(dry.status, 0, "乾跑不需要理由：\(dry.output)")
        XCTAssertTrue(try person().references.isEmpty)

        let done = try run(["authorize-names", "--apply", "--judgement", "單一候選，逐筆看過"])
        XCTAssertEqual(done.status, 0, done.output)
        XCTAssertEqual(try person().names.authorized, ["Guan, Yongtao"])
        XCTAssertEqual(statements(try person().references), ["authorized|Guan, Yongtao|指定：單一候選，逐筆看過"])
    }

    // MARK: - store format 22

    func testFormat21StoreRefusesWithTheRequiredFormat() throws {
        try StoreVersion.write(root: root, format: 21)
        let venueOut = try run(["update-venue", "some-journal", "--authorize", "Psychometrika", "--judgement", "r"])
        XCTAssertNotEqual(venueOut.status, 0, venueOut.output)
        XCTAssertTrue(venueOut.output.contains("22"), venueOut.output)
        let orgOut = try run(["update-organization", "iss", "--authorize", "Institute of Statistical Science", "--judgement", "r"])
        XCTAssertNotEqual(orgOut.status, 0, orgOut.output)
        XCTAssertTrue(orgOut.output.contains("22"), orgOut.output)
        let namesOut = try run(["authorize-names", "--apply", "--judgement", "r"])
        XCTAssertNotEqual(namesOut.status, 0, namesOut.output)
        XCTAssertTrue(namesOut.output.contains("22"), namesOut.output)
        XCTAssertTrue(try venue().references.isEmpty && (try org().references.isEmpty) && (try person().references.isEmpty), "零寫入")
        XCTAssertEqual(try StoreVersion.read(root: root), 21, "marker 不動")
    }
}
