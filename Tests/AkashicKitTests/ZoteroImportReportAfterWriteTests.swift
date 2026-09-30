import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicZoteroImport

/// #702：主來源更新分支的 `authorsPreserved`、`authorsOverwritten`、`fieldsRemovedByPull` 只記**寫進去了**的那一筆。
///
/// 先前這三個清單在 `guardedWrite` 之前就記下，於是目的檔被隔離（`quarantineConflicts`）或寫入擲錯（`writeFailed`）的那一筆，
/// 報告同時說它的作者被覆寫、欄位被拿掉了——那一筆實際上沒有寫。#696 R1 起 MCP 回應也帶這兩個鍵，兩個面都看得到這個誤報。
///
/// 兩支測試各讓一筆寫不進去、另一筆寫得進去：失敗的那一筆只能在失敗清單裡，成功的那一筆照常記下（正面也要釘住，
/// 否則「一律不記」也會通過）。作者清單兩種各有一筆失敗：已歸戶的走 `authorsPreserved`、未歸戶的走 `authorsOverwritten`。
extension ZoteroImportTests {
    private func runImport702() throws -> ImportReport {
        try ZoteroImporter(store: store).run(zoteroDB: fixture.dbURL, now: Date(timeIntervalSince1970: 1_753_000_000))
    }

    private func stored702(_ citekey: String) throws -> Entry {
        try XCTUnwrap(try store.load().entries.first { $0.citekey == citekey }, citekey)
    }

    /// 文章：未歸戶作者換成別的字串、加一個 Zotero 不會給的欄位——pull 會覆寫作者、拿掉那個欄位。
    private func primeArticle702() throws -> Entry {
        var article = try stored702("cheng2025identifiability")
        article.authors = [.literal("Someone Else")]
        article.fields["annotation"] = "手加"
        try store.writeEntry(article)
        return article
    }

    /// 目的檔被隔離：`entries/<citekey>.yaml` 有一份讀不出來的 legacy 殘留，load 隔離它、importer 的寫入閘因此拒寫這個 citekey。
    func testQuarantinedDestinationIsNotReportedAsOverwrittenOrPruned() throws {
        _ = try runImport702()
        let article = try primeArticle702()
        var book = try stored702("chen2004matrix")
        book.authors = [.key("chen-chun-houh")]
        book.fields["annotation"] = "手加"
        try store.writeEntry(book)
        try fixture.db.execute("UPDATE items SET version = 9 WHERE itemID IN (10, 11)")
        let residue = store.entriesDir.appendingPathComponent("\(article.citekey).yaml")
        try "broken: [yaml\n".write(to: residue, atomically: true, encoding: .utf8)

        let report = try runImport702()

        XCTAssertEqual(report.quarantineConflicts, [article.citekey], "\(report)")
        XCTAssertEqual(report.authorsOverwritten, [], "隔離的那一筆沒有寫，作者沒被覆寫：\(report)")
        XCTAssertEqual(report.fieldsRemovedByPull, ["annotation": 1], "只算寫進去的那一筆（書）：\(report)")
        XCTAssertEqual(report.authorsPreserved, [book.citekey], "寫進去的那一筆照常記下：\(report)")
        XCTAssertEqual(report.updated, [book.citekey], "\(report)")
        let after = try stored702(article.citekey)
        XCTAssertEqual(after.authors, [.literal("Someone Else")], "磁碟上的作者沒動")
        XCTAssertEqual(after.fields["annotation"], "手加", "磁碟上的欄位沒動")
    }

    /// 寫入擲錯：書的檔案帶一個 encode 平移不變式會拒寫的未知欄位（`testWriteFailureContainedPerItem` 同一個手法）。
    /// 書另帶一個 Zotero 沒給的 DOI：pull 會把它清掉，而寫入失敗時那個識別碼也不能記進 `fieldsRemovedByPull`
    /// （#702 R1 verify：識別碼那一半先前沒有專屬測試，把它的記錄移回寫入之前，三支測試都照綠）。
    func testWriteFailureIsNotReportedAsPreservedOrPruned() throws {
        _ = try runImport702()
        let article = try primeArticle702()
        let book = try stored702("chen2004matrix")
        let frozen = """
        work:
        id: \(book.id.uuidString)
        citekey: \(book.citekey)
        type: book
        title: Matrix Visualization
        doi:
        - 10.1037/abc123
        authors:
          - key: chen-chun-houh
        fields:
          annotation: 手加
        provenance:
          zotero_key: KEYBOOK1
          zotero_version: 1
          library_id: 1
        akashic:
            tags:
            - keep
            weird: [a,
          b]
        """
        try (frozen + "\n").write(to: store.entityURL(id: book.id), atomically: true, encoding: .utf8)
        try fixture.db.execute("UPDATE items SET version = 9 WHERE itemID = 10")

        let report = try runImport702()

        XCTAssertNotNil(report.writeFailed[book.citekey], "\(report)")
        XCTAssertEqual(report.authorsPreserved, [], "寫入失敗的那一筆沒有寫，不是「作者已保留」：\(report)")
        XCTAssertEqual(report.fieldsRemovedByPull, ["annotation": 1],
                       "只算寫進去的那一筆（文章）；書的 annotation 與 doi 都沒有真的被拿掉：\(report)")
        XCTAssertEqual(report.authorsOverwritten, [article.citekey], "寫進去的那一筆照常記下：\(report)")
        XCTAssertEqual(report.updated, [article.citekey], "\(report)")
        let onDisk = try String(contentsOf: store.entityURL(id: book.id), encoding: .utf8)
        XCTAssertTrue(onDisk.contains("annotation: 手加"), "寫入失敗不毀檔")
        XCTAssertTrue(onDisk.contains("10.1037/abc123"), "DOI 還在磁碟上，所以報告不能說它被拿掉")
    }

    /// #702 R1 verify（DA 席）：`guardedWrite` 回 false 不等於沒寫。#631 的搬移先寫 `entities/<id>.yaml`、**之後**才刪
    /// legacy 檔；刪不掉時內容已經寫進去了。那一筆的作者覆寫、欄位拿掉都真的發生了，要照寫入成功記下，留下兩份的事實
    /// 在 `writeFailed` 的訊息裡。這裡讓 `entries/` 唯讀，搬移的刪除必然失敗。
    func testWriteThatLandsBeforeLegacyRemovalFailsIsReportedAsWritten() throws {
        _ = try runImport702()
        GitFixture.initRepo(store.root)
        var article = try stored702("cheng2025identifiability")
        article.authors = [.literal("Someone Else")]
        article.fields["annotation"] = "手加"
        // 把文章搬回 legacy 佈局：只有 `entries/<citekey>.yaml` 一份，受 git 追蹤、乾淨——寫入時會搬移它（#631）
        let legacy = store.entriesDir.appendingPathComponent("\(article.citekey).yaml")
        try EntryYAML.encode(article).write(to: legacy, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: store.entityURL(id: article.id))
        GitFixture.commitAll(store.root)
        try fixture.db.execute("UPDATE items SET version = 9 WHERE itemID = 10")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: store.entriesDir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.entriesDir.path) }
        let probe = store.entriesDir.appendingPathComponent("probe-\(UUID().uuidString)")
        if FileManager.default.createFile(atPath: probe.path, contents: Data()) {
            try? FileManager.default.removeItem(at: probe)
            throw XCTSkip("這個環境的權限擋不住刪檔（以 root 執行？），造不出「寫完之後刪 legacy 失敗」")
        }

        let report = try runImport702()

        let written = try String(contentsOf: store.entityURL(id: article.id), encoding: .utf8)
        XCTAssertFalse(written.contains("Someone Else"), "前提：內容已經寫進 entities/（作者換成 Zotero 的）")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path), "前提：legacy 檔沒刪掉")
        XCTAssertEqual(report.authorsOverwritten, [article.citekey], "寫了，作者覆寫真的發生了：\(report)")
        XCTAssertEqual(report.fieldsRemovedByPull, ["annotation": 1], "寫了，欄位真的被拿掉了：\(report)")
        XCTAssertEqual(report.updated, [article.citekey], "\(report)")
        let message = try XCTUnwrap(report.writeFailed[article.citekey], "留下兩份要說出來：\(report)")
        XCTAssertTrue(message.hasPrefix("已寫入"), message)
        XCTAssertTrue(message.contains("entries/\(article.citekey).yaml"), message)
    }
}
