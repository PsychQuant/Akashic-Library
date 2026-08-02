import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicAppKit

/// #15：App 的 library membership 編輯面。
final class AppLibraryMembershipTests: XCTestCase {
    var root: URL!
    var state: AppState!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-alm-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writeLibrary(Library(key: "reading", name: "待讀"))
        try store.writeLibrary(Library(key: "cited", name: "已引用"))
        try store.writeEntry(Entry(id: UUID(), citekey: "a2020a", type: "article",
                                   title: "T", authors: [.literal("X")], date: "2020"))
        state = AppState(root: root)
        try state.load()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func libs(_ ck: String) -> [String] {
        state.entries.first { $0.citekey == ck }?.akashic.libraries ?? []
    }

    func testAddAndRemoveMembership() throws {
        try state.addToLibrary(citekey: "a2020a", libraryKey: "reading")
        XCTAssertEqual(libs("a2020a"), ["reading"])
        try state.removeFromLibrary(citekey: "a2020a", libraryKey: "reading")
        XCTAssertEqual(libs("a2020a"), [])
    }

    func testAddIsIdempotent() throws {
        try state.addToLibrary(citekey: "a2020a", libraryKey: "reading")
        try state.addToLibrary(citekey: "a2020a", libraryKey: "reading")
        XCTAssertEqual(libs("a2020a"), ["reading"], "重複加入產生重複成員關係")
    }

    /// 順序穩定——避免同一組成員關係因為加入順序不同而產生 diff 噪音。
    func testMembershipIsSorted() throws {
        try state.addToLibrary(citekey: "a2020a", libraryKey: "reading")
        try state.addToLibrary(citekey: "a2020a", libraryKey: "cited")
        XCTAssertEqual(libs("a2020a"), ["cited", "reading"])
    }

    /// **library key 是參照不是自由字串**——加進不存在的 library 必須 fail-loud，
    /// 否則會產生懸空成員關係（`#7b` 的跨記錄驗證會報 warning，但更好的做法是
    /// 一開始就不讓它發生）。
    func testAddingUnknownLibraryFailsLoudly() {
        XCTAssertThrowsError(try state.addToLibrary(citekey: "a2020a", libraryKey: "ghost")) {
            guard case AppStateError.unknownLibrary(let k) = $0 else {
                return XCTFail("應為 unknownLibrary，實得 \($0)")
            }
            XCTAssertEqual(k, "ghost")
        }
        XCTAssertEqual(libs("a2020a"), [], "失敗後不得留下部分狀態")
    }

    /// 移出**不檢查** registry 存在性——要能清掉懸空的成員關係，
    /// 而那正是 registry 已經沒有該 library 的情況。
    func testRemovingDanglingMembershipIsAllowed() throws {
        // 繞過 API 直接製造懸空狀態（模擬 library 被刪掉之後）
        let store = LibraryStore(root: root)
        var e = try store.load().entries[0]
        e.akashic.libraries = ["deleted-library"]
        try store.writeEntry(e)
        try state.load()
        XCTAssertEqual(libs("a2020a"), ["deleted-library"])
        try state.removeFromLibrary(citekey: "a2020a", libraryKey: "deleted-library")
        XCTAssertEqual(libs("a2020a"), [], "清不掉懸空成員關係＝使用者無法自救")
    }

    /// 選單只列**還沒加入**的 library——已加入的再列出來只會讓人誤點。
    func testAvailableLibrariesExcludesJoined() throws {
        XCTAssertEqual(state.availableLibraries(for: "a2020a").map(\.key), ["cited", "reading"])
        try state.addToLibrary(citekey: "a2020a", libraryKey: "reading")
        XCTAssertEqual(state.availableLibraries(for: "a2020a").map(\.key), ["cited"])
        try state.addToLibrary(citekey: "a2020a", libraryKey: "cited")
        XCTAssertTrue(state.availableLibraries(for: "a2020a").isEmpty)
    }

    /// 編輯後必須落磁碟——App 是 write-through（沒有草稿緩衝）。
    func testMembershipIsPersisted() throws {
        try state.addToLibrary(citekey: "a2020a", libraryKey: "reading")
        let fresh = try LibraryStore(root: root).load()
        XCTAssertEqual(fresh.entries[0].akashic.libraries, ["reading"])
    }
}
