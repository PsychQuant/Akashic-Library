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
    // store-format §5：未知欄位＝decode 錯誤（防 re-encode 靜默資料流失）
    func testUnknownTopLevelKeyRejected() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        rating: 5
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    func testUnknownAkashicKeyRejected() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        akashic:
          tags: [x]
          reading_progress: 60
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
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

    func testUnknownPersonKeyRejected() {
        XCTAssertThrowsError(try PersonYAML.decode("key: a\nnames: [A]\nemail: x@y.z\n"))
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
