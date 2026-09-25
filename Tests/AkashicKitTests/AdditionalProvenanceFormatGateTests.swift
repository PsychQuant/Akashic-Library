import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #605：附加 Zotero 來源需要 store format 18。format-17 binary 會 tolerant-preserve
/// `provenance_additional:` 但**不拿它比對**——從附加來源的 library 再匯入時會安靜地
/// 重造攣生。所以 marker 必須先擋。
final class AdditionalProvenanceFormatGateTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-605-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func twoSourceEntry() -> Entry {
        var e = Entry(id: UUID(), citekey: "cheng2021likert", type: .periodicalArticle, title: "T")
        e.provenance = Provenance(zoteroKey: "WDDP9QMR", zoteroVersion: 1, libraryID: 1)
        e.additionalProvenance = [Provenance(zoteroKey: "QFAFGFW5", zoteroVersion: 1, libraryID: 2)]
        return e
    }

    func testSupportedIs18() {
        XCTAssertGreaterThanOrEqual(StoreVersion.supported, 18)
    }

    func testFormat17RefusesAdditionalProvenance() throws {
        try StoreVersion.write(root: root, format: 17)
        XCTAssertThrowsError(try store.writeEntry(twoSourceEntry())) { error in
            XCTAssertTrue("\(error)".contains("18"), "訊息要說出需要的 format：\(error)")
        }
    }

    func testFormat17StillWritesEntryWithoutAdditionalProvenance() throws {
        try StoreVersion.write(root: root, format: 17)
        var e = twoSourceEntry(); e.additionalProvenance = []
        XCTAssertNoThrow(try store.writeEntry(e))
    }

    func testFormat18WritesAdditionalProvenance() throws {
        try StoreVersion.write(root: root, format: 18)
        XCTAssertNoThrow(try store.writeEntry(twoSourceEntry()))
        let loaded = try store.load().entries.first { $0.citekey == "cheng2021likert" }
        XCTAssertEqual(loaded?.additionalProvenance.first?.zoteroKey, "QFAFGFW5")
    }
}
