import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #54／#65：view 的**判準**住 `config.yaml`、**外延**是衍生物。
///
/// #54 拍板「view 不是 entity」，`docs/explainers/entity-vs-view.md` 定了分層。
/// **但 `config.yaml` 那一半從來沒有實作**——判準因此被推到 store 之外，由每個
/// 下游消費者各自重新發明（storyline#5 的 `4AK_build_duckdb.R` 就是實例）。
final class ViewDefinitionTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-view-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func person(_ key: String, affiliation: OrgRef?) throws {
        var p = Person(key: key, names: [key])
        if let a = affiliation {
            p.profile.affiliations = TimelineOf([TemporalValue(value: a, range: DateRange())])
        }
        try store.writePerson(p)
    }
    private func work(_ citekey: String, authors: [Author]) throws {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: "T")
        e.authors = authors; e.date = "2020"
        try store.writeEntry(e)
    }

    // MARK: - 外延

    func testPersonExtensionMatchesAffiliationKey() throws {
        try person("in-iss", affiliation: .key("iss"))
        try person("elsewhere", affiliation: .key("other"))
        try person("none", affiliation: nil)
        let def = ViewDefinition(key: "v", personAffiliation: "iss")
        XCTAssertEqual(def.extension_(in: try store.load()).people, ["in-iss"])
    }

    /// **只收 `.key` 不收 `.literal`。**
    ///
    /// 未歸戶的 literal 是合法的長期狀態，但拿它當判準會讓成員資格隨拼寫漂移。
    /// 要納入某個 literal，先 `resolve-organizations`——那才是那個動作存在的理由。
    func testLiteralAffiliationIsNotAMatch() throws {
        try person("literal-only", affiliation: .literal("iss"))
        let def = ViewDefinition(key: "v", personAffiliation: "iss")
        XCTAssertEqual(def.extension_(in: try store.load()).people, [],
                       "未歸戶的 literal 不是指涉——拿它當判準會隨拼寫漂移")
    }

    /// work 側**以 view 自身為參照**，不是再寫一次條件——兩處各寫一次就是
    /// 「判準會分岔」在同一個檔案裡重演。
    func testWorkExtensionFollowsThePersonExtension() throws {
        try person("in-iss", affiliation: .key("iss"))
        try person("outsider", affiliation: .key("other"))
        try work("a2020", authors: [.key("in-iss")])
        try work("b2020", authors: [.key("outsider")])
        try work("c2020", authors: [.key("outsider"), .key("in-iss")])
        try work("d2020", authors: [.literal("In Iss")])
        let def = ViewDefinition(key: "v", personAffiliation: "iss", workHasAuthorInView: true)
        let ext = def.extension_(in: try store.load())
        XCTAssertEqual(ext.works, ["a2020", "c2020"], "共同作者也算；未歸戶的 literal 不算")
    }

    /// 沒開 work 判準就不算 work——**外延只回答被問到的那一半**。
    func testWorkExtensionIsOptOut() throws {
        try person("in-iss", affiliation: .key("iss"))
        try work("a2020", authors: [.key("in-iss")])
        let def = ViewDefinition(key: "v", personAffiliation: "iss")
        XCTAssertEqual(def.extension_(in: try store.load()).works, [])
    }

    /// **不比對時間範圍**——「現在還在不在」是另一個問題（`endedUnknown` 的語意
    /// 未定，#63）。view 回答的是「屬於過」。這個取捨寫在 doc 裡，不留給呼叫端猜。
    func testMembershipIgnoresTimeRange() throws {
        var p = Person(key: "past", names: ["past"])
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: OrgRef.key("iss"), range: DateRange(start: "2003", end: "2008"))])
        try store.writePerson(p)
        let def = ViewDefinition(key: "v", personAffiliation: "iss")
        XCTAssertEqual(def.extension_(in: try store.load()).people, ["past"],
                       "已結束的隸屬仍算——view 回答「屬於過」")
    }

    // MARK: - 判準的持久化（config.yaml round-trip）

    func testConfigRoundTripsViews() throws {
        let url = root.appendingPathComponent("config.yaml")
        var c = AkashicConfig()
        c.files = ["main": "~/.akashic"]
        c.current = "main"
        c.views = ["iss": ViewDefinition(key: "iss", description: "中研院統計所",
                                         personAffiliation: "institute-of-statistical-science",
                                         workHasAuthorInView: true),
                   "bare": ViewDefinition(key: "bare")]
        try c.write(to: url)
        let back = try AkashicConfig.read(from: url)
        XCTAssertEqual(back.views, c.views, "判準要 round-trip——它是 canonical 設定")
        XCTAssertEqual(back.files, c.files, "既有欄位不得被 views 區塊吃掉")
        XCTAssertEqual(back.current, "main")
    }

    /// view key 走 `StoreKey`——它會出現在 CLI 旗標與下游檔名裡。
    func testInvalidViewKeyIsRejected() throws {
        let url = root.appendingPathComponent("config.yaml")
        try "views:\n  Bad Key:\n    description: x\n".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AkashicConfig.read(from: url))
    }

    /// `person-affiliation` 收的是 organization **key**，不是自由字串。
    func testInvalidViewFieldIsRejected() throws {
        let url = root.appendingPathComponent("config.yaml")
        try "views:\n  v:\n    person-affiliation: Not A Key\n"
            .write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AkashicConfig.read(from: url))
        try "views:\n  v:\n    work-has-author-in-view: yes\n"
            .write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AkashicConfig.read(from: url),
                             "YAML 1.1 的 yes/on/1 一律拒絕——與 store 端的形狀紀律一致")
    }

    /// **view 不是 entity**（#54 的裁決不因為有實作了而鬆動）。
    func testViewIsNotAnEntityKind() {
        XCTAssertNil(EntityKind(rawValue: "view"),
                     "本 change 不動 EntityKind、不新增形狀裸標籤、entities/ 不出現 view:")
    }
}
