import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #564 b33 X1（第 1／4／7／9／10／21 列）：合併搬名字分類記錄的四件事——
///
/// - 尾端矛盾以**原始倖存者**為基準、全部接完之後才算，結果不受被併者的處理順序影響；
/// - 兩筆攣生的分類歷史相同時，合併不把整段歷史再接一遍（倖存者已有、尾端一致的不重搬）；
/// - 接記錄是線性的（每個名字的最後一筆一次建好索引）；
/// - 拒絕訊息依實體、分割與矛盾的方向給出口（variant 分割那一格不是 `--authorize` 再 `--unauthorize`）。
final class NameClassificationMergeOrderTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-ncmo-\(UUID().uuidString)")
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
    private func statements(_ refs: [ProvenanceReference], name: String) -> [String] {
        refs.filter { NameClassificationRecord.isRecord($0) && $0.value == name }.compactMap { r in
            guard case .judgement(let statement, _) = r.kind else { return nil }
            return r.field + " " + statement
        }
    }
    @discardableResult
    private func seedPeople(keeper: Person, doomed: [Person]) throws -> Divergence {
        _ = try store.writePerson(keeper)
        for p in doomed { _ = try store.writePerson(p) }
        let d = Divergence(id: UUID(), question: "同一個人嗎",
                           candidates: ([keeper] + doomed).map { DivergenceCandidate(key: $0.key, shape: .person) })
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        return d
    }
    @discardableResult
    private func seedVenues(keeper: Venue, doomed: [Venue]) throws -> Divergence {
        try store.writeVenue(keeper)
        for v in doomed { try store.writeVenue(v) }
        let d = Divergence(id: UUID(), question: "同一本刊嗎",
                           candidates: ([keeper] + doomed).map { DivergenceCandidate(key: $0.key, shape: .venue) })
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")
        return d
    }
    private func message(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? "\(e)" }

    // MARK: - 相同歷史不重複（第 4／10 列）

    /// 兩筆攣生各跑過同一個兩步批次（指定 R → 確認 S）：合併不搬任何一筆，倖存者仍是兩筆、validate 沒有重複的 reference。
    func testIdenticalTwinHistoriesAreNotCarriedAgain() throws {
        let history = [record("authorized", "Alpha Beta", .designate, "R"), record("authorized", "Alpha Beta", .confirm, "S")]
        let d = try seedPeople(keeper: person("k2", authorized: ["Alpha Beta"], refs: history),
                               doomed: [person("d2", authorized: ["Alpha Beta"], refs: history)])
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "k2", overrideReason: nil)
        XCTAssertEqual(preview.referencesCarried, [], "倖存者已有、尾端一致：不搬")
        let report = try store.resolveDivergence(id: d.id, survivor: "k2")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let kept = try XCTUnwrap(store.load().people.first { $0.key == "k2" })
        XCTAssertEqual(statements(kept.references, name: "Alpha Beta"), ["authorized 指定：R", "authorized 確認：S"])
        let health = try store.health(from: store.load())
        XCTAssertEqual(health.duplicateReferences.count, 0, "\(health.duplicateReferences.map(\.issue.message))")
    }

    /// 倖存者「指定 R → 確認 R2」、被併者「指定 R」：較早的「指定 R」不被重新接成最後一筆。
    func testAnOlderRecordTheSurvivorAlreadyHoldsIsNotReappended() {
        let r = record("authorized", "Alpha Beta", .designate, "R")
        let keeper = person("k", authorized: ["Alpha Beta"], refs: [r, record("authorized", "Alpha Beta", .confirm, "R2")])
        let merged = LibraryStore.mergedPersonKeeper(keeper, absorbing: [person("d", authorized: ["Alpha Beta"], refs: [r])])
        XCTAssertEqual(merged.referencesCarried, [])
        XCTAssertEqual(statements(merged.keeper.references, name: "Alpha Beta"), ["authorized 指定：R", "authorized 確認：R2"])
    }

    /// venue 同形，兩個分割各自一段歷史：相同的不重搬。
    func testIdenticalVenueTwinHistoriesAreNotCarriedAgain() {
        let history = [record("authorized", "Journal W", .designate, "R"), record("authorized", "Journal W", .confirm, "R2"),
                       record("variant", "J. W.", .designate, "縮寫")]
        let keeper = venue("w1", names: ["Journal W", "J. W."], authorized: ["Journal W"], variant: ["J. W."], refs: history)
        let doomed = venue("w2", names: ["Journal W", "J. W."], authorized: ["Journal W"], variant: ["J. W."], refs: history)
        let merged = LibraryStore.mergedVenueKeeper(keeper, absorbing: [doomed])
        XCTAssertEqual(merged.referencesCarried, [])
        XCTAssertEqual(merged.keeper.references.map(\.byteExactKey), history.map(\.byteExactKey))
        XCTAssertEqual(merged.classificationTailConflicts, [])
    }

    // MARK: - 尾端矛盾以原始倖存者為基準、順序無關（第 1／21 列）

    /// 倖存者原本就以撤回結尾（名字仍是對外形）；一筆被併者以指定結尾、另一筆以撤回結尾。合併後的狀態與原始倖存者一樣有那個矛盾——
    /// 不是這次帶進來的，兩種順序都放行，結果逐位元組相同。
    func testAPreExistingContradictionIsNotBlamedOnTheMergeInEitherOrder() {
        let keeper = person("k", authorized: ["Xu, Yi"], refs: [record("authorized", "Xu, Yi", .designate, "R"),
                                                              record("authorized", "Xu, Yi", .withdraw, "S")])
        let a = person("a-doom", authorized: ["Xu, Yi"], refs: [record("authorized", "Xu, Yi", .designate, "T")])
        let b = person("b-doom", authorized: ["Xu, Yi"], refs: [record("authorized", "Xu, Yi", .withdraw, "U")])
        let ab = LibraryStore.mergedPersonKeeper(keeper, absorbing: [a, b])
        let ba = LibraryStore.mergedPersonKeeper(keeper, absorbing: [b, a])
        XCTAssertEqual(ab.classificationTailConflicts, [], "原始倖存者就有的矛盾不擋")
        XCTAssertEqual(ba.classificationTailConflicts, [])
        XCTAssertEqual(ab.keeper.references.map(\.byteExactKey), ba.keeper.references.map(\.byteExactKey), "處理順序不改變結果")
        XCTAssertEqual(ab.referencesCarried, ba.referencesCarried)
    }

    /// 一筆被併者自己不一致（以撤回結尾而仍是對外形），另一筆接在它後面以指定結尾：合併後的最後一筆一致——先前逐被併者累加，先處理到
    /// 不一致那一筆時就被擋，結論隨順序翻轉。現在兩種輸入順序同一個結論、同一份結果。
    func testTheDecisionDoesNotDependOnTheOrderTheDoomedAreGiven() throws {
        let keeper = person("k", authorized: ["Xu, Yi"], refs: [record("authorized", "Xu, Yi", .designate, "R")])
        let first = person("a-doom", authorized: ["Xu, Yi"], refs: [record("authorized", "Xu, Yi", .withdraw, "手改")])
        let second = person("b-doom", authorized: ["Xu, Yi"], refs: [record("authorized", "Xu, Yi", .designate, "T")])
        let forward = LibraryStore.mergedPersonKeeper(keeper, absorbing: [first, second])
        let backward = LibraryStore.mergedPersonKeeper(keeper, absorbing: [second, first])
        XCTAssertEqual(forward.classificationTailConflicts, backward.classificationTailConflicts)
        XCTAssertEqual(forward.keeper.references.map(\.byteExactKey), backward.keeper.references.map(\.byteExactKey))
        XCTAssertEqual(forward.classificationTailConflicts, [], "依 key 排序後 b-doom 的指定最後接上，尾端一致")
        XCTAssertEqual(NameClassificationRecord.latestAction(in: forward.keeper.references, name: "Xu, Yi"), .designate)

        // 走 store（候選順序與 key 順序相反）：乾跑與實跑都放行，說同一份 referencesCarried
        let d = try seedPeople(keeper: keeper, doomed: [second, first])
        let preview = try store.previewResolveDivergence(id: d.id, survivor: "k", overrideReason: nil)
        XCTAssertEqual(preview.referencesCarried, forward.referencesCarried)
        let report = try store.resolveDivergence(id: d.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        XCTAssertEqual(report.referencesCarried, preview.referencesCarried)
    }

    /// 三筆被併者、六種輸入順序：結論與結果都相同（被併者依 key 排序再接）。
    func testThreeDoomedInAnyOrderGiveTheSameKeeper() {
        let keeper = venue("k", names: ["Journal Q"], authorized: ["Journal Q"], refs: [record("authorized", "Journal Q", .designate, "R")])
        let ds = [
            venue("d1", names: ["Journal Q"], authorized: ["Journal Q"], refs: [record("authorized", "Journal Q", .withdraw, "手改")]),
            venue("d2", names: ["Journal Q"], authorized: ["Journal Q"], refs: [record("authorized", "Journal Q", .confirm, "C")]),
            venue("d3", names: ["Journal Q", "J Q"], authorized: ["Journal Q"], variant: ["J Q"],
                  refs: [record("variant", "J Q", .designate, "縮寫")]),
        ]
        let orders = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
        let results = orders.map { o in LibraryStore.mergedVenueKeeper(keeper, absorbing: o.map { ds[$0] }) }
        for r in results.dropFirst() {
            XCTAssertEqual(r.keeper.references.map(\.byteExactKey), results[0].keeper.references.map(\.byteExactKey))
            XCTAssertEqual(r.classificationTailConflicts, results[0].classificationTailConflicts)
            XCTAssertEqual(r.referencesCarried, results[0].referencesCarried)
        }
        XCTAssertEqual(results[0].classificationTailConflicts, [], "d2 的確認最後接上，authorized 的尾端一致")
    }

    // MARK: - 出口依分割與方向（第 6／7 列）

    /// variant 分割「不在 variant 卻以指定結尾」：出口要先 --add-variant，不是只有 --authorize 再 --unauthorize（那只寫 authorized 的記錄）。
    func testVariantFieldConflictGetsAVariantExit() throws {
        let keeper = venue("kv", names: ["Some Journal", "Some Jrnl"], authorized: ["Some Journal"])
        let doomed = venue("dv", names: ["Some Journal", "Some Jrnl"], authorized: ["Some Journal"],
                           refs: [record("variant", "Some Jrnl", .designate, "手改")])
        let d = try seedVenues(keeper: keeper, doomed: [doomed])
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "kv", overrideReason: nil)) { e in
            guard case DivergenceResolveError.wouldContradictClassificationTail(_, _, let exits) = e else { return XCTFail("\(e)") }
            XCTAssertEqual(exits.count, 1, "\(exits)")
            XCTAssertTrue(exits[0].contains("不在 variant") && exits[0].contains("--add-variant") && exits[0].contains("--authorize")
                          && exits[0].contains("--unauthorize") && exits[0].contains("補回"), exits[0])
            let m = message(e)
            XCTAssertTrue(m.contains("dv") && m.contains("Some Jrnl"), m)
        }
    }

    /// person「不在 authorized 卻以指定結尾」：出口說出同書寫系統已有對外形時要交換、與它的代價。
    func testPersonNotInAuthorizedConflictNamesTheSwapAndItsCost() throws {
        let keeper = person("pk", authorized: ["Beta, Alpha"], variant: ["Alpha B."])
        let doomed = person("pd", authorized: ["Beta, Alpha"], variant: ["Alpha B."],
                            refs: [record("authorized", "Alpha B.", .designate, "手改")])
        let d = try seedPeople(keeper: keeper, doomed: [doomed])
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "pk", overrideReason: nil)) { e in
            guard case DivergenceResolveError.wouldContradictClassificationTail(_, _, let exits) = e else { return XCTFail("\(e)") }
            XCTAssertEqual(exits.count, 1, "\(exits)")
            XCTAssertTrue(exits[0].contains("交換") && exits[0].contains("多一對撤回／指定"), exits[0])
        }
    }

    /// 長名字不會把出口擠掉：出口是另外的固定句子，不接在被截到 400 字的說明後面。
    func testALongNameDoesNotTruncateTheExit() throws {
        let long = String(repeating: "Longname", count: 40)
        let keeper = person("lk", authorized: [long])
        let doomed = person("ld", authorized: [long], refs: [record("authorized", long, .designate, "R"),
                                                              record("authorized", long, .withdraw, "S")])
        let d = try seedPeople(keeper: keeper, doomed: [doomed])
        XCTAssertThrowsError(try store.previewResolveDivergence(id: d.id, survivor: "lk", overrideReason: nil)) { e in
            let m = message(e)
            XCTAssertTrue(m.contains("移到 variant、再移回 authorized"), m)
        }
    }

    /// b33 X1 第 24 列：person 合併的「分類不同」與「只差空白」兩條 loss，名字很長時出口句不得被 300 字的整行截斷吃掉——
    /// 出口放在名字之前、名字各截 60。
    func testALongNameDoesNotPushTheMergeLossExitOut() {
        let long = String(repeating: "Longname", count: 25)   // 200 字元
        let disagree = LibraryStore.fieldsLostByMerging(
            person("ln-doom", authorized: [long], refs: [record("authorized", long, .designate, "R")]),
            into: person("ln-keep", authorized: ["Other, O"], variant: [long]))
        XCTAssertTrue(disagree.contains { $0.contains("分類不同") && $0.contains("update-person --fields") && $0.contains("--remove-name") }, "\(disagree)")
        let twin = long + " X"
        let unanchored = LibraryStore.fieldsLostByMerging(
            person("lt-doom", authorized: [], variant: [twin.replacingOccurrences(of: " X", with: "  X")],
                   refs: [record("authorized", twin.replacingOccurrences(of: " X", with: "  X"), .withdraw, "S")]),
            into: person("lt-keep", authorized: [twin]))
        XCTAssertTrue(unanchored.contains { $0.contains("只差空白") && $0.contains("--remove-name") && $0.contains("再合併") }, "\(unanchored)")
    }

    // MARK: - 線性（第 9 列）

    /// 兩筆各有 3,000 個互異名字、每個名字一筆記錄：接記錄是線性的。先前每一筆都倒著掃整份 references，O(N×R)。
    func testCarryingThousandsOfDistinctNamesIsLinear() {
        let n = 3_000
        let names = (0..<n).map { "Name \($0)" }
        let keeperRefs = names.map { record("authorized", $0, .withdraw, "k") }
        let doomedRefs = names.map { record("authorized", $0, .withdraw, "d") }
        var refs = keeperRefs
        let start = Date()
        let written = NameClassificationRecord.carryCollecting(doomedRefs, to: &refs, isMember: { _, _ in false })
        var appended = keeperRefs
        _ = NameClassificationRecord.appendCollecting(doomedRefs, to: &appended)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(written.count, n)
        XCTAssertEqual(refs.count, 2 * n)
        XCTAssertEqual(appended.count, 2 * n)
        XCTAssertLessThan(elapsed, 3, "6,000 筆的接續要是線性的（實得 \(elapsed) 秒）")
    }
}
