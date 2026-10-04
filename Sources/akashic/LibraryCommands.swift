import ArgumentParser
import Foundation
import AkashicCore
import AkashicMCPKit
import AkashicStoreIO
import AkashicIndex

/// #13 多 library（membership views）：registry 管理 + 成員操作。
/// store 是全集；library 只是具名成員集合，成員關係存在各 entry 的 akashic.libraries。
struct LibraryCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "library",
        abstract: "具名 library（成員集合視角）管理：list / create / add / remove / set-kind / check。注意：同一 store 的並發 add/remove/create（如 CLI 與 MCP 同時操作）不保證安全——見 README",
        discussion: """
        每個 library 有成員性質（#642）：topic（主題型，成員由你挑，照寫）、rule（規則型，以 venue key 界定，可加 \
        --type 與 --exclude）、document（文件型，成員是一筆在庫文件的 cites）。add 對 rule／document 逐筆比對，\
        不符的不寫並說出原因（不是拒絕整批，也不是照寫）；未標性質的 library 拒絕 add——先 set-kind。\
        rule／document 需要 store format ≥ \(StoreVersion.libraryMembershipFormat)（topic 不需要）；\
        **不要為了讓 add 通過而標 topic**——topic 不檢查成員。\
        set-kind 是整值替換（--type／--exclude／--source 沒再給就是清掉）：輸出帶被換掉的舊規則；規則指涉的 venue、\
        文件與排除的 citekey 都要在庫；替換一條既有的性質要求 registry 檔已 commit 且乾淨（舊值只剩 git 那一份）。\
        library check 印出完整規則（含每一個排除的 citekey）。
        """,
        subcommands: [LibraryList.self, LibraryCreate.self, LibraryAdd.self, LibraryRemove.self,
                      LibrarySetKind.self, LibraryCheck.self])
}

struct LibraryList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list", abstract: "列出 registry 中的 libraries 與成員數")

    @OptionGroup var options: LibraryOptions

    func run() throws {
        let store = try options.openStore()
        let load = try store.load()
        if load.libraries.isEmpty {
            print("（無 library——用 akashic library create <key> --name <名> --kind <topic|rule|document> 建立）")
            return
        }
        // 成員數與不符數取 entities/ 那份（#709 R2 verify）：一對 legacy 拷貝先前算成兩個成員。依據看完整的 load（`membershipReading`）
        let view = load.withoutShadowedLegacyCopies().entries
        var counts: [String: Int] = [:]
        for entry in view {
            for key in Set(entry.akashic.libraries) { counts[key, default: 0] += 1 }
        }
        for library in load.libraries {
            // 分隔的 U+3000 是程式自己放的、只消毒 store 字串——整串一起消毒會把分隔符印成 `\u{3000}`（#569 R1 verify：
            // 非 U+0020 的 Zs 自 #569 起在人可讀輸出逃脫）
            let desc = library.description.map { "　" + displaySafe($0, max: 800) } ?? ""
            print("\(displaySafe(library.key, max: 200))\t\(displaySafe(library.name, max: 800))（\(counts[library.key] ?? 0) entries）\(desc)")   // display-safe-exempt: counts[library.key]：dict 查找，值是 Int 計數；key 只是索引不進輸出
            // #642：性質與依據——要問「掛哪個 library」的地方要看得到它，不再只靠讀描述
            var basis = "  " + LibraryMembershipCheck.basis(of: library.membership)   // display-safe-exempt: basis 在 LibraryMembershipCheck 裡已逐項消毒
            if library.membership != nil {
                let bad = load.membershipReading(of: library, view: view).violations.count
                if bad > 0 { basis += "——\(bad) 筆成員不符規則（akashic library check \(displaySafe(library.key, max: 200))）" }   // display-safe-exempt: Int
            }
            print(basis)
        }
    }
}

struct LibraryCreate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create", abstract: "建立 library（registry metadata；不動任何 entry）")

    @OptionGroup var options: LibraryOptions
    @Argument(help: "library key（StoreKey 格式：小寫英數與連字號）") var key: String
    @Option(name: .long, help: "顯示名稱") var name: String
    @Option(name: .long, help: "描述（選填）") var description: String?
    @Option(name: .long, help: "成員性質（必填，#642）：topic｜rule｜document——見 akashic library --help") var kind: String?
    @Option(name: .long, help: "rule：venue key——成員必須有一條指向它的 key 邊（venue 要先在庫）") var venue: String?
    @Option(name: .customLong("type"), help: "rule：限定 entry type（可重複；不給＝不限）") var types: [String] = []
    @Option(name: .customLong("exclude"), help: "rule：依裁決不收的 citekey（可重複）") var excluded: [String] = []
    @Option(name: .long, help: "document：文件的 citekey——它的 cites 即成員（文件要先在庫）") var document: String?
    @Option(name: .long, help: "rule：這份目錄從哪裡取得（例如 openalex:S45419345；只記來歷，不作檢查依據）") var source: String?

    var membershipInput: AkashicService.LibraryMembershipInput {
        .init(kind: kind, venue: venue, types: types, excluded: excluded, document: document, source: source)
    }

    /// 驗證先行：未驗證 key 不得進任何路徑組合（存在性 oracle 防護）。放在 `validate()` 而不是 `run()`（#549 R1）：
    /// 它只看 argv，要早於開 store——否則 store 缺佈局時先報執行期失敗，同一個打錯的 key 得到不同的 exit code。
    func validate() throws {
        try requireValidLibraryKey(key)
        try argvCheck {
            guard try AkashicService.parseLibraryMembership(membershipInput) != nil else {
                throw ServiceError.invalid("create 需要 --kind（topic／rule／document）——library 的成員性質是寫入時查證的依據（#642）")
            }
        }
    }

    /// 建檔走 service（與 MCP `create` 同一條路徑）：規則指涉的 venue／文件要在庫。
    func run() throws {
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key, environment: ProcessInfo.processInfo.environment)
        do {
            _ = try service.libraries(action: "create", key: key, name: name, description: description,
                                      citekey: nil, membership: membershipInput)
        } catch {
            throw RuntimeFailure.state(displaySafeErrorText(error))
        }
        print("created: \(displaySafe(key, max: 200)).yaml")
        print("  " + LibraryMembershipCheck.basis(of: try? AkashicService.parseLibraryMembership(membershipInput)))   // display-safe-exempt: basis 在 LibraryMembershipCheck 裡已逐項消毒
    }
}

/// #642：標一個既有 library 的成員性質與規則。現有成員不符新規則時列出來、不自動移除——移除是另一個寫入。
struct LibrarySetKind: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-kind",
        abstract: "標 library 的成員性質與規則（topic／rule／document；整值替換，輸出帶先前的規則，替換既有性質要求 registry 檔已 commit）；現有成員不符時列出、不自動移除")

    @OptionGroup var options: LibraryOptions
    @Argument(help: "library key") var key: String
    @Option(name: .long, help: "成員性質（必填）：topic｜rule｜document——見 akashic library --help") var kind: String?
    @Option(name: .long, help: "rule：venue key——成員必須有一條指向它的 key 邊（venue 要先在庫）") var venue: String?
    @Option(name: .customLong("type"), help: "rule：限定 entry type（可重複；不給＝不限）") var types: [String] = []
    @Option(name: .customLong("exclude"), help: "rule：依裁決不收的 citekey（可重複）") var excluded: [String] = []
    @Option(name: .long, help: "document：文件的 citekey——它的 cites 即成員（文件要先在庫）") var document: String?
    @Option(name: .long, help: "rule：這份目錄從哪裡取得（例如 openalex:S45419345；只記來歷，不作檢查依據）") var source: String?

    var membershipInput: AkashicService.LibraryMembershipInput {
        .init(kind: kind, venue: venue, types: types, excluded: excluded, document: document, source: source)
    }

    func validate() throws {
        try requireValidLibraryKey(key)
        try argvCheck {
            guard try AkashicService.parseLibraryMembership(membershipInput) != nil else {
                throw ServiceError.invalid("set-kind 需要 --kind（topic／rule／document）")
            }
        }
    }

    func run() throws {
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key, environment: ProcessInfo.processInfo.environment)
        do {
            let change = try service.setLibraryKind(key: key, membership: membershipInput)
            print("set-kind: \(displaySafe(key, max: 200))")
            // 整值替換：先印被換掉的舊規則（完整，含每一個排除的 citekey）——不印就只能去讀 git 才知道換掉了什麼
            if change.previous != nil {
                print("  先前（已被替換；舊版在 git 裡）：")
                for line in LibraryMembershipCheck.details(of: change.previous) { print("    " + line) }   // display-safe-exempt: details 已逐項消毒
            } else {
                print("  先前：未標性質")
            }
            print("  現在：" + LibraryMembershipCheck.basis(of: change.library.membership))   // display-safe-exempt: basis 已逐項消毒
            if let problem = change.basisProblem { print("  ⚠ 依據不明確：" + problem.message) }   // display-safe-exempt: message 已逐項消毒
            printViolations(change.violations, members: change.members, key: key, basisAmbiguous: change.basisProblem != nil)
        } catch let e as ServiceError {
            throw RuntimeFailure.state(displaySafeErrorText(e))
        }
    }
}

/// #642：印出一個 library 的完整成員規則，並列出不符規則的成員（全部，不截）。唯讀。
struct LibraryCheck: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check", abstract: "印出 library 的完整成員規則，並列出不符規則的成員與原因（唯讀）")

    @OptionGroup var options: LibraryOptions
    @Argument(help: "library key") var key: String

    func validate() throws { try requireValidLibraryKey(key) }

    func run() throws {
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key, environment: ProcessInfo.processInfo.environment)
        do {
            let check = try service.libraryViolations(key: key)
            print("\(displaySafe(key, max: 200))：" + LibraryMembershipCheck.basis(of: check.library.membership))   // display-safe-exempt: basis 已逐項消毒
            guard check.library.membership != nil else {
                print("  " + Library.unmarkedMessage)
                return
            }
            // 完整規則（含每一個排除的 citekey）：`set-kind` 是整值替換，要改規則得先看得到現在的全部——list 只印摘要
            for line in LibraryMembershipCheck.details(of: check.library.membership) { print("  " + line) }   // display-safe-exempt: details 已逐項消毒
            if let problem = check.basisProblem { print("  ⚠ 依據不明確：" + problem.message) }   // display-safe-exempt: message 已逐項消毒
            printViolations(check.violations, members: check.members, key: key, basisAmbiguous: check.basisProblem != nil)
        } catch let e as ServiceError {
            throw RuntimeFailure.state(displaySafeErrorText(e))
        }
    }
}

/// set-kind 與 check 共用的渲染：CLI 不截（輸出進人的終端機，#388 的分工）。
///
/// 依據不明確時（`basisAmbiguous`）不建議 `library remove`（#709 第四次 verify LOW 23，INFO 26、28）：那時每個成員都被標不符，原因在依據
/// （文件不在庫、有不只一筆——含文件自己有 legacy 拷貝），不在成員；建議逐筆移除會把人導去移除合法的成員。改指向先修依據，與 validate 同一個方向。
private func printViolations(_ violations: [(citekey: String, violation: LibraryMembershipViolation)],
                             members: Int, key: String, basisAmbiguous: Bool) {
    guard !violations.isEmpty else {
        print("  \(members) 筆成員全部符合")   // display-safe-exempt: Int
        return
    }
    if basisAmbiguous {
        print("  \(members) 筆成員裡 \(violations.count) 筆判不出來——原因在上一行的依據、不在這些成員：先修好依據（akashic validate 列出），"   // display-safe-exempt: Int
              + "不要因此逐筆 library remove：")
    } else {
        print("  \(members) 筆成員裡 \(violations.count) 筆不符（不自動移除；確認後用 akashic library remove \(displaySafe(key, max: 200)) <citekey>...）：")   // display-safe-exempt: Int
    }
    for v in violations {
        print("  ✕ \(displaySafe(v.citekey, max: 200))：\(v.violation.message)")   // display-safe-exempt: v.violation.message：message 已逐項消毒
    }
}

/// library key 的格式檢查只看 argv——三個 library 子命令共用（#549 R1：add／remove 先前把它交給服務層，服務層的
/// `ServiceError` 被包成執行期失敗，同一個打錯的 key 在 create 回 64、在 add 回 1）。
private func requireValidLibraryKey(_ key: String) throws {
    guard StoreKey.isValid(key) else {
        throw ValidationError("library key「\(displaySafeInvisible(key, max: 200))」不符合 \(StoreKey.pattern)，拒絕寫入")
    }
}

/// add／remove 走 service 的批次形 `setMembership`（#455）：一次 load、整批驗（任一 citekey 不存在 → 整批
/// 拒絕零寫入）、逐筆寫、一次 rebuild。**先前 CLI 自己有一條 `mutateMembership`**（讀盤後 patch＋reindex），與
/// MCP 的 `libraries(action:)` 是兩條會分岔的實作路徑——`entity-backlink-completeness` 執行細節 2。
private func runMembership(options: LibraryOptions, action: String, libraryKey: String,
                           citekeys: [String]) throws -> AkashicService.MembershipReport {
    let store = try options.openStore()
    let service = AkashicService(root: store.root, key: store.key,
                                 environment: ProcessInfo.processInfo.environment)
    do {
        let report = try service.setMembership(action: action, key: libraryKey, citekeys: citekeys)
        guard report.writeFailures.isEmpty else {
            for f in report.writeFailures {
                print("  ! \(displaySafe(f.citekey, max: 200)) — \(displaySafeClipOnly(f.error, max: 3_200))")   // display-safe-exempt: error 已消毒（生產端 displaySafeError，R28 D80），只截
            }
            throw RuntimeFailure.state("\(report.writeFailures.count) 筆寫入失敗（其餘已寫入且 index 已重建）")   // display-safe-exempt: Int
        }
        return report
    } catch let e as ServiceError {
        throw RuntimeFailure.state(displaySafeErrorText(e))
    }
}

struct LibraryAdd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "把 entry 加入 library（寫 entry 的 akashic.libraries）。可一次給多個 citekey：任一不存在即整批拒絕（#455）；不符 library 成員規則的不寫、逐筆說原因，全部不符則非零結束；未標性質的 library 拒絕（#642）")

    @OptionGroup var options: LibraryOptions
    @Argument(help: "library key") var libraryKey: String
    @Argument(help: "citekey（可多個）") var citekeys: [String]

    func validate() throws { try requireValidLibraryKey(libraryKey) }

    func run() throws {
        let report = try runMembership(options: options, action: "add", libraryKey: libraryKey, citekeys: citekeys)
        // #642：要求／依據／實際寫入——三格都印（不符的不寫，逐筆說原因）
        print("依據：" + report.basis)   // display-safe-exempt: basis 在 LibraryMembershipCheck 裡已逐項消毒
        for ck in report.written {
            print("added: \(displaySafe(ck, max: 200)) → \(displaySafe(libraryKey, max: 200))")
        }
        for skip in report.skipped {
            print("  ✕ 不符規則、未寫：\(displaySafe(skip.citekey, max: 200))——\(displaySafeClipOnly(skip.reason, max: 1_200))")   // display-safe-exempt: skip.reason：reason 已逐項消毒（LibraryMembershipViolation.message），只截
        }
        // 全數不符＝零寫入：非零結束（#624 全數排除的同形）。部分不符照常結束——寫了的就是正確的那部分
        if report.written.isEmpty, !report.skipped.isEmpty {
            throw RuntimeFailure.state("\(report.skipped.count) 筆全部不符 library「\(displaySafeInvisible(libraryKey, max: 200))」的成員規則，零寫入")   // display-safe-exempt: Int
        }
    }
}

struct LibraryRemove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove", abstract: "把 entry 移出 library。可一次給多個 citekey：任一不存在即整批拒絕（#455）")

    @OptionGroup var options: LibraryOptions
    @Argument(help: "library key") var libraryKey: String
    @Argument(help: "citekey（可多個）") var citekeys: [String]

    func validate() throws { try requireValidLibraryKey(libraryKey) }

    func run() throws {
        let report = try runMembership(options: options, action: "remove", libraryKey: libraryKey, citekeys: citekeys)
        for ck in report.written {
            print("removed: \(displaySafe(ck, max: 200)) ✕ \(displaySafe(libraryKey, max: 200))")
        }
    }
}
