import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicEntity
import AkashicExport
import AkashicIndex

/// work（`Entry`）的部分更新面（`update-entry`／`akashic_update_entry`）。
///
/// ## `--remove-field`（`remove_fields`，#544）：移除一個 `fields` 的值
///
/// 在此之前**沒有任何面刪得掉一個 `fields` 的值**：`enrich` 只補不存在的鍵、`create-entry` 是建檔、`import-zotero` 整份替換
/// `fields` 但只對 Zotero 來源的記錄有效。實例：21 筆 work 的 `abstract` 是 Crossref 的錯誤頁文字（「This DOI is not currently
/// attached to any metadata records…」），兩筆的 `journaltitle`／`publisher` 裝的是補助計畫名稱與總統令字號——唯一的路是手改 YAML。
///
/// **它是判定**（`two-kinds-of-edits`）：「這段文字不是這篇的摘要」要讀內容才知道，字串謂詞做不出來。所以理由必填。
/// 使用者 2026-09-27 對移除面一族（#588／#572／#586：邊、識別碼、divergence 記錄）的裁決：**理由只進報告**、不寫進 store、不改 store format；
/// 被移除的值住在 git 的移除前副本裡，所以移除前要求那筆 work 檔已 commit、乾淨（`assertRecordsRecoverable`）。
/// **本面把那條裁決延伸到 `fields` 的值——那個延伸是 Claude 代裁、待使用者確認**（b11c R1 verify 更正：原本寫成「照裁決」）。#544 的 body
/// 要的是「留記錄、形狀取自 #450」（work 側 `references` 的退役記錄），沒有做：它要第 15 條邊的值域擴充與 store format 的變更，需要顯式裁決。
///
/// **為什麼這不違反 `lossless-intake`**：那條規則管的是**進來的那一刻**——來源給了什麼就收什麼，不得在匯入時靜默丟棄。
/// 本面管的是事後的更正：一個人讀過值之後判定「這不是來源給這個欄位的資料」（錯誤頁被當成內容收下，本身就是 lossless-intake
/// 要防的反面——收了不是來源給的東西）。它不靜默（理由必填、逐欄回報、值的前段印在報告裡）、也不讓資訊不可回復
/// （移除前的檔在 git 裡），兩者正是那條規則在意的兩件事。
///
/// 契約：
/// - `<鍵>=理由`，鍵是 `fields` 裡**現有**的鍵（逐字）；理由必填、至多 4,096 位元組。同一鍵兩次、鍵不存在、理由空白或過長、
///   一次超過 200 個——整批拒絕、零寫入。
/// - 指向被移除鍵的 `fields.<鍵>` reference 一併移除（#588 `remove_issn` 的同一處置）：留著它，那筆 reference 的語意會從
///   「值出自這份來源」**安靜地翻成**「查過了、這份來源沒給」（#517 的負結果形），而那不是任何人判定過的事。逐鍵回報筆數。
/// - 預設乾跑（`--apply`／`dry_run: false` 才寫）；乾跑不需要 git，實跑才驗。work 無法唯一定位時拒絕（#628／#641）。
///
/// **誠實邊界**：由被移除的值推導出來的 venue 邊不動——那是另一個判定（`resolve-venues --drop-venue`，#572）：literal 邊以
/// `venueEdgesFromRemovedValues` 具名；**已歸戶的 `.key` 邊連同 venue 上的 confirmed verdict 也不動**，以 `venueKeyEdgesFromRemovedValues`
/// 具名（邊本身不記出處，出處只在 venue 的 `work:<citekey> :: <literal>` verdict 上；處置是先 `--demote` 再 `--drop-venue`）。
/// **會把值補回去的路徑有三條**，報告的 `reintroductionNote` 全部點名：`import-wos` 回填（只多不少）、`enrich`（add-only）、
/// Zotero pull（主來源是 Zotero 的記錄，另附 `zoteroNote`：日後 pull 若更新這筆會整份替換 `fields`）——store 不記得這個值被判定過不屬於這裡。
/// 移除 APA7 必要欄位時報告附 `apa7RequiredNowMissing`（`BibExport.apa7Report` 的必要欄位表，只報這次新增的缺漏；`validate` 不報）。
///
/// ## `--add-source`（`add_sources`，#614）：宣告已存的內容是這篇的副本
///
/// store-format §2.4.1 規範 work 以 `akashic.sources` 攜帶 digest 清單，宣告「這些已儲存的內容是本作品的副本」（#223）。
/// 在此之前**沒有任何 CLI 或 MCP 入口寫得進它**：`store-source` 只把位元組與取得記錄存進 `sources/`，`enrich` 的
/// `sourceDigest` 寫的是欄位層級的 reference（值 ← 證據，不是作品 ← 副本），`link` 只管 cites／related。
///
/// **它是落地，不是判定**（`two-kinds-of-edits` 的程式欄）：「這份 PDF 是不是這篇」的判定在上游做——`akashic-fetch-fulltext`
/// 的驗證步驟（頁數、首頁標題、DOI），證據隨 `store-source` 的 note 記在 `sources/index.jsonl`。本面只把已判定的連結寫進記錄。
///
/// 契約：
/// - digest 要合法（`isValidDigest`——空內容的 digest 以 #654 的原句拒絕）、同一次不重複、至多 200 個。
/// - **每個要新加的 digest 都要已經在本機的 `sources/`、而且 index 有它的取得記錄**（`LibraryStore.sourcePresence`；已連過的是 no-op、不檢查——
///   全是已連過的就**不讀 index**）：本機沒有、孤兒 blob、shard 讀不到、blob 的位置不是普通檔（目錄、symlink）、index 讀不到（具名）或壞到判不出來——
///   整批拒絕、零寫入，逐個說原因。
/// - add-only、冪等：已在 `akashic.sources` 的列在 `sourcesAlreadyPresent`，沒有新東西就不寫；新的追加在後，既有的不動。
/// - 走編碼器（`writeEntry`，format ≥ 9 的閘在那裡）；預設乾跑。報告逐個帶 index 的取得記錄（origin、media-type、note…），
///   讓乾跑的人認得出這份內容是什麼。**MCP 面截 20 筆**（`sourcesAddedTotal`／`truncated` 揭露，`sourcesAddedCap`）、CLI 全列。
/// - 不與 `remove_fields` 組合（一個是判定、一個是落地）。
///
/// **誠實邊界**：「必須在本機」只是寫入當下的閘——`sources/` 不進 git，別台 clone 讀到這條連結時內容可能不在
/// （§2.4.1：載入成功、可回報缺席，`akashic validate` 的「本機缺承重存檔」）。**閘不重新雜湊 blob**：位置是普通檔、index 有記錄，
/// 但位元組是不是真的雜湊成那個 digest 沒有驗（`sources/` 被同步或複製時截斷、換掉，這裡看不出來；`auditSourceIndex` 也不雜湊）。
/// 本面沒有移除腿：連錯了目前只能以 git 還原那個 work 檔（本面不要求檔已 commit，連結前先 commit store 才有退路；#677 追蹤移除腿）。
/// **`--remove-zotero-source` 不是它的逆操作**——那條腿移除的是 work 記下的 Zotero 來源（`provenance`／`provenance_additional`），不是 `akashic.sources` 的副本。
///
/// ## `--remove-zotero-source`（`remove_zotero_sources`，#680）：移除 work 記下的 Zotero 來源
///
/// 在此之前活著的 Zotero 來源（主來源或附加來源）**沒有任何移除面**：#610 對「其中一筆記錯了」的處置是「手改 YAML」，#679 對「附加來源沒記
/// `library_id`」的出路也只能是手改。App 的裁決台只處理**已在 Zotero 端刪除**的來源。
///
/// **它是判定**（`two-kinds-of-edits`）：「這個 Zotero 條目不屬於這一筆」要讀內容才知道。移除面一族（#572／#588／#586／#544）的使用者裁決
/// （2026-09-27）：理由必填、**只進報告**、不寫進 store、不改 store format；被移除的來源住在 git 的移除前副本裡，所以實跑要求那筆 work 檔已
/// commit、乾淨（`assertRecordsRecoverable`）。
///
/// 契約：
/// - `<來源鍵>=理由`。來源鍵與跨記錄警告、`ambiguousSourceClaims` 同一種：`<library_id>:<zotero_key>`，沒記 `library_id` 的來源是 `?:<zotero_key>`
///   （`ZoteroSourceClaims.key`，全樹產生它的唯一位置）；`05:K` 與 `5:K` 是同一個來源。每個來源鍵都要在這筆 work 命中至少一處，否則整批拒絕、
///   零寫入（訊息列出這筆現有的來源）；同一來源兩次、形狀錯、理由空白或過長、一次超過 200 個，同樣整批拒絕。
/// - 同一筆 work 的主來源與附加來源恰好是同一個來源時兩處都拿掉（那筆宣稱的是「這個來源」，只拿一處它仍然宣稱）。
/// - **主來源被移除而附加來源仍在：附加來源不升格為主來源**（升格會把書目欄位的改寫權交給另一個 library，與 App 的「與 Zotero 脫鉤」同一條裁決）；
///   沒有主來源、只有附加來源是合法狀態。連結狀態的前後照 `Entry.zoteroLinkState` 的既有定義具名（`zoteroLinkState`）。書目欄位不動。
/// - 預設乾跑；乾跑不需要 git，實跑才驗。work 無法唯一定位時拒絕（#628／#641）。
///
/// **誠實邊界**：被移除的來源若在 Zotero 端仍有那個條目，下一次 `import-zotero` 會為它另建一筆新 entry（沒有 entry 宣稱它了）——報告的
/// `reimportNote` 說出這件事，行為由 `ZoteroSourceRemovalReimportTests` 釘住。要讓那個條目落在另一筆 work 上，那筆要先宣稱這個來源（攣生合併，
/// 或手改 YAML）；本面不做「移到另一筆」。沒有具名逆操作：被移除的來源只在 git 的移除前副本與報告裡。
extension AkashicService {

    /// `--remove-field`（remove_fields）的一筆（只看參數的解析結果，#654 的形）。
    struct RemoveFieldSpec {
        let key: String
        let reason: String
    }

    /// `--remove-zotero-source`（remove_zotero_sources）的一筆（只看參數的解析結果，#654 的形）。`source` 是正規化後的來源鍵
    /// （`ZoteroSourceClaims.key`：`<library_id>:<zotero_key>`，沒記 library_id 的是 `?:<zotero_key>`）。
    struct RemoveZoteroSourceSpec {
        let source: String
        let reason: String
    }

    /// 一次呼叫做的那一件事（三條腿各自單獨呼叫）。
    enum UpdateEntryLeg {
        case removeFields([RemoveFieldSpec])
        case addSources([String])
        case removeZoteroSources([RemoveZoteroSourceSpec])
    }

    /// CLI 的 `validate()` 用（#654 的形）：`update-entry` 只看參數的全部檢查——與服務在讀 store 之前跑的是同一個函式。
    public static func checkUpdateEntryArguments(removeFields: [String]?, addSources: [String]? = nil,
                                                 removeZoteroSources: [String]? = nil) throws {
        _ = try parseUpdateEntryArguments(removeFields: removeFields, addSources: addSources, removeZoteroSources: removeZoteroSources)
    }

    /// 至少要有一件事、三條腿不組合，再交給各自的形狀檢查。**不組合的理由**：`remove_fields` 與 `remove_zotero_sources` 是判定
    /// （理由只進報告、要 git 閘，而被移除的東西不同），`add_sources` 是落地（程式編輯）——`two-kinds-of-edits` 要求兩種寫入分開，
    /// 混在一次呼叫裡報告與閘的語意也跟著混。
    static func parseUpdateEntryArguments(removeFields: [String]?, addSources: [String]?,
                                          removeZoteroSources: [String]? = nil) throws -> UpdateEntryLeg {
        let removals = removeFields ?? [], additions = addSources ?? [], zoteroRemovals = removeZoteroSources ?? []
        let given = [!removals.isEmpty, !additions.isEmpty, !zoteroRemovals.isEmpty].filter { $0 }.count
        guard given > 0 else {
            throw ServiceError.invalid(
                "沒有要做的事：remove_fields（--remove-field）、add_sources（--add-source）或 remove_zotero_sources（--remove-zotero-source）給一個")
        }
        guard given == 1 else {
            throw ServiceError.invalid(
                "remove_fields（--remove-field）、add_sources（--add-source）、remove_zotero_sources（--remove-zotero-source）各自單獨呼叫——"
                + "有的是判定、有的是落地，混在一次呼叫裡會讓報告與 git 閘的語意混在一起；整批拒絕、零寫入")
        }
        if !removals.isEmpty { return .removeFields(try parseRemoveFieldSpecs(removals)) }
        if !additions.isEmpty { return .addSources(try parseAddSources(additions)) }
        return .removeZoteroSources(try parseRemoveZoteroSourceSpecs(zoteroRemovals))
    }

    /// `--remove-zotero-source` 的來源鍵：`<library_id>:<zotero_key>` 或 `?:<zotero_key>`（沒記 library_id 的來源）。library_id 要是 ASCII 數字
    /// （至多 18 位，不溢位）；正規化成 `ZoteroSourceClaims.key` 產生的形（`05:K` 與 `5:K` 是同一個來源）。不合形狀回 nil。
    static func canonicalZoteroSourceKey(_ locator: String) -> String? {
        guard let colon = locator.firstIndex(of: ":") else { return nil }
        let prefix = String(locator[..<colon]), zoteroKey = String(locator[locator.index(after: colon)...])
        guard !zoteroKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if prefix == "?" { return ZoteroSourceClaims.key(libraryID: nil, zoteroKey: zoteroKey) }
        guard (1...18).contains(prefix.count), prefix.allSatisfy({ $0.isASCII && $0.isNumber }), let lid = Int(prefix) else { return nil }
        return ZoteroSourceClaims.key(libraryID: lid, zoteroKey: zoteroKey)
    }

    /// 一次的上限、`<來源鍵>=理由` 的形狀、理由的空白與長度、同一來源兩次（正規化後）。
    static func parseRemoveZoteroSourceSpecs(_ specs: [String]) throws -> [RemoveZoteroSourceSpec] {
        guard specs.count <= Self.maxSpecsPerCall else {
            throw ServiceError.invalid("一次最多移除 \(Self.maxSpecsPerCall) 個 Zotero 來源（這次 \(specs.count) 個）——分次送")   // display-safe-exempt: Self.maxSpecsPerCall 與 specs.count 都是 Int
        }
        var out: [RemoveZoteroSourceSpec] = []
        var seen = Set<String>()
        for raw in specs {
            guard let eq = raw.firstIndex(of: "=") else {
                throw ServiceError.invalid(
                    "remove_zotero_sources「\(displaySafeInvisible(raw, max: 200))」缺少 `=`——格式是 <來源鍵>=理由（來源鍵是 <library_id>:<zotero_key>，"
                    + "沒記 library_id 的來源是 ?:<zotero_key>），理由必填；整批拒絕、零寫入")
            }
            let locator = String(raw[..<eq])
            let reason = String(raw[raw.index(after: eq)...])
            guard let source = Self.canonicalZoteroSourceKey(locator) else {
                throw ServiceError.invalid(
                    "remove_zotero_sources「\(displaySafeInvisible(locator, max: 200))」不是來源鍵——形狀是 <library_id>:<zotero_key>（library_id 是 ASCII 數字）"
                    + "或 ?:<zotero_key>（沒記 library_id 的來源）；先用 get-entry 看這筆的 provenance；整批拒絕、零寫入")
            }
            if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ServiceError.invalid(
                    "remove_zotero_sources「\(displaySafeInvisible(source, max: 200))」的理由是空白——移除是判定，要寫為什麼這個來源不屬於這一筆；報告與 commit 靠它")
            }
            guard reason.utf8.count <= Self.maxStatementBytes else {
                throw ServiceError.invalid(
                    "remove_zotero_sources「\(displaySafeInvisible(source, max: 200))」的理由超過 \(Self.maxStatementBytes) 位元組——精簡它")   // display-safe-exempt: Self.maxStatementBytes 是 Int 常數
            }
            guard seen.insert(source).inserted else {
                throw ServiceError.invalid(
                    "remove_zotero_sources「\(displaySafeInvisible(source, max: 200))」在一次呼叫裡出現兩次——整批拒絕、零寫入")
            }
            out.append(RemoveZoteroSourceSpec(source: source, reason: reason))
        }
        return out
    }

    /// 一次的上限、`<鍵>=理由` 的形狀、理由的空白與長度、同一鍵兩次。
    static func parseRemoveFieldSpecs(_ specs: [String]) throws -> [RemoveFieldSpec] {
        guard specs.count <= Self.maxSpecsPerCall else {
            throw ServiceError.invalid("一次最多移除 \(Self.maxSpecsPerCall) 個欄位（這次 \(specs.count) 個）——分次送")   // display-safe-exempt: Self.maxSpecsPerCall 與 specs.count 都是 Int
        }
        var out: [RemoveFieldSpec] = []
        var seen = Set<String>()
        for raw in specs {
            guard let eq = raw.firstIndex(of: "=") else {
                throw ServiceError.invalid(
                    "remove_fields「\(displaySafeInvisible(raw, max: 200))」缺少 `=`——格式是 <鍵>=理由，理由必填；整批拒絕、零寫入")
            }
            let key = String(raw[..<eq])
            let reason = String(raw[raw.index(after: eq)...])
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ServiceError.invalid("remove_fields「\(displaySafeInvisible(raw, max: 200))」的鍵是空的——`=` 前面要接 fields 的鍵名")
            }
            if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ServiceError.invalid(
                    "remove_fields「\(displaySafeInvisible(key, max: 200))」的理由是空白——移除是判定，要寫為什麼這個值不屬於這個欄位；報告與 commit 靠它")
            }
            guard reason.utf8.count <= Self.maxStatementBytes else {
                throw ServiceError.invalid(
                    "remove_fields「\(displaySafeInvisible(key, max: 200))」的理由超過 \(Self.maxStatementBytes) 位元組——精簡它")   // display-safe-exempt: Self.maxStatementBytes 是 Int 常數
            }
            guard seen.insert(key).inserted else {
                throw ServiceError.invalid(
                    "remove_fields「\(displaySafeInvisible(key, max: 200))」在一次呼叫裡出現兩次——整批拒絕、零寫入")
            }
            out.append(RemoveFieldSpec(key: key, reason: reason))
        }
        return out
    }

    /// `--add-source`（add_sources）的形狀：合法的 digest、同一次不重複、上限。
    static func parseAddSources(_ digests: [String]) throws -> [String] {
        guard digests.count <= Self.maxSpecsPerCall else {
            throw ServiceError.invalid("一次最多宣告 \(Self.maxSpecsPerCall) 份副本（這次 \(digests.count) 份）——分次送")   // display-safe-exempt: Self.maxSpecsPerCall 與 digests.count 都是 Int
        }
        var seen = Set<String>()
        for d in digests {
            if d == ProvenanceReference.emptyContentDigest {
                throw ServiceError.invalid("add_sources：\(ProvenanceReference.emptyContentDigestReason)")   // display-safe-exempt: ProvenanceReference.emptyContentDigestReason 是常量句
            }
            guard ProvenanceReference.isValidDigest(d) else {
                throw ServiceError.invalid(
                    "add_sources「\(displaySafeInvisible(d, max: 120))」不是合法的 digest（sha256: 加 64 個小寫十六進位）"
                    + "——先用 store-source 存檔拿 digest；整批拒絕、零寫入")
            }
            guard seen.insert(d).inserted else {
                throw ServiceError.invalid("add_sources「\(d)」在一次呼叫裡出現兩次——整批拒絕、零寫入")   // display-safe-exempt: d 已過 isValidDigest，只含 sha256: 與小寫十六進位
            }
        }
        return digests
    }

    /// MCP 面 `sourcesAdded` 列幾筆（b11c R1 verify 第 29／31 列）。每個 item 帶 index 的五個第三方字串（至多約 2 KB），一次至多 200 個
    /// digest，輸出進 LLM context、呼叫端無法在收到後丟棄已付的代價——`akashic_enrich` 的 items 與 `verdictsRetired` 的既有形：
    /// 截 20 筆、`sourcesAddedTotal`／`truncated` 揭露。**只有 MCP 面截**：CLI 傳 `sourcesLimit: nil` 全列。
    public static let sourcesAddedCap = 20

    func addEntrySources(citekey: String, digests: [String], dryRun: Bool, sourcesLimit: Int?) throws -> String {
        var entry = try requireEntry(citekey)   // 無法唯一定位（#628／#641）與不存在都在這裡拒絕
        let already = digests.filter { entry.akashic.sources.contains($0) }
        let added = digests.filter { !entry.akashic.sources.contains($0) }
        // 閘守的是寫入：已連過的是 no-op，不要求本機有位元組（別台 clone 上 `sources/` 本來就可能不在，§2.4.1）。
        // **沒有要新加的就不碰 index**（b11c R1 verify 第 4／20／30 列）：`sourcePresence` 一開頭就讀整個 index，index 不可讀時
        // 「全是已連過的」這個 no-op 反而失敗——與文件說的「不檢查」不符。
        let presence = added.isEmpty ? [:] : try store.sourcePresence(digests: added)
        var problems: [String] = []
        for d in added {
            switch presence[d] {
            case .stored?:
                continue
            case .unindexed?:
                problems.append("\(d)：blob 在、sources/index.jsonl 沒有它的取得記錄（孤兒 blob）——用 store-source 對同一份檔再存一次會補上條目")   // display-safe-exempt: d 已過 isValidDigest
            case .unreadable?:
                problems.append("\(d)：所在的 shard 目錄讀不到——讀不到不等於缺席，先修好權限")   // display-safe-exempt: d 已過 isValidDigest
            case .notRegularFile(let kind)?:
                problems.append("\(d)：sources/ 裡它的位置是\(kind)、不是普通檔——內容讀不到，不能宣告為副本；先移走那個位置，再對同一份檔重跑 store-source")   // display-safe-exempt: d 已過 isValidDigest；kind 是 SourceStore 的三個固定字串
            case .absent?, nil:
                problems.append("\(d)：本機沒有這份存檔——新內容先用 store-source 存；sources/ 不進 git，換機器後要重新取得")   // display-safe-exempt: d 已過 isValidDigest
            }
        }
        guard problems.isEmpty else {
            throw ServiceError.invalid(
                "add_sources 有 \(problems.count) 個 digest 不能宣告為副本——"   // display-safe-exempt: Int
                + problems.joined(separator: "；") + "。整批拒絕、零寫入")   // display-safe-exempt: problems 的每一項只含已過 isValidDigest 的 digest 與固定句
        }
        if !added.isEmpty {
            entry.akashic.sources.append(contentsOf: added)
            // 寫入前的檢查兩種模式都跑（唯讀）：乾跑說「可以」時，實跑不會在內容閘（format ≥ 9 等）上才被拒
            try store.preflightWrite(entry)
            if !dryRun {
                try store.writeEntry(entry)
                try LibraryIndex(store: store).rebuild()
            }
        }
        let shown = sourcesLimit.map { Array(added.prefix($0)) } ?? added
        var payload: [String: Any] = [
            "citekey": displaySafe(citekey, max: 200),
            "dryRun": dryRun,   // display-safe-exempt: Bool
            "sourcesAddedTotal": added.count,   // display-safe-exempt: Int
            "truncated": shown.count < added.count,   // display-safe-exempt: Bool
            "sourcesAdded": shown.map { d -> [String: Any] in
                var item: [String: Any] = ["digest": d]   // display-safe-exempt: d 已過 isValidDigest；其餘欄位是 index.jsonl 的字串，下面逐一消毒
                if case .stored(let e)? = presence[d] {
                    for (from, to, cap) in [("media-type", "mediaType", 200), ("retrieved", "retrieved", 200),
                                            ("origin", "origin", 800), ("acquisition", "acquisition", 200),
                                            ("note", "note", 800)] {
                        if let v = e[from] { item[to] = displaySafe(v, max: cap) }
                    }
                }
                return item
            },
            "sourcesAlreadyPresent": already,   // display-safe-exempt: 已過 isValidDigest
            "sourcesTotal": entry.akashic.sources.count,   // display-safe-exempt: Int
        ]
        if dryRun {
            payload["dryRunNote"] = "乾跑：沒有寫入。實跑（CLI --apply、MCP dry_run:false）才寫"
        }
        return try jsonString(payload)
    }

    /// 報告裡被移除的值只印前段（值本身在 git 的移除前副本裡；報告要的是讓人認得出是哪一段）。
    static let removedValuePreviewScalars = 300

    /// `update-entry`／`akashic_update_entry` 的入口：只看參數的檢查在讀 store 之前（#654 的形），再分派到那一條腿。
    /// `sourcesLimit`：`add_sources` 的報告列幾筆。預設是 MCP 面的上限（`sourcesAddedCap`），CLI 傳 nil 全列（`sourcesAddedCap` 的 doc）。
    public func updateEntry(citekey: String, removeFields: [String]?, addSources: [String]? = nil,
                            removeZoteroSources: [String]? = nil, dryRun: Bool,
                            sourcesLimit: Int? = AkashicService.sourcesAddedCap) throws -> String {
        switch try Self.parseUpdateEntryArguments(removeFields: removeFields, addSources: addSources, removeZoteroSources: removeZoteroSources) {
        case .removeFields(let specs): return try removeEntryFields(citekey: citekey, specs: specs, dryRun: dryRun)
        case .addSources(let digests): return try addEntrySources(citekey: citekey, digests: digests, dryRun: dryRun, sourcesLimit: sourcesLimit)
        case .removeZoteroSources(let specs): return try removeEntryZoteroSources(citekey: citekey, specs: specs, dryRun: dryRun)
        }
    }

    /// MCP 面 `zoteroSourcesRemaining` 列幾筆（一筆 entry 的來源數不受本工具限制，手改的 store 可以有很多個附加來源）。
    static let zoteroSourcesRemainingCap = 20

    private static func linkStateName(_ state: ZoteroLinkState) -> String {
        switch state {
        case .intact: return "intact"
        case .orphaned: return "orphaned"
        case .additionalSourceOrphaned: return "additionalSourceOrphaned"
        }
    }

    /// `--remove-zotero-source`（remove_zotero_sources，#680）：從一筆 work 拿掉它記下的 Zotero 來源（主來源或附加來源）。
    ///
    /// 見檔頭的契約；這一條腿的形狀：
    /// - `<來源鍵>=理由`，來源鍵是 `<library_id>:<zotero_key>`（沒記 library_id 的來源是 `?:<zotero_key>`，與跨記錄警告、`ambiguousSourceClaims` 同一種鍵）。
    ///   每個來源鍵都要在這筆 work 裡命中至少一處，否則整批拒絕、零寫入（訊息列出這筆現有的來源）。同一筆 work 的主來源與附加來源恰好是
    ///   同一個來源時兩處都拿掉——移除的是「這筆宣稱這個來源」，只拿掉一處它仍然宣稱。
    /// - 主來源被移除而附加來源仍在：**不升格**（升格會把書目欄位的改寫權交給另一個 library，與 App 的「與 Zotero 脫鉤」同一條裁決）；
    ///   沒有主來源、只有附加來源是合法狀態。連結狀態的變化照 `Entry.zoteroLinkState` 的既有定義具名（`zoteroLinkState.before／after`）。
    /// - 判定：理由必填、只進報告；實跑要求 work 檔已 commit 且乾淨（被移除的來源只剩 git 裡那一份）。預設乾跑，乾跑不需要 git。
    func removeEntryZoteroSources(citekey: String, specs: [RemoveZoteroSourceSpec], dryRun: Bool) throws -> String {
        var entry = try requireEntry(citekey)   // 無法唯一定位（#628／#641）與不存在都在這裡拒絕
        let stateBefore = entry.zoteroLinkState
        let present = ZoteroSourceClaims.sources(of: entry)
        let label = "work「\(displaySafeInvisible(citekey, max: 200))」"
        guard !present.isEmpty else {
            throw ServiceError.invalid("\(label)沒有任何 Zotero 來源——沒有東西可移除；整批拒絕、零寫入")   // display-safe-exempt: label 已含 displaySafeInvisible(citekey)
        }
        let presentKeys = Set(present.map(\.key))
        for s in specs where !presentKeys.contains(s.source) {
            let current = present.prefix(10).map { displaySafeInvisible($0.key, max: 200) }.joined(separator: "、")
            throw ServiceError.invalid(
                "\(label)沒有來源「\(displaySafeInvisible(s.source, max: 200))」——這筆現有的來源：\(current)"   // display-safe-exempt: label 與 current 的每一項都已 displaySafeInvisible
                + (present.count > 10 ? "…共 \(present.count) 個" : "")   // display-safe-exempt: Int
                + "。library_id 要與來源記的相符（沒記的用 ?:）；整批拒絕、零寫入")
        }
        let reasonByKey = Dictionary(specs.map { ($0.source, $0.reason) }, uniquingKeysWith: { first, _ in first })
        var removed: [[String: Any]] = []
        var removedPrimary = false
        var anyLive = false
        var dropAdditional = Set<Int>()
        for s in present {
            guard let given = reasonByKey[s.key] else { continue }
            let provenance: Provenance
            let role: String
            switch s.role {
            case .primary:
                guard let p = entry.provenance else { continue }
                provenance = p; role = "primary"; removedPrimary = true
            case .additional(let i):
                provenance = entry.additionalProvenance[i]; role = "additional"; dropAdditional.insert(i)
            }
            if provenance.orphanedAt == nil { anyLive = true }
            removed.append([
                "source": displaySafeInvisible(s.key, max: 200),
                "role": role,
                "orphaned": provenance.orphanedAt != nil,   // display-safe-exempt: Bool
                "zoteroVersion": provenance.zoteroVersion,   // display-safe-exempt: Int
                // 理由不進 store，報告是它唯一的一份——不截在入口上限之下（#588 R1 verify 的同一條）
                "reason": displaySafe(given, max: Self.maxStatementBytes),   // display-safe-exempt: given 是呼叫端原文、在這裡消毒一次
            ])
        }
        if removedPrimary { entry.provenance = nil }
        if !dropAdditional.isEmpty {
            entry.additionalProvenance = entry.additionalProvenance.enumerated().filter { !dropAdditional.contains($0.offset) }.map(\.element)
        }

        // 寫入前的檢查兩種模式都跑（唯讀）：乾跑說「可以」時，實跑不會在內容閘上才被拒
        try store.preflightWrite(entry)
        if !dryRun {
            try assertRecordsRecoverable([(entry.id, label)],
                                         action: "這次會從 \(label)移除 \(removed.count) 個 Zotero 來源",   // display-safe-exempt: removed.count 是 Int
                                         issue: "#680")
            try store.writeEntry(entry)
            try LibraryIndex(store: store).rebuild()
        }

        let remaining = ZoteroSourceClaims.sources(of: entry)
        var payload: [String: Any] = [
            "citekey": displaySafe(citekey, max: 200),
            "dryRun": dryRun,   // display-safe-exempt: Bool
            "zoteroSourceRemovals": removed,
            "zoteroLinkState": ["before": Self.linkStateName(stateBefore), "after": Self.linkStateName(entry.zoteroLinkState)],
            "zoteroSourcesRemaining": remaining.prefix(Self.zoteroSourcesRemainingCap).map { s -> String in
                var orphaned = false
                switch s.role {
                case .primary: orphaned = entry.provenance?.orphanedAt != nil
                case .additional(let i): orphaned = entry.additionalProvenance[i].orphanedAt != nil
                }
                let role: String
                if case .primary = s.role { role = "primary" } else { role = "additional" }
                return "\(role) \(displaySafeInvisible(s.key, max: 200))" + (orphaned ? "（已刪除）" : "")   // display-safe-exempt: role 是兩個固定字串；key 已消毒
            },
            "zoteroSourcesRemainingTotal": remaining.count,   // display-safe-exempt: Int
            "reasonNote": "理由只在這份報告裡——要留在 git，寫進接下來的 commit message（#680，使用者 2026-09-27 對移除面一族的裁決）",
        ]
        if dryRun {
            payload["dryRunNote"] = "乾跑：沒有寫入。實跑（CLI --apply、MCP dry_run:false）要求這筆 work 的檔已在 git 裡 commit、乾淨"
        }
        if removedPrimary && !entry.additionalProvenance.isEmpty {
            payload["primaryRemovedNote"] = "主來源已移除；剩下的附加來源不升格為主來源——升格會把書目欄位的改寫權交給另一個 library"
                + "（與 App 的「與 Zotero 脫鉤」同一條裁決）。這筆的書目欄位之後不再被任何 Zotero 條目改寫"
        }
        if anyLive {
            payload["reimportNote"] = "被移除的來源若在 Zotero 端仍有那個條目，下一次 import-zotero 會為它另建一筆新 entry（已沒有任何 entry 宣稱它）；"
                + "要讓它落在另一筆 work 上，那筆要先宣稱這個來源（攣生合併，或手改 YAML）"
        }
        return try jsonString(payload)
    }

    func removeEntryFields(citekey: String, specs: [RemoveFieldSpec], dryRun: Bool) throws -> String {
        var entry = try requireEntry(citekey)   // 無法唯一定位（#628／#641）與不存在都在這裡拒絕
        let before = entry
        for s in specs where entry.fields[s.key] == nil {
            throw ServiceError.invalid(
                "work「\(displaySafeInvisible(citekey, max: 200))」的 fields 沒有鍵「\(displaySafeInvisible(s.key, max: 200))」"
                + "——鍵要逐字相符（先用 get-entry 看）；整批拒絕、零寫入")
        }

        var removed: [[String: Any]] = []
        var referencesRemoved: [String: Int] = [:]
        for s in specs {
            let value = entry.fields.removeValue(forKey: s.key) ?? ""
            let refField = ProvenanceReference.workFieldPrefix + s.key
            entry.references.removeAll { r in
                guard r.field == refField else { return false }
                referencesRemoved[s.key, default: 0] += 1
                return true
            }
            removed.append([
                "field": displaySafe(s.key, max: 200),
                "value": displaySafe(value, max: Self.removedValuePreviewScalars),
                "valueBytes": value.utf8.count,   // display-safe-exempt: Int
                // 理由不進 store，報告是它唯一的一份——不截在入口上限之下（#588 R1 verify 的同一條）
                "reason": displaySafe(s.reason, max: Self.maxStatementBytes),   // display-safe-exempt: reason 是呼叫端原文、在這裡消毒一次
                "referencesRemoved": referencesRemoved[s.key] ?? 0,   // display-safe-exempt: referencesRemoved[s.key] 是 Int
            ])
        }

        // 寫入前的檢查兩種模式都跑（唯讀）：乾跑說「可以」時，實跑不會在內容閘上才被拒
        try store.preflightWrite(entry)
        // 下面兩個提醒（已歸戶的 venue 邊、APA7 必要欄位）都要讀整個 store；在寫入**之前**算——乾跑也要看得到，且寫入不改 venue 與 people
        let load = try store.load()
        let keyEdges = Self.venueKeyEdgesFromRemovedValues(before: before, after: entry, venues: load.venues)
        let apa7Missing = Self.apa7RequiredNowMissing(before: before, after: entry, load: load)
        if !dryRun {
            try assertRecordsRecoverable([(entry.id, "work「\(displaySafeInvisible(citekey, max: 200))」")],
                                         action: "這次會從 work「\(displaySafeInvisible(citekey, max: 200))」移除 \(specs.count) 個欄位",   // display-safe-exempt: specs.count 是 Int
                                         issue: "#544")
            try store.writeEntry(entry)
            try LibraryIndex(store: store).rebuild()
        }

        var payload: [String: Any] = [
            "citekey": displaySafe(citekey, max: 200),
            "dryRun": dryRun,   // display-safe-exempt: Bool
            "fieldRemovals": removed,
            "reasonNote": "理由只在這份報告裡——要留在 git，寫進接下來的 commit message（#544，使用者 2026-09-27 對移除面一族的裁決）",
        ]
        if dryRun {
            payload["dryRunNote"] = "乾跑：沒有寫入。實跑（CLI --apply、MCP dry_run:false）要求這筆 work 的檔已在 git 裡 commit、乾淨"
        }
        let orphaned = Self.venueEdgesFromRemovedValues(before: before, after: entry)
        if !orphaned.isEmpty {
            payload["venueEdgesFromRemovedValues"] = orphaned
        }
        if !keyEdges.isEmpty {
            payload["venueKeyEdgesFromRemovedValues"] = keyEdges
        }
        if !orphaned.isEmpty || !keyEdges.isEmpty {
            payload["venueEdgesNote"] = "這些 venue 邊是由被移除的值推導出來的，本面不動它們。literal 邊要刪用 resolve-venues --drop-venue（MCP drop_venue，#572）；"
                + "已歸戶的 key 邊（venueKeyEdgesFromRemovedValues）連同 venue 上的 confirmed verdict 一起留著、歸屬仍然有效——"
                + "先用 resolve-venues --demote（MCP demote）把邊退回 literal（verdict 隨之處理），再用 --drop-venue 刪。"
                + "欄位移除之後 migrate-venues 不會再推導出新的邊"
        }
        if !apa7Missing.isEmpty {
            payload["apa7RequiredNowMissing"] = apa7Missing
            payload["apa7Note"] = "這次移除讓這筆缺 APA7 必要欄位：export-bib 會對它印 ERROR，而 validate 不報（apa7-is-the-work-floor 的下限）。"
                + "確認移除是有意的，或補上正確的值（enrich 補不存在的鍵）"
        }
        // 移除是在 store 裡刪一個值；下面三條路徑都會在同一個鍵缺席時把值補回來，而 store 裡沒有任何東西記得「這個值被判定過不屬於這裡」
        payload["reintroductionNote"] = "被移除的值可能被三條路徑補回來：import-wos 回填（只多不少，缺席的鍵會被補進去）、enrich（add-only）、"
            + "Zotero pull（主來源是 Zotero 的記錄；整份替換 fields）。store 不記得這個值被判定過不屬於這裡——重跑同一份來源它就回來；"
            + "要擋住，改來源或下次別補這個鍵（#544；#676 討論的是核心層要不要偵測 Crossref 錯誤頁樣板）"
        if entry.provenance != nil {
            payload["zoteroNote"] = "這筆的主來源是 Zotero：日後 pull 若更新這筆（Zotero 端有改、或對映演進）會整份替換 fields、"
                + "把被移除的值帶回來——在 Zotero 那邊一併改掉"
        }
        return try jsonString(payload)
    }

    /// 被移除的值曾經推導出、現在推導不出的 literal（`before` 有而 `after` 沒有）。
    private static func removedDerivedLiterals(before: Entry, after: Entry) -> Set<String> {
        let still = Set(VenueDerivation.literals(for: after).compactMap { ref -> String? in
            if case .literal(let s) = ref { return s }
            return nil
        })
        return Set(VenueDerivation.literals(for: before).compactMap { ref -> String? in
            if case .literal(let s) = ref, !still.contains(s) { return s }
            return nil
        })
    }

    /// 移除之後，本 work 仍掛著的**已歸戶**（`.key`）venue 邊，而那個 venue 上有 confirmed verdict 的 literal 就是被移除的值（正規化後相等）——
    /// 也就是這條邊當初是從那個值歸戶來的（b11c R1 verify 第 23／35 列）。歸戶時 `resolve-venues apply` 把 `work:<citekey> :: <literal>` 寫在 venue 上，
    /// 所以那是**唯一**看得出邊的出處的地方；邊本身不記出處。只列，不動。
    static func venueKeyEdgesFromRemovedValues(before: Entry, after: Entry, venues: [Venue]) -> [String] {
        let gone = Set(removedDerivedLiterals(before: before, after: after).map { NameNormalization.matchingKey($0) })
        guard !gone.isEmpty else { return [] }
        // #669：重複的 venue key 留第一筆，不 trap
        let byKey = Dictionary(venues.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var out: [String] = []
        for (i, ref) in after.venues.enumerated() {
            guard case .key(let k) = ref, let venue = byKey[k] else { continue }
            let literals = ResolutionLedger.verdicts(references: venue.references).verdicts
                .filter { $0.kind == .confirmed && $0.holderKind == .work && $0.holder == after.citekey
                          && gone.contains(NameNormalization.matchingKey($0.literal)) }
                .map(\.literal)
            for lit in literals {
                out.append("\(displaySafe(after.citekey, max: 200)):\(i) key:\(displaySafe(k, max: 200)) literal:\(displaySafe(lit, max: 300))")   // display-safe-exempt: i 是 Int
            }
        }
        return out
    }

    /// 這次移除讓這筆**新增**缺哪些 APA7 必要欄位（欄位名，已排序）。用 `BibExport.apa7Report`——既有的必要欄位表，不另立第二份；
    /// 只算移除**前**沒缺、移除**後**缺的（移除前就缺的——例如沒有作者——不是這次造成的）。
    static func apa7RequiredNowMissing(before: Entry, after: Entry, load: LibraryLoad) -> [String] {
        func missing(_ e: Entry) -> Set<String> {
            let report = BibExport.apa7Report(entries: [e], people: load.people, organizations: load.organizations, venues: load.venues)
            let prefix = "Missing required field: "
            return Set(report.issues.filter { $0.severity == .error && $0.message.hasPrefix(prefix) }.map { String($0.message.dropFirst(prefix.count)) })
        }
        return missing(after).subtracting(missing(before)).sorted()
    }

    /// 移除之後不再能由 `fields` 推導出來、而本 work 仍掛著的 literal venue 邊（index 與字面；已消毒）。
    static func venueEdgesFromRemovedValues(before: Entry, after: Entry) -> [String] {
        let gone = removedDerivedLiterals(before: before, after: after)
        guard !gone.isEmpty else { return [] }
        return after.venues.enumerated().compactMap { i, ref in
            guard case .literal(let s) = ref, gone.contains(s) else { return nil }
            return "\(displaySafe(after.citekey, max: 200)):\(i) literal:\(displaySafe(s, max: 300))"   // display-safe-exempt: i 是 Int
        }
    }
}
