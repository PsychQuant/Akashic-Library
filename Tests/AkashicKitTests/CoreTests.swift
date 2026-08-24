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
            type: .periodicalArticle,
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
            AttachmentRef(kind: .zotero, path: "storage/ABCD1234/supplement.pdf"),
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
        var entry = Entry(id: UUID(), citekey: "chen2026matrix", type: .periodicalArticle,
                          title: "矩陣視覺化與廣義關聯圖", authors: [.literal("陳君厚")], date: "2026")
        entry.fields["journaltitle"] = "中國統計學報"
        let decoded = try EntryYAML.decode(try EntryYAML.encode(entry))
        XCTAssertEqual(decoded.title, "矩陣視覺化與廣義關聯圖")
        XCTAssertEqual(decoded.authors, [.literal("陳君厚")])
    }

    func testMinimalEntryRoundTrip() throws {
        let entry = Entry(id: UUID(), citekey: "anon2020entry", type: .webpage,
                          title: "Untitled note", authors: [], date: nil)
        let decoded = try EntryYAML.decode(try EntryYAML.encode(entry))
        XCTAssertEqual(decoded, entry)
    }

    func testDecodeRejectsMissingCitekey() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        type: periodical-article
        title: Foo
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    func testDecodeRejectsAuthorWithBothForms() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: foo2020bar
        type: periodical-article
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
        let entry = Entry(id: UUID(), citekey: "cheng2025identifiability", type: .periodicalArticle,
                          title: "T", authors: [.key("cheng-che")], date: "2025")
        XCTAssertTrue(entry.validate().filter { $0.severity == .error }.isEmpty)
    }

    func testBadCitekeyIsError() {
        let entry = Entry(id: UUID(), citekey: "Bad Key!", type: .periodicalArticle,
                          title: "T", authors: [], date: nil)
        XCTAssertTrue(entry.validate().contains { $0.severity == .error })
    }

    func testEmptyTitleIsWarning() {
        let entry = Entry(id: UUID(), citekey: "a2020b", type: .periodicalArticle,
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
                            orcid: ORCID("0000-0002-1825-0097"), openalex: "A5017898742",
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
        type: periodical-article
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
        type: periodical-article
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

    // 附件鍵域是封閉集合，收窄為只剩 zotero 一種（#223）。未知種類走整檔拒絕，
    // 不是 tolerant-preserve——鍵域 strict 正是 format 提升的依據。
    func testPoolAttachmentKindIsRejected() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: periodical-article
        title: T
        attachments:
          - pool: 2025/a2020b.pdf
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml)) { error in
            guard case StoreYAMLError.invalidField(let field, let message) = error else {
                return XCTFail("預期 invalidField，實得 \(error)")
            }
            XCTAssertEqual(field, "attachments")
            XCTAssertFalse(
                message.contains("pool"),
                "錯誤訊息不得把 pool 呈現為合法值，否則讀者會以為只是打錯字：\(message)"
            )
        }
    }

    func testZoteroAttachmentKindStillAccepted() throws {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: periodical-article
        title: T
        attachments:
          - zotero: storage/ABCD1234/paper.pdf
        """
        let entry = try EntryYAML.decode(yaml)
        XCTAssertEqual(entry.attachments,
                       [AttachmentRef(kind: .zotero, path: "storage/ABCD1234/paper.pdf")])
    }

    func testUnknownProvenanceKeyRejected() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: periodical-article
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
        type: periodical-article
        title: T
        akashic:
          relations:
            cites: [x2020y]
            blocks: [z2020w]
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    func testUnknownPersonKeyToleratedAndPreserved() throws {
        let person = try PersonYAML.decode("id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [A]}\nemail: x@y.z\n")
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
        id: 11111111-1111-4111-8111-111111111111
        key: cheng-ching-shui
        names:
          variant:
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
        meta.unknownFields = [UnknownField(key: "reading_progress", raw: "  reading_progress: 60\n")]
        // 否則「只有未知欄位的 akashic 段」會被 encode 整段略掉——靜默資料遺失
        XCTAssertFalse(meta.isEmpty)
    }

    // α nested 縮排平移：原檔 akashic 子層縮排 4 → 寫回等量平移到 emitter 的 2，
    // 語意不變、re-decode 相等（key 集合與內容）
    func testNestedUnknownReindentedUniformly() throws {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: periodical-article
        title: T
        akashic:
            tags: [x]
            reading_progress: 60
        """
        let entry = try EntryYAML.decode(yaml + "\n")
        XCTAssertEqual(entry.akashic.unknownFields.map(\.key), ["reading_progress"])
        let reencoded = try EntryYAML.encode(entry)
        let decoded = try EntryYAML.decode(reencoded)
        XCTAssertEqual(decoded.akashic.unknownFields.map(\.key), ["reading_progress"])
        XCTAssertEqual(decoded.akashic.tags, ["x"])
        XCTAssertTrue(reencoded.contains("  reading_progress: 60"), "子層平移到縮排 2")
    }

    // verify R1 F1（#23）：implicit-null 未知欄位（`foo:` 空值）必須可 round-trip——
    // 先前 decode 成功但 encode throw，讓該筆記錄「讀得到但永遠寫不回」
    func testImplicitNullUnknownFieldRoundTrips() throws {
        let person = try PersonYAML.decode("id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [A]}\naffiliations:\n")
        XCTAssertEqual(person.unknownFields.map(\.key), ["affiliations"])
        let reencoded = try PersonYAML.encode(person)          // 先前在此 throw
        let decoded = try PersonYAML.decode(reencoded)
        XCTAssertEqual(decoded.unknownFields.map(\.key), ["affiliations"])
        // entry 頂層與 akashic nested 同型
        let eYaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: periodical-article
        title: T
        rating:
        akashic:
          reading_progress:
        """
        let entry = try EntryYAML.decode(eYaml)
        let entry2 = try EntryYAML.decode(try EntryYAML.encode(entry))   // 先前在此 throw
        XCTAssertEqual(entry2.unknownFields.map(\.key), ["rating"])
        XCTAssertEqual(entry2.akashic.unknownFields.map(\.key), ["reading_progress"])
    }

    // α + oracle：**中等** alias 子樹原樣保留、不展開（raw-text 下無 serialize，
    // 放大在結構上不存在）；**病態深炸彈**超出 oracle 驗證預算 → quarantine
    // （fail-closed，檔案原封不動——資料完整性優先於病態檔案的可用性）
    func testAliasSubtreePreservedVerbatimWithoutExpansion() throws {
        var yaml = "id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [A]}\nbomb:\n  a0: &a0 [x, x, x, x, x, x, x, x, x]\n"
        for i in 1...3 {
            yaml += "  a\(i): &a\(i) [*a\(i-1), *a\(i-1), *a\(i-1), *a\(i-1), *a\(i-1), *a\(i-1), *a\(i-1), *a\(i-1), *a\(i-1)]\n"
        }
        let person = try PersonYAML.decode(yaml)
        XCTAssertEqual(person.unknownFields.map(\.key), ["bomb"])
        let reencoded = try PersonYAML.encode(person)
        XCTAssertTrue(reencoded.contains("&a0"), "anchor 必須逐字保留")
        XCTAssertTrue(reencoded.contains("*a2"), "alias 必須逐字保留、不展開")
        XCTAssertLessThan(reencoded.utf8.count, yaml.utf8.count + 200,
                          "輸出大小必須與輸入同量級——不得展開放大")
        XCTAssertEqual(try PersonYAML.decode(reencoded), person)
    }

    func testDeepAliasBombExceedsOracleBudgetAndQuarantines() {
        var yaml = "id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [A]}\nbomb:\n  a0: &a0 [x, x, x, x, x, x, x, x, x]\n"
        for i in 1...8 {
            yaml += "  a\(i): &a\(i) [*a\(i-1), *a\(i-1), *a\(i-1), *a\(i-1), *a\(i-1), *a\(i-1), *a\(i-1), *a\(i-1), *a\(i-1)]\n"
        }
        XCTAssertThrowsError(try PersonYAML.decode(yaml),
                             "DAG 比對爆炸超出 oracle 預算——fail-closed quarantine")
    }

    // α CRITICAL regression（R2 DA 實測毀檔路徑）：文字相同、型別不同的兩個 key
    // （'123' 是 str、123 是 int）必須逐字寫回為兩行不同文字，re-decode 成功
    func testTypedKeysSurviveWriteBack() throws {
        let yaml = "id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [A]}\n'123': first\n123: second\n"
        let person = try PersonYAML.decode(yaml)
        XCTAssertEqual(person.unknownFields.map(\.key), ["123", "123"])
        let reencoded = try PersonYAML.encode(person)
        XCTAssertTrue(reencoded.contains("'123': first"), "quoted key 必須保留引號")
        XCTAssertTrue(reencoded.contains("123: second"))
        let decoded = try PersonYAML.decode(reencoded)   // R2 前這裡 parse 失敗（重複鍵）
        XCTAssertEqual(decoded.unknownFields.map(\.key), ["123", "123"])
    }

    // α verbatim 保真：tag / 註解 / block scalar 在未知區塊內逐字保留
    func testUnknownBlockVerbatimFidelity() throws {
        let yaml = """
        id: 11111111-1111-4111-8111-111111111111
        key: a
        names: {variant: [A]}
        payload: !!binary R0lGODlh
        notes_block: |
          第一行
            縮排第二行
        annotated: value  # 尾隨註解
        """
        let person = try PersonYAML.decode(yaml + "\n")
        XCTAssertEqual(person.unknownFields.map(\.key), ["payload", "notes_block", "annotated"])
        let reencoded = try PersonYAML.encode(person)
        XCTAssertTrue(reencoded.contains("!!binary R0lGODlh"), "tag 必須逐字保留")
        XCTAssertTrue(reencoded.contains("notes_block: |"))
        XCTAssertTrue(reencoded.contains("    縮排第二行"), "block scalar 內容縮排必須逐字保留")
        XCTAssertTrue(reencoded.contains("# 尾隨註解"), "未知區塊的註解必須保留")
        XCTAssertEqual(try PersonYAML.decode(reencoded), person)
    }

    // α fail-closed：切分無法與 compose 對齊（complex key）→ throw → load 層 quarantine
    func testComplexKeyFileRejected() {
        let yaml = "id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [A]}\n? complex\n: value\n"
        XCTAssertThrowsError(try PersonYAML.decode(yaml))
    }

    // 多文件 YAML：root compose 本身就拒收（單文件 stream 假設）——
    // 不需要（也不再有）文字層守衛（R3 finding 6/7：守衛只會誤傷 block scalar 內容）
    func testMultiDocumentFileRejected() {
        let yaml = "id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [A]}\nextra: 1\n---\nkey: b\n"
        XCTAssertThrowsError(try PersonYAML.decode(yaml))
    }

    // R3 CRITICAL regression（oracle round）——五個「計數相等但錯位」家族：

    // (1) 跨區塊 anchor/alias 引用一律 quarantine（區塊獨立 compose 擋下）：
    //     不論 anchor 在已知或未知欄位側，寫回都會產生 dangling / 倒置 alias。
    //     同一區塊內自足的 anchor/alias 由 testSelfContainedAnchorPreserved 覆蓋。
    func testCrossBoundaryAliasQuarantinedAtLoad() {
        XCTAssertThrowsError(try PersonYAML.decode("id: 11111111-1111-4111-8111-111111111111\nkey: &k a\nnames: {variant: [A]}\nextra: *k\n"),
                             "alias 指向已知欄位的 anchor → quarantine")
        XCTAssertThrowsError(try PersonYAML.decode("id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [A]}\ntitle_note: &t Shared\nextra: *t\n"),
                             "兩個未知區塊之間的 anchor/alias 引用同樣 quarantine（fail-closed）")
    }

    // (1b) 自足的 anchor/alias（同一個未知區塊內）仍然容忍且逐字保留
    func testSelfContainedAnchorPreserved() throws {
        let yaml = "id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [A]}\nbomb:\n  base: &b [x, y]\n  mirror: *b\n"
        let person = try PersonYAML.decode(yaml)
        XCTAssertEqual(person.unknownFields.map(\.key), ["bomb"])
        let re = try PersonYAML.encode(person)
        XCTAssertTrue(re.contains("&b"))
        XCTAssertTrue(re.contains("*b"))
        XCTAssertEqual(try PersonYAML.decode(re), person)
    }

    // (2) flow-style 多行 mapping：計數可能相等但對齊錯位 → oracle 擋下
    func testMultilineFlowMappingQuarantined() {
        let yaml = "{key: a, email: smuggle,\norcid: EVIL-0000,\nnote:\nn}\n"
        XCTAssertThrowsError(try PersonYAML.decode(yaml))
        let akFlow = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: periodical-article
        title: T
        akashic: {
          tags: [x], status: read,
          reading_progress:
          60}
        """
        XCTAssertThrowsError(try EntryYAML.decode(akFlow + "\n"))
    }

    // (3) CRLF / 混合行尾：Swift 行模型與 libyaml 分歧 → 顯式 reject（fail-closed）
    func testCRLFWithUnknownFieldsQuarantined() {
        let mixed = "extra: 1\r\nkey: i-mix\nnames: {variant: [\nA]}\n"
        XCTAssertThrowsError(try PersonYAML.decode(mixed))
    }

    // R4 CRITICAL regression：CRLF 守衛必須在 unicodeScalar 層比對——
    // Swift 把 \r\n 當單一 grapheme，`contains("\r")` 對 CRLF 恆 false（死碼守衛）。
    // 本案例（folded scalar 內 CRLF）在 R4 前會「良性通過」oracle——守衛修好後必擋。
    func testCRLFGuardActuallyFiresOnGraphemePairs() {
        let benign = "id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [A]}\nextra: >\r\n  folded content\n"
        XCTAssertThrowsError(try PersonYAML.decode(benign),
                             "CRLF 必須被 scalar 層守衛擋下，不得依賴 oracle 碰巧攔截")
        // NEL 與 CR 同族（libyaml 讀取有損、emitter 會 escape）——R7 回歸守衛，
        // R8 起由 decode 入口的毀字守衛更早攔下（純 known 檔也涵蓋）
        XCTAssertThrowsError(try PersonYAML.decode("id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [A]}\nextra: v\u{85}more: 1\n")) {
            XCTAssertTrue(String(describing: $0).contains("NEL"), "\($0)")
        }
        // 裸 LS 在 plain scalar：libyaml 當 break 多切出 key → 不走守衛、由
        // 切分計數 oracle fail-closed（R6-verify [20] 更正——非「compose 不過」）
        XCTAssertThrowsError(try PersonYAML.decode("id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [A]}\nextra: v\u{2028}more: 1\n")) {
            XCTAssertTrue(String(describing: $0).contains("無法可靠切分"), "\($0)")
        }
        // 孤立 CR（classic-Mac）照舊擋
        XCTAssertThrowsError(try PersonYAML.decode("id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [A]}\nextra: 1\rmore: 2\n"))
    }

    // R4 HIGH regression：column-0 的 `...`/`---`（stream-scoped token）被吸進
    // 未知區塊會讓 encode 永遠被 canary 拒寫（「讀得到但永遠寫不回」）——
    // 擷取時剝除；縮排的 `...` 是 scalar 內容、不受影響
    func testDocEndMarkerStrippedFromUnknownBlock() throws {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: periodical-article
        title: T
        rating: 5
        akashic:
          reading_progress: 60
        ...
        """
        let entry = try EntryYAML.decode(yaml + "\n")
        XCTAssertEqual(entry.akashic.unknownFields.map(\.key), ["reading_progress"])
        XCTAssertFalse(entry.akashic.unknownFields[0].raw.contains("..."),
                       "stream-scoped 標記不屬於欄位資料，必須剝除")
        let re = try EntryYAML.encode(entry)          // R4 前在此被 canary 永久拒寫
        XCTAssertEqual(try EntryYAML.decode(re).akashic.unknownFields.map(\.key),
                       ["reading_progress"])
    }

    // R4 HIGH regression：語意 canary——parse-only 驗不出 key↔raw 不符的程式化注入
    func testSemanticCanaryRefusesKeyRawMismatch() {
        var person = Person(key: "a", names: ["A"])
        person.unknownFields = [UnknownField(key: "x", raw: "orcid: HIJACKED-0000\n")]
        XCTAssertThrowsError(try PersonYAML.encode(person),
                             "raw 注入 known 欄位——語意 canary 必須拒寫")
    }

    // R3 CRITICAL #4 regression（R4 補）：tagged decoy——同字串異型別的 `akashic` 鍵
    func testTaggedDecoyAkashicKeyQuarantined() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: periodical-article
        title: T
        !!str akashic: {status: decoy}
        akashic:
          reading_progress: 60
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml + "\n"))
    }

    // (4) 值截斷（flow 造成的靜默 null 化）→ oracle 的值等值檢查擋下
    //     （由 (2) 的 akFlow 案例涵蓋——reading_progress 的 60 會被切掉）

    // (5) 檔尾空行：只除 split artifact，`|+` keep-chomping 的尾空行逐字保真
    func testKeepChompingTrailingBlanksPreserved() throws {
        let yaml = "id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [A]}\nnotes: |+\n  content\n\n\n"
        let person = try PersonYAML.decode(yaml)
        XCTAssertEqual(person.unknownFields.map(\.key), ["notes"])
        XCTAssertTrue(person.unknownFields[0].raw.hasSuffix("content\n\n\n"),
                      "|+ 的尾端空行是 scalar 值的一部分，必須保留")
        let re = try PersonYAML.encode(person)
        XCTAssertEqual(try PersonYAML.decode(re), person, "round-trip 冪等且不累積")
        let re2 = try PersonYAML.encode(try PersonYAML.decode(re))
        XCTAssertEqual(re2, re, "第二輪 encode 必須 byte 穩定")
    }

    // encode canary：寫出前 compose 自檢——程式化構造的毀損 raw 不得進磁碟
    func testEncodeCanaryRefusesCorruptOutput() {
        var person = Person(key: "a", names: ["A"])
        person.unknownFields = [UnknownField(key: "x", raw: "x: 1\nkey: dup\n")]
        XCTAssertThrowsError(try PersonYAML.encode(person),
                             "產物含重複鍵——canary 必須拒寫，不得原子性覆蓋合法檔案")
    }

    // verify R1 F2（#23）：merge key `<<` 語意在 parser 間分歧，不入 tolerant 範圍
    func testMergeKeyUnknownFieldRejected() {
        let yaml = "id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [A]}\n<<: {orcid: smuggled}\n"
        XCTAssertThrowsError(try PersonYAML.decode(yaml))
    }

    // verify R1 F3（#23）：§5 MUST 3 的第三層——library 的未知欄位要有 validate warning
    func testLibraryValidateWarnsOnUnknownFields() throws {
        let lib = try LibraryYAML.decode("id: 11111111-1111-4111-8111-111111111111\nkey: sinica\nname: 中研院\ncolor: blue\n")
        let issues = lib.validate()
        XCTAssertTrue(issues.contains { $0.severity == .warning && $0.message.contains("color") })
        XCTAssertFalse(issues.contains { $0.severity == .error })
    }

    func testPersonValidateWarnsOnUnknownFields() throws {
        let person = try PersonYAML.decode("id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [A]}\nemail: x@y.z\n")
        let issues = person.validate()
        XCTAssertTrue(issues.contains { $0.severity == .warning && $0.message.contains("email") })
        XCTAssertFalse(issues.contains { $0.severity == .error })
    }

    func testEntryValidateWarnsOnUnknownFields() throws {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: periodical-article
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
        type: periodical-article
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
        type: periodical-article
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
    // R6（取代 R3 的嚴格拒收）：字串欄位以 scalar 的字串面解讀。emitter 對
    // 「長得像 int/bool 的字串」輸出 plain 樣式（tags: ["2026"] → `- 2026`），
    // R3 的拒收使本 binary 自己寫出的檔案永久 decode 失敗（寫得出、讀不回的
    // 自我毒化——DA R5 更正二）。字串面解讀與 emitter 對合、encode/decode 等冪。
    func testPlainScalarFaceAcceptedInTags() throws {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: periodical-article
        title: T
        akashic:
          tags: [ok, 123, true]
        """
        XCTAssertEqual(try EntryYAML.decode(yaml).akashic.tags, ["ok", "123", "true"])
    }

    func testQuotedNumericStringTagAccepted() throws {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: periodical-article
        title: T
        akashic:
          tags: ["123"]
        """
        XCTAssertEqual(try EntryYAML.decode(yaml).akashic.tags, ["123"])
    }

    // DA R5 更正二的實測案例：Zotero 使用者標籤「2026」建檔 seed 後，encode
    // 寫出 plain `- 2026`——R6 前這筆記錄下次 load 即 quarantine（自我毒化）。
    func testNumericFaceTagsRoundTripIdempotent() throws {
        var e = Entry(id: UUID(), citekey: "a2020b", type: .periodicalArticle, title: "T")
        e.akashic.tags = ["2026", "null", "yes", "10.5"]
        let out = try EntryYAML.encode(e)
        XCTAssertEqual(try EntryYAML.decode(out), e)
    }

    func testPlainScalarFaceAcceptedInAuthorKey() throws {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: periodical-article
        title: T
        authors:
          - key: 123
        """
        XCTAssertEqual(try EntryYAML.decode(yaml).authors, [.key("123")])
    }

    func testPlainScalarFaceAcceptedInPersonNames() throws {
        XCTAssertEqual(try PersonYAML.decode("id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [123]}\n").names, ["123"])
    }

    // 非 scalar 元素仍拒收（字串面只對 scalar 有定義）
    func testSequenceElementInTagsStillRejected() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: periodical-article
        title: T
        akashic:
          tags: [[nested]]
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }
}

extension StrictSchemaTests {
    // Phase 2（#9）：provenance 新欄位 round-trip；strict set 同步擴充
    func testProvenanceLibraryIDAndHashRoundTrip() throws {
        var entry = Entry(id: UUID(), citekey: "a2020b", type: .periodicalArticle, title: "T")
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
        type: periodical-article
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
        type: periodical-article
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
        var e = Entry(id: UUID(), citekey: "cheng2025identifiability", type: .periodicalArticle, title: "T")
        e.akashic.libraries = ["sinica", "psychology"]
        let yaml = try EntryYAML.encode(e)
        XCTAssertTrue(yaml.contains("libraries"), "非空 libraries 要序列化")
        let decoded = try EntryYAML.decode(yaml)
        XCTAssertEqual(decoded.akashic.libraries, ["sinica", "psychology"])
        XCTAssertEqual(decoded, e)
    }

    func testEmptyLibrariesNotSerialized() throws {
        let e = Entry(id: UUID(), citekey: "cheng2025identifiability", type: .periodicalArticle, title: "T")
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
        type: periodical-article
        title: T
        akashic:
          libraries: sinica
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml),
                             "libraries 存在但非 sequence → 必須擲錯，不得靜默當空")
    }

    func testLibraryDescriptionWrongTypeRejected() {
        let yaml = """
        id: 11111111-1111-4111-8111-111111111111
        key: sinica
        name: 中研院
        description:
          nested: nope
        """
        XCTAssertThrowsError(try LibraryYAML.decode(yaml))
    }
}

// #223：work 記錄以 digest 指向「是本作品副本」的已儲存內容。與欄位層級的
// `references` 是不同的關係項——references 說「這個欄位的值以那份內容為據」，
// sources 說「那些位元組是這篇作品的副本」。兩者不得合併。
final class EntrySourceReferenceTests: XCTestCase {
    private let digest =
        "sha256:0a9a79d3030c457b7a3f54ecc98c9fa11d60b8901ffd8e709b528d47f151125a"

    private func yaml(akashicBody: String) -> String {
        """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: periodical-article
        title: T
        akashic:
        \(akashicBody)
        """
    }

    private let bare = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: periodical-article
        title: T
        """

    func testCopyListRoundTripsVerbatim() throws {
        let entry = try EntryYAML.decode(yaml(akashicBody: "  sources:\n    - \(digest)"))
        XCTAssertEqual(entry.akashic.sources, [digest])
        let decoded = try EntryYAML.decode(try EntryYAML.encode(entry))
        XCTAssertEqual(decoded.akashic.sources, [digest], "digest 必須逐字保留，不得正規化")
        XCTAssertEqual(decoded, entry)
    }

    func testEmptyCopyListIsIndistinguishableFromAbsent() throws {
        let withEmpty = try EntryYAML.decode(yaml(akashicBody: "  sources: []"))
        let absent = try EntryYAML.decode(bare)
        XCTAssertEqual(withEmpty.akashic.sources, [])
        XCTAssertEqual(withEmpty, absent, "空清單與缺席在行為上必須不可區分")
    }

    func testMalformedDigestIsRejectedNamingTheField() {
        let yamlText = yaml(akashicBody: "  sources:\n    - sha256:notahexdigest")
        XCTAssertThrowsError(try EntryYAML.decode(yamlText)) { error in
            guard case StoreYAMLError.invalidField(let field, _) = error else {
                return XCTFail("預期 invalidField，實得 \(error)")
            }
            XCTAssertEqual(field, "akashic.sources",
                           "錯誤訊息要指名欄位，否則使用者不知道是哪一段壞了")
        }
    }
}
