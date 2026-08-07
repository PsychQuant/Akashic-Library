import Foundation

/// 靠推理而非擷取得到的主張，以及它所依據的位元組。
///
/// **這是與 `add-provenance-references` 共用的件，不是它的複本。** 那個變更的
/// `ProvenanceReference` 是「指名宿主欄位的 `field:`」加上「擷取型或判斷型二選一」
/// 的組合；判斷型那一半就是這裡。歧異的判斷不指向宿主的某個欄位（它是關於**哪個
/// 候選才對**），所以它用的是不含 `field:` 的這一半。一套詞彙、兩種組合方式。
///
/// **兩個欄位在型別上綁在一起，不是靠檢查。** 沒有依據的斷言不是判斷；沒有斷言的
/// 依據不知道在支持什麼。把它們做成一個值，讓「只有其一」在型別層就無法表達——
/// decode 端仍要擋（YAML 可以只寫一個），但擋下之後不會有半個判斷流進系統。
public struct Judgement: Equatable {
    /// **相等性不看 `restsOn` 的儲存順序。** 它是一組摘要，不是序列——同樣的證據以
    /// 不同順序寫進來是同一個判斷。序列化仍排序輸出（位元組唯一），但比較不看順序。
    /// 兩者是不同的函式：共用同一個比較器正是 Akashic-Library#69 診斷出的病。
    public static func == (a: Judgement, b: Judgement) -> Bool {
        a.statement == b.statement && a.restsOn.sorted() == b.restsOn.sorted()
            && a.prefers == b.prefers
    }

    /// 判斷本身，人寫的一句話。
    public var statement: String
    /// 這個判斷建立在哪些存檔上（`sha256:` 前綴的摘要）。
    public var restsOn: [String]
    /// **選填**：判斷傾向哪個候選（#75 對一）。`statement` 是自由文字，「它指向誰」
    /// 無法機械判定——這個欄位讓消歧能**比對**（`prefers ≠ survivor` → 拒絕）。
    ///
    /// **不代選**：消歧不會照 `prefers` 自動執行。#133 起判斷可經 MCP 由 LLM 寫入，
    /// 自動採信＝把「當場判斷」換成「延遲自動判斷」，繞過 #71 的人工確認底線。
    /// survivor 仍必須是消歧當下的人工輸入；`prefers` 只擋下不一致。
    ///
    /// **MUST 是本記錄的候選之一**（decode 驗證）——指向別的東西是無法執行的判斷。
    public var prefers: String?

    public init(statement: String, restsOn: [String], prefers: String? = nil) {
        self.statement = statement
        self.restsOn = restsOn
        self.prefers = prefers
    }
}

/// 歧異的一個候選：指名某個實體。
///
/// **`shape` 是必填而非推導**。decode 沒有 store 存取，無從查某個鍵屬於哪個形狀；
/// 而鍵在不同形狀之間可以同名（`organization` spec 明載「`key` 與 person 同名是
/// 刻意的」——判別由標籤負責，identity 欄位不必兼差當形狀名）。要在載入時就擋下
/// 跨形狀的候選，形狀必須寫在記錄裡。
public struct DivergenceCandidate: Equatable {
    public var key: String
    public var shape: EntityKind

    public init(key: String, shape: EntityKind) {
        self.key = key
        self.shape = shape
    }
}

/// 未決的同一性問題。
///
/// store 已有「寧可分割，絕不合併」——同一個人的兩種寫法會建成兩筆記錄，因為錯誤
/// 合併不可逆而錯誤分割可逆。但分割之後兩筆各自失憶：沒有地方記「這兩筆可能是同
/// 一個」。這個形狀補的就是那個位置。
///
/// **它是短暫的。** 消歧完成時整筆刪除，歷史託給版本控制而非 store 自己。所以它
/// 沒有「已解決」狀態——一個永遠不會進入該狀態的欄位不該存在。store 承載「現在
/// 相信什麼」，不承載「曾經不確定什麼」。
public struct Divergence: Equatable {
    /// **相等性不看 `candidates` 的儲存順序。** 「這些是不是同一個」不因候選的排列
    /// 而改變。理由與 `Judgement` 相同，見該型別的說明。
    public static func == (a: Divergence, b: Divergence) -> Bool {
        let ka = a.candidates.map { [$0.shape.rawValue, $0.key] }.sorted { $0.lexicographicallyPrecedes($1) }
        let kb = b.candidates.map { [$0.shape.rawValue, $0.key] }.sorted { $0.lexicographicallyPrecedes($1) }
        return a.id == b.id && a.question == b.question && ka == kb
            && a.judgement == b.judgement
            // **逐位元組比未知欄位，不是只比 key。** encode canary 就是靠這個比較器
            // 看見「寫出去的東西與原值不符」；只比 key 會讓它對未知區塊的**內容**
            // 全盲——tolerant-preserve 保證的正是那些位元組不變（#71 R1 verify）。
            && a.unknownFields == b.unknownFields
    }

    /// 不變的機器身分。
    public var id: UUID
    /// 未決的是什麼，人寫的一句話。
    public var question: String
    /// 兩個以上的候選，全部同形狀。
    public var candidates: [DivergenceCandidate]
    /// 已經形成的判斷（若有）。判斷存在不代表已消歧——消歧是一個操作，不是一個欄位。
    public var judgement: Judgement?
    /// 較新版本寫入、本 binary 不認得的欄位（§5 tolerant-preserve）。
    public var unknownFields: [UnknownField]

    public init(id: UUID, question: String, candidates: [DivergenceCandidate],
                judgement: Judgement? = nil, unknownFields: [UnknownField] = []) {
        self.id = id
        self.question = question
        self.candidates = candidates
        self.judgement = judgement
        self.unknownFields = unknownFields
    }

    /// 全部候選共有的形狀。空候選時為 `nil`——但那種記錄過不了載入。
    public var shape: EntityKind? { candidates.first?.shape }
}

extension Divergence {
    /// 與其他形狀同型的單筆檢查。
    ///
    /// **存在的理由是可見性**：`akashic validate` 的未知欄位提示完全來自每筆記錄的
    /// `validate()`，不是 `load.unknownFieldFiles`（那條路只餵 doctor 與 App）。沒有
    /// 這個方法，一筆由較新 binary 寫入、帶著本 binary 看不懂欄位的歧異記錄，在
    /// `validate` 下印出來的是「✓ … 1 divergences 全部通過」——「全部通過」四個字
    /// 正是這裡最不該說的（#71 R1 verify 的 DA 更正四）。
    public func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for c in candidates where !StoreKey.isValid(c.key) {
            issues.append(ValidationIssue(
                severity: .error,
                message: "候選 key '\(displaySafe(c.key, max: 120))' 不符合 \(StoreKey.pattern)"))
        }
        for f in unknownFields {
            issues.append(ValidationIssue(severity: .warning,
                message: "未知欄位「\(displaySafe(f.key, max: 120))」——可能由較新版本寫入（已保留；升級 binary 或檢查 typo）"))
        }
        return issues
    }
}
