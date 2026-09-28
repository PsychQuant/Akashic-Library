import Foundation
import AkashicCore

/// #642：library 成員規則的跨記錄事實——`validate`／`doctor` 的 warning 與改名、合併的守衛共用這裡。
/// 判定本身只有一份（`LibraryMembershipCheck`，AkashicCore）；這裡只是把它套到整份 load 上。
extension LibraryLoad {
    /// warning 裡逐筆點名的上限。全部列出的面是 `library check`（CLI 不截、MCP 受位元組預算）。
    static let libraryViolationExamples = 5

    /// 規則指涉的東西不在庫、或既有成員不符規則。**warning 不是 error**：成員關係錯了不毀資料，而 error 會讓
    /// `assertNoCrossRecordErrors` 擋下不相干的改名與合併。未標性質的 warning 住在 `Library.validate()`（per-record）。
    func libraryMembershipIssues() -> [ValidationIssue] {
        var out: [ValidationIssue] = []
        let venueKeys = Set(venues.map(\.key))
        for lib in libraries {
            guard let membership = lib.membership else { continue }
            let name = displaySafeInvisible(lib.key, max: 200)
            let members = entries.filter { $0.akashic.libraries.contains(lib.key) }.count
            if let v = membership.referencedVenue, !venueKeys.contains(v) {
                out.append(ValidationIssue(severity: .warning,
                    message: "library「\(name)」的成員規則指向不在庫的 venue「\(displaySafeInvisible(v, max: 200))」"
                           + "——規則對不到任何記錄；先建那筆 venue，或以 akashic library set-kind 改規則（#642）"))
            }
            if case .document(let ck) = membership {
                let hits = entries.filter { $0.citekey == ck }.count
                if hits != 1 {
                    let why = hits == 0 ? "不在庫" : "的 citekey 有 \(hits) 筆"   // display-safe-exempt: Int
                    out.append(ValidationIssue(severity: .warning,
                        message: "library「\(name)」的文件「\(displaySafeInvisible(ck, max: 200))」\(why)"   // display-safe-exempt: why 是本函式的字面常量加 Int
                               + "——查不到它引了什麼，add 一律不寫，現有 \(members) 筆成員無從查證；"   // display-safe-exempt: Int
                               + "先建那筆文件（或修好重複），或以 akashic library set-kind 改（#642）"))
                    continue   // 每一筆成員都會以同一個原因不符——不再逐筆重報
                }
            }
            let bad = LibraryMembershipCheck(library: lib, entries: entries).nonconformingMembers()
            guard !bad.isEmpty else { continue }
            let examples = bad.prefix(Self.libraryViolationExamples)
                .map { "\(displaySafeInvisible($0.citekey, max: 200))（\($0.violation.message)）" }   // display-safe-exempt: violation.message 在 LibraryMembershipViolation 裡已逐項消毒
                .joined(separator: "；")
            let more = bad.count > Self.libraryViolationExamples ? "；…" : ""
            out.append(ValidationIssue(severity: .warning,
                message: "library「\(name)」（\(LibraryMembershipCheck.basis(of: membership))）有 \(bad.count) 筆成員不符規則："   // display-safe-exempt: basis 在 LibraryMembershipCheck 裡已逐項消毒；count 是 Int
                       + examples + more
                       + "——全部列出用 akashic library check \(name)（MCP：akashic_libraries action check），"
                       + "不該在的用 library remove 移除（#642）"))
        }
        return out
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
