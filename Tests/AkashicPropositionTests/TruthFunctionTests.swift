import XCTest
import AkashicCore
@testable import AkashicProposition

/// #204：有限真值函數式組合（TLP 5 那一層）。
///
/// **本檔守的第一件事是「這一層不是 Akashic 的三值」**——古典二值 truth-function
/// 與知識狀態是兩件事，混用會把「我們查不到」誤稱為《論考》的形式語意。
final class TruthFunctionTests: XCTestCase {

    private func atom(_ n: String) -> Proposition {
        .authored(person: .key("p\(n)"), work: .key("w\(n)"))
    }
    private var p: Formula { .atom(atom("1")) }
    private var q: Formula { .atom(atom("2")) }

    private func val(_ f: Formula, _ a: [(Proposition, Bool)]) throws -> Bool {
        try f.classicalValue(under: ClassicalValuation(
            formula: f, assignment: Dictionary(uniqueKeysWithValues: a)))
    }

    // MARK: - 完整賦值是不變式

    /// **部分賦值不是「資訊少一點的賦值」——真值函數對它沒有定義。**
    /// 不得把缺的原子當 false。
    func testIncompleteValuationIsRefusedNotDefaulted() {
        let f = Formula.and(p, q)
        XCTAssertThrowsError(try ClassicalValuation(formula: f,
                                                    assignment: [atom("1"): true])) { e in
            guard case .incompleteValuation(let missing) = e as? TruthFunctionError else {
                return XCTFail("應為 incompleteValuation，實際 \(e)")
            }
            XCTAssertEqual(missing.count, 1)
        }
    }

    // MARK: - 古典真值表

    func testClassicalOperators() throws {
        let t = (atom("1"), true), f = (atom("1"), false)
        let t2 = (atom("2"), true), f2 = (atom("2"), false)
        XCTAssertFalse(try val(.not(p), [t]))
        XCTAssertTrue(try val(.not(p), [f]))
        XCTAssertTrue(try val(.and(p, q), [t, t2]))
        XCTAssertFalse(try val(.and(p, q), [t, f2]))
        XCTAssertTrue(try val(.or(p, q), [f, t2]))
        XCTAssertFalse(try val(.or(p, q), [f, f2]))
        // 實質蘊含：只有 T→F 為假
        XCTAssertFalse(try val(.implies(p, q), [t, f2]))
        XCTAssertTrue(try val(.implies(p, q), [f, f2]))
        XCTAssertTrue(try val(.implies(p, q), [f, t2]))
        XCTAssertTrue(try val(.implies(p, q), [t, t2]))
        // NOR：只有雙假為真
        XCTAssertTrue(try val(.nor(p, q), [f, f2]))
        XCTAssertFalse(try val(.nor(p, q), [t, f2]))
    }

    /// 2^n 列，且列與欄的順序決定性。
    func testTruthTableIsCompleteAndDeterministic() throws {
        let f = Formula.implies(p, q)
        let t1 = try f.truthTable(), t2 = try f.truthTable()
        XCTAssertEqual(t1.count, 4, "2 個原子 → 4 列")
        XCTAssertEqual(t1.map(\.value), t2.map(\.value), "兩次必須一樣")
        XCTAssertEqual(t1.filter { !$0.value }.count, 1, "蘊含只有一列為假")
    }

    /// 原子多到算不完就**拒絕**——算不完的 truth table 對使用者是當機不是結果。
    func testTooManyAtomsIsRefused() {
        var f = Formula.atom(atom("0"))
        for i in 1...5 { f = .and(f, .atom(atom("\(i)"))) }
        XCTAssertThrowsError(try f.truthTable(limit: 3)) { e in
            guard case .tooManyAtoms = e as? TruthFunctionError else {
                return XCTFail("應為 tooManyAtoms，實際 \(e)")
            }
        }
    }

    // MARK: - 等價以 truth conditions 判斷，不是 AST

    /// `p ∨ q` 與 `q ∨ p` 的 **AST 不同、真值條件相同**。拿 AST 當判準會把
    /// 「不同寫法的同一個命題」判成兩個。
    func testEquivalenceIsByTruthConditionsNotAST() throws {
        XCTAssertNotEqual(Formula.or(p, q), Formula.or(q, p), "AST 確實不同")
        XCTAssertTrue(try Formula.or(p, q).isEquivalent(to: .or(q, p)), "但真值條件相同")
    }

    /// De Morgan 與實質蘊含的定義。
    func testClassicalEquivalences() throws {
        XCTAssertTrue(try Formula.not(.and(p, q)).isEquivalent(to: .or(.not(p), .not(q))))
        XCTAssertTrue(try Formula.not(.or(p, q)).isEquivalent(to: .and(.not(p), .not(q))))
        XCTAssertTrue(try Formula.implies(p, q).isEquivalent(to: .or(.not(p), q)))
        XCTAssertFalse(try Formula.implies(p, q).isEquivalent(to: .implies(q, p)),
                       "蘊含不對稱")
    }

    /// 原子集合不同時在**聯集**上比較——`p` 與 `p ∧ (q ∨ ¬q)` 等價。
    func testEquivalenceAcrossDifferentAtomSets() throws {
        XCTAssertTrue(try p.isEquivalent(to: .and(p, .or(q, .not(q)))))
    }

    func testTautologyAndContradiction() throws {
        XCTAssertTrue(try Formula.or(p, .not(p)).isTautology())
        XCTAssertTrue(try Formula.and(p, .not(p)).isContradiction())
        XCTAssertFalse(try p.isTautology())
        XCTAssertFalse(try p.isContradiction())
    }

    // MARK: - TLP 5.5 的完備基底

    /// **每個運算子都能只用 NOR 重寫，且重寫後等價。** 這是「一切真值函數都是
    /// 對基本命題連續套用單一運算的結果」的可執行版本。
    func testNorRewriteIsEquivalent() throws {
        let cases: [Formula] = [
            .not(p), .and(p, q), .or(p, q), .implies(p, q),
            .and(.or(p, q), .not(.implies(q, p))),          // 巢狀
        ]
        for f in cases {
            let n = f.rewrittenAsNor()
            XCTAssertTrue(n.isNorOnly, "重寫後應只剩 atom 與 nor：\(n)")
            XCTAssertTrue(try f.isEquivalent(to: n), "重寫必須等價：\(f)")
        }
    }

    // MARK: - 分層：三值不得冒充二值

    /// **同一個公式，兩層給出不同種類的答案**——這正是分層的意義。
    ///
    /// 古典層要求完整二值賦值、回 `Bool`；認識層對 model 求值、回三值。
    /// 認識層的 `.undetermined` **不會**出現在 truth table 裡。
    func testEpistemicLayerIsNotTheClassicalLayer() throws {
        var e = Entry(id: UUID(), citekey: "w1", type: "article", title: "T",
                      authors: [], date: "2025")
        e.fields = [:]
        let m = try PropositionModel(entries: [e], people: [Person(key: "p1", names: ["A"])])

        // 認識層：查不到 → 未定
        guard case .undetermined = try Formula.atom(atom("1")).evaluate(in: m) else {
            return XCTFail("認識層應為未定")
        }
        // 古典層：給定賦值 → 二值，沒有第三種
        let f = Formula.atom(atom("1"))
        XCTAssertTrue(try val(f, [(atom("1"), true)]))
        XCTAssertFalse(try val(f, [(atom("1"), false)]))
        // truth table 的值域是 Bool——結構上放不進 undetermined
        XCTAssertEqual(try f.truthTable().count, 2)
    }

    /// 認識層的組合走 **Kleene 強三值**：已知部分足以決定時就給結果。
    /// `false ∧ unknown` 是 false——不論那個 unknown 是什麼，合取都為假。
    func testKleeneStrongComposition() {
        let unknown = TruthValue.undetermined(.noSupportingEvidence)
        XCTAssertEqual(Formula.kleeneAnd(.fails, unknown), .fails, "假 ∧ 未知 = 假")
        XCTAssertEqual(Formula.kleeneOr(.holds, unknown), .holds, "真 ∨ 未知 = 真")
        XCTAssertEqual(Formula.kleeneAnd(.holds, unknown), unknown, "真 ∧ 未知 = 未知")
        XCTAssertEqual(Formula.kleeneOr(.fails, unknown), unknown, "假 ∨ 未知 = 未知")
        XCTAssertEqual(Formula.kleeneNot(unknown), unknown, "¬未知 = 未知")
    }
}
