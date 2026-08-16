import XCTest
import Foundation
@testable import AkashicCore

/// venue 作為第五種記錄形狀（#304 裁決：期刊＋會議＋出版社一次到位）。
///
/// 沿革（裁決五b）直接重用 `TimelineOf<String>`——org 的 names 已是時間軸，
/// venue 跟隨同一模式，刊名改名史免費獲得。
final class VenueTests: XCTestCase {

    // MARK: - 型別與 validate（task 1.1）

    func testVenueTypeIsClosedEnumeration() {
        XCTAssertEqual(VenueType.allCases.map(\.rawValue).sorted(),
                       ["conference", "journal", "publisher"])
    }

    func testNewVenueGetsRandomV4ID() {
        // #241 doctrine：id 是單一來源事件的 v4，不由名字推導。
        // 同 key 兩次建構必須得到不同 id——決定性推導正是被廢除的行為。
        let a = Venue(key: "jcgs", type: .journal)
        let b = Venue(key: "jcgs", type: .journal)
        XCTAssertNotEqual(a.id, b.id)
    }

    func testValidateRejectsBadKey() {
        let v = Venue(key: "Bad Key!", type: .journal)
        XCTAssertTrue(v.validate().contains { $0.severity == .error })
    }

    func testNameTimelineSegments() throws {
        // 改名史：舊刊名帶 end、現刊名帶 start——兩者並存，現行名可推導。
        var v = Venue(key: "jcgs", type: .journal)
        v.names = Timeline([
            TemporalValue(value: "Old Journal Title", range: DateRange(end: "2003")),
            TemporalValue(value: "Journal of Computational and Graphical Statistics",
                          range: DateRange(start: "2003")),
        ])
        XCTAssertEqual(v.names.current?.value,
                       "Journal of Computational and Graphical Statistics")
        XCTAssertEqual(v.names.entries.count, 2)
    }

    func testDisplayNamePrefersAuthorized() {
        var v = Venue(key: "jcgs", type: .journal)
        v.names = Timeline([TemporalValue(value: "JCGS")])
        v.authorized = ["Journal of Computational and Graphical Statistics"]
        XCTAssertEqual(v.displayName,
                       "Journal of Computational and Graphical Statistics")
    }

    // MARK: - YAML round-trip（task 1.2）

    func testVenueRoundTripsCanonically() throws {
        var v = Venue(key: "journal-of-computational-and-graphical-statistics",
                      type: .journal)
        v.names = Timeline([
            TemporalValue(value: "Journal of Computational and Graphical Statistics"),
            TemporalValue(value: "JCGS"),
        ])
        v.authorized = ["Journal of Computational and Graphical Statistics"]
        v.note = "測試"
        let text = try VenueYAML.encode(v)
        XCTAssertTrue(text.hasPrefix("venue:"), "形狀裸標籤必須最前")
        let back = try VenueYAML.decode(text)
        XCTAssertEqual(back, v)
        // canonical：encode(decode(x)) == x
        XCTAssertEqual(try VenueYAML.encode(back), text)
    }

    func testUnknownTypeRejected() throws {
        let yaml = """
        venue:
        id: \(UUID().uuidString)
        key: some-series
        type: series
        """
        XCTAssertThrowsError(try VenueYAML.decode(yaml)) { err in
            XCTAssertTrue(String(describing: err).contains("journal"),
                          "錯誤訊息必須點名封閉列舉，實得：\(err)")
        }
    }

    func testMissingTypeRejected() throws {
        let yaml = """
        venue:
        id: \(UUID().uuidString)
        key: no-type
        """
        XCTAssertThrowsError(try VenueYAML.decode(yaml))
    }

    func testEntityKindPeeksVenue() throws {
        let yaml = """
        venue:
        id: \(UUID().uuidString)
        key: jcgs
        type: journal
        """
        XCTAssertEqual(try EntityKind.peek(yaml), .venue)
    }

    func testUnknownFieldsTolerantPreserved() throws {
        var v = Venue(key: "jcgs", type: .journal)
        v.names = Timeline([TemporalValue(value: "JCGS")])
        var text = try VenueYAML.encode(v)
        text += "future_field: hello\n"
        let back = try VenueYAML.decode(text)
        XCTAssertEqual(back.unknownFields.map(\.key), ["future_field"])
        // 寫回時原樣保留
        XCTAssertTrue(try VenueYAML.encode(back).contains("future_field: hello"))
    }

    // MARK: - Entry.venues 二態 ref（task 1.3）

    func testEntryVenuesRoundTrip() throws {
        var e = Entry(id: UUID(), citekey: "cheng2025universal", type: "article", title: "T")
        e.venues = [.literal("JOURNAL OF STATISTICS"), .key("jcgs")]
        let text = try EntryYAML.encode(e)
        let back = try EntryYAML.decode(text)
        XCTAssertEqual(back.venues, e.venues)
        // 順序帶語意——不得重排
        XCTAssertEqual(back.venues.first, .literal("JOURNAL OF STATISTICS"))
    }

    func testEntryVenuesRejectsUnknownElementKey() throws {
        var e = Entry(id: UUID(), citekey: "x2025", type: "article", title: "T")
        e.venues = [.key("jcgs")]
        var text = try EntryYAML.encode(e)
        text = text.replacingOccurrences(of: "- key: jcgs", with: "- name: jcgs")
        XCTAssertThrowsError(try EntryYAML.decode(text))
    }

    func testEntryWithoutVenuesUnchanged() throws {
        // 既有 entry（無 venues 鍵）round-trip 零 diff——additive 契約。
        let e = Entry(id: UUID(), citekey: "old2020", type: "article", title: "Old")
        let text = try EntryYAML.encode(e)
        XCTAssertFalse(text.contains("venues"))
        XCTAssertEqual(try EntryYAML.decode(text).venues, [])
    }
}
