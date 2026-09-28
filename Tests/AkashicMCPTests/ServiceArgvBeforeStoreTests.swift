import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #654：服務層只看參數的檢查在讀 store 之前跑——MCP 面與 CLI 的 `validate()` 呼叫的是同一個 static 函式。
///
/// 服務指向一個**沒有 store** 的目錄：若檢查仍排在讀 store 之後，這裡拿到的會是「找不到 venue」「需要 store format ≥ N」之類
/// store 狀態的錯誤，而不是參數的錯誤。每一格斷言的是服務的原句（CLI 的 `ServiceArgvExitCodeTests` 斷言同一批句子）。
final class ServiceArgvBeforeStoreTests: XCTestCase {
    private var bare: URL!
    private var service: AkashicService!
    private let emptyDigest = "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    override func setUpWithError() throws {
        bare = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-argv-first-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        service = AkashicService(root: bare, key: nil, environment: [:])
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: bare) }

    private func assertInvalid(_ needle: String, file: StaticString = #filePath, line: UInt = #line,
                               _ body: () throws -> Any) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            guard case ServiceError.invalid(let why) = error else {
                return XCTFail("應是參數錯誤（ServiceError.invalid），得 \(error)", file: file, line: line)
            }
            XCTAssertTrue(why.contains(needle), "要說出「\(needle)」：\(why)", file: file, line: line)
        }
    }

    /// 先前排在「讀 store 版本」之後的：judge／refute、未決腿、repoint／demote——沒有 store 時會先報 format 或 notFound。
    func testResolveLegSyntaxIsCheckedBeforeTheStore() {
        assertInvalid("缺少 `=`") { try self.service.resolvePeople(apply: nil, judge: ["a2020b:0:p-one"]) }
        assertInvalid("不是三段形") { try self.service.resolvePeople(apply: nil, refute: ["a2020b:p-one=r"]) }
        assertInvalid("的說明是空白") { try self.service.resolvePeople(apply: nil, undecided: ["a2020b:0:p-one= "]) }
        assertInvalid("0 byte") {
            try self.service.resolvePeople(apply: nil, undecided: ["a2020b:0:p-one=查過"], restsOn: [self.emptyDigest])
        }
        assertInvalid("缺少 `=`") { try self.service.splitAuthors(["a2020b:0:與"]) }
        assertInvalid("缺少 `:`") { try self.service.unsplitAuthors(["nocolon"]) }
        assertInvalid("的判定理由是空的") { try self.service.dropAuthors(["a2020b:X= "]) }
        assertInvalid("不是三段形") { try self.service.attributeToOrganizations(["a2020b:x:org=r"]) }
        assertInvalid("不是 citekey:venueIndex:newKey 形") { try self.service.resolveVenues(apply: nil, repoint: ["a2020b:0"]) }
        assertInvalid("不是 citekey:venueIndex 形") { try self.service.resolveVenues(apply: nil, demote: ["a2020b"]) }
        assertInvalid("理由必填") { try self.service.resolveVenues(apply: nil, drop: ["a2020b:0"]) }
        assertInvalid("一次最多判定") {
            try self.service.resolveOrganizations(apply: nil, judge: (0...200).map { "row\($0)@org=x" })
        }
        // org 的 id 要在列表上切（讀 store），但連一個 `@<orgKey>=` 位置都沒有的與列表無關——先前排在 format 閘與 load 之後
        assertInvalid("的格式（orgKey 是小寫英數與連字號）") {
            try self.service.resolveOrganizations(apply: nil, judge: ["no-cut-position=理由"])
        }
        assertInvalid("的格式（orgKey 是小寫英數與連字號）") {
            try self.service.resolveOrganizations(apply: nil, undecided: ["row@Org=x"])
        }
    }

    /// 先前排在「讀 store、確認記錄存在」之後的：update-venue 的參數、add-person 的 orcid、add-venue 的名字。
    func testRecordArgumentsAreCheckedBeforeTheStore() {
        assertInvalid("缺少 `=`") {
            try self.service.updateVenue(key: "v-one", addNames: nil, note: nil, type: nil, removeISSN: ["0378-5955"])
        }
        assertInvalid("設 paginated 必附 judgement") {
            try self.service.updateVenue(key: "v-one", addNames: nil, note: nil, type: nil, paginated: true)
        }
        // 這一格的錯誤來自 `ProvenanceReference` 的平面 init（rests-on 的單一驗證入口），型別是 store 層的欄位錯誤
        XCTAssertThrowsError(try self.service.updateVenue(key: "v-one", addNames: nil, note: nil, type: nil, paginated: true,
                                                          judgement: "j", restsOn: [self.emptyDigest])) { error in
            XCTAssertTrue("\(error)".contains("0 byte"), "空內容的 digest 要在讀 store 之前被拒：\(error)")
            XCTAssertFalse("\(error)".contains("找不到"), "不得先報 venue 不存在：\(error)")
        }
        assertInvalid("兩句矛盾的話") {
            try self.service.updateVenue(key: "v-one", addNames: nil, note: nil, type: nil,
                                         addVariant: ["Alpha"], authorize: ["Alpha"])
        }
        assertInvalid("不是合法的 ORCID") { try self.service.addPerson(key: "p-one", names: ["X"], orcid: "0000", openalex: nil) }
        assertInvalid("不符合") { try self.service.addPerson(key: "Bad Key", names: ["X"], orcid: nil, openalex: nil) }
        assertInvalid("names 全是空白") { try self.service.addVenue(key: "v-one", names: ["  "], type: "periodical") }
        assertInvalid("mediaType 不可為空") {
            try self.service.storeSource(path: "/nonexistent", mediaType: " ", retrieved: "r", origin: "o", acquisition: "a")
        }
        assertInvalid("kind 必須是 cites / related") { try self.service.link(citekey: "a2020b", kind: "nope", add: ["b"], remove: []) }
        assertInvalid("status 與 clear 互斥") { try self.service.setStatus(citekey: "a2020b", status: "read", clear: true) }
        assertInvalid("add 與 remove 至少要給一個") { try self.service.tag(citekey: "a2020b", add: [], remove: []) }
        assertInvalid("key 與 name 互斥") { try self.service.person(key: "p", name: "n", library: nil) }
        assertInvalid("候選格式為 `key:shape`") {
            try self.service.recordDivergence(question: "q", candidates: ["p-a:bogus", "p-b:person"], judgement: nil, restsOn: [])
        }
    }
}
