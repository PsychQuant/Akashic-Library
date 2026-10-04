import Foundation
import AkashicCore

/// #642：library 成員規則的跨記錄事實——`validate`／`doctor` 的 warning 與改名、合併的守衛共用這裡。
/// 判定本身只有一份（`LibraryMembershipCheck`，AkashicCore）；這裡只是把它套到整份 load 上。
extension LibraryLoad {
    /// warning 裡逐筆點名的上限。全部列出的面是 `library check`（CLI 不截、MCP 受位元組預算）。
    static let libraryViolationExamples = 5

    /// 規則指涉的東西不在庫、規則的依據不明確、或既有成員不符規則。**warning 不是 error**：成員關係錯了不毀資料，而 error 會讓
    /// `assertNoCrossRecordErrors` 擋下不相干的改名與合併。未標性質的 warning 住在 `Library.validate()`（per-record）。
    func libraryMembershipIssues() -> [ValidationIssue] {
        var out: [ValidationIssue] = []
        let venueKeys = Set(venues.map(\.key))
        let entryKeys = Set(entries.map(\.citekey))
        for lib in libraries {
            guard let membership = lib.membership else { continue }
            let name = displaySafeInvisible(lib.key, max: 200)
            let members = entries.filter { $0.akashic.libraries.contains(lib.key) }.count
            if let v = membership.referencedVenue, !venueKeys.contains(v) {
                out.append(ValidationIssue(severity: .warning,
                    message: "library「\(name)」的成員規則指向不在庫的 venue「\(displaySafeInvisible(v, max: 200))」"
                           + "——規則對不到任何記錄；先建那筆 venue，或以 akashic library set-kind 改規則（#642）"))
            }
            let check = LibraryMembershipCheck(library: lib, entries: entries, venues: venues)
            // 依據本身有問題：每一筆成員都會以同一個原因不符——說一次，不逐筆重報（零成員的 library 也看得到）
            if let problem = check.basisProblem {
                out.append(ValidationIssue(severity: .warning,
                    message: "library「\(name)」的成員規則依據不明確：\(problem.message)"   // display-safe-exempt: problem.message：message 已逐項消毒
                           + "；add 一律不寫，現有 \(members) 筆成員無從查證（以 akashic library set-kind 改規則，或先修好依據；#642）"))   // display-safe-exempt: Int
                continue
            }
            // 排除清單指向不在庫的 citekey：排除對不到任何 work。打錯的 citekey 讓排除無聲失效——而那正是排除要防的東西
            // 會被收進來；刪檔或改名（未經 rename）之後也會出現這個狀態（#642 R1 verify）
            if case .rule(let rule) = membership {
                let dangling = rule.excluded.filter { !entryKeys.contains($0) }
                if !dangling.isEmpty {
                    let shown = dangling.prefix(Self.libraryViolationExamples).map { displaySafeInvisible($0, max: 200) }.joined(separator: "、")
                    out.append(ValidationIssue(severity: .warning,
                        message: "library「\(name)」的排除清單有 \(dangling.count) 筆指向不在庫的 citekey：\(shown)"   // display-safe-exempt: Int；shown 已逐項 displaySafeInvisible
                               + (dangling.count > Self.libraryViolationExamples ? "…" : "")
                               + "——排除對不到任何 work（citekey 打錯、或那筆已刪除）；完整規則用 akashic library check \(name)，"
                               + "改規則用 akashic library set-kind（#642）"))
                }
            }
            let bad = check.nonconformingMembers()
            guard !bad.isEmpty else { continue }
            let examples = bad.prefix(Self.libraryViolationExamples)
                .map { "\(displaySafeInvisible($0.citekey, max: 200))（\($0.violation.message)）" }   // display-safe-exempt: $0.violation.message：violation.message 在 LibraryMembershipViolation 裡已逐項消毒
                .joined(separator: "；")
            let more = bad.count > Self.libraryViolationExamples ? "；…" : ""
            // 指路句放前段：MCP doctor 每則訊息截 300 字，點名 ≥3 筆時放在尾端的指路句會被切掉（#642 R1 verify）
            out.append(ValidationIssue(severity: .warning,
                message: "library「\(name)」有 \(bad.count) 筆成員不符規則（全部列出用 akashic library check \(name)；"   // display-safe-exempt: Int
                       + "MCP：akashic_libraries action check；不該在的用 library remove 移除）：\(examples)\(more)"
                       + "——規則：\(LibraryMembershipCheck.basis(of: membership))（#642）"))   // display-safe-exempt: basis 在 LibraryMembershipCheck 裡已逐項消毒
        }
        return out
    }

    /// `library list`／`library check`／`set-kind`（CLI 與 MCP）讀的一個 library 的成員數、不符清單與依據問題（#709 第三次 verify）——
    /// 三個面同一個函式，不各自組。
    ///
    /// - 成員數與不符清單是**讀數**：成員取以 entities/ 為準的視圖（`withoutShadowedLegacyCopies`），一對 legacy 拷貝算一個成員、同一個 citekey
    ///   不列兩次。`view` 由呼叫端傳入（`library list` 對每個 library 共用一份視圖）。
    /// - 依據（`basisProblem`：文件型的文件在庫裡有幾筆、規則的 venue key 有幾筆）是**判定**：看完整的 load，與 `library add`、
    ///   `validate`（`libraryMembershipIssues`）、App 的加入動作同一份。文件自己有 legacy 拷貝時依據不明確——add 拒絕，這裡也照說。
    public func membershipReading(of library: Library, view: [Entry])
        -> (members: Int, violations: [(citekey: String, violation: LibraryMembershipViolation)],
            basisProblem: LibraryMembershipViolation?) {
        let check = LibraryMembershipCheck(library: library, entries: entries, venues: venues)
        return (view.filter { $0.akashic.libraries.contains(library.key) }.count,
                check.nonconformingMembers(among: view), check.basisProblem)
    }

    /// 成員規則指涉某個 citekey（文件型的文件、規則型的排除清單）的 library key——改名與 work 合併問它。
    public func librariesNaming(citekey: String) -> [String] {
        libraries.filter { $0.membership?.referencedCitekeys.contains(citekey) ?? false }.map(\.key).sorted()
    }

    /// 成員規則以某個 venue 界定的 library key——venue 合併問它。
    public func librariesNaming(venue: String) -> [String] {
        libraries.filter { $0.membership?.referencedVenue == venue }.map(\.key).sorted()
    }
}

/// 改名時被同批遷移的一條 library 成員規則（第 16 條邊；#642 R1 verify）。報告逐條列出——改名改寫了**別的**記錄，
/// 不印等於沒發生過（`renameEntry` 對其他遷移面的既有立場）。
public struct LibraryRuleRewrite: Equatable {
    public enum Role: String, Equatable {
        case document = "文件"
        case excluded = "排除"
    }
    public var library: String
    public var role: Role
    public var from: String
    public var to: String

    public init(library: String, role: Role, from: String, to: String) {
        self.library = library; self.role = role; self.from = from; self.to = to
    }

    /// 已消毒——呼叫端不再包一次（`displaySafe` 不冪等）。
    public var describedSafely: String {
        "library「\(displaySafeInvisible(library, max: 200))」的\(role.rawValue)：\(displaySafeInvisible(from, max: 200)) → \(displaySafeInvisible(to, max: 200))"   // display-safe-exempt: role.rawValue 是封閉值域（文件／排除）
    }
}

extension LibraryLoad {
    /// 改名 `old` → `new` 時，成員規則裡要跟著換的 citekey（文件型的文件、規則型的排除清單）。回傳只含**真的會變**的 library：
    /// 改寫前、改寫後、逐條紀錄。規則是 library 的屬性（第 16 條邊）而改名不改身分——所以遷移它，不是拒絕它。
    /// 呼叫端負責先確認 `new` 沒有被任何規則指涉（`librariesNaming(citekey: new)` 為空），否則排除清單可能出現重複。
    func libraryRulesMigrating(citekey old: String, to new: String)
        -> [(before: Library, after: Library, rewrites: [LibraryRuleRewrite])] {
        var out: [(before: Library, after: Library, rewrites: [LibraryRuleRewrite])] = []
        for lib in libraries {
            var after = lib
            var rewrites: [LibraryRuleRewrite] = []
            switch lib.membership {
            case .document(let ck)? where ck == old:
                after.membership = .document(citekey: new)
                rewrites.append(.init(library: lib.key, role: .document, from: old, to: new))
            case .rule(var rule)? where rule.excluded.contains(old):
                rule.excluded = rule.excluded.map { $0 == old ? new : $0 }
                after.membership = .rule(rule)
                rewrites.append(.init(library: lib.key, role: .excluded, from: old, to: new))
            default:
                continue
            }
            out.append((before: lib, after: after, rewrites: rewrites))
        }
        return out
    }
}

extension LibraryLoad {
    /// 合併時被併的鍵被 library 規則指涉，要給一條**做得到的出路**（#642 R1 verify：先前只說「先 set-kind」，而 set-kind 是整值替換、
    /// 操作者得先自己拼出整條規則）。逐個 library 寫出可直接照做的命令；命令裡只有 StoreKey 與 entry type 的字面值
    /// （不含 shell 特殊字元），`source` 是自由文字所以不內嵌、改指 `library check`。
    ///
    /// **這些出路都不經過 topic**：規則全程都在，只是換了指涉的對象（倖存者一定在庫，`set-kind` 的參照檢查過得了）。
    /// 而 `set-kind` 替換既有規則要求 registry 檔已 commit（舊值只剩 git 那一份）。
    /// `merged` 是被併的鍵（work 的 citekey 或 venue 的 key），`survivor` 是倖存者。
    func libraryRuleMergeSteps(libraries keys: [String], merged: String, survivor: String) -> [String] {
        func s(_ v: String) -> String { displaySafeInvisible(v, max: 200) }
        var out: [String] = []
        for key in keys {
            guard let lib = libraries.first(where: { $0.key == key }), let membership = lib.membership else { continue }
            let head = "akashic library set-kind \(s(key))"
            switch membership {
            case .topic:
                continue
            case .document:
                out.append("library「\(s(key))」（文件型，文件是被併的「\(s(merged))」）：\(head) --kind document --document \(s(survivor))")
            case .rule(let r):
                var cmd = "\(head) --kind rule --venue " + s(r.venue == merged ? survivor : r.venue)
                for ty in r.types { cmd += " --type \(ty.rawValue)" }   // display-safe-exempt: WorkType.rawValue 是封閉值域
                let excluded = r.excluded.contains(merged)
                    ? r.excluded.filter { $0 != merged } + (r.excluded.contains(survivor) ? [] : [survivor])
                    : r.excluded
                let what: String
                if r.venue == merged {
                    what = "規則的 venue 是被併的「\(s(merged))」"
                } else {
                    what = "排除清單有被併的「\(s(merged))」"
                }
                if excluded.count <= 8 {
                    for ck in excluded { cmd += " --exclude \(s(ck))" }
                } else {
                    cmd += " --exclude <每個排除的 citekey——用 akashic library check \(s(key)) 讀出全部"
                    if r.excluded.contains(merged) { cmd += "；其中被併的「\(s(merged))」換成倖存者「\(s(survivor))」（倖存者已在清單裡就直接拿掉被併者）" }
                    cmd += ">"
                }
                if r.source != nil { cmd += " --source <來歷：照 library check 印出的原值>" }
                out.append("library「\(s(key))」（規則型，\(what)）：\(cmd)")
            }
        }
        return out
    }
}

extension LibraryStore {
    /// **被隔離的 registry 檔**（`libraries/…`）裡位元組提到這些鍵的檔案（#642 R1 verify）。
    ///
    /// 一個 membership 形狀不合法的 registry 檔整檔進 quarantine，它的成員規則就不在 `load.libraries`——改名的守衛
    /// 只掃 `load.libraries`，於是對那條規則看不見、放行，之後規則安靜懸空。（合併不缺這一半，見下方 `quarantinedRegistryRefusal`。）與 `assertNoVerdictAlreadyAt` 對 quarantined 檔的
    /// 立場相同：讀不出來的檔，用位元組比對它有沒有提到要動的鍵（**token 邊界**：鍵前後不是 StoreKey 字元；不是子字串——
    /// 短鍵 `pm` 不該被 `ppm-catalog` 擋下）。讀不到內容一律當成提到（fail-closed）。
    /// **只擋提到那個鍵的**：一個壞掉的 registry 檔不會讓不相干的改名與合併永久卡住。
    func quarantinedRegistryFiles(mentioning keys: [String], in load: LibraryLoad) -> [String] {
        var out: [String] = []
        for q in load.quarantined where q.file.hasPrefix("libraries/") {
            guard let text = try? String(contentsOf: root.appendingPathComponent(q.file), encoding: .utf8) else {
                out.append(q.file)   // fail-closed
                continue
            }
            if keys.contains(where: { Self.containsKeyToken(text, $0) }) { out.append(q.file) }
        }
        return out.sorted()
    }

    static func containsKeyToken(_ text: String, _ key: String) -> Bool {
        guard !key.isEmpty else { return false }
        func isKeyChar(_ c: Character?) -> Bool {
            guard let c else { return false }
            return c.isASCII && (c.isLetter || c.isNumber || c == "-")
        }
        var search = text.startIndex..<text.endIndex
        while let r = text.range(of: key, range: search) {
            let before: Character? = r.lowerBound == text.startIndex ? nil : text[text.index(before: r.lowerBound)]
            let after: Character? = r.upperBound == text.endIndex ? nil : text[r.upperBound]
            if !isKeyChar(before), !isKeyChar(after) { return true }
            search = r.upperBound..<text.endIndex
        }
        return false
    }

    /// 被隔離的 registry 檔擋下改名的拒絕句。`why` 是這個操作要動的東西的一句。合併不需要它：`resolveDivergence` 對所有 quarantined 檔
    /// 本來就做位元組比對（`DivergenceResolveError.quarantinedPresent`，#295，不分目錄）。
    static func quarantinedRegistryRefusal(files: [String], why: String) -> String {
        "被隔離的 registry 檔提到\(why)，但它的成員規則讀不出來（quarantine），改名與合併看不見它、放行之後規則會安靜懸空："   // display-safe-exempt: why 由呼叫端組、已消毒
        + files.prefix(5).map { displaySafeInvisible($0, max: 300) }.joined(separator: "、")
        + (files.count > 5 ? "…" : "")
        + "——先修好那個檔（akashic validate 會說它為什麼被隔離）或把它移走，再重跑"
    }
}
