import Foundation

/// 欄位層級的 provenance reference（#66）。
///
/// 一筆 reference 同時回答兩個問題：**怎麼取得的**（URL、擷取日期、HTTP 狀態——
/// 路徑）與**取得了什麼**（SHA-256 定址的位元組——內容）。只有 URL 不構成
/// provenance：實測兩個 host 回相同位元組、第三個 404——URL 是通往內容的路徑，
/// 不是內容本身（design Context）。
///
/// **兩種 reference 在建構層即互斥**（D6）：擷取型與判斷型的驗證條件不同，混在
/// 一起會讓「這筆 provenance 完不完整」無法機械判定。Swift 側用 enum——判斷型
/// 帶 `content` 在型別上**不可能**；YAML 側的平面欄位經 `init(field:...)` 的
/// throwing 建構器驗證，混合即拒。
/// 帶欄位層級 provenance 的記錄（#394 verify）。
///
/// 四個型別各自有 `references`，而在此之前**沒有共同抽象**——於是任何「對所有帶
/// reference 的記錄做同一件事」的邏輯只能逐型別複製，或者退化成空殼。
/// `IdentifierMigration.rewritingProvenance` 曾經是後者。
public protocol ProvenanceCarrying {
    var references: [ProvenanceReference] { get set }
}

public struct ProvenanceReference: Equatable {

    /// #232：resolution verdict 欄位的**封閉對**——僅此二值，不得類推第三個。
    /// init 的空 restsOn 例外、person／organization 的 validateReferenceAttachment、
    /// ResolutionLedger 四處都引這一個列舉（單一來源，不留漂移面）。
    public static let resolutionVerdictFields: Set<String> = [
        "resolution-confirmed", "resolution-rejected",
    ]

    /// #450：**一階人為裁決**的欄位集合——judgement 的空 rests-on 只對這些放行（#232 D8 的例外
    /// 一般化）。＝ `resolutionVerdictFields ∪ {authors}`：拆分同樣是一階裁決，原文逐字保存於 value
    /// 就是證據。**第二個具名集合，不把 `authors` 塞進上面那個**——上面那個被三處當 verdict 文法
    /// （`<kind>:<key> :: <literal>`）解析：`ResolutionLedger.verdicts`、死 verdict 掃描、demote 的
    /// 逐字取回。塞進去會讓它們對拆分記錄解析失敗或誤判；拆分記錄的 statement 走 `SplitRecordValue`。
    public static let firstOrderRulingFields: Set<String> = resolutionVerdictFields.union(["authors"])

    /// work 的**非識別碼欄位**（`Entry.fields` 的鍵）在 reference 上的命名空間前綴（#517）。
    ///
    /// **為什麼要前綴，而不是直接用鍵名。** `Entry.fields` 是 `[String: String]`，鍵由來源決定
    /// （`lossless-intake`：來源給什麼就收什麼），所以它**必然**會與 reference 已保留的欄位名撞上
    /// ——2026-09-09 實測 live store：`fields` 有 40 種鍵，其中 **`doi` 3 筆、`isbn` 3 筆**與保留字
    /// 同名。裸鍵名之下，`field: doi` 到底指結構化的 `entry.doi` 清單還是 `fields["doi"]`，
    /// **今天就已經是歧義**。
    ///
    /// 前綴讓那個歧義在文法上寫不出來（`entity-backlink-completeness` 引 3.325 的同一個立場），
    /// 而不是靠一份「哪些鍵不准用」的白名單——那種白名單會漏，本 repo 已經記過兩次
    /// （`PATH_ROOTS`、`trigger-coverage` 的 `DATA`）。
    public static let workFieldPrefix = "fields."

    /// #232 verify（DA）：verdict `value` 的**單一文法**——`<kind>:<key> :: <literal>`。
    ///
    /// kind token **必填**且**兩族統一**：person 與 organization 的 key 可合法同名
    /// （#166），沒有 kind，一筆 org 側否決會連帶抑制同名 person 的配對；而「person
    /// 族免 token、靠掛載記錄推斷」是兩套文法靠脈絡區辨——D3 已自認過的
    /// grammar-in-string 漂移，不再開第二個。文法住 AkashicCore：store 閘
    /// （`validateReferenceAttachment`）與 `ResolutionLedger` 共用**同一個**解析器。
    public enum VerdictHolderKind: String, CaseIterable, Sendable {
        case work      // entry citekey（person-resolution 的 holder）
        case person    // 持有 affiliations literal 的 person key（org-resolution）
        case org       // 持有 parents literal 的 organization key（org-resolution）
    }

    /// 解析後的配對定位。encode／parse 是彼此的反函數；holder key 受 StoreKey
    /// 約束（`[a-z0-9-]`，無 `:`、無空白），literal 任意（含 ` :: ` 也能 round-trip
    /// ——切分一律取**第一個**分隔）。
    /// verdict 的證據類別名。**字面住在這裡**（#468）：`ResolutionLedger` 以既有名字
    /// 引用它們，而收攏政策（`AkashicStoreIO`）也要判斷「這條是不是完全命中」，
    /// 兩個 module 之間沒有依賴。字面只有一份，`ResolutionLedger.personRule` 是引用不是副本。
    public enum RuleName {
        public static let personExact = "author-name-exact"
        public static let orgExact = "org-name-exact"
        public static let venueExact = "venue-name-exact"
        public static let judgedPerWork = "author-judged-per-work"
        /// 三族的「完全命中」。**弱血統的判準是「不是這些」**——與
        /// `PersonResolver` 的 `rules.filter { $0 != personRule }` 同一個謂詞
        /// （那裡只比 person 族，因為它只處理 person 提名）。
        public static let exact: Set<String> = [personExact, orgExact, venueExact]
    }

    /// verdict statement 尾註 `[rule: <name>]` 的 tolerant 解析——缺席回 nil。
    /// **單一定義**：`ResolutionLedger.ruleTail` 與收攏政策共用這一份。
    public static func ruleTail(ofStatement statement: String) -> String? {
        guard statement.hasSuffix("]"),
              let open = statement.range(of: "[rule: ", options: .backwards) else { return nil }
        let inner = statement[open.upperBound..<statement.index(before: statement.endIndex)]
        let trimmed = inner.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// **verdict 相等的單一定義**（#470）。
    ///
    /// 在此之前寫入面與讀取面各有一個：寫入面（merge 的 `dedupKey`、rename 兩處 `seen`、
    /// `ResolutionLedger.appendIfAbsent`）比 `value` 的**原字串**；讀取面
    /// （`PersonResolver` 的 `rejectedNorm`）比 `NameNormalization.matchingKey(literal)`。
    /// 於是 `work:k :: Fann, C.` 與 `work:k :: Fann,  C.` 在寫入面是兩筆、讀取面是同一筆
    /// ——「store 永不持有重複 verdict」在**讀取面的意義上**已經被違反。
    ///
    /// **裁決：相等取正規化的那一個**，理由是 verdict 的用途本身：它抑制的是「這個
    /// (holder, literal) 配對已經判過了」，而提名層一路都用正規化比對
    /// （`LooseNameKey`／`PersonResolver.normalize`）。若寫入面比位元組，一個正規化後
    /// 等價的重複就會累積，而讀取面看到的是同一個配對有兩筆判定。
    ///
    /// **正規化只住在鍵裡，不外洩成資料**——`value` 仍逐字存原字串，`demote`（#418）
    /// 因此仍取得回原本那個 literal。這句話不是本輪發明的：它逐字寫在
    /// `PersonResolver.normalize` 的 doc 上，本輪只是把它套到另一面。
    ///
    /// 非 verdict 欄位或文法不合的 value 回退到原字串——它們不在這條不變式的轄下，
    /// 而把它們正規化會擴大 dedup 的作用面（`migratedVerdicts` 的既有立場：非 verdict
    /// 的 reference 原樣通過、不 dedup）。
    ///
    /// **2026-09-09 實測 live store：2,700 筆 verdict，正規化後重複而位元組不同的組 0**
    /// ——所以這次統一不改變任何既有資料。量測腳本見 #470。
    public static func verdictEqualityKey(field: String, value: String?) -> String {
        guard resolutionVerdictFields.contains(field),
              let v = value,
              let p = VerdictPairingValue.parse(v) else {
            // 回退鍵帶一個合法配對鍵寫不出的前綴（U+0001；合法鍵的第二段以 `VerdictHolderKind.rawValue` 的字母開頭）——
            // 一個字面帶 U+0000 的 malformed value 否則能拼出與合法配對相同的鍵（#554 R14 verify security 第 28 列；
            // YAML reader 擋得住 U+0000，但鍵的形狀不該靠別處的 reader 撐）。**value 缺席與空字串是兩把鍵**（R25；R24 verify
            // logic 第 25 列：`byteExactKey` 用 presence tag 分開了，這裡沒跟上——#517 以「value 缺席」表達「查過了、沒有」）。
            return "\(field)\u{0}\u{1}malformed\u{0}" + (value.map { "\u{1}" + $0 } ?? "\u{2}absent")
        }
        return "\(field)\u{0}\(p.holderKind.rawValue):\(p.holder)\u{0}"
             + NameNormalization.matchingKey(p.literal)
    }

    public struct VerdictPairingValue: Equatable, Sendable {
        public let holderKind: VerdictHolderKind
        public let holder: String
        public let literal: String

        public init(holderKind: VerdictHolderKind, holder: String, literal: String) {
            self.holderKind = holderKind
            self.holder = holder
            self.literal = literal
        }

        public var encoded: String { "\(holderKind.rawValue):\(holder) :: \(literal)" }

        /// 回 nil＝malformed——呼叫端必須 loud（store 閘拒收、ledger 進 malformed）。
        /// kind token 缺席**不是**舊格式（verdict 欄位對自 #232 才存在，沒有舊資料）
        /// ——不設回退（no-compat-fallback）。
        public static func parse(_ value: String) -> VerdictPairingValue? {
            guard let sep = value.range(of: " :: ") else { return nil }
            let holderToken = String(value[..<sep.lowerBound])
            guard let colon = holderToken.firstIndex(of: ":"),
                  let kind = VerdictHolderKind(rawValue: String(holderToken[..<colon]))
            else { return nil }
            let holder = String(holderToken[holderToken.index(after: colon)...])
            // holder 過 StoreKey 文法（R2-fix，logic N6 的根修）：holder 恆為
            // citekey／entity key，兩者都受 StoreKey 約束——不驗的話，含 `|` 等
            // 任意字元的 holder 會流進下游以複合字串鍵做的比對（resolver 的
            // rejectedNorm）。在唯一解析點擋掉，比在每個消費端防禦便宜。
            guard StoreKey.isValid(holder) else { return nil }
            return VerdictPairingValue(holderKind: kind, holder: holder,
                                       literal: String(value[sep.upperBound...]))
        }
    }

    /// 擷取型 vs 判斷型——互斥的兩種（D6）。
    public enum Kind: Equatable {
        /// 單次擷取：路徑 + 內容。`content` 是 `sha256:` 前綴的 digest。
        /// `status` 一併記錄：錯誤頁面同樣有 digest（「死」本身也是內容，D3）——
        /// 200 不代表活著（實測有 200 + 122 bytes meta-refresh 的偽裝）。
        case retrieval(url: String, retrieved: String, status: Int,
                       mediaType: String?, content: String)
        /// 對多份證據的推理：斷言 + 所依據的 digest 清單。沒有自己的 URL、
        /// 沒有自己的位元組。
        case judgement(statement: String, restsOn: [String])
    }

    /// 這筆 reference 支持哪個欄位（D1：清單住頂層、每筆自報欄位）。
    public var field: String
    /// 欄位是 collection 時以**值**定位（D2：索引在重排時失效）。
    public var value: String?
    public var kind: Kind

    /// **位元組精確的相等鍵**（#554 R24，D65；R23 verify Codex 第 1 列 HIGH）。
    ///
    /// 「兩筆 reference 完全相同」在本 repo 的意思是**逐位元組相同**——四個問「兩筆是不是同一筆」的地方都以它為判準（R25 D69 補齊
    /// 後三個，R24 verify 第 9／26／29 列：R24 只換了前兩個、doc 卻宣稱全 repo）：D62 的 rename 折疊（`migratedVerdicts`）、D64 的
    /// 「全部完全相同」（`duplicateVerdictRecordIssues`，判 kind 那一半用 `kindByteKey`）、合併的遺失偵測（`fieldsLostByMerging` 的
    /// person／work 兩份——canonical `==` 曾讓被併記錄的 NFD 拼法被判成「倖存者已有」、隨檔案消失而報告說沒遺失）、`paginated` 寫入面的
    /// 冪等閘（`updateVenue`——只差 NFC／NFD 的 judgement 曾被靜默吞掉）。
    /// 因為零資訊損失的承諾是對 store 裡的位元組說的，不是對 Unicode 的等價類說的。Swift `String` 的 `==` 與 `hashValue` 走
    /// canonical equivalence（NFC 的 `Sankhyā` 與 NFD 的 `Sankhya\u{0304}` 相等），合成的 `Hashable` 繼承同一語意——R23 用它當
    /// 字典鍵，NFC／NFD 兩筆被折成一筆、其中一種拼法永久消失，而 R16（D42）已經在第二半掃描上修過同一個缺陷（`Set<[UInt8]>`）。
    /// 所以本型別**刻意不合成 `Hashable`**：要拿它當鍵，只有這一把。
    ///
    /// 形狀是 `[[UInt8]]`：每個欄位自成一個位元組陣列，nil 與空字串靠 tag 元素分開、`Kind` 的兩個 case 靠 tag 元素分開、
    /// `restsOn` 的每一段各占一格——沒有分隔符可以被內容撞上。`Equatable` 仍是 Swift 的（canonical）：兩者不同是刻意的，
    /// `==` 給「這兩筆說的是同一件事」的讀者，`byteExactKey` 給「這兩筆可以只留一筆而不丟任何位元組」的寫入面。
    public var byteExactKey: [[UInt8]] {
        var parts: [[UInt8]] = [Array(field.utf8)]
        if let v = value { parts.append([1]); parts.append(Array(v.utf8)) } else { parts.append([0]) }
        return parts + kindByteKey
    }

    /// `byteExactKey` 的 kind 那一半（tag ＋ payload 逐欄位）——D64 要分開說「literal 拼法只差位元組」與「judgement 或 rests-on
    /// 彼此不同」（R25 D67；R24 verify 第 3／11／16 列：R24 拿整筆 `byteExactKey` 判 sameness，value 的拼法差異也被說成 judgement 衝突，
    /// 操作者會去找一個不存在的證據衝突）。與 `byteExactKey` 同一個 switch，不是第二份描述。
    public var kindByteKey: [[UInt8]] {
        var parts: [[UInt8]] = []
        switch kind {
        case .retrieval(let url, let retrieved, let status, let mediaType, let content):
            parts.append([0])
            parts.append(Array(url.utf8)); parts.append(Array(retrieved.utf8)); parts.append(Array(String(status).utf8))
            if let m = mediaType { parts.append([1]); parts.append(Array(m.utf8)) } else { parts.append([0]) }
            parts.append(Array(content.utf8))
        case .judgement(let statement, let restsOn):
            parts.append([1])
            parts.append(Array(statement.utf8))
            parts.append(Array(String(restsOn.count).utf8))
            for d in restsOn { parts.append(Array(d.utf8)) }
        }
        return parts
    }

    public init(field: String, value: String? = nil, kind: Kind) {
        self.field = field
        self.value = value
        self.kind = kind
    }

    /// digest 的形狀：`sha256:` + 64 個小寫 hex。
    ///
    /// 形狀錯的 digest 永遠 resolve 不到內容——內容定址的根壞了，這筆 reference
    /// 的「內容」半邊就是假的。fail-fast 於寫入/載入，勝過存了一個永遠找不到的指涉。
    public static func isValidDigest(_ s: String) -> Bool {
        let bytes = Array(s.utf8)
        let prefix = Array("sha256:".utf8)
        guard bytes.count == prefix.count + 64,
              bytes.starts(with: prefix) else { return false }
        return bytes.dropFirst(prefix.count).allSatisfy { byte in
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
        }
    }

    /// 從平面欄位建構（YAML decode 的入口）。**驗證住這裡**，decode 只搬運：
    ///
    /// - 擷取側鍵（url/retrieved/status/media-type/content）與判斷側鍵
    ///   （judgement/rests-on）同時在場 → 拒（D6 互斥；「判斷型帶 content」是
    ///   其中最重要的一例——判斷不是擷取，沒有自己的位元組）
    /// - 擷取型四欄皆必要（url/retrieved/status/content）；缺 content 的錯誤
    ///   指名 content——只有 URL 不構成 provenance 正是本 change 要修的病
    /// - 判斷型 judgement 與 rests-on 成對且皆非空——沒有依據的斷言不是判斷
    /// - 兩側皆空 → 拒（不知道這筆是什麼）
    public init(field: String, value: String?,
                url: String?, retrieved: String?, status: Int?, mediaType: String?,
                content: String?, judgement: String?, restsOn: [String]) throws {
        guard !field.isEmpty else {
            throw StoreYAMLError.missingField("reference.field")
        }
        // field 來自 YAML 檔案（未信任）——錯誤訊息一律用消毒後的值（#139 守衛
        // 合併掃描面後照出；行級掃描對跨行 throw 有盲區，所以這裡整批處理）
        let safeField = displaySafe(field, max: 120)
        let hasRetrievalSide = url != nil || retrieved != nil || status != nil
            || mediaType != nil || content != nil
        let hasJudgementSide = judgement != nil || !restsOn.isEmpty

        switch (hasRetrievalSide, hasJudgementSide) {
        case (true, true):
            if content != nil {
                throw StoreYAMLError.invalidField(
                    "reference(field: \(safeField))",
                    "判斷型 reference 不得帶 content——判斷不是擷取，沒有自己的位元組；"
                    + "它依據的內容以 rests-on 指名")
            }
            throw StoreYAMLError.invalidField(
                "reference(field: \(safeField))",
                "擷取型欄位（url/retrieved/status/media-type）與判斷型欄位"
                + "（judgement/rests-on）不得混用——兩種 reference 互斥")
        case (false, false):
            throw StoreYAMLError.invalidField(
                "reference(field: \(safeField))",
                "無法辨識種類：擷取型需要 url/retrieved/status/content，"
                + "判斷型需要 judgement/rests-on，兩側都是空的")
        case (true, false):
            guard let url else { throw StoreYAMLError.missingField("reference(field: \(safeField)).url") }   // display-safe-exempt: safeField 已於本 init 開頭 displaySafe
            guard let retrieved else {
                throw StoreYAMLError.missingField("reference(field: \(safeField)).retrieved")   // display-safe-exempt: safeField 已消毒
            }
            guard let status else {
                throw StoreYAMLError.missingField("reference(field: \(safeField)).status")   // display-safe-exempt: safeField 已消毒
            }
            guard let content else {
                throw StoreYAMLError.missingField(
                    "reference(field: \(safeField)).content——只有 URL 不構成 provenance，"
                    + "內容的 digest 是必要的另一半")
            }
            guard Self.isValidDigest(content) else {
                throw StoreYAMLError.invalidField(
                    "reference(field: \(safeField)).content",
                    "digest 形狀必須是 sha256: + 64 個小寫 hex，實得「\(displaySafe(content, max: 120))」")
            }
            self.init(field: field, value: value,
                      kind: .retrieval(url: url, retrieved: retrieved, status: status,
                                       mediaType: mediaType, content: content))
        case (false, true):
            guard let judgement, !judgement.isEmpty else {
                throw StoreYAMLError.missingField(
                    "reference(field: \(safeField)).judgement——沒有斷言的依據不知道在支持什麼")
            }
            // #232 design D8：verdict 是一階人為裁決、非對既有證據的推理——
            // 僅對封閉欄位對允許空 rests-on（有證據時 SHOULD 附）；其他欄位維持拒收。
            // #450 把「一階裁決」一般化成 `firstOrderRulingFields`（多 `authors` 一格：拆分記錄）。
            guard !restsOn.isEmpty || Self.firstOrderRulingFields.contains(field) else {
                throw StoreYAMLError.missingField(
                    "reference(field: \(safeField)).rests-on——沒有依據的斷言不是判斷")
            }
            for d in restsOn where !Self.isValidDigest(d) {
                throw StoreYAMLError.invalidField(
                    "reference(field: \(safeField)).rests-on",
                    "digest 形狀必須是 sha256: + 64 個小寫 hex，實得「\(displaySafe(d, max: 120))」")
            }
            self.init(field: field, value: value,
                      kind: .judgement(statement: judgement, restsOn: restsOn))
        }
    }
}

import Yams

/// `references:` 清單的 YAML 編解碼（#66 task 2.2）。
///
/// 驗證住 `ProvenanceReference` 的 throwing 建構器，這裡只搬運形狀——decode 抽
/// 平面欄位後交給建構器，錯誤訊息只有一份。
///
/// **清單內的鍵是 strict**（同 timeline 段內鍵的慣例）：未知鍵拒收而非
/// tolerant-preserve。這意味著未來對 reference 加欄位是 **non-additive**
/// （#74 判準：判 additive 前先確認新鍵落在哪一層）——記在這裡，別再踩 #63。
public enum ProvenanceYAML {

    /// 欄位輸出順序固定（同一份資料每次 encode 位元組相同）；清單順序保留
    /// ——references 的順序是使用者的敘事順序，不重排。
    public static func node(_ refs: [ProvenanceReference]) throws -> Node {
        node(refs, strictStrings: false)
    }

    /// Canonical closed shapes 可要求 string scalar 保持 `.str` tag；只有會被 YAML
    /// resolver 判成 bool／int／null／timestamp 等型別的值才加雙引號，避免無謂 byte drift。
    static func strictNode(_ refs: [ProvenanceReference]) throws -> Node {
        node(refs, strictStrings: true)
    }

    static func strictStringNode(_ value: String) -> Node {
        let plain = Node(value)
        guard plain.tag != Tag(.str) else { return plain }
        return Node(value, Tag(.str), .doubleQuoted)
    }

    private static func node(
        _ refs: [ProvenanceReference],
        strictStrings: Bool
    ) -> Node {
        func stringNode(_ value: String) -> Node {
            strictStrings ? Self.strictStringNode(value) : Node(value)
        }
        return Node(refs.map { r -> Node in
            var pairs: [(Node, Node)] = [(Node("field"), stringNode(r.field))]
            if let v = r.value { pairs.append((Node("value"), stringNode(v))) }
            switch r.kind {
            case let .retrieval(url, retrieved, status, mediaType, content):
                pairs.append((Node("url"), stringNode(url)))
                pairs.append((Node("retrieved"), stringNode(retrieved)))
                pairs.append((Node("status"), Node("\(status)", Tag(.int))))
                if let mt = mediaType { pairs.append((Node("media-type"), stringNode(mt))) }
                pairs.append((Node("content"), stringNode(content)))
            case let .judgement(statement, restsOn):
                pairs.append((Node("judgement"), stringNode(statement)))
                pairs.append((Node("rests-on"), Node(restsOn.map(stringNode))))
            }
            return Node(pairs)
        })
    }

    static let knownKeys: Set<String> = ["field", "value", "url", "retrieved",
                                          "status", "media-type", "content",
                                          "judgement", "rests-on"]

    public static func decode(_ node: Node, context: String) throws -> [ProvenanceReference] {
        guard let seq = node.sequence else {
            throw StoreYAMLError.invalidField("\(context).references", "必須是 sequence")   // display-safe-exempt: context 是呼叫端字面量（person/organization）
        }
        return try seq.enumerated().map { (i, item) in
            guard let map = item.mapping else {
                throw StoreYAMLError.invalidField(
                    "\(context).references[\(i)]", "每筆 reference 必須是 mapping")   // display-safe-exempt: context 是呼叫端字面量（person/organization）、i 是索引
            }
            for k in map.keys.compactMap({ $0.scalar?.string }) where !knownKeys.contains(k) {
                throw StoreYAMLError.invalidField(
                    "\(context).references[\(i)]",
                    "不認得的鍵「\(displaySafe(k, max: 120))」——reference 內的鍵是 strict（合法鍵："
                    + knownKeys.sorted().joined(separator: "、") + "）")
            }
            func scalar(_ key: String) throws -> String? {
                guard let n = map[key] else { return nil }
                guard let s = n.scalar?.string else {
                    throw StoreYAMLError.invalidField(
                        "\(context).references[\(i)].\(key)", "必須是 scalar")
                }
                return s
            }
            var status: Int?
            if let raw = try scalar("status") {
                guard let n = Int(raw) else {
                    throw StoreYAMLError.invalidField(
                        "\(context).references[\(i)].status", "必須是整數，實得「\(raw)」")
                }
                status = n
            }
            var restsOn: [String] = []
            if let n = map["rests-on"] {
                guard let s = n.sequence else {
                    throw StoreYAMLError.invalidField(
                        "\(context).references[\(i)].rests-on", "必須是 sequence")
                }
                restsOn = try s.map {
                    guard let v = $0.scalar?.string else {
                        throw StoreYAMLError.invalidField(
                            "\(context).references[\(i)].rests-on", "每個 digest 必須是 scalar")
                    }
                    return v
                }
            }
            return try ProvenanceReference(
                field: try scalar("field") ?? "",
                value: try scalar("value"),
                url: try scalar("url"), retrieved: try scalar("retrieved"),
                status: status, mediaType: try scalar("media-type"),
                content: try scalar("content"),
                judgement: try scalar("judgement"), restsOn: restsOn)
        }
    }
}

/// 附著的存在性驗證（#66 task 3.3，D2）：reference 指名的欄位/值必須存在。
///
/// 值改寫時 provenance 會變成孤兒——這道驗證在載入時擋下（D2 記明的代價與對策）。
/// **誠實邊界**：`profile.*` 維度只驗 timeline 非空，`value` 不比對——OrgRef 等
/// 複合值沒有 canonical 字串表示，字串比對會製造假陰性；那裡的細部定位交由
/// 消費端與 doctor（後續 issue）處理。
extension Person {
    public func validateReferenceAttachment() throws {
        for r in references {
            switch r.field {
            case "names", "authorized":
                // #227 巢狀化後：field "names" 指名任一名字（聯集）、"authorized"
                // 指名對外名字（分割）。authorized ⊆ all 由結構保證。
                let pool = r.field == "names" ? names.all : names.authorized
                guard let v = r.value else {
                    throw StoreYAMLError.invalidField(
                        "person.references(field: \(r.field))",
                        "\(r.field) 是清單，reference 必須帶 value 指名支持的是哪個值（D2）")
                }
                guard pool.contains(v) else {
                    throw StoreYAMLError.invalidField(
                        "person.references(field: \(r.field))",
                        "value「\(v)」不在 \(r.field) 清單內——值被改寫後 provenance 成了孤兒，"
                        + "把 value 更新成現值或移除這筆 reference")
                }
            case "orcid", "openalex", "died", "note":
                // #145 verify F3：純量欄位的 value 沒有意義又永不被驗——靜默收下
                // 就是安靜的垃圾欄位，拒絕並說明 value 屬於清單欄位的定位（D2）
                guard r.value == nil else {
                    throw StoreYAMLError.invalidField(
                        "person.references(field: \(r.field))",
                        "\(r.field) 是純量欄位，不收 value——value 是清單欄位"
                        + "（names/authorized）的定位用（D2）")
                }
                let present: Bool
                switch r.field {
                case "orcid": present = orcid != nil
                case "openalex": present = openalex != nil
                case "died": present = died != nil
                default: present = note != nil
                }
                guard present else {
                    throw StoreYAMLError.invalidField(
                        "person.references(field: \(r.field))",
                        "記錄沒有 \(r.field) 欄位——reference 指名的欄位必須存在")
                }
            case "profile.affiliations", "profile.ranks", "profile.administrative",
                 "profile.appointments", "profile.fields":
                let empty: Bool
                switch r.field {
                case "profile.affiliations": empty = profile.affiliations.isEmpty
                case "profile.ranks": empty = profile.ranks.isEmpty
                case "profile.administrative": empty = profile.administrative.isEmpty
                case "profile.appointments": empty = profile.appointments.isEmpty
                default: empty = profile.fields.isEmpty
                }
                guard !empty else {
                    throw StoreYAMLError.invalidField(
                        "person.references(field: \(r.field))",
                        "記錄的 \(r.field) 是空的——reference 指名的欄位必須存在")
                }
            case _ where ProvenanceReference.resolutionVerdictFields.contains(r.field):
                // #232：verdict 虛欄位（封閉對）——value 定位配對（<kind>:<key> ::
                // <literal>），不屬任何集合、不做成員檢查。malformed 在**寫入邊界**
                // 拒收（verify DA fix-7）：一筆解析不了的 verdict 既不計數也不抑制，
                // 讓它進 store 等於允許一個靜默 no-op 的判定。
                guard case .judgement = r.kind else {
                    throw StoreYAMLError.invalidField(
                        "person.references(field: \(r.field))",
                        "verdict 必須是判斷型（judgement）——擷取型帶不動人為裁決")
                }
                guard let v = r.value,
                      ProvenanceReference.VerdictPairingValue.parse(v) != nil else {
                    throw StoreYAMLError.invalidField(
                        "person.references(field: \(r.field))",
                        "\(r.field) 的 value 必須是「<kind>:<key> :: <literal>」"
                        + "（kind ∈ work/person/org）——verdict 沒有可解析的配對即無錨")
                }
            default:
                throw StoreYAMLError.invalidField(
                    "person.references(field: \(r.field))",
                    "person 沒有可附著 reference 的欄位「\(r.field)」（合法：names、authorized、"
                    + "orcid、openalex、died、note、profile.affiliations、profile.ranks、"
                    + "profile.administrative、profile.appointments、profile.fields、"
                    + "resolution-confirmed、resolution-rejected）")
            }
        }
    }
}


// MARK: - 識別碼欄位的附著驗證（#394 §5）

/// 清單型識別碼的成員判定。**比對走正規形**——磁碟上是非正規形時（遷移前的既有
/// 記錄），reference 的 `value` 仍應對得上，否則那些記錄會因為一個大小寫而整筆拒讀，
/// 而 §4 的整個「讀取面寬容保留」就被這裡抵銷掉了。
///
/// 這也是 `Identifier` 的 `==` 由 `normalized` 決定的同一個理由（見該 protocol 的
/// extension）：`0003-066x` 與 `0003-066X` 是同一個識別碼。
func identifierListContains<T: Identifier>(_ ids: [T], value: String,
                                           _ make: (String) -> T?) -> Bool {
    guard let probe = make(value) else { return false }
    return ids.contains(probe)
}

extension Organization {
    public func validateReferenceAttachment() throws {
        for r in references {
            switch r.field {
            case "names":
                guard let v = r.value else {
                    throw StoreYAMLError.invalidField(
                        "organization.references(field: names)",
                        "names 是時間軸清單，reference 必須帶 value 指名支持的是哪個名字（D2）")
                }
                guard names.entries.contains(where: { $0.value == v }) else {
                    throw StoreYAMLError.invalidField(
                        "organization.references(field: names)",
                        "value「\(v)」不在 names 內——值被改寫後 provenance 成了孤兒")
                }
            case "authorized":
                guard let v = r.value else {
                    throw StoreYAMLError.invalidField(
                        "organization.references(field: authorized)",
                        "authorized 是清單，reference 必須帶 value（D2）")
                }
                guard authorized.contains(v) else {
                    throw StoreYAMLError.invalidField(
                        "organization.references(field: authorized)",
                        "value「\(v)」不在 authorized 清單內")
                }
            case "founded", "dissolved", "note", "ror":
                guard r.value == nil else {
                    throw StoreYAMLError.invalidField(
                        "organization.references(field: \(r.field))",
                        "\(r.field) 是純量欄位，不收 value（D2）")
                }
                let present: Bool
                switch r.field {
                case "founded": present = founded != nil
                case "dissolved": present = dissolved != nil
                // #394：ROR 是純量——每個機構一筆 ROR 記錄，由定義。
                case "ror": present = ror != nil
                default: present = note != nil
                }
                guard present else {
                    throw StoreYAMLError.invalidField(
                        "organization.references(field: \(r.field))",
                        "記錄沒有 \(r.field) 欄位——reference 指名的欄位必須存在")
                }
            case "parents":
                guard !parents.isEmpty else {
                    throw StoreYAMLError.invalidField(
                        "organization.references(field: parents)",
                        "記錄的 parents 是空的——reference 指名的欄位必須存在")
                }
            case _ where ProvenanceReference.resolutionVerdictFields.contains(r.field):
                // #232：同 person 側——封閉對、judgement 必須、value 必須可解析
                guard case .judgement = r.kind else {
                    throw StoreYAMLError.invalidField(
                        "organization.references(field: \(r.field))",
                        "verdict 必須是判斷型（judgement）——擷取型帶不動人為裁決")
                }
                guard let v = r.value,
                      ProvenanceReference.VerdictPairingValue.parse(v) != nil else {
                    throw StoreYAMLError.invalidField(
                        "organization.references(field: \(r.field))",
                        "\(r.field) 的 value 必須是「<kind>:<key> :: <literal>」"
                        + "（kind ∈ work/person/org）——verdict 沒有可解析的配對即無錨")
                }
            default:
                throw StoreYAMLError.invalidField(
                    "organization.references(field: \(r.field))",
                    "organization 沒有可附著 reference 的欄位「\(r.field)」"
                    + "（合法：names、authorized、founded、dissolved、note、ror、parents、"
                    + "resolution-confirmed、resolution-rejected）")
            }
        }
    }
}

// MARK: - Venue 的附著驗證（#394 §5）

/// **venue 原本完全沒有這個方法**——`validateReferenceAttachment` 只有 person 與
/// organization 有，`VenueYAML.decode` 也從不呼叫。於是一筆 venue reference 可以寫
/// 任何欄位名而照樣載入，這是 #304 建立 venue 形狀時留下的洞。
///
/// **補上它是有風險的動作，所以先量過**：實測真實 store 有 **817 筆** venue
/// reference，全部是 `resolution-confirmed`（`resolve-venues` 的判定，封閉列舉第 13
/// 條）。漏掉那一格的話 405 筆 venue 記錄會全部拒讀——`IdentifierProvenanceTests`
/// 的第一條測試釘的就是它。
extension Venue {
    public func validateReferenceAttachment() throws {
        for r in references {
            switch r.field {
            case "names":
                guard let v = r.value else {
                    throw StoreYAMLError.invalidField(
                        "venue.references(field: names)",
                        "names 是時間軸清單（刊名沿革），reference 必須帶 value 指名支持的是哪個名字（D2）")
                }
                guard names.entries.contains(where: { $0.value == v }) else {
                    throw StoreYAMLError.invalidField(
                        "venue.references(field: names)",
                        "value「\(v)」不在 names 內——值被改寫後 provenance 成了孤兒")
                }
            case "authorized":
                guard let v = r.value else {
                    throw StoreYAMLError.invalidField(
                        "venue.references(field: authorized)",
                        "authorized 是清單，reference 必須帶 value（D2）")
                }
                guard authorized.contains(v) else {
                    throw StoreYAMLError.invalidField(
                        "venue.references(field: authorized)",
                        "value「\(v)」不在 authorized 清單內")
                }
            case "issn":
                // #394：ISSN 是清單——print 與 electronic 是兩個真的號，所以一筆
                // 記錄級的 reference 不說支持哪一個，另一個就**看起來有來源而其實沒有**。
                guard let v = r.value else {
                    throw StoreYAMLError.invalidField(
                        "venue.references(field: issn)",
                        "issn 是清單（print 與 electronic 是兩個真的號），"
                        + "reference 必須帶 value 指名支持的是哪一個（D2）")
                }
                guard identifierListContains(issn, value: v, ISSN.init) else {
                    throw StoreYAMLError.invalidField(
                        "venue.references(field: issn)",
                        "value「\(displaySafe(v, max: 120))」不在 issn 清單內"
                        + "——值被改寫後 provenance 成了孤兒，"
                        + "把 value 更新成現值或移除這筆 reference")
                }
            case "paginated":
                // #406：「本刊是否使用頁碼」的判定要留 verdict 與證據（欄位契約
                // 明文）。判定必須是判斷型——「本刊不用頁碼」是關於世界的斷言，
                // 擷取型帶不動人為裁決。
                //
                // **#500 起 `paginated` 是 D2「純量欄位不收 value」的明文例外**，
                // 而例外的理由是兩個原本寫不出來的東西：
                //
                //   (b) **撤回判定**。翻轉 true↔false 可以（留史），但撤回到誠實的
                //       未判定狀態沒有面——舊規則要求「記錄的 paginated 非 nil」，
                //       所以「退回 nil 但保留判定史」在**驗證層就寫不出來**：要嘛丟掉
                //       全部 reference（違反留史），要嘛改規則。`resolve-venues demote`
                //       （#418）在這個域的對應物因此不存在。
                //   (c) **翻轉語意**。value 恆 nil 時資料層看不出哪句理由對應哪個值；
                //       同 statement 翻回時 (field, value, kind) 冪等會吞掉新翻轉。
                //
                // 三值封閉：`true`／`false`／`nil`（後者＝撤回，是一筆帶理由與證據的
                // **判定**，不是刪除）。**不是**「凡是判定型純量都收 value」——那句話
                // 會在下一個純量上長出沒人同意的答案；要收就再明寫一個例外。
                //
                // **舊筆（value 缺席）放行**——這是一條相容路徑，所以依 `no-compat-fallback`
                // 第 2 條附上退場條件與量它的方法：
                //
                //     grep -h -A1 'field: paginated' ~/.akashic/entities/*.yaml \\
                //       | grep -c 'value:'          # 帶 value 的筆數
                //     grep -l 'field: paginated' ~/.akashic/entities/*.yaml | wc -l   # 總筆數
                //
                // 2026-09-09（#500 落地當日）：總 33 筆、帶 value **0** 筆。
                // **退場條件**：兩個數字相等時，把上面的 `if let v` 改成 `guard let v else { throw }`
                // 並刪掉本段——留著的相容路徑不會保護任何東西，它只是在等一個新的呼叫端誤入。
                if let v = r.value {
                    guard ["true", "false", "nil"].contains(v) else {
                        throw StoreYAMLError.invalidField(
                            "venue.references(field: paginated)",
                            "value「\(displaySafe(v, max: 60))」不在封閉三值（true／false／nil）內"
                            + "——nil 是撤回判定，不是「沒有值」")
                    }
                }
                // **不再要求 `paginated != nil`**：撤回之後記錄的欄位就是 nil，而判定史
                // 要留著。舊規則正是 (b) 寫不出來的原因。
                guard case .judgement = r.kind else {
                    throw StoreYAMLError.invalidField(
                        "venue.references(field: paginated)",
                        "paginated 的判定必須是判斷型（judgement）——"
                        + "「本刊是否使用頁碼」是人為裁決，不是一次擷取")
                }
            case "note":
                guard r.value == nil else {
                    throw StoreYAMLError.invalidField(
                        "venue.references(field: note)",
                        "note 是純量欄位，不收 value（D2）")
                }
                guard note != nil else {
                    throw StoreYAMLError.invalidField(
                        "venue.references(field: note)",
                        "記錄沒有 note 欄位——reference 指名的欄位必須存在")
                }
            case _ where ProvenanceReference.resolutionVerdictFields.contains(r.field):
                // #232／#304：`resolve-venues` 的判定落在被判定的 venue 記錄上。
                // **實測 817 筆，這一格是承重的。**
                guard case .judgement = r.kind else {
                    throw StoreYAMLError.invalidField(
                        "venue.references(field: \(r.field))",
                        "verdict 必須是判斷型（judgement）——擷取型帶不動人為裁決")
                }
                guard let v = r.value,
                      ProvenanceReference.VerdictPairingValue.parse(v) != nil else {
                    throw StoreYAMLError.invalidField(
                        "venue.references(field: \(r.field))",
                        "\(r.field) 的 value 必須是「<kind>:<key> :: <literal>」"
                        + "（kind ∈ work/person/org）——verdict 沒有可解析的配對即無錨")
                }
            default:
                throw StoreYAMLError.invalidField(
                    "venue.references(field: \(r.field))",
                    "venue 沒有可附著 reference 的欄位「\(displaySafe(r.field, max: 120))」"
                    + "（合法：names、authorized、issn、note、paginated、"
                    + "resolution-confirmed、resolution-rejected）")
            }
        }
    }
}

// MARK: - Entry 的附著驗證（#394 §5／§6——本輪新增的邊）

/// work 的識別碼要能攜帶來源。spec 的 requirement 寫得很硬：
///
/// > An identifier that **cannot carry a reference** SHALL NOT be treated as a
/// > first-class field of the record.
///
/// 而 `Entry` 原本**沒有 `references` 欄位**（`Models.swift` 那個屬於 `Person`），
/// 所以在本輪之前 work 的 `doi`／`pmid`／`isbn` 照該 requirement 的字面不算一等公民
/// ——這正是本 change 的標題所主張的東西。使用者 2026-08-24 裁定補齊。
///
/// **值域刻意只有三個識別碼欄位＋一格拆分記錄。** work 的其餘欄位（`title`／`date`／`fields.*`）
/// 要不要能攜帶來源是另一個問題，#394 不裁決——寫在這裡是為了讓「只有這幾個」
/// 是一個看得見的選擇，而不是一個沒人注意到的省略。
///
/// **`authors` 那一格的語意與其他三格相反**（#450）：識別碼 reference 附著在**當下存在**的值
/// （D2 以值定位、`identifierListContains` 驗值在場）；拆分記錄指向的是**已退役**的值（被拆掉的
/// 原 literal），所以不驗 value 在場——它的一致性條件是「statement 各段至少一段仍是本 work 的
/// 作者位」，而那放在 `StoreHealth`（warning），不在 decode 期：記錄合法，只是證據錨可能失效。
/// 這一格的例外**只有 `authors`**，其他 field 不得類推（`default` 分支照舊拒絕）。
extension Entry {
    public func validateReferenceAttachment() throws {
        for r in references {
            switch r.field {
            case "authors":
                // **兩種記錄共用這一格**：拆分（#450，退役後留 N ≥ 2 段）與移除（#457，留 0 段）。
                // 兩者的語意相同——value 是**已退役**的作者 literal——差別只在退役之後剩幾段，
                // 所以它們住同一個 field，由 statement 前綴分辨（`拆為 ` vs `移除：`）。
                guard let v = r.value, !v.isEmpty else {
                    throw StoreYAMLError.invalidField(
                        "entry.references(field: authors)",
                        "作者位記錄必須帶 value＝被退役的原 literal（逐字）"
                        + "——沒有它，拆分記錄無從 un-split、移除記錄無從說出移除了什麼")
                }
                guard case .judgement(let statement, _) = r.kind else {
                    throw StoreYAMLError.invalidField(
                        "entry.references(field: authors)",
                        "作者位記錄必須是 judgement 型"
                        + "（statement 走 `拆為 ⟦a⟧ ⟦b⟧：理由` 或 `移除：理由`）")
                }
                guard SplitRecordValue.parse(statement) != nil
                        || AuthorRemovalRecordValue.parse(statement) != nil else {
                    throw StoreYAMLError.invalidField(
                        "entry.references(field: authors)",
                        "statement「\(displaySafe(statement, max: 200))」不是合法的作者位記錄文法"
                        + "（拆分 `拆為 ⟦a⟧ ⟦b⟧…：理由`：段 ≥ 2、括號平衡、理由非空；"
                        + "移除 `移除：理由`：理由非空）")
                }
            case "doi", "pmid", "isbn":
                // **value 缺席 ＝ 這一筆說的是「對這個欄位做過的一次查找」，不是某一個號的來源**
                // （#517）。負結果因此寫得出來：欄位空 ＋ 這樣一筆 ＝「查過了，沒有」。
                //
                // 既有規則要求 value，理由是「一筆記錄真的會有多個 DOI，要說支持哪一個」——
                // 那個理由只在「這一筆關於某個值」時成立，關於整個欄位時不成立。
                //
                // **kind 必須是 retrieval**：一次查找有 url 與日期，而**那兩件事沒有別的地方記**
                // （`sources/index.jsonl` 記 origin／retrieved／media-type，但不記 url）。
                // judgement 走不到這裡——它的空 rests-on 已被平面 init 擋下（識別碼欄位不在
                // `firstOrderRulingFields`），而帶 digest 的 judgement 說的是「依據某份存檔做的
                // 判定」，那要說支持哪一個值，仍須 value。
                guard let v = r.value else {
                    guard case .retrieval = r.kind else {
                        throw StoreYAMLError.invalidField(
                            "entry.references(field: \(r.field))",
                            "\(r.field) 的 reference 沒帶 value 時說的是「對這個欄位做過的一次查找」"
                            + "，必須是擷取型（retrieval：url 與日期沒有別的地方記）。"
                            + "要說某一個號的來源就帶上那個 value")
                    }
                    continue
                }
                let ok: Bool
                switch r.field {
                case "doi": ok = identifierListContains(doi, value: v, DOI.init)
                case "pmid": ok = identifierListContains(pmid, value: v, PMID.init)
                default: ok = identifierListContains(isbn, value: v, ISBN.init)
                }
                guard ok else {
                    throw StoreYAMLError.invalidField(
                        "entry.references(field: \(r.field))",
                        "value「\(displaySafe(v, max: 120))」不在 \(r.field) 清單內"
                        + "——值被改寫後 provenance 成了孤兒")
                }
            case _ where r.field.hasPrefix(ProvenanceReference.workFieldPrefix):
                // **非識別碼欄位的來源**（#517）——`fields.<key>`。
                //
                // 值域從「三個識別碼 ＋ authors」擴到這裡的理由：補進去的 `abstract` 在此之前
                // 永遠是「不知道從哪來的」，而 `replace-endnote-and-zotero` 第 2 條要求位元組住
                // Akashic——位元組在 `sources/`，記錄卻指不到它。
                let key = String(r.field.dropFirst(ProvenanceReference.workFieldPrefix.count))
                guard !key.isEmpty else {
                    throw StoreYAMLError.invalidField(
                        "entry.references(field: \(r.field))",
                        "「\(ProvenanceReference.workFieldPrefix)」後面要接 fields 的鍵名")
                }
                // **純量欄位不收 value**（D2，比照 `note`／`founded`）：`fields` 的每個鍵恰有
                // 一個值，沒有「支持哪一個」可說。
                guard r.value == nil else {
                    throw StoreYAMLError.invalidField(
                        "entry.references(field: \(r.field))",
                        "fields 的每個鍵恰有一個值，reference 不收 value（D2）")
                }
                // **刻意不檢查 `fields[key]` 在場**——那正是負結果的形狀：欄位缺席 ＋ 一筆
                // 查找記錄 ＝「查過了，沒有」。代價寫在這裡：打錯的鍵名會靜靜附上去，而
                // 沒有東西擋得住。要擋它就得放棄負結果的表達法，那是本 change 的核心。
                //
                // judgement 型合法且不必另設閘：它的空 rests-on 已被平面 init 擋下
                // （`fields.*` 不在 `firstOrderRulingFields`），所以走這條必然帶著真的 digest
                // ——離線來源（掃描的紙本頁）因此表達得出來，而 retrieval 的 url 是必填的。
                break
            default:
                throw StoreYAMLError.invalidField(
                    "entry.references(field: \(r.field))",
                    "work 沒有可附著 reference 的欄位「\(displaySafe(r.field, max: 120))」"
                    + "（合法：doi、pmid、isbn、authors、fields.<鍵名>）")
            }
        }
    }
}


extension Entry: ProvenanceCarrying {}
extension Person: ProvenanceCarrying {}
extension Organization: ProvenanceCarrying {}
extension Venue: ProvenanceCarrying {}
