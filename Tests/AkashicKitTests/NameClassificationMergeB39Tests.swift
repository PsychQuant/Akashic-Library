import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #564 b38 Z1 第 0／1／3／6／7 列（使用者 2026-10-15 裁決：「被併者自己不一致就拒絕」收窄）。
///
/// b37 對被併者自己的記錄尾端一律拒絕——連被併者什麼都不搬的合併、只重複倖存者原本就有的矛盾的攣生也擋，訊息還說矛盾是被併者「帶來」的、
/// 說「合併後它在…的最後一筆是…」（對被併者自己的矛盾是假話）。現在只在兩個條件都成立時拒絕：
/// 1. 那筆被併者**單獨**併進原始倖存者時，真的會把那個（分割, 名字）的記錄接上至少一筆；
/// 2. 原始倖存者在同一個（分割, 名字）上沒有矛盾。
/// 條件 1 綁原始倖存者的歷史、不綁實際合併時誰先接上——否則結論重新取決於被併者的 key 順序。
final class NameClassificationMergeB39Tests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-ncm39-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        GitFixture.initRepo(root)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func record(_ field: String, _ name: String, _ action: NameClassificationRecord.Action, _ reason: String) -> ProvenanceReference {
        NameClassificationRecord.make(field: field, name: name, action: action, reason: reason, restsOn: [])
    }
    private func person(_ key: String, authorized: [String], variant: [String] = [], refs: [ProvenanceReference] = []) -> Person {
        var p = Person(key: key, names: PersonNames(authorized: authorized, variant: variant))
        p.references = refs
        return p
    }
    private func venue(_ key: String, names: [String], authorized: [String] = [], variant: [String] = [],
                       refs: [ProvenanceReference] = []) -> Venue {
        var v = Venue(key: key, type: .periodical, names: Timeline(names.map { TemporalValue(value: $0) }), authorized: authorized)
        v.variant = variant
        v.references = refs
        return v
    }
    private func message(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? "\(e)" }
    @discardableResult
    private func seed(_ people: [Person]) throws -> Divergence {
        for p in people { _ = try store.writePerson(p) }
        let d = Divergence(id: UUID(), question: "同一個人嗎", candidates: people.map { DivergenceCandidate(key: $0.key, shape: .person) })
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        return d
    }

    // MARK: - 條件 2：原始倖存者已有同一個矛盾（攣生）

    /// 第 0 列的重現一：兩筆 person 逐位元組持有同一個矛盾（「Lin, Mei」在 variant、authorized 欄的最後一筆是「指定」）。合併什麼都不搬、
    /// 倖存者原本就有那個矛盾——乾跑與實跑都放行，倖存者的記錄不變。b37 拒絕並說矛盾是 pd「帶來的」。
    func testIdenticalTwinsHoldingTheSameContradictionMerge() throws {
        let history = [record("authorized", "Lin, Mei", .designate, "同一句理由")]
        let keeper = person("pk", authorized: ["Mei Lin"], variant: ["Lin, Mei"], refs: history)
        let d = try seed([keeper, person("pd", authorized: ["Mei Lin"], variant: ["Lin, Mei"], refs: history)])
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "pk", overrideReason: nil)
        XCTAssertEqual(preview.referencesCarried, [], "什麼都不搬")
        let report = try store.resolveDivergence(id: d.id, survivor: "pk")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let kept = try XCTUnwrap(store.load().people.first { $0.key == "pk" })
        XCTAssertEqual(kept.references.map(\.byteExactKey), history.map(\.byteExactKey), "倖存者的記錄不變")
    }

    /// 第 7 列：venue 攣生逐位元組持有「指定 r → 撤回 手改」而名字仍是對外形。被併者會搬（「指定 r」接上、合併後尾端回到一致），
    /// 但它重複的是倖存者原本就有的矛盾——條件 2 豁免，放行。
    func testAVenueTwinRepeatingTheSurvivorsContradictionIsNotRefused() {
        let history = [record("authorized", "Real J", .designate, "r"), record("authorized", "Real J", .withdraw, "手改")]
        let keeper = venue("jv-k", names: ["Real J"], authorized: ["Real J"], refs: history)
        let merged = LibraryStore.mergedVenueKeeper(keeper, absorbing: [venue("jv-d1", names: ["Real J"], authorized: ["Real J"], refs: history)])
        XCTAssertEqual(merged.classificationTailConflicts, [], "倖存者合併前就有的矛盾不擋")
    }

    /// 「同一個矛盾」要同一個方向：倖存者手改出一筆錨不到 names 的 variant 記錄（「X J」不在它的 names、最後一筆「指定」——不在 variant 卻以指定結尾），
    /// 被併者把「X J」以 variant 帶進來、自己的最後一筆是「撤回」（仍在 variant 卻以撤回結尾）。合併後「X J」在 variant、最後一筆是撤回——
    /// 那不是倖存者原本那個矛盾。先前兩道檢查都只比（分割, 名字），這一格放行。
    func testASurvivorContradictionInTheOtherDirectionDoesNotExempt() {
        let keeper = venue("kx", names: ["Main J"], authorized: ["Main J"], refs: [record("variant", "X J", .designate, "手改")])
        XCTAssertEqual(LibraryStore.venueTailConflicts(keeper).map(\.last), [.designate], "前提：倖存者原本的矛盾是「不在 variant 卻以指定結尾」")
        let doomed = venue("dx", names: ["Main J", "X J"], authorized: ["Main J"], variant: ["X J"],
                           refs: [record("variant", "X J", .withdraw, "手改")])
        let merged = LibraryStore.mergedVenueKeeper(keeper, absorbing: [doomed])
        XCTAssertEqual(NameClassificationRecord.latestAction(in: merged.keeper.references, name: "X J"), .withdraw)
        XCTAssertFalse(merged.classificationTailConflicts.isEmpty, "方向不同的矛盾不是倖存者原本那一個，不豁免")
        XCTAssertTrue(merged.classificationTailConflicts.allSatisfy { $0.broughtBy == "dx" && $0.last == .withdraw },
                      "\(merged.classificationTailConflicts)")
    }

    // MARK: - 條件 1：被併者什麼都不搬

    /// 第 1 列的重現二：倖存者一致（「指定 r → 撤回 w」、名字在 variant），被併者只有「指定 r」——倖存者歷史的前綴，自己的最後一筆與分類矛盾。
    /// 單獨併進倖存者時一筆都不接（倖存者已有、而且尾端一致），合併前後倖存者逐位元組相同——放行。b37 拒絕，訊息說「合併後它在 authorized 的
    /// 最後一筆是「指定」」，而合併後的最後一筆是撤回。
    func testADoomedThatCarriesNothingIsNotRefused() throws {
        let history = [record("authorized", "Lin, Mei", .designate, "r"), record("authorized", "Lin, Mei", .withdraw, "w")]
        let keeper = person("pk", authorized: ["Mei Lin"], variant: ["Lin, Mei"], refs: history)
        let doomed = person("pd", authorized: ["Mei Lin"], variant: ["Lin, Mei"], refs: [history[0]])
        XCTAssertFalse(NameClassificationRecord.tailConflicts(in: doomed.references) { _, _ in false }.isEmpty, "前提：被併者自己不一致")
        let d = try seed([keeper, doomed])
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "pk", overrideReason: nil)
        XCTAssertEqual(preview.referencesCarried, [])
        let report = try store.resolveDivergence(id: d.id, survivor: "pk")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let kept = try XCTUnwrap(store.load().people.first { $0.key == "pk" })
        XCTAssertEqual(kept.references.map(\.byteExactKey), history.map(\.byteExactKey))
        XCTAssertTrue(LibraryStore.personTailConflicts(kept).isEmpty)
    }

    /// 條件 1 綁原始倖存者、不綁實際合併時誰先接上（第 1 列的提醒）：倖存者沒有記錄，一筆被併者只有「指定 x」（名字在 variant——自己不一致），
    /// 另一筆「指定 x → 撤回 w」。以實際合併來判時，一致的那一筆先接上會讓不一致那一筆的「指定 x」被「倖存者已有」略過——換個 key 拼法就從拒絕
    /// 變成放行。兩種拼法都拒絕、說出不一致的那一筆。
    func testWhetherADoomedCarriesIsJudgedAgainstTheOriginalSurvivorNotTheMergeOrder() {
        let keeper = person("pk", authorized: ["Mei Lin"], variant: ["Lin, Mei"])
        let bad = [record("authorized", "Lin, Mei", .designate, "x")]
        let good = [record("authorized", "Lin, Mei", .designate, "x"), record("authorized", "Lin, Mei", .withdraw, "w")]
        for (badKey, goodKey) in [("a-one", "z-two"), ("z-two", "a-one")] {
            let merged = LibraryStore.mergedPersonKeeper(keeper, absorbing: [
                person(badKey, authorized: ["Mei Lin"], variant: ["Lin, Mei"], refs: bad),
                person(goodKey, authorized: ["Mei Lin"], variant: ["Lin, Mei"], refs: good),
            ])
            XCTAssertEqual(merged.classificationTailConflicts.map(\.broughtBy), [badKey], "不一致的叫 \(badKey) 時也要拒絕並具名")
            XCTAssertEqual(merged.classificationTailConflicts.map(\.doomedOwn), [true])
        }
    }

    // MARK: - 措辭（第 3／6 列）

    /// 倖存者「指定 R」；jv-d1「指定 R → 撤回 手改」（自己不一致）；jv-d9「指定 R」——jv-d9 的指定接在撤回之後，合併後的最後一筆一致。
    /// 仍拒絕（jv-d1 會搬「撤回 手改」、倖存者原本沒有這個矛盾），但說的是被併者自己的最後一筆，不說「合併後它在 authorized 的最後一筆是「撤回」」。
    func testADoomedOwnConflictIsWordedAsTheDoomedsOwnTail() throws {
        let keeper = venue("jv-k", names: ["Real J"], authorized: ["Real J"], refs: [record("authorized", "Real J", .designate, "R")])
        let d1 = venue("jv-d1", names: ["Real J"], authorized: ["Real J"],
                       refs: [record("authorized", "Real J", .designate, "R"), record("authorized", "Real J", .withdraw, "手改")])
        let d9 = venue("jv-d9", names: ["Real J"], authorized: ["Real J"], refs: [record("authorized", "Real J", .designate, "R")])
        let merged = LibraryStore.mergedVenueKeeper(keeper, absorbing: [d1, d9])
        XCTAssertEqual(NameClassificationRecord.latestAction(in: merged.keeper.references, name: "Real J"), .designate, "前提：合併後的最後一筆一致")
        XCTAssertEqual(merged.classificationTailConflicts.map(\.broughtBy), ["jv-d1"])
        let lines = LibraryStore.describeTailConflicts(merged.classificationTailConflicts, kind: "venue")
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("被併的 venue「jv-d1」自己的記錄裡") && lines[0].contains("最後一筆是「撤回」"), lines[0])
        XCTAssertFalse(lines[0].contains("合併後它在"), "被併者自己的矛盾不得說成合併後的事實：\(lines[0])")

        try store.writeVenue(keeper)
        try store.writeVenue(d1)
        try store.writeVenue(d9)
        let d = Divergence(id: UUID(), question: "同一本刊嗎", candidates: ["jv-k", "jv-d1", "jv-d9"].map { DivergenceCandidate(key: $0, shape: .venue) })
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "jv-k", overrideReason: nil)) { e in
            guard case DivergenceResolveError.wouldContradictClassificationTail = e else { return XCTFail("\(e)") }
            let m = message(e)
            XCTAssertTrue(m.contains("被併的 venue「jv-d1」自己的記錄裡") && m.contains("倖存者合併前就有同一個矛盾的不擋"), m)
            XCTAssertFalse(m.contains("合併後它在"), m)
        }
    }
}
