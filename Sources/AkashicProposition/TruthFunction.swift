import Foundation
import AkashicCore

/// 有限真值函數式命題組合（#204）——《邏輯哲學論》命題 5 的那一層。
///
/// # 這一層與 Akashic 的三值**不是同一件事**
///
/// 這是本檔存在的全部理由，也是最容易搞錯的地方：
///
/// | | 這一層（classical） | Akashic 的 `TruthValue` |
/// |---|---|---|
/// | 值域 | **二值** true／false | 三值 holds／fails／undetermined |
/// | 在問什麼 | 給定原子的真假，**複合式**的真假是什麼 | 我們**知不知道**這件事 |
/// | 學科 | 真值函數語意 | 知識狀態 |
/// | TLP 5 對應 | ✅ 就是它 | ❌ 不是 |
///
/// `undetermined` 是**知識不足**，不是「第三個真值」。把它當成三值邏輯的第三個
/// 值再去做 truth table，等於宣稱「我不知道」是世界的一種狀態——那不是命題 5
/// 在講的東西，而且會讓「Akashic 查不到」被誤稱為「《論考》的形式語意」。
///
/// 所以本檔的 evaluator **要求完整的二值賦值**（`ClassicalValuation`），
/// 賦值不完整就**拒絕**，不會偷偷把缺的原子當 false。缺一個原子的 truth table
/// 不是「部分結果」，它根本不是一個 truth table。
///
/// 認識面的組合（`Formula.evaluate(in:)`）走 Kleene 強三值，住在 `Negation.swift`
/// ——兩層各自完整，互不冒充。
public extension Formula {

    /// 原子的**正規化排序鍵**。truth table 的欄位順序必須是決定性的，否則
    /// 「同一個公式的 truth table」在兩次執行間長得不一樣，等價比較也就無從談起。
    static func atomKey(_ p: Proposition) -> String {
        switch p {
        case let .authored(person, work):
            // display-safe-exempt: 這是**排序鍵**不是訊息——消毒會改變鍵的內容，
            // 讓「同一個原子」在消毒前後排到不同位置。鍵流進錯誤訊息的那一處
            // （TruthFunctionError.incompleteValuation）自己消毒。
            func s(_ r: EntityRef) -> String {
                switch r {
                case .key(let k): return "k:\(k)"   // display-safe-exempt: 排序鍵非訊息，見上
                case .literal(let l): return "l:\(l)"   // display-safe-exempt: 同上
                }
            }
            return "authored(\(s(person)),\(s(work)))"
        }
    }

    /// 公式裡的相異原子，依 `atomKey` 排序。
    var canonicalAtoms: [Proposition] {
        var seen = Set<String>()
        var out: [Proposition] = []
        for a in atoms where seen.insert(Formula.atomKey(a)).inserted { out.append(a) }
        return out.sorted { Formula.atomKey($0) < Formula.atomKey($1) }
    }
}

/// 對一組原子的**完整**二值賦值。
///
/// 「完整」是本型別的不變式：構造時就要求涵蓋公式的每一個原子。部分賦值不是
/// 「資訊少一點的賦值」——真值函數對它**沒有定義**。
public struct ClassicalValuation: Equatable {
    private let assignment: [String: Bool]

    /// - Throws: 賦值未涵蓋 `formula` 的某個原子時 `TruthFunctionError.incompleteValuation`。
    public init(formula: Formula, assignment: [Proposition: Bool]) throws {
        var byKey: [String: Bool] = [:]
        for (p, v) in assignment { byKey[Formula.atomKey(p)] = v }
        let missing = formula.canonicalAtoms
            .map(Formula.atomKey)
            .filter { byKey[$0] == nil }
        guard missing.isEmpty else {
            throw TruthFunctionError.incompleteValuation(missing: missing.sorted())
        }
        self.assignment = byKey
    }

    /// 內部用：由 truth table 列舉產生，必然完整。
    fileprivate init(byKey: [String: Bool]) { self.assignment = byKey }

    public func value(of p: Proposition) -> Bool? { assignment[Formula.atomKey(p)] }
}

public enum TruthFunctionError: Error, Equatable, LocalizedError {
    case incompleteValuation(missing: [String])
    case tooManyAtoms(count: Int, limit: Int)

    public var errorDescription: String? {
        switch self {
        case .incompleteValuation(let missing):
            // **這裡才是訊息邊界**：atomKey 的 `l:` 分支帶著命題的 literal，
            // 那是 store 衍生內容，進使用者可見輸出前必須消毒。
            return "賦值不完整，缺少原子："
                + missing.map { displaySafe($0, max: 120) }.joined(separator: "、")
                + "——真值函數對部分賦值沒有定義，不得把缺的當 false"
        case let .tooManyAtoms(count, limit):
            return "公式有 \(count) 個相異原子，truth table 需要 2^\(count) 列，超過上限 \(limit)"   // display-safe-exempt: 三者都是 Int，結構上帶不了 store 內容
        }
    }
}

public extension Formula {

    /// **古典二值求值。** 需要完整賦值。
    func classicalValue(under v: ClassicalValuation) throws -> Bool {
        switch self {
        case .atom(let p):
            guard let b = v.value(of: p) else {
                throw TruthFunctionError.incompleteValuation(missing: [Formula.atomKey(p)])
            }
            return b
        case .not(let f):       return !(try f.classicalValue(under: v))
        case let .and(a, b):    return try a.classicalValue(under: v) && b.classicalValue(under: v)
        case let .or(a, b):     return try a.classicalValue(under: v) || b.classicalValue(under: v)
        // 實質蘊含：`p → q` ≡ `¬p ∨ q`
        case let .implies(a, b): return try !a.classicalValue(under: v) || b.classicalValue(under: v)
        case let .nor(a, b):    return try !(a.classicalValue(under: v) || b.classicalValue(under: v))
        }
    }

    /// 2^n 列的完整 truth table。列的順序與原子順序都是決定性的。
    ///
    /// 有上限：n 個原子要 2^n 列，`limit` 預設 16（65536 列）。超過就**拒絕**
    /// 而非慢慢算——一個算不完的 truth table 對使用者是當機，不是結果。
    func truthTable(limit: Int = 16) throws -> [(valuation: ClassicalValuation, value: Bool)] {
        let atoms = canonicalAtoms
        guard atoms.count <= limit else {
            throw TruthFunctionError.tooManyAtoms(count: atoms.count, limit: limit)
        }
        var rows: [(ClassicalValuation, Bool)] = []
        for mask in 0..<(1 << atoms.count) {
            var byKey: [String: Bool] = [:]
            for (i, a) in atoms.enumerated() {
                byKey[Formula.atomKey(a)] = (mask >> i) & 1 == 1
            }
            let v = ClassicalValuation(byKey: byKey)
            rows.append((v, try classicalValue(under: v)))
        }
        return rows
    }

    /// **以 truth conditions 判斷等價**，不是 AST 字面相同。
    ///
    /// `p ∨ q` 與 `q ∨ p` 的 AST 不同、truth conditions 相同——它們是同一個
    /// 真值函數。反過來，AST 相同必然等價，但拿 AST 當判準會把「不同寫法的同一
    /// 個命題」判成兩個，那正是命題 5 系列（尤其 5.141）要否認的。
    ///
    /// 兩式的原子集合不同時，在**聯集**上比較——`p` 與 `p ∧ (q ∨ ¬q)` 等價。
    func isEquivalent(to other: Formula, limit: Int = 16) throws -> Bool {
        let union = Formula.and(self, other).canonicalAtoms
        guard union.count <= limit else {
            throw TruthFunctionError.tooManyAtoms(count: union.count, limit: limit)
        }
        for mask in 0..<(1 << union.count) {
            var byKey: [String: Bool] = [:]
            for (i, a) in union.enumerated() { byKey[Formula.atomKey(a)] = (mask >> i) & 1 == 1 }
            let v = ClassicalValuation(byKey: byKey)
            if try classicalValue(under: v) != other.classicalValue(under: v) { return false }
        }
        return true
    }

    /// 所有賦值皆真。
    func isTautology(limit: Int = 16) throws -> Bool {
        try truthTable(limit: limit).allSatisfy(\.value)
    }

    /// 所有賦值皆假。
    func isContradiction(limit: Int = 16) throws -> Bool {
        try truthTable(limit: limit).allSatisfy { !$0.value }
    }
}

// MARK: - 完備基底（TLP 5.5 的直接證據）

public extension Formula {

    /// 用**共同否定**（joint denial／NOR，Sheffer 的對偶）重寫這個公式。
    ///
    /// 命題 5.5 說一切真值函數都是對基本命題連續套用單一運算的結果。NOR 是
    /// functionally complete 的單一運算，所以「任何公式都能只用 NOR 重寫」是那句
    /// 話的**可執行**版本。
    ///
    /// `rewrittenAsNor` 的產物與原式**必須等價**——那是這條主張的驗收條件，
    /// 由 `testNorRewriteIsEquivalent` 對所有運算子逐一檢查。
    func rewrittenAsNor() -> Formula {
        switch self {
        case .atom: return self
        // ¬p ≡ p ↓ p
        case .not(let f):
            let r = f.rewrittenAsNor()
            return .nor(r, r)
        // p ∧ q ≡ (p ↓ p) ↓ (q ↓ q)
        case let .and(a, b):
            let x = a.rewrittenAsNor(), y = b.rewrittenAsNor()
            return .nor(.nor(x, x), .nor(y, y))
        // p ∨ q ≡ (p ↓ q) ↓ (p ↓ q)
        case let .or(a, b):
            let x = a.rewrittenAsNor(), y = b.rewrittenAsNor()
            let n = Formula.nor(x, y)
            return .nor(n, n)
        // p → q ≡ ¬p ∨ q
        case let .implies(a, b):
            return Formula.or(.not(a), b).rewrittenAsNor()
        case let .nor(a, b):
            return .nor(a.rewrittenAsNor(), b.rewrittenAsNor())
        }
    }

    /// 這個公式是否只由 atom 與 `nor` 構成。
    var isNorOnly: Bool {
        switch self {
        case .atom: return true
        case let .nor(a, b): return a.isNorOnly && b.isNorOnly
        case .not, .and, .or, .implies: return false
        }
    }
}
