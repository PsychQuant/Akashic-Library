import Foundation
import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

final class LibrarySnapshotTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-snapshot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        roots.append(root)
        return root
    }

    private func makeStore(id: UUID = UUID()) throws -> LibraryStore {
        let root = try makeRoot()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        try (id.uuidString + "\n").write(
            to: StoreIncarnation.url(in: root), atomically: true, encoding: .utf8)
        return LibraryStore(root: root)
    }

    private func entry(_ key: String, id: UUID, title: String) -> Entry {
        Entry(id: id, citekey: key, type: "article", title: title,
              authors: [.literal("A")], date: "2026")
    }

    private func write(_ bytes: Data, relativePath: String, in store: LibraryStore) throws {
        let url = store.root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url, options: .atomic)
    }

    private func write(_ text: String, relativePath: String, in store: LibraryStore) throws {
        try write(Data(text.utf8), relativePath: relativePath, in: store)
    }

    /// 會抓到的回歸：snapshot 若用路徑當身分、revision 不是 SHA-256，或公開結果沒有
    /// 保存同一份 strict incarnation，這個外部契約就會失敗。
    func testValidIncarnationIdentifiesStoreAndDigestHasShape() throws {
        let expected = UUID(uuidString: "68CFAFD8-3A66-4C44-BF32-B8F55C8378B6")!
        let snapshot = try makeStore(id: expected).loadSnapshot()

        XCTAssertEqual(snapshot.id.store.uuid, expected)
        XCTAssertNotNil(
            snapshot.id.revision.digest.range(
                of: #"^sha256:[0-9a-f]{64}$"#,
                options: .regularExpression))
        XCTAssertTrue(snapshot.load.entries.isEmpty)
    }

    /// 會抓到的回歸：snapshot 對缺席 incarnation 退回 path identity，或順手建立新 id。
    func testMissingIncarnationIsTypedRefusalAndDoesNotCreateIt() throws {
        let root = try makeRoot()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        let store = LibraryStore(root: root)

        XCTAssertThrowsError(try store.loadSnapshot()) { error in
            XCTAssertEqual(error as? StoreSnapshotError, .missingIncarnation)
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: StoreIncarnation.url(in: root).path))
    }

    /// 會抓到的回歸：空白、垃圾或非 UTF-8 incarnation 被當成可選欄位略過。
    func testEmptyMalformedAndUnreadableIncarnationHaveDistinctTypedRefusals() throws {
        let cases: [(Data, StoreSnapshotError)] = [
            (Data("\n".utf8), .malformedIncarnation),
            (Data("not-one-uuid\n".utf8), .malformedIncarnation),
            (Data([0xFF, 0xFE]), .unreadableIncarnation),
        ]
        for (bytes, expected) in cases {
            let store = try makeStore()
            try bytes.write(to: StoreIncarnation.url(in: store.root), options: .atomic)
            XCTAssertThrowsError(try store.loadSnapshot()) { error in
                XCTAssertEqual(error as? StoreSnapshotError, expected)
            }
        }
    }

    /// 會抓到的回歸：revision 使用列舉順序、建立時間或 root path。
    func testEnumerationAndCreationOrderDoNotAffectRevision() throws {
        let identity = UUID(uuidString: "6A4D3397-C65C-47D7-A36D-511070D8B2A2")!
        let first = try makeStore(id: identity)
        let second = try makeStore(id: identity)
        let a = entry("a2026work", id: UUID(uuidString: "10BF82EF-8BFD-430B-B3F9-5AD00898D22A")!,
                      title: "A")
        let b = entry("b2026work", id: UUID(uuidString: "4233A2EB-EF25-4708-8631-3B16D54F9570")!,
                      title: "B")
        try first.writeEntry(a)
        try first.writeEntry(b)
        try second.writeEntry(b)
        try second.writeEntry(a)

        XCTAssertEqual(try first.loadSnapshot().id.revision,
                       try second.loadSnapshot().id.revision)
    }

    /// 會抓到的回歸：digest 是常數，或漏掉真正拿去解碼的 canonical YAML bytes。
    func testCanonicalByteAndPathChangesChangeRevisionWithoutChangingIdentity() throws {
        let store = try makeStore()
        let recordID = UUID(uuidString: "877E4A1B-D48E-4BD4-BE1C-8C21D9C4B43F")!
        try store.writeEntry(entry("same2026work", id: recordID, title: "Before"))
        let before = try store.loadSnapshot()

        try store.writeEntry(entry("same2026work", id: recordID, title: "After"))
        let changedBytes = try store.loadSnapshot()
        XCTAssertEqual(before.id.store, changedBytes.id.store)
        XCTAssertNotEqual(before.id.revision, changedBytes.id.revision)

        try write("broken: [", relativePath: "entries/path-a.yaml", in: store)
        let pathA = try store.loadSnapshot()
        try FileManager.default.moveItem(
            at: store.root.appendingPathComponent("entries/path-a.yaml"),
            to: store.root.appendingPathComponent("entries/path-b.yaml"))
        let pathB = try store.loadSnapshot()
        XCTAssertNotEqual(pathA.id.revision, pathB.id.revision,
                          "相同 bytes 換 relative path 也必須是另一個 revision")
    }

    /// 會抓到的回歸：衍生物、來源附件或 loader 不讀的檔案誤入 revision。
    func testDerivedSourcesHiddenAndNonYAMLBytesAreExcluded() throws {
        let store = try makeStore()
        let before = try store.loadSnapshot().id.revision

        try write("index-a", relativePath: ".akashic/index.sqlite", in: store)
        try write("source-a", relativePath: "sources/source.pdf", in: store)
        try write("hidden-a", relativePath: "entities/.hidden.yaml", in: store)
        try write("text-a", relativePath: "entries/readme.txt", in: store)
        let afterCreate = try store.loadSnapshot().id.revision
        try write("index-b", relativePath: ".akashic/index.sqlite", in: store)
        try write("source-b", relativePath: "sources/source.pdf", in: store)
        try write("hidden-b", relativePath: "entities/.hidden.yaml", in: store)
        try write("text-b", relativePath: "entries/readme.txt", in: store)
        let afterChange = try store.loadSnapshot().id.revision

        XCTAssertEqual(before, afterCreate)
        XCTAssertEqual(before, afterChange)
    }

    /// 會抓到的回歸：digest 只收成功 decode 的記錄，讓 quarantine 警告漂移卻沿用 id。
    func testQuarantinedYAMLStillChangesRevision() throws {
        let store = try makeStore()
        try write("entry: [broken-a", relativePath: "entries/broken.yaml", in: store)
        let first = try store.loadSnapshot()
        try write("entry: [broken-b", relativePath: "entries/broken.yaml", in: store)
        let second = try store.loadSnapshot()

        XCTAssertEqual(first.load.quarantined.map(\.file), ["entries/broken.yaml"])
        XCTAssertEqual(second.load.quarantined.map(\.file), ["entries/broken.yaml"])
        XCTAssertNotEqual(first.id.revision, second.id.revision)
    }

    /// 會抓到的回歸：capture 只納入小寫 `.yaml`，與既有 tolerant loader 的枚舉集合分叉。
    func testUppercaseYAMLExtensionIsCanonicalAndChangesRevision() throws {
        let store = try makeStore()
        try write("bad: [A", relativePath: "entries/Broken.YAML", in: store)
        let first = try store.loadSnapshot()
        try write("bad: [B", relativePath: "entries/Broken.YAML", in: store)
        let second = try store.loadSnapshot()

        XCTAssertEqual(first.load.quarantined.map(\.file), ["entries/Broken.YAML"])
        XCTAssertNotEqual(first.id.revision, second.id.revision)
    }

    /// 會抓到的回歸：digest 把 incarnation 只當解析後 UUID，而漏掉 capture 的原始 bytes。
    func testIncarnationRawBytesChangeRevisionButNotIdentity() throws {
        let identity = UUID(uuidString: "7F8ED8A9-C7EB-4E21-AD8C-2E4E933F5A19")!
        let store = try makeStore(id: identity)
        let uppercaseWithNewline = try store.loadSnapshot()
        try identity.uuidString.lowercased().write(
            to: StoreIncarnation.url(in: store.root), atomically: true, encoding: .utf8)
        let lowercaseWithoutNewline = try store.loadSnapshot()

        XCTAssertEqual(uppercaseWithNewline.id.store, lowercaseWithoutNewline.id.store)
        XCTAssertNotEqual(uppercaseWithNewline.id.revision,
                          lowercaseWithoutNewline.id.revision)
    }

    /// 會抓到的回歸：marker 只拿解析後的 format 整數進 digest，漏掉原始 bytes／缺席狀態。
    func testMarkerBytesAndPresenceChangeRevision() throws {
        let store = try makeStore()
        let original = try store.loadSnapshot().id.revision
        try "# same format, different canonical bytes\nformat: \(StoreVersion.supported)\n".write(
            to: StoreVersion.url(in: store.root), atomically: true, encoding: .utf8)
        let changedBytes = try store.loadSnapshot().id.revision
        try FileManager.default.removeItem(at: StoreVersion.url(in: store.root))
        let absent = try store.loadSnapshot().id.revision

        XCTAssertNotEqual(original, changedBytes)
        XCTAssertNotEqual(changedBytes, absent)
    }

    /// 會抓到的回歸：只串接 path/content 而不加 record count 與固定寬度 lengths。
    func testStructuralFramingSeparatesEqualUnframedConcatenations() throws {
        let identity = UUID(uuidString: "5B7C91BA-458D-4925-A94F-6B90848880A7")!
        let left = try makeStore(id: identity)
        let right = try makeStore(id: identity)
        let pathB = "entries/b.yaml"
        let pathC = "entries/c.yaml"
        // 兩邊若天真串 `path + content`，都會得到：
        // entries/a.yaml + x + entries/b.yaml + entries/c.yaml + z
        try write("x\(pathB)", relativePath: "entries/a.yaml", in: left)
        try write("z", relativePath: pathC, in: left)
        try write("x", relativePath: "entries/a.yaml", in: right)
        try write("\(pathC)z", relativePath: pathB, in: right)

        XCTAssertNotEqual(try left.loadSnapshot().id.revision,
                          try right.loadSnapshot().id.revision)
    }

    /// 會抓到的回歸：domain、record count 或 path/content length 的編碼被改掉，
    /// relational tests 仍可能全綠，卻會讓所有既有 revision 無聲重編號。
    func testV1RevisionFramingMatchesGoldenDigest() {
        let records = [
            CapturedCanonicalRecord(path: "b.yaml", bytes: Data([0x00, 0xFF])),
            CapturedCanonicalRecord(path: "a.yaml", bytes: Data("xy".utf8)),
        ]

        XCTAssertEqual(
            StoreRevision.derive(from: records).digest,
            "sha256:3948749d80430232999c253714069c2cd32ad5fcc71a5919def04ad91999bb55",
            "v1 固定使用 domain separator、raw UTF-8 path sort 與 UInt64 big-endian framing")
    }

    /// 會抓到的回歸：即使前兩個 capture 已相同，實作仍一律多讀第三次。
    func testStableFirstPairAcceptsImmediatelyAfterSecondPass() throws {
        let store = try makeStore()
        let stable = try store.captureCanonicalStore()
        var passCount = 0

        _ = try store.loadSnapshot {
            passCount += 1
            if passCount > 2 {
                XCTFail("相鄰前兩份已相同，不得再要求第三個 capture")
            }
            return stable
        }

        XCTAssertEqual(passCount, 2)
    }

    /// 會抓到的回歸：每次比較都從頭成對重讀（會多於三 pass），或接受 A/B 混合後再讀盤。
    func testThreePassSlidingCaptureAcceptsAThenBThenBAndDecodesAcceptedBytes() throws {
        let identity = UUID(uuidString: "8684F505-F0BF-414D-998F-D14B3C1A52A7")!
        let store = try makeStore(id: identity)
        let recordID = UUID(uuidString: "90AD65BB-E0B5-4541-8CC9-107994908806")!
        try store.writeEntry(entry("stable2026work", id: recordID, title: "A"))
        let captureA = try store.captureCanonicalStore()
        try store.writeEntry(entry("stable2026work", id: recordID, title: "B"))
        let captureB = try store.captureCanonicalStore()
        // 接受 captureB 後若任何 canonical 欄位又讀磁碟，會錯誤看到 C。
        try store.writeEntry(entry("stable2026work", id: recordID, title: "C"))
        let reference = try makeStore(id: identity)
        try reference.writeEntry(entry("stable2026work", id: recordID, title: "B"))
        let expectedBRevision = try reference.loadSnapshot().id.revision
        let diskIdentityC = UUID(uuidString: "FB7FA062-C952-45B3-9CE3-02FC47A04A92")!
        try (diskIdentityC.uuidString + "\n").write(
            to: StoreIncarnation.url(in: store.root), atomically: true, encoding: .utf8)
        try "format: \(StoreVersion.supported + 1)\n".write(
            to: StoreVersion.url(in: store.root), atomically: true, encoding: .utf8)
        var captures = [captureA, captureB, captureB]
        var passCount = 0

        let snapshot = try store.loadSnapshot {
            passCount += 1
            return captures.removeFirst()
        }

        XCTAssertEqual(passCount, 3)
        XCTAssertEqual(snapshot.id.store.uuid, identity,
                       "identity 必須解析 accepted capture 的 incarnation，不得重讀磁碟 C")
        XCTAssertEqual(snapshot.load.entries.map(\.title), ["B"])
        XCTAssertEqual(snapshot.id.revision, expectedBRevision,
                       "identity、format、decode 與 revision 都必須由同一份 accepted B 產生")
    }

    /// 會抓到的回歸：第三個不同 capture 仍被當成可接受，或偷偷做第四 pass。
    func testThreeDistinctCapturePassesFailClosedAtExactlyThree() throws {
        let store = try makeStore()
        let recordID = UUID(uuidString: "E5D4A2CB-2E4B-4030-A543-64903359D066")!
        var captures: [CapturedCanonicalStore] = []
        for title in ["A", "B", "C"] {
            try store.writeEntry(entry("drift2026work", id: recordID, title: title))
            captures.append(try store.captureCanonicalStore())
        }
        var passCount = 0

        XCTAssertThrowsError(try store.loadSnapshot {
            passCount += 1
            return captures.removeFirst()
        }) { error in
            XCTAssertEqual(error as? StoreSnapshotError, .changedDuringCapture)
        }
        XCTAssertEqual(passCount, 3)
    }

    /// 會抓到的回歸：Swift String 把 NFC/NFD 視為相等，`Dictionary(uniqueKeysWithValues:)`
    /// 因而對兩個 filesystem 可區分的 raw path 直接 precondition trap。
    func testCanonicalEquivalentRawPathsRemainDistinctWithoutDecoderCrash() throws {
        let store = try makeStore()
        let base = try store.captureCanonicalStore()
        let nfc = "entries/caf\u{E9}.yaml"
        let nfd = "entries/cafe\u{301}.yaml"
        XCTAssertEqual(nfc, nfd, "本測試的前提：Swift String equality 會 canonicalize")
        XCTAssertNotEqual(Data(nfc.utf8), Data(nfd.utf8),
                          "filesystem/revision 身分仍是不同 raw UTF-8 bytes")
        let full = CapturedCanonicalStore(
            markerBytes: base.markerBytes,
            incarnationBytes: base.incarnationBytes,
            yamlRecords: [
                CapturedCanonicalRecord(path: nfc, bytes: Data("bad: [NFC".utf8)),
                CapturedCanonicalRecord(path: nfd, bytes: Data("bad: [NFD".utf8)),
            ])
        let single = CapturedCanonicalStore(
            markerBytes: base.markerBytes,
            incarnationBytes: base.incarnationBytes,
            yamlRecords: [CapturedCanonicalRecord(path: nfc, bytes: Data("bad: [NFC".utf8))])

        let snapshot = try store.loadSnapshot { full }
        let oneRecord = try store.loadSnapshot { single }
        let quarantinedRawPaths = Set(snapshot.load.quarantined.map { Data($0.file.utf8) })

        XCTAssertEqual(snapshot.load.quarantined.count, 2)
        XCTAssertEqual(quarantinedRawPaths, Set([Data(nfc.utf8), Data(nfd.utf8)]))
        XCTAssertNotEqual(snapshot.id.revision, oneRecord.id.revision,
                          "兩個 raw path/bytes 都必須進 revision，不得 canonical-collapse")
    }

    /// 會抓到的回歸：CapturedCanonicalRecord synthesized Equatable 用 canonical String
    /// equality，讓 NFC→NFD rename（bytes 不變）在第二 pass 就被誤判穩定。
    func testCanonicalEquivalentPathRenameCountsAsDriftAndChangesRevision() throws {
        let store = try makeStore()
        let base = try store.captureCanonicalStore()
        let nfc = "entries/caf\u{E9}.yaml"
        let nfd = "entries/cafe\u{301}.yaml"
        let bytes = Data("bad: [same".utf8)
        let recordNFC = CapturedCanonicalRecord(path: nfc, bytes: bytes)
        let recordNFD = CapturedCanonicalRecord(path: nfd, bytes: bytes)
        XCTAssertNotEqual(recordNFC, recordNFD, "capture equality 必須用 raw UTF-8 path bytes")
        let captureNFC = CapturedCanonicalStore(
            markerBytes: base.markerBytes,
            incarnationBytes: base.incarnationBytes,
            yamlRecords: [recordNFC])
        let captureNFD = CapturedCanonicalStore(
            markerBytes: base.markerBytes,
            incarnationBytes: base.incarnationBytes,
            yamlRecords: [recordNFD])
        var captures = [captureNFC, captureNFD, captureNFD]
        var passCount = 0

        let renamed = try store.loadSnapshot {
            passCount += 1
            return captures.removeFirst()
        }
        let original = try store.loadSnapshot { captureNFC }

        XCTAssertEqual(passCount, 3, "第 2 pass 的 raw path 已不同，不得提前接受")
        XCTAssertEqual(renamed.load.quarantined.map { Data($0.file.utf8) }, [Data(nfd.utf8)])
        XCTAssertNotEqual(renamed.id.revision, original.id.revision)
    }

    /// 會抓到的回歸：legacy `yamlFiles` 用 canonical Swift String `<`，而 snapshot
    /// 用 raw UTF-8 排序；NFC/NFD raw-distinct paths 的 quarantine 順序因而分叉。
    func testLegacyEnumerationMatchesSnapshotRawUTF8PathOrder() throws {
        let store = try makeStore()
        let base = try store.captureCanonicalStore()
        let nfc = "entries/caf\u{E9}.yaml"
        let nfd = "entries/cafe\u{301}.yaml"
        let nfcURL = URL(string: "file:///virtual/entries/caf%C3%A9.yaml")!
        let nfdURL = URL(string: "file:///virtual/entries/cafe%CC%81.yaml")!

        let legacyOrder = try store.yamlFiles(
            in: store.root,
            listing: { _ in [nfcURL, nfdURL] }
        ).map { Data("entries/\($0.lastPathComponent)".utf8) }
        let capture = CapturedCanonicalStore(
            markerBytes: base.markerBytes,
            incarnationBytes: base.incarnationBytes,
            yamlRecords: [
                CapturedCanonicalRecord(path: nfd, bytes: Data("bad: [NFD".utf8)),
                CapturedCanonicalRecord(path: nfc, bytes: Data("bad: [NFC".utf8)),
            ])
        let snapshotOrder = try store.loadSnapshot { capture }
            .load.quarantined.map { Data($0.file.utf8) }

        XCTAssertEqual(legacyOrder, [Data(nfd.utf8), Data(nfc.utf8)])
        XCTAssertEqual(legacyOrder, snapshotOrder)
    }

    /// 會抓到的回歸：snapshot 另寫一套 decoder，逐漸偏離 legacy `load()` 的 tolerant 行為。
    func testLegacyLoadAndSnapshotDecodeTheSameFixtureEquivalently() throws {
        let store = try makeStore()
        try StoreVersion.write(root: store.root, format: 1)
        let record = entry(
            "legacy2026work",
            id: UUID(uuidString: "CA91A260-1D6A-4D29-A0A3-B9D1BA3C4403")!,
            title: "Legacy")
        try store.writeEntry(record)
        try write("entry: [broken", relativePath: "entries/broken.yaml", in: store)
        try write(
            """
            key: future-one
            names:
              - Future One
            affiliations:
              - organization: ISS
            """,
            relativePath: "people/future-one.yaml",
            in: store)

        let legacy = try store.load()
        let snapshot = try store.loadSnapshot().load

        XCTAssertEqual(snapshot.entries, legacy.entries)
        XCTAssertEqual(snapshot.people, legacy.people)
        XCTAssertEqual(snapshot.organizations, legacy.organizations)
        XCTAssertEqual(snapshot.divergences, legacy.divergences)
        XCTAssertEqual(snapshot.libraries, legacy.libraries)
        XCTAssertEqual(snapshot.quarantined, legacy.quarantined)
        XCTAssertEqual(snapshot.unknownFieldFiles, legacy.unknownFieldFiles)
    }
}
