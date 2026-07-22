import Foundation
import AkashicCore

/// Zotero → biblatex 的對映表。
public enum ZoteroMapping {
    public static let typeMap: [String: String] = [
        "journalArticle": "article",
        "magazineArticle": "article",
        "newspaperArticle": "article",
        "book": "book",
        "bookSection": "incollection",
        "conferencePaper": "inproceedings",
        "thesis": "thesis",
        "report": "report",
        "preprint": "online",
        "webpage": "online",
        "manuscript": "unpublished",
        "presentation": "unpublished",
        "document": "misc",
    ]

    /// Zotero fieldName → biblatex 欄位名。title/date 由 Entry 一級欄位承接，不進 fields。
    public static let fieldMap: [String: String] = [
        "publicationTitle": "journaltitle",
        "bookTitle": "booktitle",
        "proceedingsTitle": "booktitle",
        "volume": "volume",
        "issue": "number",
        "pages": "pages",
        "DOI": "doi",
        "url": "url",
        "abstractNote": "abstract",
        "publisher": "publisher",
        "place": "location",
        "ISBN": "isbn",
        "ISSN": "issn",
        "series": "series",
        "seriesNumber": "number",
        "edition": "edition",
        "language": "language",
        "shortTitle": "shorttitle",
        "university": "institution",
        "institution": "institution",
        "thesisType": "type",
        "reportType": "type",
        "numPages": "pagetotal",
    ]

    public static func biblatexType(for zoteroType: String) -> String {
        typeMap[zoteroType] ?? "misc"
    }

    /// 不在 fieldMap 的 Zotero 欄位（title/date 除外）——會被捨棄，
    /// importer 記進 report.droppedFields，不靜默流失。
    public static func unmappedFields(of item: ZoteroItem) -> [String] {
        item.fields.keys.filter { $0 != "title" && $0 != "date" && fieldMap[$0] == nil }.sorted()
    }

    /// 把 ZoteroItem 的 biblatex 面向填進 Entry（不動 id/citekey/akashic）。
    public static func applyBiblatexFields(from item: ZoteroItem, to entry: inout Entry) {
        entry.type = biblatexType(for: item.typeName)
        entry.title = item.fields["title"] ?? ""
        entry.date = item.fields["date"]
        var fields: [String: String] = [:]
        for (zField, value) in item.fields {
            if zField == "title" || zField == "date" { continue }
            guard let bibField = fieldMap[zField] else { continue }
            fields[bibField] = value
        }
        entry.fields = fields
        // pool 附件是 Akashic 自有資料，保留；zotero reference 整批以 Zotero 為準
        let poolAttachments = entry.attachments.filter { $0.kind == .pool }
        entry.attachments = item.attachmentPaths.map { AttachmentRef(kind: .zotero, path: $0) }
            + poolAttachments
    }
}
