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
            // 僅對封閉欄位對允許空 rests-on（有證據時 SHOULD 附）；其他欄位維持拒收
            guard !restsOn.isEmpty || Self.resolutionVerdictFields.contains(field) else {
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
                    + "（合法：names、authorized、issn、note、"
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
/// **值域刻意只有三個識別碼欄位。** work 的其餘欄位（`title`／`date`／`fields.*`）
/// 要不要能攜帶來源是另一個問題，本 change 不裁決——寫在這裡是為了讓「只有三個」
/// 是一個看得見的選擇，而不是一個沒人注意到的省略。
extension Entry {
    public func validateReferenceAttachment() throws {
        for r in references {
            switch r.field {
            case "doi", "pmid", "isbn":
                guard let v = r.value else {
                    throw StoreYAMLError.invalidField(
                        "entry.references(field: \(r.field))",
                        "\(r.field) 是清單，reference 必須帶 value 指名支持的是哪一個（D2）"
                        + "——實測 37 組同題同年而 DOI 不同，一筆記錄真的會有多個")
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
            default:
                throw StoreYAMLError.invalidField(
                    "entry.references(field: \(r.field))",
                    "work 沒有可附著 reference 的欄位「\(displaySafe(r.field, max: 120))」"
                    + "（合法：doi、pmid、isbn）")
            }
        }
    }
}


extension Entry: ProvenanceCarrying {}
extension Person: ProvenanceCarrying {}
extension Organization: ProvenanceCarrying {}
extension Venue: ProvenanceCarrying {}
