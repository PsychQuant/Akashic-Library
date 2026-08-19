import CryptoKit
import Foundation
import AkashicCore

/// Zotero → Akashic 的對映表。
public enum ZoteroMapping {
    /// Zotero itemType → `WorkType`（#325 階段二：目標由自由字串改為封閉列舉）。
    ///
    /// 更名順帶修掉兩個舊值域的實際損失：
    /// - `presentation` 先前壓成 `unpublished`，但它明明是 **10.5 Conference
    ///   Session**——那正是 store 裡 21 筆「欄位全空的 unpublished」的來源。
    /// - `magazineArticle`／`newspaperArticle` 先前壓成 `article`。壓縮本身沒錯
    ///   （APA7 的 periodical 就涵蓋這三者），錯的是舊名字掩蓋了它——新值域叫
    ///   `periodical-article` 就名副其實。
    public static let typeMap: [String: WorkType] = [
        "journalArticle": .periodicalArticle,
        "magazineArticle": .periodicalArticle,
        "newspaperArticle": .periodicalArticle,
        "book": .book,
        "bookSection": .bookChapter,
        "conferencePaper": .conferenceSession,
        "thesis": .thesis,
        "report": .report,
        "preprint": .unpublishedWork,
        "webpage": .webpage,
        "manuscript": .unpublishedWork,
        "presentation": .conferenceSession,
        "document": .webpage,
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

    /// Zotero itemType → `WorkType`。
    ///
    /// **fallback 是 `.webpage` 不是「雜項」**（#325 階段二）：舊值域的 `misc` 是
    /// catch-all，而實測那 14 筆全是線上百科條目——catch-all 的名字說「雜項」，內容
    /// 說「沒人給它們正確的格子」。新值域沒有雜項格，未知 itemType 落最接近的
    /// 10.16 Webpages，讓它在 APA7 匯出時仍是可產出的。
    public static func workType(for zoteroType: String) -> WorkType {
        typeMap[zoteroType] ?? .webpage
    }

    /// 不在 `fieldMap` 的 Zotero 欄位（title/date 除外）。
    ///
    /// **這些欄位現在會入庫**（#206）——以正規化後的原名收進 `fields`，不再捨棄。
    /// 名稱與消費端的 `report.residualFields` 一起改過：舊名是 `droppedFields`，
    /// CLI 印「未映射的 Zotero 欄位，**未入庫**」。
    ///
    /// **那句話在 #206 之後是假的**（verify H2）。更糟的是
    /// `testUnmappedZoteroFieldsAreReportedNotSilentlyDropped` 仍然綠——套件
    /// 因此**釘住了那個謊**：把 `ZoteroMapping` 改回靜默丟棄，27 條
    /// `ZoteroImportTests` 全綠，只有 `LosslessIntakeTests` 會紅。
    ///
    /// 保留這個查詢是有用的（「哪些欄位沒有 canonical 對照」是編目訊號，值得看見），
    /// 只是它的**語意從「丟了什麼」變成「以原名收了什麼」**。
    public static func residualFields(of item: ZoteroItem) -> [String] {
        item.fields.keys.filter { $0 != "title" && $0 != "date" && fieldMap[$0] == nil }.sorted()
    }

    /// mapping 產出的 biblatex 面向 canonical hash（SHA-256）。
    /// update 條件之一：hash 不同 → re-apply（涵蓋本機未同步修改與 mapping 邏輯演進）。
    /// 涵蓋範圍＝pull 管的一切：type/title/normalized date/mapped fields/authors/attachments。
    public static func mappingHash(of item: ZoteroItem) -> String {
        var probe = Entry(id: UUID(), citekey: "probe", type: .webpage, title: "")
        applyBiblatexFields(from: item, to: &probe)
        // JSON 序列化（sortedKeys）保證結構性——串接式 canonical 曾被構造出碰撞（verify R1）
        //
        // **`.rawValue` 是必要的**（#325 階段二）：`[String: Any]` 是去型別化邊界，
        // 直接放 `WorkType` 會通過編譯、在 `JSONSerialization` 才炸
        // （`Invalid type in JSON write (__SwiftValue)`）。封閉列舉在 `switch` 上的
        // 窮盡保證到 `Any` 就失效——這種點只有測試接得住。
        //
        // **已知且刻意的後果**：值域更名（`article` → `periodical-article`）會改變
        // 每一筆 Zotero 來源記錄的 hash，所以部署後第一次 `import-zotero` 會把它們
        // 全部視為「已變更」而重新套用。這是**可見的**大批更新，不是安靜的——
        // `lossless-intake` 要求 pull 覆寫回報 `authorsOverwritten` 與
        // `fieldsRemovedByPull`，那條路照常走。
        let canonical: [String: Any] = [
            "type": probe.type.rawValue,
            "title": probe.title,
            "date": probe.date ?? "",
            "fields": probe.fields,
            "authors": item.authors.map(\.display),
            "attachments": item.attachmentPaths,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: canonical, options: [.sortedKeys])) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 把 ZoteroItem 的 biblatex 面向填進 Entry（不動 id/citekey/akashic）。
    /// date 經 DateNormalizer；解析不了保留原字串（importer 另行 report）。
    public static func applyBiblatexFields(from item: ZoteroItem, to entry: inout Entry) {
        entry.type = workType(for: item.typeName)
        entry.title = item.fields["title"] ?? ""
        entry.date = item.fields["date"].map { DateNormalizer.normalize($0) ?? $0 }
        var fields: [String: String] = [:]
        // **殘餘收集**（#206）——`fieldMap` 命中就用 canonical biblatex 名，
        // **沒命中的不再丟掉**，改用正規化後的原名收進來。
        //
        // 這一行原本是 `guard let bibField = fieldMap[zField] else { continue }`
        // ——那個 `continue` 就是 `.claude/rules/lossless-intake.md` 點名的靜默丟棄。
        // Zotero 的 item 依 type 有幾十種欄位（`presentationType`／`meetingName`／
        // `repository`／`archiveLocation`…），`fieldMap` 涵蓋不到的一律消失。
        //
        // **對映優先於殘餘**：`fieldMap` 是語意對照（Zotero 名 → biblatex 正典名），
        // 殘餘是原樣搬運。同一個 zField 只會走其中一條。
        for (zField, value) in item.fields {
            if zField == "title" || zField == "date" { continue }
            guard let key = fieldMap[zField] ?? FieldKey.normalized(zField) else { continue }
            guard !value.isEmpty else { continue }
            // 對映後撞名（兩個 Zotero 欄位映到同一個 biblatex 名，或殘餘撞上對映）：
            // **`fieldMap` 的結果勝出**，不靜默覆寫。`item.fields` 是 Dictionary、
            // 迭代順序不定，所以不能靠順序決定——必須顯式讓對映優先。
            if let existing = fields[key], fieldMap[zField] == nil {
                _ = existing   // 殘餘不覆寫既有值
                continue
            }
            fields[key] = value
        }
        entry.fields = fields
        // #304：載體二態 ref。**只在 venues 為空時推導**——已歸戶的 `.key` 或先前
        // 的 literal 一律不覆寫（Zotero pull 對 fields 跟隨上游，但 venues 的歸戶
        // 判定不是 Zotero 供給的資料，同 `.key` 作者永不被覆寫的既有紀律）。
        // 對映唯一來源在 VenueDerivation（與 WoS／migration 共用）。
        if entry.venues.isEmpty {
            entry.venues = VenueDerivation.literals(for: entry)
        }
        // 鍵域收窄後只剩 zotero 一種，而它整批以 Zotero 為準（#223）。使用者自有的
        // 副本引用改住 `akashic.sources`（以 digest 指涉），不經此路徑，所以這裡
        // 不再需要過濾保留任何附件種類——namespace 契約已經擋住覆寫。
        entry.attachments = item.attachmentPaths.map { AttachmentRef(kind: .zotero, path: $0) }
    }
}
