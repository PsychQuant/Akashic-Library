import XCTest
@testable import AkashicCore

final class CitekeyTests: XCTestCase {
    func testBasicGeneration() {
        let key = Citekey.generate(familyName: "Cheng", year: "2025",
                                   title: "Identifiability of polychoric models", existing: [])
        XCTAssertEqual(key, "cheng2025identifiability")
    }

    func testStopwordsSkipped() {
        let key = Citekey.generate(familyName: "Cheng", year: "2024",
                                   title: "On the Existence and Uniqueness of MLE", existing: [])
        XCTAssertEqual(key, "cheng2024existence")
    }

    func testDiacriticsFolded() {
        let key = Citekey.generate(familyName: "Müller", year: "2020",
                                   title: "Ökonometrie heute", existing: [])
        XCTAssertEqual(key, "muller2020okonometrie")
    }

    func testCollisionInsertsLetterAfterYear() {
        let base = "cheng2025identifiability"
        let key = Citekey.generate(familyName: "Cheng", year: "2025",
                                   title: "Identifiability of ordinal SEM", existing: [base])
        XCTAssertEqual(key, "cheng2025bidentifiability")
        let key2 = Citekey.generate(familyName: "Cheng", year: "2025",
                                    title: "Identifiability of IFA", existing: [base, key])
        XCTAssertEqual(key2, "cheng2025cidentifiability")
    }

    func testMissingPartsFallBack() {
        let key = Citekey.generate(familyName: nil, year: nil, title: nil, existing: [])
        XCTAssertEqual(key, "anonndentry")
    }

    func testCJKTitleFallsBackToEntryWord() {
        let key = Citekey.generate(familyName: "陳", year: "2026", title: "矩陣視覺化", existing: [])
        // CJK 姓名/標題無 ASCII 實詞可取 → fallback
        XCTAssertEqual(key, "anon2026entry")
    }
}

final class EntryYAMLTests: XCTestCase {
    private func makeEntry() -> Entry {
        var entry = Entry(
            id: UUID(uuidString: "7C1F6C2E-0000-0000-0000-000000000001")!,
            citekey: "cheng2025identifiability",
            type: "article",
            title: "Identifiability of polychoric models with latent elliptical distributions",
            authors: [.key("cheng-che"), .literal("Hau-Hung Yang"), .literal("Yung-Fong Hsu")],
            date: "2025"
        )
        entry.fields = [
            "journaltitle": "Psychometrika",
            "volume": "90",
            "number": "2",
            "doi": "10.1017/psy.2025.1",
        ]
        entry.attachments = [
            AttachmentRef(kind: .zotero, path: "storage/ABCD1234/paper.pdf"),
            AttachmentRef(kind: .pool, path: "2025/cheng2025identifiability.pdf"),
        ]
        entry.provenance = Provenance(zoteroKey: "ABCD1234", zoteroVersion: 123,
                                      importedAt: Date(timeIntervalSince1970: 1_753_000_000))
        entry.akashic.tags = ["identifiability", "polychoric"]
        entry.akashic.status = "published"
        entry.akashic.relations.cites = ["olsson1979maximum"]
        entry.akashic.relations.related = ["foldnes2019bivariate"]
        return entry
    }

    func testRoundTripPreservesEverything() throws {
        let entry = makeEntry()
        let yaml = try EntryYAML.encode(entry)
        let decoded = try EntryYAML.decode(yaml)
        XCTAssertEqual(decoded, entry)
    }

    func testEncodeContainsHumanReadableKeys() throws {
        let yaml = try EntryYAML.encode(makeEntry())
        XCTAssertTrue(yaml.contains("citekey: cheng2025identifiability"))
        XCTAssertTrue(yaml.contains("journaltitle: Psychometrika"))
        XCTAssertTrue(yaml.contains("key: cheng-che"))
        XCTAssertTrue(yaml.contains("literal: Hau-Hung Yang"))
        XCTAssertTrue(yaml.contains("zotero_key: ABCD1234"))
    }

    func testCJKContentSurvivesRoundTrip() throws {
        var entry = Entry(id: UUID(), citekey: "chen2026matrix", type: "article",
                          title: "矩陣視覺化與廣義關聯圖", authors: [.literal("陳君厚")], date: "2026")
        entry.fields["journaltitle"] = "中國統計學報"
        let decoded = try EntryYAML.decode(try EntryYAML.encode(entry))
        XCTAssertEqual(decoded.title, "矩陣視覺化與廣義關聯圖")
        XCTAssertEqual(decoded.authors, [.literal("陳君厚")])
    }

    func testMinimalEntryRoundTrip() throws {
        let entry = Entry(id: UUID(), citekey: "anon2020entry", type: "misc",
                          title: "Untitled note", authors: [], date: nil)
        let decoded = try EntryYAML.decode(try EntryYAML.encode(entry))
        XCTAssertEqual(decoded, entry)
    }

    func testDecodeRejectsMissingCitekey() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        type: article
        title: Foo
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    func testDecodeRejectsAuthorWithBothForms() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: foo2020bar
        type: article
        title: Foo
        authors:
          - key: someone
            literal: Someone Else
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }
}

final class ValidationTests: XCTestCase {
    func testValidEntryHasNoErrors() {
        let entry = Entry(id: UUID(), citekey: "cheng2025identifiability", type: "article",
                          title: "T", authors: [.key("cheng-che")], date: "2025")
        XCTAssertTrue(entry.validate().filter { $0.severity == .error }.isEmpty)
    }

    func testBadCitekeyIsError() {
        let entry = Entry(id: UUID(), citekey: "Bad Key!", type: "article",
                          title: "T", authors: [], date: nil)
        XCTAssertTrue(entry.validate().contains { $0.severity == .error })
    }

    func testEmptyTitleIsWarning() {
        let entry = Entry(id: UUID(), citekey: "a2020b", type: "article",
                          title: "", authors: [], date: nil)
        let issues = entry.validate()
        XCTAssertTrue(issues.contains { $0.severity == .warning })
        XCTAssertFalse(issues.contains { $0.severity == .error })
    }
}

final class PersonYAMLTests: XCTestCase {
    func testRoundTrip() throws {
        let person = Person(key: "chen-chun-houh",
                            names: ["Chun-Houh Chen", "陳君厚", "C.-H. Chen"],
                            orcid: "0000-0002-0000-0000", openalex: "A5017898742",
                            note: "中研院統計所")
        let decoded = try PersonYAML.decode(try PersonYAML.encode(person))
        XCTAssertEqual(decoded, person)
    }

    func testDecodeRejectsMissingKey() {
        XCTAssertThrowsError(try PersonYAML.decode("names:\n  - Foo Bar\n"))
    }
}

final class StrictSchemaTests: XCTestCase {
    // store-format §5 v1.3（#23）：頂層與 akashic 的未知欄位＝容忍 + round-trip 保留
    // （tolerant-preserve）。strict 只保留在 closed shape（authors / provenance / relations）。
    func testUnknownTopLevelKeyToleratedAndPreserved() throws {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        rating: 5
        """
        let entry = try EntryYAML.decode(yaml)
        XCTAssertEqual(entry.unknownFields.map(\.key), ["rating"])
        let decoded = try EntryYAML.decode(try EntryYAML.encode(entry))
        XCTAssertEqual(decoded, entry, "round-trip 必須保留未知欄位（資料毀損防線）")
    }

    func testUnknownAkashicKeyToleratedAndPreserved() throws {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        akashic:
          tags: [x]
          reading_progress: 60
        """
        let entry = try EntryYAML.decode(yaml)
        XCTAssertEqual(entry.akashic.unknownFields.map(\.key), ["reading_progress"])
        let decoded = try EntryYAML.decode(try EntryYAML.encode(entry))
        XCTAssertEqual(decoded, entry)
    }

    func testUnknownProvenanceKeyRejected() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        provenance:
          zotero_key: K
          zotero_version: 1
          sync_source: foo
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    func testUnknownRelationsKeyRejected() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        akashic:
          relations:
            cites: [x2020y]
            blocks: [z2020w]
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    func testUnknownPersonKeyToleratedAndPreserved() throws {
        let person = try PersonYAML.decode("key: a\nnames: [A]\nemail: x@y.z\n")
        XCTAssertEqual(person.unknownFields.map(\.key), ["email"])
        let decoded = try PersonYAML.decode(try PersonYAML.encode(person))
        XCTAssertEqual(decoded, person)
    }
}

final class ForwardCompatTests: XCTestCase {
    /// #23 核心場景：#20 之後的「新版」person 檔（affiliations / facts），
    /// 本版 binary 扮演「舊 binary」——必須可讀、可用、round-trip 不丟新欄位。
    func testFuturePersonSchemaDecodesAndRoundTrips() throws {
        let yaml = """
        key: cheng-ching-shui
        names:
          - 鄭清水
        affiliations:
          - organization: 中央研究院統計科學研究所
            from: 2003-01
            to: 2006-08
          - organization: 中央研究院統計科學研究所
            from: 2013-07
            to: 2017-06
        facts:
          - kind: rank
            value: 研究員
            source: iss-retired-page@2026-07-30
        """
        let person = try PersonYAML.decode(yaml)
        XCTAssertEqual(person.key, "cheng-ching-shui")
        XCTAssertEqual(person.names, ["鄭清水"])
        XCTAssertEqual(person.unknownFields.map(\.key), ["affiliations", "facts"])
        // round-trip：未知子樹整棵保留（含巢狀 mapping 與多段 sequence）
        let reencoded = try PersonYAML.encode(person)
        let decoded = try PersonYAML.decode(reencoded)
        XCTAssertEqual(decoded, person)
        XCTAssertTrue(reencoded.contains("organization"))
        XCTAssertTrue(reencoded.contains("2013-07"))
    }

    func testLibraryUnknownKeyToleratedAndPreserved() throws {
        let lib = try LibraryYAML.decode("key: sinica\nname: 中研院\ncolor: blue\n")
        XCTAssertEqual(lib.unknownFields.map(\.key), ["color"])
        let decoded = try LibraryYAML.decode(try LibraryYAML.encode(lib))
        XCTAssertEqual(decoded, lib)
    }

    func testAkashicMetaIsEmptyIncludesUnknownFields() {
        var meta = AkashicMeta()
        XCTAssertTrue(meta.isEmpty)
        meta.unknownFields = [UnknownField(key: "reading_progress", yaml: "60\n")]
        // 否則「只有未知欄位的 akashic 段」會被 encode 整段略掉——靜默資料遺失
        XCTAssertFalse(meta.isEmpty)
    }

    func testPersonValidateWarnsOnUnknownFields() throws {
        let person = try PersonYAML.decode("key: a\nnames: [A]\nemail: x@y.z\n")
        let issues = person.validate()
        XCTAssertTrue(issues.contains { $0.severity == .warning && $0.message.contains("email") })
        XCTAssertFalse(issues.contains { $0.severity == .error })
    }

    func testEntryValidateWarnsOnUnknownFields() throws {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        rating: 5
        akashic:
          reading_progress: 60
        """
        let entry = try EntryYAML.decode(yaml)
        let issues = entry.validate()
        XCTAssertTrue(issues.contains { $0.severity == .warning && $0.message.contains("rating") })
        XCTAssertTrue(issues.contains { $0.severity == .warning && $0.message.contains("reading_progress") })
        XCTAssertFalse(issues.contains { $0.severity == .error })
    }
}

extension StrictSchemaTests {
    func testUnknownAuthorKeyRejected() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        authors:
          - literal: Ada Lovelace
            role: editor
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    func testNonStringTagElementRejected() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        akashic:
          tags:
            - ok
            - {nested: map}
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    func testTrailingNewlineCitekeyInvalid() {
        XCTAssertFalse(StoreKey.isValid("abc\n"))
        XCTAssertFalse(StoreKey.isValid("abc\r"))
    }
}

extension StrictSchemaTests {
    // R3：plain-style 非字串 scalar（int/bool/null）在清單與作者鍵位必須拒絕
    func testNonStringScalarInTagsRejected() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        akashic:
          tags: [ok, 123, true]
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    func testQuotedNumericStringTagAccepted() throws {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        akashic:
          tags: ["123"]
        """
        XCTAssertEqual(try EntryYAML.decode(yaml).akashic.tags, ["123"])
    }

    func testNonStringAuthorKeyRejected() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        authors:
          - key: 123
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    func testNonStringPersonNameRejected() {
        XCTAssertThrowsError(try PersonYAML.decode("key: a\nnames: [123]\n"))
    }
}

extension StrictSchemaTests {
    // Phase 2（#9）：provenance 新欄位 round-trip；strict set 同步擴充
    func testProvenanceLibraryIDAndHashRoundTrip() throws {
        var entry = Entry(id: UUID(), citekey: "a2020b", type: "article", title: "T")
        entry.provenance = Provenance(zoteroKey: "K", zoteroVersion: 1,
                                      libraryID: 1, zoteroHash: "abc123")
        let decoded = try EntryYAML.decode(try EntryYAML.encode(entry))
        XCTAssertEqual(decoded.provenance?.libraryID, 1)
        XCTAssertEqual(decoded.provenance?.zoteroHash, "abc123")
        XCTAssertEqual(decoded, entry)
    }

    func testProvenanceWithoutNewFieldsStillValid() throws {
        // pre-Phase-2 舊檔（缺 library_id/zotero_hash）合法，不 quarantine
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        provenance:
          zotero_key: K
          zotero_version: 1
        """
        let entry = try EntryYAML.decode(yaml)
        XCTAssertNil(entry.provenance?.libraryID)
        XCTAssertNil(entry.provenance?.zoteroHash)
    }
}

extension StrictSchemaTests {
    // Codex MEDIUM：provenance library_id malformed 值不得靜默吞成 nil
    func testMalformedLibraryIDRejected() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        provenance:
          zotero_key: K
          zotero_version: 1
          library_id: abc
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }
}

/// #13 多 library：akashic.libraries 衍生層欄位 + Library registry model 的 strict YAML。
final class LibraryModelTests: XCTestCase {
    func testAkashicLibrariesRoundTrip() throws {
        var e = Entry(id: UUID(), citekey: "cheng2025identifiability", type: "article", title: "T")
        e.akashic.libraries = ["sinica", "psychology"]
        let yaml = try EntryYAML.encode(e)
        XCTAssertTrue(yaml.contains("libraries"), "非空 libraries 要序列化")
        let decoded = try EntryYAML.decode(yaml)
        XCTAssertEqual(decoded.akashic.libraries, ["sinica", "psychology"])
        XCTAssertEqual(decoded, e)
    }

    func testEmptyLibrariesNotSerialized() throws {
        let e = Entry(id: UUID(), citekey: "cheng2025identifiability", type: "article", title: "T")
        let yaml = try EntryYAML.encode(e)
        XCTAssertFalse(yaml.contains("libraries"), "空 libraries 不序列化（與 tags 同慣例）")
    }

    func testLibraryYAMLRoundTripAndStrict() throws {
        let lib = Library(key: "sinica", name: "中研院", description: "統計所 lab context")
        let yaml = try LibraryYAML.encode(lib)
        XCTAssertEqual(try LibraryYAML.decode(yaml), lib)
        // 未知欄位 → 容忍 + 保留（§5 v1.3 tolerant-preserve，#23）
        let tolerated = try LibraryYAML.decode(yaml + "extra: nope\n")
        XCTAssertEqual(tolerated.unknownFields.map(\.key), ["extra"])
        // 缺 key → 仍拒絕（必要欄位不屬 tolerant 範圍）
        XCTAssertThrowsError(try LibraryYAML.decode("name: 沒有 key\n"))
    }
}

/// #13 verify fix round：present-but-wrong-type 必須擲錯（strict 哲學）。
extension LibraryModelTests {
    func testScalarLibrariesFieldRejected() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-00000000CCCC
        citekey: scalar2020x
        type: article
        title: T
        akashic:
          libraries: sinica
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml),
                             "libraries 存在但非 sequence → 必須擲錯，不得靜默當空")
    }

    func testLibraryDescriptionWrongTypeRejected() {
        let yaml = """
        key: sinica
        name: 中研院
        description:
          nested: nope
        """
        XCTAssertThrowsError(try LibraryYAML.decode(yaml))
    }
}
