import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #232 task 4.3：CLI 面的 verdict 動作與三態計數渲染。
///
/// 用真 binary：verdict 要「落 YAML」這件事只有走完整條 CLI → service → store
/// 路徑才驗得到（`ResolveAmbiguityCLITests` 檔頭的教訓——kit 層全綠擋不住
/// 輸出面整段被關掉）。沙箱紀律同 harness：`AKASHIC_*` 一律剝除。
final class ResolveVerdictCLITests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-verdict-cli-\(UUID().uuidString)")
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func runCLI(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: [:])
    }

    /// 從磁碟重載（新 store 是 entities layout，檔名是 UUID——驗內容不驗路徑）。
    private func reload() throws -> LibraryLoad {
        try LibraryStore(root: root, key: nil, environment: [:]).load()
    }

    private func seedPersonCandidate() throws {
        try store.writePerson(Person(key: "cheng-che", names: ["Che Cheng"]))
        try store.writeEntry(Entry(id: UUID(), citekey: "a2020x", type: .periodicalArticle,
                                   title: "T", authors: [.literal("Che Cheng")], date: "2020"))
        try store.writeEntry(Entry(id: UUID(), citekey: "b2021y", type: .periodicalArticle,
                                   title: "U", authors: [.literal("Che Cheng")], date: "2021"))
    }

    // MARK: - resolve-people --reject

    func testRejectLandsInPersonYAMLAndSinksInListing() throws {
        try seedPersonCandidate()
        let r = try runCLI(["resolve-people", "--reject", "a2020x:0"])
        XCTAssertEqual(r.status, 0, r.output)
        let load = try reload()
        let p = load.people.first { $0.key == "cheng-che" }!
        XCTAssertTrue(p.references.contains {
            $0.field == "resolution-rejected" && $0.value == "work:a2020x :: Che Cheng"
        }, "verdict 要落 YAML：\(p.references)")
        // entry 不動
        let e = load.entries.first { $0.citekey == "a2020x" }!
        XCTAssertEqual(e.authors, [.literal("Che Cheng")], "reject 不得改寫 entry")
        // 重列：已否決沉底不隱藏、active 只剩 b2021y
        let list = try runCLI(["resolve-people"])
        XCTAssertEqual(list.status, 0, list.output)
        XCTAssertTrue(list.output.contains("已否決"), "沉底列要有標記：\n\(list.output)")
        let activeLine = list.output.split(separator: "\n").first { $0.contains("a2020x") }
        XCTAssertNotNil(activeLine, "已否決配對仍要看得到（沉底非隱藏）：\n\(list.output)")
    }

    func testListingShowsThreeStateCounts() throws {
        try seedPersonCandidate()
        _ = try runCLI(["resolve-people", "--reject", "a2020x:0"])
        let list = try runCLI(["resolve-people"])
        XCTAssertEqual(list.status, 0, list.output)
        for token in ["已確認 0", "已否決 1", "未處理 1"] {
            XCTAssertTrue(list.output.contains(token),
                          "三態計數要渲染出「\(token)」：\n\(list.output)")
        }
    }

    func testApplyWritesConfirmedReferenceViaCLI() throws {
        try seedPersonCandidate()
        let r = try runCLI(["resolve-people", "--apply", "--citekey", "a2020x"])
        XCTAssertEqual(r.status, 0, r.output)
        let load = try reload()
        let p = load.people.first { $0.key == "cheng-che" }!
        XCTAssertTrue(p.references.contains {
            $0.field == "resolution-confirmed" && $0.value == "work:a2020x :: Che Cheng"
        }, "CLI apply 也要寫 confirmed（parity）：\(p.references)")
        let e = load.entries.first { $0.citekey == "a2020x" }!
        XCTAssertEqual(e.authors, [.key("cheng-che")], "apply 的既有行為不變")
    }

    // MARK: - #624：篩選式批次不帶走淘汰而得的唯一候選

    /// a2020x 是同名兩人（cheng-che／cheng-che-2）的歧義列；否決 cheng-che 之後
    /// 只剩 cheng-che-2——沒有人判定過它是對的。b2021y 是一般候選（只有一人）。
    private func seedEliminatedSurvivor() throws {
        try store.writePerson(Person(key: "cheng-che", names: ["Che Cheng"]))
        try store.writePerson(Person(key: "cheng-che-2", names: ["Che Cheng"]))
        try store.writePerson(Person(key: "olsson-ulf", names: ["Ulf Olsson"]))
        try store.writeEntry(Entry(id: UUID(), citekey: "a2020x", type: .periodicalArticle,
                                   title: "T", authors: [.literal("Che Cheng")], date: "2020"))
        try store.writeEntry(Entry(id: UUID(), citekey: "b2021y", type: .periodicalArticle,
                                   title: "U", authors: [.literal("Ulf Olsson")], date: "2021"))
        let r = try runCLI(["resolve-people", "--refute", "a2020x:0:cheng-che=機構不符"])
        XCTAssertEqual(r.status, 0, r.output)
    }

    func testFilteredApplySkipsEliminatedSurvivorAndSaysSo() throws {
        try seedEliminatedSurvivor()
        let r = try runCLI(["resolve-people", "--apply", "--tier", "exact"])
        XCTAssertEqual(r.status, 0, r.output)
        let load = try reload()
        let a = load.entries.first { $0.citekey == "a2020x" }!
        XCTAssertEqual(a.authors, [.literal("Che Cheng")],
                       "淘汰而得的唯一候選不得被篩選式批次升格：\n\(r.output)")
        let b = load.entries.first { $0.citekey == "b2021y" }!
        XCTAssertEqual(b.authors, [.key("olsson-ulf")], "一般候選照常寫入")
        XCTAssertTrue(r.output.contains("淘汰而得") && r.output.contains("a2020x"),
                      "被排除的要逐筆列出：\n\(r.output)")
        XCTAssertTrue(r.output.contains("--judge"), "要指路逐筆判定：\n\(r.output)")
    }

    func testFilteredApplyWithOnlyEliminatedSurvivorWritesNothing() throws {
        try seedEliminatedSurvivor()
        let r = try runCLI(["resolve-people", "--apply", "--citekey", "a2020x"])
        XCTAssertNotEqual(r.status, 0, "套用集全被排除時要非零結束：\n\(r.output)")
        let a = try reload().entries.first { $0.citekey == "a2020x" }!
        XCTAssertEqual(a.authors, [.literal("Che Cheng")], "零寫入")
        XCTAssertTrue(r.output.contains("淘汰而得"), r.output)
        let survivor = try reload().people.first { $0.key == "cheng-che-2" }!
        XCTAssertFalse(survivor.references.contains { $0.field == "resolution-confirmed" },
                       "零寫入也包括 verdict：\(survivor.references)")
    }

    func testListingTagsEliminatedSurvivorWithoutApply() throws {
        try seedEliminatedSurvivor()
        let r = try runCLI(["resolve-people"])
        XCTAssertEqual(r.status, 0, r.output)
        let line = r.output.split(separator: "\n").first { $0.contains("a2020x") && $0.contains("cheng-che-2") }
        XCTAssertTrue(line?.contains("淘汰而得") == true, "列表模式就要標出來：\n\(r.output)")
    }

    /// fall-through：exact 唯一命中被否決 → initials 冒出另一個人（淘汰所得）。
    /// tier 閘看排除後的套用集，所以裸 --apply 不該為了一筆終究不套用的 initials 擋下整批。
    func testTierGateIgnoresEliminatedLooseSurvivor() throws {
        try store.writePerson(Person(key: "cheng-che", names: ["Che Cheng"]))
        try store.writePerson(Person(key: "cheng-chun-erh", names: ["Cheng, C."]))
        try store.writePerson(Person(key: "olsson-ulf", names: ["Ulf Olsson"]))
        try store.writeEntry(Entry(id: UUID(), citekey: "a2020x", type: .periodicalArticle,
                                   title: "T", authors: [.literal("Che Cheng")], date: "2020"))
        try store.writeEntry(Entry(id: UUID(), citekey: "b2021y", type: .periodicalArticle,
                                   title: "U", authors: [.literal("Ulf Olsson")], date: "2021"))
        XCTAssertEqual(try runCLI(["resolve-people", "--refute", "a2020x:0:cheng-che=機構不符"]).status, 0)
        let r = try runCLI(["resolve-people", "--apply"])
        XCTAssertEqual(r.status, 0, "寬鬆層只有淘汰所得時，tier 閘不該擋：\n\(r.output)")
        let load = try reload()
        XCTAssertEqual(load.entries.first { $0.citekey == "b2021y" }!.authors, [.key("olsson-ulf")])
        XCTAssertEqual(load.entries.first { $0.citekey == "a2020x" }!.authors, [.literal("Che Cheng")])
    }

    func testRejectAndApplyMutuallyExclusive() throws {
        try seedPersonCandidate()
        let r = try runCLI(["resolve-people", "--apply", "--reject", "a2020x:0"])
        XCTAssertNotEqual(r.status, 0, "同一次呼叫不可同時 apply 與 reject：\n\(r.output)")
    }

    // MARK: - resolve-organizations（同資訊形）

    private func seedOrgCandidate() throws {
        var p = Person(key: "che-cheng", names: ["Che Cheng"])
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: .literal("統計科學研究所"), range: DateRange(start: "2022")),
        ])
        try store.writePerson(p)
        var org = Organization(key: "stat-sinica")
        org.names = TimelineOf([TemporalValue(value: "統計科學研究所",
                                              range: DateRange(start: "1987"))])
        try store.writeOrganization(org)
    }

    func testOrgRejectLandsInOrganizationYAML() throws {
        try seedOrgCandidate()
        let r = try runCLI(["resolve-organizations", "--reject", "--holder", "che-cheng"])
        XCTAssertEqual(r.status, 0, r.output)
        let load = try reload()
        let org = load.organizations.first { $0.key == "stat-sinica" }!
        XCTAssertTrue(org.references.contains {
            $0.field == "resolution-rejected" && $0.value == "person:che-cheng :: 統計科學研究所"
        }, "org verdict 要落 YAML：\(org.references)")
        // person 的 affiliation 不動（reject 不是套用）
        let p = load.people.first { $0.key == "che-cheng" }!
        if case .literal(let l)? = p.profile.affiliations.entries.first?.value {
            XCTAssertEqual(l, "統計科學研究所")
        } else {
            XCTFail("affiliation 不得被改寫成 .key：\(p.profile.affiliations)")
        }
        // 重列：三態計數 + 沉底標記
        let list = try runCLI(["resolve-organizations"])
        XCTAssertEqual(list.status, 0, list.output)
        XCTAssertTrue(list.output.contains("已否決 1"), list.output)
        XCTAssertTrue(list.output.contains("已否決"), "沉底列要有標記：\n\(list.output)")
    }

    /// 全庫盲掃否決是把一次判斷放大成批次動作——reject 必須帶收窄條件。
    func testOrgRejectRequiresNarrowing() throws {
        try seedOrgCandidate()
        let r = try runCLI(["resolve-organizations", "--reject"])
        XCTAssertNotEqual(r.status, 0, r.output)
    }
}
