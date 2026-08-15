import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #74：divergence 形狀的 format 歸屬（回填 5，使用者拍板 2026-08-07）＋
/// `writeDivergence` 的 format gate。
///
/// 判準（#131 教訓）：形狀標籤是 strict——舊 binary（format ≤ 4 世代）讀到
/// `divergence:` 標籤即整檔 quarantine，所以它是 **non-additive**、必須有版本
/// 歸屬。gate 關掉「後果一的生成路徑」：新 binary 不可能在舊 format store 裡
/// 埋下讓舊 binary quarantine 的檔。拒絕而非自動 bump——升 marker 會讓其餘
/// binary 整庫拒開，必須是使用者知情的動作。
final class DivergenceFormatGateTests: XCTestCase {

    private func makeStore(format: Int) throws -> LibraryStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-divgate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: dir, format: format)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return LibraryStore(root: dir)
    }

    private var record: Divergence {
        Divergence(id: UUID(), question: "是否為同一人",
                   candidates: [DivergenceCandidate(key: "a-key", shape: .person),
                                DivergenceCandidate(key: "b-key", shape: .person)])
    }

    func testWriteRefusedBelowFormat5WithGuidance() throws {
        let store = try makeStore(format: 4)
        XCTAssertThrowsError(try store.writeDivergence(record),
                             "format 4 store 寫 divergence＝替舊 binary 埋 quarantine 地雷") { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("format") && msg.contains("5"),
                          "錯誤必須指名需要的 format：\(msg)")
            XCTAssertTrue(msg.contains("store.yaml"), "錯誤必須指路怎麼升：\(msg)")
        }
        // 拒絕發生在動磁碟之前
        let files = try FileManager.default.contentsOfDirectory(
            atPath: store.root.appendingPathComponent("entities").path)
        XCTAssertTrue(files.isEmpty, "拒寫不得留檔案：\(files)")
    }

    func testWriteAllowedAtFormat5AndAbove() throws {
        for f in [5, 6] {
            let store = try makeStore(format: f)
            XCTAssertNoThrow(try store.writeDivergence(record),
                             "format \(f) 應放行")
        }
    }
}

/// #147 verify F1 的 regression：format < 5 store 上的消歧（會遷移其他歧異記錄）
/// 必須在**動磁碟前**被 gate 擋——不是走到寫入才收容成撕裂。
extension DivergenceFormatGateTests {
    func testResolveOnOldFormatStoreRefusedUpfrontNotTorn() throws {
        // format 5 建好（含兩筆歧異、D2 引用會被併的鍵）再降 marker 到 4——
        // 模擬 #71 之後、#74 gate 之前寫過 divergence 的 format 4 store 族群
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-divgate-torn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: dir, format: 10)   // #227：seed 需過 v10 names 閘
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let store = LibraryStore(root: dir)
        for k in ["fann-a", "fann-b", "fann-c"] {
            var p = Person(key: k); p.names = [k]
            try store.writePerson(p)
        }
        let d1 = try store.recordDivergence(
            question: "a b 同一人？",
            candidates: [("fann-a", .person), ("fann-b", .person)],
            judgement: nil, restsOn: [])
        _ = try store.recordDivergence(
            question: "b c 同一人？",
            candidates: [("fann-b", .person), ("fann-c", .person)],
            judgement: nil, restsOn: [])
        GitFixture.initRepo(dir)
        GitFixture.commitAll(dir, message: "seed at format 10")
        try StoreVersion.write(root: dir, format: 4)   // 降 marker
        GitFixture.commitAll(dir, message: "downgrade marker")

        let before = try snapshotEntities(dir)
        XCTAssertThrowsError(
            try store.resolveDivergence(id: d1.id, survivor: "fann-a"),
            "otherToWrite 的預檢必須鏡射 gate——動磁碟前拒絕") { error in
            let msg = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            XCTAssertTrue(msg.contains("format"), msg)
        }
        XCTAssertEqual(try snapshotEntities(dir), before,
                       "拒絕必須是完全 no-op——倖存者不得已被改寫")
    }

    private func snapshotEntities(_ dir: URL) throws -> [String: Int] {
        var out: [String: Int] = [:]
        for f in try FileManager.default.contentsOfDirectory(
            atPath: dir.appendingPathComponent("entities").path) {
            out[f] = try Data(contentsOf: dir.appendingPathComponent("entities/\(f)")).hashValue
        }
        return out
    }
}
