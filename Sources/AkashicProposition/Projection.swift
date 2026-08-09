import Foundation
import AkashicCore

/// 命題投射規則（#199）：從符號與引數，到模型／世界狀態。
///
/// 文件把缺口列成四問——符號 P 指涉哪個 person identity、符號 W 指涉哪個 work
/// identity、`authored` 的方向與 arity 是什麼、什麼世界狀態使命題成立。前兩問是
/// `Projection`，第三問已由 `Proposition` 的封閉型別回答（arity 與方向在型別裡），
/// 第四問是 `TruthValue` 的判定規則。
///
/// **投射不足時拒絕真值宣稱**是本型別存在的理由：沒有這一層，`Bool` 結果只能
/// 表示「檢索命中」，而檢索命中不是真值。
public enum Projection: Equatable {
    /// 每個符號都對到模型裡的一個 identity。
    case projected(person: Person, work: Entry)
    /// 投射不足——**不得對這個命題宣稱真值**。
    case unprojectable(UnprojectableReason)
}

public enum UnprojectableReason: Equatable {
    /// 引數還是 `literal`，尚未歸戶。
    case unresolvedSymbol(role: String, literal: String)
    /// 引數是 key，但模型裡沒有這個 identity。
    case unknownIdentity(role: String, key: String)
    /// 引數指到的東西型別不對（例如把 work 放進 person 的位置）。
    /// **這一項證明方向是有意義的**——`authored(w, p)` 通常落在這裡。
    case wrongEntityKind(role: String, key: String, expected: String)
}

/// 三值。**不是 `Bool`。**
///
/// store 不是封閉世界：一筆記錄不存在，不代表那件事不成立。把「找不到」回成
/// `false` 與把它回成 `true` 一樣錯——那正是「把書目搜尋結果包裝成真值」的鏡像。
public enum TruthValue: Equatable {
    case holds
    /// **需要正面的反證**，不是「找不到」。見下方 `evaluate` 的誠實邊界。
    case fails
    case undetermined(UndeterminedReason)
}

public enum UndeterminedReason: Equatable {
    case notProjectable(UnprojectableReason)
    /// 模型裡沒有支持這個命題的內容——**而模型無法宣稱自己完備**，所以這是
    /// 「未定」不是「為假」。
    case noSupportingEvidence
    /// 作者槽仍是 `literal`：字面像，但沒有 identity 可比對。
    case supportingEvidenceUnresolved(literal: String)
}

/// 模型構造期就該拒絕的輸入（#205）。
public enum ModelError: Error, Equatable, LocalizedError {
    case duplicateEntryCitekey(String)
    case duplicatePersonKey(String)

    public var errorDescription: String? {
        switch self {
        case .duplicateEntryCitekey(let k):
            return "model 有重複的 entry citekey：'\(displaySafe(k, max: 120))'——歧義的 model 不得用於求值"
        case .duplicatePersonKey(let k):
            return "model 有重複的 person key：'\(displaySafe(k, max: 120))'——歧義的 model 不得用於求值"
        }
    }
}

/// 投射與求值的模型面：目前就是 store 載入後的 entries 與 people。
public struct PropositionModel {
    public let entriesByKey: [String: Entry]
    public let peopleByKey: [String: Person]

    /// **重複鍵 fail closed**（#205 證據二）。
    ///
    /// 前一版用 `uniquingKeysWith: { _, last in last }`，理由是「損壞 store 出現重複
    /// key 時不 trap」。那個理由對**載入**成立，對**求值**不成立：last-wins 讓真值
    /// 取決於陣列順序。實測同一組輸入的兩種排列——
    ///
    ///     [不含作者的 dup, 含作者的 dup]  → .holds
    ///     [含作者的 dup, 不含作者的 dup]  → .undetermined(.noSupportingEvidence)
    ///
    /// ——於是 `adjudicate` 會**只因為陣列順序**在「建立 AcceptedFact」與「拒絕」
    /// 之間改變。一個歧義的 model 不是「有點髒的 model」，它**不是一個 model**：
    /// 同一個符號指到兩個不同的東西，投射這個概念本身就沒有定義。
    ///
    /// 損壞 store 的處置是 `validate`／`doctor` 的事；求值面該做的是拒絕，不是挑一個。
    public init(entries: [Entry], people: [Person]) throws {
        var e: [String: Entry] = [:]
        for entry in entries {
            guard e[entry.citekey] == nil else {
                throw ModelError.duplicateEntryCitekey(entry.citekey)
            }
            e[entry.citekey] = entry
        }
        var p: [String: Person] = [:]
        for person in people {
            guard p[person.key] == nil else {
                throw ModelError.duplicatePersonKey(person.key)
            }
            p[person.key] = person
        }
        self.entriesByKey = e
        self.peopleByKey = p
    }
}

extension Proposition {

    /// 把符號投射到模型的 identity。
    ///
    /// **會先 `validate()`，非法命題 throw**（#205 證據一）。
    ///
    /// `Proposition` 與它的 case 都是 public，所以 `makeAuthored` 的驗證繞得過去：
    /// 直接寫 `.authored(person: .key("Not A Key"), work: …)` 就得到一個非法值。
    /// 前一版的註解說「驗證同時提供成 `validate()`，由消費端在邊界上呼叫」——
    /// **而消費端一個都沒呼叫**。實測非法命題求值回 `.holds`，再被 `adjudicate`
    /// 接受成 `AcceptedFact`。
    ///
    /// **不折成 `.undetermined`**：「這不是一個合法的命題」與「我不知道它真假」
    /// 是兩件事。把前者說成後者，等於宣稱一個 malformed key 只是「還沒歸戶」——
    /// open-world 的寬容不該延伸到語法錯誤。所以是 throw，不是第四個 TruthValue。
    public func project(in model: PropositionModel) throws -> Projection {
        try validate()
        switch self {
        case let .authored(person, work):
            // person 位置
            let p: Person
            switch person {
            case .literal(let s):
                return .unprojectable(.unresolvedSymbol(role: "person", literal: s))
            case .key(let k):
                // **先看是不是 work**：這樣「方向搞反」會回 wrongEntityKind 而不是
                // 語意較弱的 unknownIdentity，訊息才指得出真正的問題。
                if model.entriesByKey[k] != nil, model.peopleByKey[k] == nil {
                    return .unprojectable(.wrongEntityKind(role: "person", key: k, expected: "person"))
                }
                guard let found = model.peopleByKey[k] else {
                    return .unprojectable(.unknownIdentity(role: "person", key: k))
                }
                p = found
            }
            // work 位置
            switch work {
            case .literal(let s):
                return .unprojectable(.unresolvedSymbol(role: "work", literal: s))
            case .key(let k):
                if model.peopleByKey[k] != nil, model.entriesByKey[k] == nil {
                    return .unprojectable(.wrongEntityKind(role: "work", key: k, expected: "work"))
                }
                guard let e = model.entriesByKey[k] else {
                    return .unprojectable(.unknownIdentity(role: "work", key: k))
                }
                return .projected(person: p, work: e)
            }
        }
    }

    /// 什麼世界狀態使這個命題成立。
    ///
    /// ## 誠實邊界：`authored` 目前**永遠不會回 `.fails`**
    ///
    /// `.fails` 需要**正面的反證**——對 `authored` 而言那要求「這篇的作者名單已
    /// 完備」這個事實，而 store **沒有任何欄位能表達名單完備**。作者槽可以是
    /// `.literal`（還沒歸戶）、可以缺漏（匯入來源只給了前三位）、可以是別名沒
    /// 對上。所以「名單裡沒有他」只支持**未定**，不支持為假。
    ///
    /// `TruthValue.fails` 仍留在型別裡，因為答案空間需要它可被表達（#200 的
    /// yes/no 兩個答案命題本來就要成對）；只是目前沒有規則產生它。這個落差是
    /// 模型的真實極限，不是待辦——要它可產生，得先有「名單完備」的證言型別。
    /// 由 `testAuthoredNeverReturnsFails` 釘住，改了會紅。
    ///
    /// **非法命題 throw，不回 `.undetermined`**（#205）——見 `project` 的說明。
    public func evaluate(in model: PropositionModel) throws -> TruthValue {
        switch try project(in: model) {
        case .unprojectable(let why):
            return .undetermined(.notProjectable(why))
        case let .projected(person, work):
            switch self {
            case .authored:
                var sawUnresolved: String?
                for slot in work.authors {
                    switch slot {
                    case .key(let k) where k == person.key:
                        return .holds
                    case .key:
                        continue
                    case .literal(let s):
                        // 字面像但沒 identity——記下來，讓「未定」帶得出原因
                        if person.names.contains(where: {
                            NameNormalization.matchingKey($0) == NameNormalization.matchingKey(s)
                        }) { sawUnresolved = s }
                    }
                }
                if let s = sawUnresolved { return .undetermined(.supportingEvidenceUnresolved(literal: s)) }
                return .undetermined(.noSupportingEvidence)
            }
        }
    }
}
