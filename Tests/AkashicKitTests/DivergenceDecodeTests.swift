import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// `divergence` 形狀的載入與拒絕條件（#71）。
///
/// 這個形狀承載的是**未決的同一性問題**：兩個以上的候選可能指向同一個對象，
/// 而還沒有人判定。拒絕條件全部來自 design 的「失敗模式」表——它們不是防禦性
/// 檢查，而是形狀本身的意義：少於兩個候選的「歧異」沒有東西可以與之相同。
final class DivergenceDecodeTests: XCTestCase {

    // MARK: - 正常路徑

    /// 兩個同形狀候選 → 接受。
    ///
    /// 例子取自 spec 的 `Example: Two spellings of one name`——名冊裡同一位研究員
    /// 的兩種排版慣例，`bootstrap-people` 依「寧可分割」建成兩筆。
    func testTwoCandidatesLoads() throws {
        let yaml = """
        divergence:
        id: 6577DE3B-DAFE-5CC0-A9DE-2E04030737B3
        question: 是否為同一人
        candidates:
        - key: fann-cathy-s-j
          shape: person
        - key: fann-cathy-s-j-2
          shape: person

        """
        let d = try DivergenceYAML.decode(yaml)
        XCTAssertEqual(d.question, "是否為同一人")
        XCTAssertEqual(d.candidates.map(\.key), ["fann-cathy-s-j", "fann-cathy-s-j-2"])
        XCTAssertNil(d.judgement, "未判定時不該有判斷")
    }

    /// 帶判斷與證據 → 接受。兩者成對出現。
    func testJudgementWithRestsOnLoads() throws {
        let d = try DivergenceYAML.decode(Self.withJudgement)
        let j = try XCTUnwrap(d.judgement)
        XCTAssertEqual(j.statement,
                       "兩者的姓與 given initials 一致，差異僅在連字號與句點的排版慣例")
        XCTAssertEqual(j.restsOn, ["sha256:9a23d701e4fe4888"])
    }

    // MARK: - 拒絕條件（design「失敗模式」前四列）

    /// 候選少於兩筆 → 拒絕。
    ///
    /// 「這些是不是同一個」需要有東西與之相同；一個候選的歧異不是歧異。
    func testSingleCandidateRefused() throws {
        let yaml = """
        divergence:
        id: 6577DE3B-DAFE-5CC0-A9DE-2E04030737B3
        question: 是否為同一人
        candidates:
        - key: fann-cathy-s-j
          shape: person

        """
        XCTAssertThrowsError(try DivergenceYAML.decode(yaml)) { error in
            let msg = "\(error)"
            XCTAssertTrue(msg.contains("兩個"), "錯誤須說明至少需要兩個候選：\(msg)")
        }
    }

    /// 候選跨形狀 → 拒絕，且錯誤同時指名兩個候選。
    ///
    /// 「這些是不是同一個」在跨形狀時無法回答：一個 person 與一個 work 不可能是
    /// 同一個對象，那不是未決的問題而是類別錯誤。
    func testCandidatesSpanningShapesRefused() throws {
        let yaml = """
        divergence:
        id: 6577DE3B-DAFE-5CC0-A9DE-2E04030737B3
        question: 是否為同一個
        candidates:
        - key: fann-cathy-s-j
          shape: person
        - key: shen2015model
          shape: work

        """
        XCTAssertThrowsError(try DivergenceYAML.decode(yaml)) { error in
            let msg = "\(error)"
            XCTAssertTrue(msg.contains("fann-cathy-s-j") && msg.contains("shen2015model"),
                          "錯誤須指名兩個候選：\(msg)")
            XCTAssertTrue(msg.contains("person") && msg.contains("work"),
                          "錯誤須指名各自的形狀：\(msg)")
        }
    }

    /// 有判斷無證據 → 拒絕。
    ///
    /// 一個沒有依據的斷言不是判斷，是意見。這條與下一條共同保證
    /// `judgement` / `rests-on` 成對——否則「這筆 provenance 完不完整」無法機械判定。
    func testJudgementWithoutRestsOnRefused() throws {
        let yaml = Self.withJudgement
            .replacingOccurrences(of: "rests-on:\n- sha256:9a23d701e4fe4888\n", with: "")
        XCTAssertThrowsError(try DivergenceYAML.decode(yaml)) { error in
            XCTAssertTrue("\(error)".contains("成對"), "錯誤須說明兩者成對：\(error)")
        }
    }

    /// 有證據無判斷 → 拒絕。
    func testRestsOnWithoutJudgementRefused() throws {
        let yaml = Self.withJudgement.split(separator: "\n")
            .filter { !$0.hasPrefix("judgement:") }
            .joined(separator: "\n") + "\n"
        XCTAssertThrowsError(try DivergenceYAML.decode(yaml)) { error in
            XCTAssertTrue("\(error)".contains("成對"), "錯誤須說明兩者成對：\(error)")
        }
    }

    // MARK: - 承載的可觀察性

    /// 記錄真的進得了 store，且不是被 quarantine 掉。
    ///
    /// decode 綠燈只證明「這串字轉得成型別」；載入路徑另有檔名即身分的檢查
    /// （stem 必須是合法 UUID 且與記錄的 id 相符），那條路徑要單獨走過一次。
    func testLoadReportsDivergence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-div-load-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        let store = LibraryStore(root: root)

        let d = Divergence(
            id: UUID(), question: "是否為同一人",
            candidates: [DivergenceCandidate(key: "fann-cathy-s-j", shape: .person),
                         DivergenceCandidate(key: "fann-cathy-s-j-2", shape: .person)])
        try store.writeDivergence(d)

        let load = try store.load()
        XCTAssertTrue(load.quarantined.isEmpty, "\(load.quarantined)")
        XCTAssertEqual(load.divergences.map(\.id), [d.id])
    }

    // MARK: - Fixtures

    static let withJudgement = """
    divergence:
    id: 6577DE3B-DAFE-5CC0-A9DE-2E04030737B3
    question: 是否為同一人
    candidates:
    - key: fann-cathy-s-j
      shape: person
    - key: fann-cathy-s-j-2
      shape: person
    judgement: 兩者的姓與 given initials 一致，差異僅在連字號與句點的排版慣例
    rests-on:
    - sha256:9a23d701e4fe4888

    """
}
