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
        try store.writeLibrary(Library(key: "reading", name: "待讀", membership: .topic))
        try store.writeLibrary(Library(key: "cited", name: "已引用", membership: .topic))
        try store.writeEntry(Entry(id: UUID(), citekey: "a2020a", type: .periodicalArticle,
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

    /// #642：App 是第三個寫入面——同一份規則判定（`LibraryMembershipCheck`），不符就不寫並說原因。
    func testUnmarkedLibraryRefusesAdd() throws {
        try LibraryStore(root: root).writeLibrary(Library(key: "old", name: "舊"))
        try state.load()
        XCTAssertThrowsError(try state.addToLibrary(citekey: "a2020a", libraryKey: "old")) {
            guard case AppStateError.libraryUnmarked(let k) = $0 else { return XCTFail("應為 libraryUnmarked，實得 \($0)") }
            XCTAssertEqual(k, "old")
            XCTAssertTrue(($0 as? LocalizedError)?.errorDescription?.contains("set-kind") ?? false)
        }
        XCTAssertEqual(libs("a2020a"), [])
    }

    func testRuleLibraryRefusesANonconformingEntryAndSaysWhy() throws {
        try LibraryStore(root: root).writeLibrary(Library(key: "pm-catalog", name: "PM",
            membership: .rule(LibraryRule(venue: "psychological-methods"))))
        try state.load()
        XCTAssertThrowsError(try state.addToLibrary(citekey: "a2020a", libraryKey: "pm-catalog")) {
            guard case AppStateError.libraryRuleViolation(_, _, let reason) = $0 else {
                return XCTFail("應為 libraryRuleViolation，實得 \($0)")
            }
            XCTAssertTrue(reason.contains("venue"), reason)
        }
        XCTAssertEqual(libs("a2020a"), [], "不符規則的不寫")
    }

    // MARK: - R1 verify

    /// `FileWatcher` 不監看 registry 時，記憶體快照會落後：CLI／MCP 把 library 從 topic 改成 rule 之後，App 仍當它 topic。
    /// `addToLibrary` 用磁碟上剛讀到的 registry 判定（比照 `mutate()` 重讀 entries）。
    func testAddDecidesOnTheRegistryOnDiskNotOnTheStaleSnapshot() throws {
        XCTAssertEqual(state.libraries.first { $0.key == "reading" }?.membership, .topic, "前提：快照裡它是 topic")
        // 外部（CLI／MCP）改成規則型——App 的快照沒刷新
        try LibraryStore(root: root).updateLibrary(Library(key: "reading", name: "待讀",
            membership: .rule(LibraryRule(venue: "psychological-methods"))))
        XCTAssertEqual(state.libraries.first { $0.key == "reading" }?.membership, .topic, "快照仍是舊的")
        XCTAssertThrowsError(try state.addToLibrary(citekey: "a2020a", libraryKey: "reading")) {
            guard case AppStateError.libraryRuleViolation = $0 else { return XCTFail("應為 libraryRuleViolation，實得 \($0)") }
        }
        XCTAssertEqual(try LibraryStore(root: root).load().entries[0].akashic.libraries, [], "不符規則的不寫")
    }

    /// 反方向：外部把它改回 topic，快照仍是 rule——不該憑舊規則擋下使用者。
    func testAddAllowsWhatTheDiskRegistryNowAllows() throws {
        try LibraryStore(root: root).updateLibrary(Library(key: "cited", name: "已引用",
            membership: .rule(LibraryRule(venue: "psychological-methods"))))
        try state.load()
        try LibraryStore(root: root).updateLibrary(Library(key: "cited", name: "已引用", membership: .topic))
        XCTAssertNoThrow(try state.addToLibrary(citekey: "a2020a", libraryKey: "cited"))
    }

    /// 三個面同一份判定：規則指向的 venue key 變成重複，App 也不寫。
    func testARuleWhoseVenueKeyBecomesDuplicatedRefusesAddInTheApp() throws {
        let store = LibraryStore(root: root)
        for _ in 0..<2 {
            try store.writeVenue(Venue(key: "psychological-methods", type: .periodical,
                                       names: Timeline([TemporalValue(value: "Psychological Methods")])))
        }
        var e = try XCTUnwrap(try store.load().entries.first)
        e.venues = [.key("psychological-methods")]
        try store.writeEntry(e)
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM",
                                       membership: .rule(LibraryRule(venue: "psychological-methods"))))
        try state.load()
        XCTAssertThrowsError(try state.addToLibrary(citekey: "a2020a", libraryKey: "pm-catalog")) {
            guard case AppStateError.libraryRuleViolation(_, _, let reason) = $0 else {
                return XCTFail("應為 libraryRuleViolation，實得 \($0)")
            }
            XCTAssertTrue(reason.contains("不只一筆"), reason)
        }
        XCTAssertEqual(try store.load().entries[0].akashic.libraries, [])
    }

    /// App 沒有標性質的面：訊息要指向 CLI，不是只說「用 set-kind 標」就結束。
    func testTheUnmarkedRefusalPointsAtTheTerminalBecauseTheAppCannotMarkAKind() throws {
        try LibraryStore(root: root).writeLibrary(Library(key: "old", name: "舊"))
        try state.load()
        XCTAssertThrowsError(try state.addToLibrary(citekey: "a2020a", libraryKey: "old")) {
            let m = ($0 as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(m.contains("App 沒有標性質的面") && m.contains("終端機"), m)
            XCTAssertTrue(m.contains("不要改標 topic"), m)
        }
    }

    /// 選單項目的 tooltip 帶描述與性質；未標性質的說明為什麼被停用。
    func testTheMenuHelpCarriesTheDescriptionAndTheKind() {
        let rule = Library(key: "pm", name: "PM", description: "Psychological Methods 全量目錄",
                           membership: .rule(LibraryRule(venue: "v")))
        XCTAssertEqual(EntryDetailView.libraryMenuHelp(rule), "Psychological Methods 全量目錄・規則型")
        let unmarked = EntryDetailView.libraryMenuHelp(Library(key: "old", name: "舊"))
        XCTAssertTrue(unmarked.hasPrefix("（沒有描述）・未標性質"), unmarked)
        XCTAssertTrue(unmarked.contains("set-kind") && unmarked.contains("終端機"), unmarked)
    }
}
