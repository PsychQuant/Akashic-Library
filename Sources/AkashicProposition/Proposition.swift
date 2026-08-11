import Foundation
import AkashicCore

/// 具型別的命題表示（#198）。
///
/// ## 為什麼不是 `(subject, predicate, object)`
///
/// 通用三元組會把 **schema 文法**與**單筆事實**攤平成同一層：`authored` 的 arity
/// 與方向變成執行期的字串比對，而不是型別。這個 repo 對「一般化的資料驅動
/// registry」已經有明確立場——`Entry`／`Person`／`Organization` 都是 shape-specific
/// 的，不是一張 `(entity, field, value)` 表。命題層沿用同一個立場。
///
/// 所以 `Proposition` 是**封閉的代數型別**：新增一個 predicate 要改這個 enum，而
/// 那正是要的——編譯器會逼所有 `switch` 一起更新，投射規則與答案空間不會默默
/// 落後於新 predicate。
///
/// ## 封閉而刻意限縮的 predicate 集合
///
/// `authored(person:work:)` 是 snapshot-scoped 的基線；#202 再加入第一個 valid-time
/// vertical slice：`affiliated(person:organization:)`。兩者都維持固定 arity、具方向的
/// role 與明確 identity 狀態；沒有因此退回通用 predicate registry，也沒有一次納入
/// 所有關係。
public enum Proposition: Equatable, Hashable {
    /// 「這個人寫了這件作品」。**方向不可交換**——`authored(a, b)` 與
    /// `authored(b, a)` 是不同的命題，而且後者多半不可投射（work 不是 person）。
    case authored(person: EntityRef, work: EntityRef)
    /// 「這個人在指定有效日隸屬於這個機構」。方向同樣是文法的一部分：
    /// `person → organization`，不能由機構的上級／包含關係反推。
    case affiliated(person: EntityRef, organization: EntityRef)
}

/// 命題引數的兩種 identity 狀態，沿用 store 既有的 `key`／`literal` sum-type。
///
/// **`literal` 不是「壞掉的 key」**，它是一個誠實的狀態：這個符號還沒被歸戶到
/// 任何 identity。把它強制轉成 identity 會**把未知偽裝成已解析的事實**——那是
/// #198 診斷列的風險之一，也是 `resolve-people` 一直堅持「只提名、絕不自動歸戶」
/// 的同一件事。
public enum EntityRef: Equatable, Hashable {
    /// 已歸戶：指向 store 的一個 identity。
    case key(String)
    /// 未歸戶：只有字面符號，還不知道指誰。
    case literal(String)

    public var key: String? { if case let .key(k) = self { return k } else { return nil } }
}

// MARK: - 構造驗證

/// 構造期就拒絕的錯誤。**錯誤的 arity 在型別層已不可表達**（enum 的 case 固定帶
/// 兩個具名引數），所以這裡只剩型別擋不住的那些。
public enum PropositionError: Error, Equatable, LocalizedError, CustomStringConvertible {
    case malformedKey(String)
    case emptyLiteral

    public var errorDescription: String? {
        switch self {
        case .malformedKey(let k):
            return "命題引數的 key 不合法：'\(displaySafe(k, max: 120))'（須符合 ^[a-z0-9][a-z0-9-]*$）"
        case .emptyLiteral:
            return "命題引數的 literal 不可為空——空字串不是一個符號"
        }
    }

    /// 避免一般 `Error` 字串插值反射 associated value，而繞過 `displaySafe`。
    public var description: String {
        errorDescription ?? "命題引數不合法"
    }
}

extension EntityRef {
    /// 驗證這個引數本身是可表達的。
    ///
    /// `key` 走 `StoreKey.isValid`：一個指不到任何 identity 的字串當 key，不是
    /// 「未解析」而是**構造錯誤**——`literal` 才是表達「還不知道指誰」的方式。
    /// 兩者混用會讓「未知」與「壞掉」變成同一個狀態。
    public func validate() throws {
        switch self {
        case .key(let k):
            guard StoreKey.isValid(k) else { throw PropositionError.malformedKey(k) }
        case .literal(let s):
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PropositionError.emptyLiteral
            }
        }
    }
}

extension Proposition {
    /// 具名建構子。這是呼叫端最簡單的安全建構路徑；直接寫
    /// `.authored(person:work:)` 仍可能繞過，所以所有產生投射、真值、答案或 fact
    /// 的公開操作也會在語意邊界呼叫 `validate()`。
    ///
    /// 沒有把 enum 的 case 藏起來改用 `private init`：那會讓 pattern matching
    /// 失去 exhaustiveness，而 exhaustiveness 正是選封閉型別的理由。
    public static func makeAuthored(person: EntityRef, work: EntityRef) throws -> Proposition {
        let p = Proposition.authored(person: person, work: work)
        try p.validate()
        return p
    }

    public static func makeAffiliated(
        person: EntityRef,
        organization: EntityRef
    ) throws -> Proposition {
        let proposition = Proposition.affiliated(person: person, organization: organization)
        try proposition.validate()
        return proposition
    }

    public func validate() throws {
        switch self {
        case let .authored(person, work):
            try person.validate()
            try work.validate()
        case let .affiliated(person, organization):
            try person.validate()
            try organization.validate()
        }
    }

    /// 這個命題的引數，依 predicate 定義的順序。
    public var arguments: [EntityRef] {
        switch self {
        case let .authored(person, work): return [person, work]
        case let .affiliated(person, organization): return [person, organization]
        }
    }

    /// 人可讀的 predicate 名。**只給訊息用**，不參與任何判定——一旦有邏輯讀它，
    /// 封閉型別就退化回字串比對的三元組。
    public var predicateName: String {
        switch self {
        case .authored: return "authored"
        case .affiliated: return "affiliated"
        }
    }
}
