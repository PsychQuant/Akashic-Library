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
public struct ProvenanceReference: Equatable {

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
        guard s.hasPrefix("sha256:") else { return false }
        let hex = s.dropFirst("sha256:".count)
        return hex.count == 64 && hex.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isLowercase) }
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
        let hasRetrievalSide = url != nil || retrieved != nil || status != nil
            || mediaType != nil || content != nil
        let hasJudgementSide = judgement != nil || !restsOn.isEmpty

        switch (hasRetrievalSide, hasJudgementSide) {
        case (true, true):
            if content != nil {
                throw StoreYAMLError.invalidField(
                    "reference(field: \(field))",
                    "判斷型 reference 不得帶 content——判斷不是擷取，沒有自己的位元組；"
                    + "它依據的內容以 rests-on 指名")
            }
            throw StoreYAMLError.invalidField(
                "reference(field: \(field))",
                "擷取型欄位（url/retrieved/status/media-type）與判斷型欄位"
                + "（judgement/rests-on）不得混用——兩種 reference 互斥")
        case (false, false):
            throw StoreYAMLError.invalidField(
                "reference(field: \(field))",
                "無法辨識種類：擷取型需要 url/retrieved/status/content，"
                + "判斷型需要 judgement/rests-on，兩側都是空的")
        case (true, false):
            guard let url else { throw StoreYAMLError.missingField("reference(field: \(field)).url") }
            guard let retrieved else {
                throw StoreYAMLError.missingField("reference(field: \(field)).retrieved")
            }
            guard let status else {
                throw StoreYAMLError.missingField("reference(field: \(field)).status")
            }
            guard let content else {
                throw StoreYAMLError.missingField(
                    "reference(field: \(field)).content——只有 URL 不構成 provenance，"
                    + "內容的 digest 是必要的另一半")
            }
            guard Self.isValidDigest(content) else {
                throw StoreYAMLError.invalidField(
                    "reference(field: \(field)).content",
                    "digest 形狀必須是 sha256: + 64 個小寫 hex，實得「\(content)」")
            }
            self.init(field: field, value: value,
                      kind: .retrieval(url: url, retrieved: retrieved, status: status,
                                       mediaType: mediaType, content: content))
        case (false, true):
            guard let judgement, !judgement.isEmpty else {
                throw StoreYAMLError.missingField(
                    "reference(field: \(field)).judgement——沒有斷言的依據不知道在支持什麼")
            }
            guard !restsOn.isEmpty else {
                throw StoreYAMLError.missingField(
                    "reference(field: \(field)).rests-on——沒有依據的斷言不是判斷")
            }
            for d in restsOn where !Self.isValidDigest(d) {
                throw StoreYAMLError.invalidField(
                    "reference(field: \(field)).rests-on",
                    "digest 形狀必須是 sha256: + 64 個小寫 hex，實得「\(d)」")
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
        Node(refs.map { r -> Node in
            var pairs: [(Node, Node)] = [(Node("field"), Node(r.field))]
            if let v = r.value { pairs.append((Node("value"), Node(v))) }
            switch r.kind {
            case let .retrieval(url, retrieved, status, mediaType, content):
                pairs.append((Node("url"), Node(url)))
                pairs.append((Node("retrieved"), Node(retrieved)))
                pairs.append((Node("status"), Node("\(status)", Tag(.int))))
                if let mt = mediaType { pairs.append((Node("media-type"), Node(mt))) }
                pairs.append((Node("content"), Node(content)))
            case let .judgement(statement, restsOn):
                pairs.append((Node("judgement"), Node(statement)))
                pairs.append((Node("rests-on"), Node(restsOn.map { Node($0) })))
            }
            return Node(pairs)
        })
    }

    static let knownKeys: Set<String> = ["field", "value", "url", "retrieved",
                                          "status", "media-type", "content",
                                          "judgement", "rests-on"]

    public static func decode(_ node: Node, context: String) throws -> [ProvenanceReference] {
        guard let seq = node.sequence else {
            throw StoreYAMLError.invalidField("\(context).references", "必須是 sequence")
        }
        return try seq.enumerated().map { (i, item) in
            guard let map = item.mapping else {
                throw StoreYAMLError.invalidField(
                    "\(context).references[\(i)]", "每筆 reference 必須是 mapping")
            }
            for k in map.keys.compactMap({ $0.scalar?.string }) where !knownKeys.contains(k) {
                throw StoreYAMLError.invalidField(
                    "\(context).references[\(i)]",
                    "不認得的鍵「\(k)」——reference 內的鍵是 strict（合法鍵："
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
                let pool = r.field == "names" ? names : authorized
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
            default:
                throw StoreYAMLError.invalidField(
                    "person.references(field: \(r.field))",
                    "person 沒有可附著 reference 的欄位「\(r.field)」（合法：names、authorized、"
                    + "orcid、openalex、died、note、profile.affiliations、profile.ranks、"
                    + "profile.administrative、profile.appointments、profile.fields）")
            }
        }
    }
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
            case "founded", "dissolved", "note":
                guard r.value == nil else {
                    throw StoreYAMLError.invalidField(
                        "organization.references(field: \(r.field))",
                        "\(r.field) 是純量欄位，不收 value（D2）")
                }
                let present: Bool
                switch r.field {
                case "founded": present = founded != nil
                case "dissolved": present = dissolved != nil
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
            default:
                throw StoreYAMLError.invalidField(
                    "organization.references(field: \(r.field))",
                    "organization 沒有可附著 reference 的欄位「\(r.field)」"
                    + "（合法：names、authorized、founded、dissolved、note、parents）")
            }
        }
    }
}
