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
        XCTAssertEqual(report.fieldsRemovedByPull, ["annotation": 1], "只算寫進去的那一筆（文章）：\(report)")
        XCTAssertEqual(report.authorsOverwritten, [article.citekey], "寫進去的那一筆照常記下：\(report)")
        XCTAssertEqual(report.updated, [article.citekey], "\(report)")
        let onDisk = try String(contentsOf: store.entityURL(id: book.id), encoding: .utf8)
        XCTAssertTrue(onDisk.contains("annotation: 手加"), "寫入失敗不毀檔")
    }
}
