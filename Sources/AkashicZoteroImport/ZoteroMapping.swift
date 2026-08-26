import CryptoKit
import Foundation
import AkashicCore
import AkashicStoreIO

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
        // #340：`encyclopediaArticle` 先前**不在表內**，落 fallback `.webpage`。
        //
        // 那不是「粗一點」，是**落錯節**：百科條目是 10.3（Entries in Reference
        // Works），而 `.webpage` 是 10.16。10.3 的 source element 是
        // 「In *Title of reference work*」——落到 10.16 之後那個元素在渲染時
        // 根本沒有位置，於是這筆記錄在 `apa7-is-the-work-floor` 的意義下
        // **由構造保證跌破下限**，不是資料缺漏。
        //
        // 另有一個潛伏的回歸：#325 的遷移已把這 14 筆訂為 `wikipedia-entry`
        // （#409 起改名為 `reference-work-entry`），而 `applyBiblatexFields` 每次
        // pull 都會重設 `entry.type`——只要有人跑一次 `import-zotero`，那 14 筆就會
        // 被**降回** `webpage`。表裡缺一列的代價不是「這次沒對映到」，是「上次對的
        // 會被改錯」。
        //
        // **先前這裡有一條「誠實邊界」，#409 把它修掉了。** 它記的是：
        // `.wikipediaEntry` 這個名字對非維基的參考書是過度宣稱，而當時本庫的
        // `encyclopediaArticle` 恰 14 筆、每一個實例都真的是維基，所以「出現非維基
        // 的參考書條目時，該補的是一個更廣的 10.3-entry 型別」。
        //
        // 那個形狀在 #339 出現了（3 筆 SEP 條目），於是 #409 做了那條註解預告的事：
        // 改名成 `referenceWorkEntry`。**那條邊界不再需要，因為它描述的缺陷已經不在。**
        //
        // **但它記的一個零實例事實仍然有效，所以留著**：Zotero 的 `dictionaryEntry`
        // 本庫**零筆**（2026-08-23 重量，#409 verify R2 指名——搬回這句時沒附量測依據，
        // 而 `assertions-must-be-measured` 管的正是這個形狀）：
        //     grep -l dictionaryEntry ~/.akashic/entities/*.yaml | wc -l   # → 0
        // 辭典條目與百科條目在 APA7 同屬 §10.3，但它們是否該共用
        // `.referenceWorkEntry` 這一格，等真的出現實例時再裁（`zero-instance-guards`
        // 的立場：還沒發生的形狀不現在猜）。
        "encyclopediaArticle": .referenceWorkEntry,
    ]

    /// Zotero fieldName → biblatex 欄位名。title/date 由 Entry 一級欄位承接，不進 fields。
    public static let fieldMap: [String: String] = [
        "publicationTitle": "journaltitle",
        "bookTitle": "booktitle",
        "proceedingsTitle": "booktitle",
        // #340：APA7 10.3 的 source element 是「In *Title of reference work*」，
        // 在 `biblatex-apa` 的 `@INREFERENCE` 就是 `BOOKTITLE`。與上面兩列同類
        // ——都是「載體標題」映到 `booktitle`，只是 Zotero 依 itemType 換了名字。
        //
        // 沒有這一列時它會走殘餘路徑、以 `encyclopediatitle` 入庫（#206 起不再
        // 丟棄），**資料在、但 APA7 仍然報缺**——殘餘保住了資訊，沒保住可引用性。
        // 這一列補的正是這段落差。
        "encyclopediaTitle": "booktitle",
        // #340／#359：APA7 10.5 的 template 把 Source 欄寫成「**Conference Name,
        // Location.**」——**會議名稱就是 source element**，在 `@PRESENTATION` 是
        // `EVENTTITLE`。手冊的四個編號例（60–63）無一例外都帶它
        // （`APA7GoldenTests.testEverySection105ExampleCarriesTheConferenceName`）。
        //
        // #359 把「缺 EVENTTITLE 的會議發表跌破下限」記成 known gap 時，量到 25 筆
        // 受影響。**那 25 筆的會議名稱其實一直在 Zotero 裡**（實測 21 筆 presentation
        // 全部帶 `meetingName`），只是走殘餘路徑以 `meetingname` 入庫——
        // 與 `encyclopediaTitle` 完全同型的落差：資訊沒丟，可引用性丟了。
        "meetingName": "eventtitle",
        // 方括號內的類型標籤（手冊：「Include a label in square brackets after the
        // title that matches how the presentation was described at the conference」）。
        // Zotero 的值就是會議自己的描述（`Poster presentation`／`Oral presentation`），
        // 正是手冊要的那個「matches how it was described」。
        "presentationType": "titleaddon",
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
    /// 上游值 → 結構化識別碼清單,三態語意見呼叫處（#394 verify R5 ①）。
    ///
    /// 多值欄位（`issn`／`isbn`）走 `IdentifierMigration` 既有的 tokenizer——它是
    /// 為了同一個形狀（一個字串裡有多個號）寫的,這裡沒有理由再造一個。
    /// 回傳 `parsed`＝**這一輪真的從上游字串解析出東西**。呼叫端用它決定要不要把
    /// 原字串移出 `fields`——問「欄位空不空」會在第三態誤刪（#394 verify R6 ③）。
    static func followUpstream<T: Identifier>(
        _ raw: String?, existing: [T], field: String
    ) -> (values: [T], parsed: Bool) {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ([], false)                           // 上游沒給 → 清空
        }
        // 吸不吸收多值**按欄位種類**,而那個裁決連同它的量測住在 `absorbsMultipleValues`
        // 的 doc 裡（DOI 刻意不吸收——吸收附錄的 DOI 等於一句假的身分宣稱）。這裡引用它,
        // 不複製:兩份會分岔。
        let parsed: [T]
        var anyUnparseable = false
        if IdentifierMigration.absorbsMultipleValues(field: field) {
            // **`.values` 會把 `unparseable` 整個丟掉**（#394 verify R7 ①）。
            // `IdentifierMigration` 對同一個形狀有明文裁決,逐字是:
            //
            //   > 只要有任何一個 bad,就**不移除殘留**——殘留是那些解不了的值唯一的棲身處。
            //
            // R6 借了它的 tokenizer,**沒借這條紀律**。於是「一個 token 解得出、另一個
            // 解不出」時原字串被整個移出 `fields`,解不出的號從 store 徹底消失且零回報。
            let r = IdentifierMigration.normalizedUniqueQualified(
                IdentifierMigration.qualifiedCandidates(raw, field: field), T.init)
            parsed = r.values
            anyUnparseable = !r.unparseable.isEmpty
        } else {
            parsed = T(raw).map { [$0] } ?? []
        }
        // 讀不懂 → 保留既有（**不是**清空），且回報 `parsed: false` 讓呼叫端把原字串
        // 留在 `fields`。R5 的版本只做了前半,於是上游字串被靜默刪除。
        if parsed.isEmpty { return (existing, false) }
        // 部分成功:值進結構化欄位,但 `parsed: false` 讓呼叫端**保留殘留字串**。
        return (parsed, !anyUnparseable)
    }

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
        // **識別碼進結構化欄位，不留 `fields` 殘留**（#425 verify HIGH）。
        //
        // 我修過 add-only 的 `enrich-from-zotero`，而**姊妹路徑 pull 沒修**——
        // 而 pull 是預設的 Zotero 匯入面（新建與更新兩條路徑都走這裡）。殘留一旦
        // 回來，同一個值就有兩份副本可各自漂移，且 `BibExport` 的
        // `if fields["issn"] == nil` venue 拉取會被遮蔽。
        //
        // **解析不出來的不猜**——原值留在 `fields`，交由既有的殘餘路徑（#206）處理。
        // `issn` **刻意不在此處理**：它不屬於 work（spec 明文的 misplacement），
        // 由 `ZoteroImporter` 在拿得到回報通道的地方移除並記進 `fieldsRemovedByPull`。
        // **跟隨上游，兩個方向都跟隨**（#394 verify R4 ④）。
        //
        // 第一版只有 `if let`——於是 Zotero 這次沒給時，`entry.doi` 原封不動。
        // 那既不是 follow（`fields` 是整份替換）也不是 preserve（`venues` 與 `authors`
        // 各有**顯式**的守衛與回報），而且**沒有一行程式碼說那是刻意的**。
        //
        // 後果是過期值安靜留著：使用者在 Zotero 清掉一個掛錯篇的 DOI，重跑 pull 之後
        // store 仍然帶著它，而 `export-bib` 繼續印、`import-wos` 拿它當身分證
        // （`existing(matching:)` 先查 `canonicalDOIs`）。
        //
        // 清掉是**恢復**提升進結構化欄位之前的行為：那時 DOI 住 `fields`，
        // 整份替換本來就會讓它消失，而 `fieldsRemovedByPull` 記得到。
        // 那個回報通道由 `ZoteroImporter` 一併恢復。
        // **狀態有三個，不是兩個**（#394 verify R5 ①——R4 把後兩者折在一起）：
        //
        // | 上游 | 動作 |
        // |---|---|
        // | 沒給 | 清空（跟隨） |
        // | 給了且讀得懂 | 取代（跟隨） |
        // | **給了但讀不懂** | **保留既有值**——那是我們的解析限制,不是上游的意思 |
        //
        // 第三格是 R4 的資料遺失回歸：**Zotero 把多個 ISBN 塞在同一個字串裡**
        // （`978-… 978-…`），而 `ISBN.init` 對它必然回 nil。R4 把那個 nil 讀成
        // 「上游清空了」，於是 `migrate-identifiers` 剛拆出來的號被扔掉。
        // 實測受害者 2 筆（`dweck2000social` 精裝／平裝、`kelley2023sample`）。
        //
        // 多值欄位走 migration 既有的 tokenizer，所以「兩個真的號」讀得出來、
        // 跟隨語意對它們也成立——**而不是只把資料保住**。
        // **問「這次有沒有解析成功」,不是「欄位空不空」**（#394 verify R6 ③）。
        //
        // R5 的版本問後者,而第三態（讀不懂 → 回傳 existing）剛把欄位填回去了——於是
        // 上游那個**讀不懂的原字串被一併刪掉**,與它上方兩行的註解正好相反。
        //
        // 三件事同時成立:資訊損失（且是相對 main 的**回歸**——遷移前 DOI 住 `fields`,
        // 整份替換之後上游字串仍在）、**零回報**（`identifiersBefore/After` 只看「有沒有
        // 變空」,前後都非空 → 不記）、留下的是**過期識別碼**（而識別碼終結指涉,
        // `existing(matching:)` 會拿它認人、`export-bib` 會印它）。
        let d = followUpstream(fields["doi"], existing: entry.doi, field: "doi")
        let p = followUpstream(fields["pmid"], existing: entry.pmid, field: "pmid")
        let i = followUpstream(fields["isbn"], existing: entry.isbn, field: "isbn")
        entry.doi = d.values; entry.pmid = p.values; entry.isbn = i.values
        // 解析得出來的已進結構化欄位——**解析不出的原值留在 `fields`**（不猜，#206）。
        if d.parsed { fields.removeValue(forKey: "doi") }
        if p.parsed { fields.removeValue(forKey: "pmid") }
        if i.parsed { fields.removeValue(forKey: "isbn") }
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
