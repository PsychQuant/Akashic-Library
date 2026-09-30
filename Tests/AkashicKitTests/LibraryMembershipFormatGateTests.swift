import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// store format 21 的寫入閘（#642 整合）。`membership` 是 registry 頂層的新鍵，format-20 binary 走 tolerant-preserve
/// **原樣保留而不解讀**——它的 `library add` 不查規則，對規則型與文件型 library 照樣寫進不符的成員。那是「保留不等於
/// 遵守」（StoreVersion 5、18 的同一個論證），所以要 marker 讓 refuse-if-newer 出聲；marker 還沒升的 store 不得寫進
/// 會被舊 binary 違反的性質。**主題型不閘**：它不帶任何規則，舊 binary 的行為與新語意相同。
final class LibraryMembershipFormatGateTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-lmfg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private let rule = LibraryMembership.rule(LibraryRule(venue: "psychological-methods"))
    private let document = LibraryMembership.document(citekey: "cheng2026critique")

    /// #564 起 supported 是 22（名字分類的判定記錄）；成員性質的門檻仍是 21——兩個數各自是一個 vocabulary 的門檻。
    func testSupportedIsTwentyTwoAndTheMembershipGateStaysAtTwentyOne() {
        XCTAssertEqual(StoreVersion.supported, 22)
        XCTAssertEqual(StoreVersion.libraryMembershipFormat, 21)
    }

    func testFormatTwentyRefusesRuleAndDocumentButNotTopic() throws {
        try StoreVersion.write(root: root, format: 20)
        for m in [rule, document] {
            XCTAssertThrowsError(try store.writeLibrary(Library(key: "x-\(m.kind)", name: "X", membership: m))) { error in
                XCTAssertTrue("\(error)".contains("store format ≥ 21"), "\(error)")
            }
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: root.appendingPathComponent("libraries/x-\(m.kind).yaml").path), "零寫入")
        }
        try store.writeLibrary(Library(key: "topic-lib", name: "T", membership: .topic))
        try store.writeLibrary(Library(key: "unmarked", name: "U"))
        // 改寫路徑同一道閘：未標性質 → 規則型要被擋、原檔不動
        let before = try Data(contentsOf: root.appendingPathComponent("libraries/unmarked.yaml"))
        XCTAssertThrowsError(try store.updateLibrary(Library(key: "unmarked", name: "U", membership: rule)))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("libraries/unmarked.yaml")), before)
        XCTAssertNoThrow(try store.updateLibrary(Library(key: "unmarked", name: "U", membership: .topic)))
    }

    func testFormatTwentyOneAcceptsAllThree() throws {
        try StoreVersion.write(root: root, format: 21)
        try store.writeLibrary(Library(key: "r", name: "R", membership: rule))
        try store.writeLibrary(Library(key: "d", name: "D", membership: document))
        try store.writeLibrary(Library(key: "t", name: "T", membership: .topic))
        XCTAssertEqual(try store.load().libraries.count, 3)
    }

    /// #642 R1 verify：撞閘的訊息要說出**為什麼不能改標 topic 來解鎖**——升到 21 之前唯一標得上的性質是 topic，
    /// 而 topic 不檢查成員，一行就回到 #642 起因的狀態。未標性質的拒絕訊息（add／validate）同樣要說。
    func testTheGateMessageAndTheUnmarkedMessageBothWarnAgainstMarkingTopicToUnblock() throws {
        try StoreVersion.write(root: root, format: 20)
        XCTAssertThrowsError(try store.writeLibrary(Library(key: "x", name: "X", membership: rule))) { error in
            let m = "\(error)"
            XCTAssertTrue(m.contains("不要改標 topic 來解鎖") && m.contains("topic 不檢查成員"), m)
            XCTAssertTrue(m.contains("規則型保護不存在"), "說出 marker 升到 21 之前的處境：\(m)")
        }
        let unmarked = Library.unmarkedMessage
        XCTAssertTrue(unmarked.contains("store format ≥ 21") && unmarked.contains("不要改標 topic") && unmarked.contains("topic 不檢查成員"), unmarked)
        XCTAssertTrue(Library(key: "u", name: "U").validate().contains { $0.message == unmarked }, "validate 的 warning 用同一句")
    }
}
