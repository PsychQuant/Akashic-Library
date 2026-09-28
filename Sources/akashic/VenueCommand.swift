import ArgumentParser
import Foundation
import AkashicMCPKit
import AkashicCore
import AkashicStoreIO

/// venue 的 CLI 面（#304）。四個 subcommand 與 MCP 的
/// `akashic_venue`／`akashic_venues`／`akashic_add_venue`／`akashic_resolve_venues`
/// 落到 **同一個 `AkashicService` 函式**（entity-backlink 執行細節 2：一個讀取面
/// 只有一條實作路徑）。讀取面 `--json` 原樣轉印＋人可讀同源；寫入面是封閉例外形
/// （只回 service payload——mcp-cli-parity 的既有裁決）。

struct VenueCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "venue",
        abstract: "看一個發表載體：記錄 + 刊名沿革 + 文章編年 list（編年由反向邊算出，不存在記錄裡）")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "venue key")
    var key: String

    @Flag(name: .long, help: "原樣輸出 service JSON（與 MCP akashic_venue 逐欄位相同）")
    var json: Bool = false

    /// 空白 key 是用法錯誤，早於開 store（#654；檢查本身在 service，兩面同一個函式）
    func validate() throws { try argvCheck { _ = try AkashicService.venueLookupKey(key) } }

    func run() throws {
        let store = try options.openStore()
        // `key:` 不可省——同 PersonCmd 的 #220 教訓（keyless store 會分岔出第二份 index）
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        let payload = try service.venue(key: key)
        if json { print(payload); return }
        try Self.render(payload)
    }

    /// 人可讀輸出。輸入是 service 回應（已逐欄位 displaySafe——本函式不從 store
    /// 另讀任何東西，且 `displaySafe` 不冪等，故不再包一次；同 PersonCmd 的 exemption）。
    static func render(_ payload: String) throws {
        guard let obj = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
            print(payload); return
        }
        let key = obj["key"] as? String ?? "?"
        let type = obj["type"] as? String ?? "?"
        print("\(key)（\(type)）")
        // **標題不再叫「沿革」**（#422 verify R1）：`names` 是時間軸，但不帶時間欄位的項目
        // 對時間**不作宣稱**——印成「沿革」正是 #422 要修掉的那句謊。每項就地標記它落在
        // 哪個分割（〔authorized〕／〔variant〕／未標＝尚未判定），不另起一行重列 variant。
        let authorizedSet = Set(obj["authorized"] as? [String] ?? [])
        let variantSet = Set(obj["variant"] as? [String] ?? [])
        if let names = obj["names"] as? [[String: Any]], !names.isEmpty {
            print("  names（帶時間欄位者為沿革；〔authorized〕權威形／〔variant〕異寫／未標＝未判定）：")
            for n in names {
                let value = n["value"] as? String ?? "?"
                var line = "    \(value)"
                if authorizedSet.contains(value) { line += " 〔authorized〕" }
                if variantSet.contains(value) { line += " 〔variant〕" }
                var span: [String] = []
                if let s = n["start"] as? String { span.append("start \(s)") }
                if let e = n["end"] as? String { span.append("end \(e)") }
                if n["ended"] as? Bool == true { span.append("已結束（時點未知）") }
                if let a = n["attested"] as? [String], !a.isEmpty {
                    span.append("attested \(a.joined(separator: ","))")
                }
                if !span.isEmpty { line += "（\(span.joined(separator: "、"))）" }
                print(line)
            }
        }
        // authorized／variant 已在上方逐項就地標記（#422 verify R1：不重列兩次）；
        // `--json` 的 payload 不變，兩個分割仍是獨立欄位。
        // **三態**（#406）：印 true／false，缺席**什麼都不印**——那是「尚未判定」，
        // 而印「未判定」會讓它看起來像一個已經查過的結論。
        if let p = obj["paginated"] as? Bool {
            print("  paginated：\(p ? "是（本刊使用頁碼）" : "否（article number 制）")")   // display-safe-exempt: 編譯期常量
        }
        // 判定的理由要看得到（#406 R1 verify）——回溯的讀取面。多筆＝翻轉留史。
        if let js = obj["paginatedJudgements"] as? [[String: Any]], !js.isEmpty {
            for j in js {
                let n = (j["restsOn"] as? [String])?.count ?? 0
                print("    判定：\(j["statement"] as? String ?? "")（證據 \(n) 份）")   // display-safe-exempt: statement 取自 service（已 displaySafe），二次消毒非冪等；n 是 Int
            }
        }
        if let issn = obj["issn"] as? [[String: Any]], !issn.isEmpty {
            let rendered = issn.map { one -> String in
                let v = one["value"] as? String ?? "?"
                if let m = one["medium"] as? String { return "\(v)（\(m)）" }
                return v
            }
            print("  ISSN：\(rendered.joined(separator: "、"))")   // display-safe-exempt: service 已逐值消毒（40），displaySafe 不冪等
        }
        if let note = obj["note"] as? String { print("  note：\(note)") }
        if let vs = obj["verdicts"] as? [[String: Any]], !vs.isEmpty {
            print("  歸戶判定（\(vs.count)）：")
            for v in vs {
                let kind = v["kind"] as? String ?? "?"
                let state = v["state"] as? String ?? "?"
                let lit = v["literal"] as? String ?? "?"
                let holder = v["holder"] as? String ?? "?"
                print("    [\(kind)/\(state)] 「\(lit)」← \(holder)")   // display-safe-exempt: service 已逐欄位消毒，displaySafe 不冪等
                if let s = v["statement"] as? String { print("        查了：\(s)") }   // display-safe-exempt: service 已消毒（#619 未決記錄）
                if let ro = v["restsOn"] as? [String], !ro.isEmpty {
                    let more = (v["restsOnTotal"] as? Int).map { "（共 \($0) 個，只列前 \(ro.count) 個）" } ?? ""   // display-safe-exempt: Int
                    print("        rests-on：\(ro.joined(separator: "、"))\(more)")   // display-safe-exempt: service 已消毒
                }
            }
        }
        let count = obj["workCount"] as? Int ?? 0
        print("")
        print("文章（\(count)，編年）")
        if let works = obj["works"] as? [[String: Any]] {
            for w in works {
                let year = (w["year"] as? Int).map(String.init) ?? "—"
                print("\(w["citekey"] as? String ?? "?")\t\(year)\t\(w["title"] as? String ?? "")")   // display-safe-exempt: service 已逐欄位消毒（citekey 200／title 500），displaySafe 不冪等
            }
        }
        if count == 0 { print("（零篇——這是結果，不是錯誤）") }
    }
}

struct VenuesCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "venues",
        abstract: "列出全部發表載體（key / type / 顯示名 / 文章數）")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "原樣輸出 service JSON（與 MCP akashic_venues 相同）")
    var json: Bool = false

    func run() throws {
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        let payload = try service.venues()
        if json { print(payload); return }
        guard let obj = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
              let rows = obj["venues"] as? [[String: Any]] else {
            print(payload); return
        }
        for r in rows {
            print("\(r["key"] as? String ?? "?")\t\(r["type"] as? String ?? "?")\t" +
                  "\(r["name"] as? String ?? "?")\t\(r["workCount"] as? Int ?? 0)")
        }
        print("（\(rows.count) 個 venue）")
    }
}

struct AddVenueCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add-venue",
        abstract: "建發表載體實體（type 值域：\(VenueType.domainDescription)；需 store format ≥ 11）")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "kebab-case venue key")
    var key: String

    @Option(name: .long, parsing: .upToNextOption,
            help: "名稱變體（可多個）。契約同 update-venue --add-name（#554 D8）：以 canonical 形入庫（空白類——含 tab／換行／LS——收斂為單一空格、NFC）、近重複只留一筆、空白項略過；含其他控制／格式／不可見字元、拉丁或 CJK 之間的接合字元、或無任何字母或數字即整個呼叫拒絕、零寫入；全部空白＝沒有名字，同樣拒絕。報告：names 是存入的拼法、被折成 canonical 形才存的列 namesFolded、真的沒進 store 的列 namesDropped")
    var names: [String]

    @Option(name: .long, help: "\(VenueType.domainDescription)")
    var type: String

    @Option(name: .long, help: "備註（選填）")
    var note: String?

    /// #394：建檔時就知道 ISSN 是常見的。少了它得「先建再更新」——一次操作變兩次，
    /// 中間有一個 ISSN 不在的狀態。不合法即整個拒絕、零寫入；相等看正規形。
    @Option(name: .long, parsing: .upToNextOption,
            help: "ISSN（可多個；print 與 electronic 是兩個真的號。不合法即整批拒絕）")
    var issn: [String] = []

    /// type 值域、key 格式、名字與 ISSN 的形狀只看 argv——早於開 store（#654）；檢查本身在 service，兩面同一個函式
    func validate() throws {
        try argvCheck { _ = try AkashicService.addVenueArguments(key: key, names: names, type: type, issn: issn) }
    }

    func run() throws {
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        // 寫入面封閉例外形：只回 service payload（mcp-cli-parity 的既有裁決）
        print(try service.addVenue(key: key, names: names, type: type, note: note,
                                   issn: issn.isEmpty ? nil : issn))
    }
}

struct UpdateVenueCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-venue",
        abstract: "venue 的部分更新（#306／#394／#471／#554）——append 語意：--add-name／--add-issn／--add-variant 只附加不重複的值（整組替換刻意不提供）；--authorize 是同書寫系統替換（不是 append，見其 help）；--note／--type 替換。venue 無法唯一定位（\(UnlocatableReason.venue)）時整批拒絕、零寫入（#670）")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "既有 venue key")
    var key: String

    @Option(name: .long, parsing: .upToNextOption,
            help: "要附加的名稱變體（可多個；相等看 canonical——前後／連續空白、NFC——近重複略過、新名字以 canonical 形入庫：空白類（含 tab／換行／LS／PS／NEL）收斂為單一空格。其他控制／格式／不可見字元（bidi、零寬、變體選擇子、填充字元）、拉丁或 CJK 之間的接合字元（ZWJ／ZWNJ 只在使用 join control 的文字——阿拉伯系／印度系／蒙古文等——裡合法：virama 之後、左鄰是同文字的字母／標記／數字而右鄰是同文字的字母／數字（右鄰不收標記）、或 Devanagari／Bengali 的 virama 之前且其後接字母）、或無任何字母或數字即整批拒絕，#554 D8）。報告：實際寫入的拼法列 namesAdded、canonical 形本來就在的列 namesAlreadyPresent、這次才存但拼法被折過的列 namesFolded、全空白的列 namesDropped")
    var addName: [String] = []

    @Option(name: .long, help: "備註（替換；選填）")
    var note: String?

    @Option(name: .long, help: "\(VenueType.domainDescription)（替換；選填）")
    var type: String?

    /// **append 語意，與 `--add-name` 一致**（#394）。ISSN 本來就是清單——print 與
    /// electronic 是兩個真的號。相等看正規形；任一個不合法即整個呼叫拒絕、零寫入。
    @Option(name: .customLong("add-issn"), parsing: .upToNextOption,
            help: "要附加的 ISSN（可多個；正規形相同者自動略過，不合法即整批拒絕）")
    var addISSN: [String] = []

    /// #588：寫錯的號（常是姊妹刊的號）在此之前拿不掉，只能手改 YAML。
    @Option(name: .customLong("remove-issn"), parsing: .upToNextOption,
            help: "移除 ISSN（可多個）：<issn>=理由。移除是判定的逆轉，理由必填；理由只印在報告（issnRemoved，全文），不寫進 store。指向被移除號的 field: issn provenance reference 一併刪除，報告逐號列筆數（referencesRemoved）。所以這個 venue 檔要已在 git 裡 commit（tracked、無未提交修改），否則整批拒絕——git 保存的是移除前的檔，理由要留在 git 得自己寫進 commit message。號不合法、這本刊沒有這個號、同一次呼叫裡重複、或同時出現在 --add-issn，都整批拒絕、零寫入（#588）")
    var removeISSN: [String] = []

    @Option(name: .customLong("add-variant"), parsing: .upToNextOption,
            help: ArgumentHelp("要標成異寫法的名字（append 語意；相等看 canonical、新名字以 canonical 形入庫——空白類收斂為單一空格、NFC——其他控制／格式／不可見字元、拉丁或 CJK 之間的接合字元、無字母無數字即整批拒絕——同 --add-name，#554 D8）。不在 names 裡的一併加進 names"
                             + "——兩個分割都是對 names 的標記，標一個 names 沒有的字串會造出"
                             + "孤兒，而孤兒 variant 自 #473 起是 error（#471）。整項空白的不寫、回報在 variantDropped"))
    var addVariant: [String] = []

    @Option(name: .customLong("authorize"), parsing: .upToNextOption,
            help: ArgumentHelp("指定為對外形的名字。**不是 append**：authorized 每個書寫系統"
                             + "（han／latn／other）至多一個，同一書寫系統原本的指定會移出 authorized、"
                             + "留在 names、不標 variant（報告逐筆印出）；不同書寫系統之間才是 append。"
                             + "一次給兩個同書寫系統的名字是矛盾，整批拒絕。不在 names 的一併加進 names。"
                             + "這是合併拿掉某個名字 authorized 身分那個動作在該名字上的逆操作（#553 時那個名字進 variant、#565 起留在未標）——在此之前"
                             + "authorized 沒有判定型寫入面，唯一寫入者是 bootstrap 取第一個名字，而那些"
                             + "機械值換不掉。不留 judgement（#564 另裁）。報告的桶：authorizedRemoved（被換下來的舊指定）、"
                             + "liftedFromVariant（原本在 variant、被抬進 authorized）、alreadyAuthorized（no-op 但不沉默）、"
                             + "authorizedRewritten（唯一會宣告 store 位元組被改寫的桶：同名 NFD 舊指定換成 canonical）；"
                             + "整項空白的不寫、回報在 authorizeDropped（#554；R25 verify 第 20 列：這裡曾只列一個桶、MCP 描述列四個）"))
    var authorize: [String] = []

    @Flag(name: .customLong("clear-paginated"),
          help: ArgumentHelp("撤回 paginated 判定，回到誠實的未判定狀態（#500）。"
                           + "**撤回是一筆判定**：同樣要 --judgement，並在 references 留下"
                           + "一筆 value=nil 的記錄。省略 --paginated 的意思是「這次不動它」，"
                           + "不是清除——清除須顯式（同 set-status 的既有裁決）"))
    var clearPaginated: Bool = false

    /// #406：「本刊是否使用頁碼」的**判定**。判定要留 verdict 與證據
    /// （`identity-is-judged-not-matched`），所以設它必附 `--judgement` 與
    /// `--rests-on`（缺任一即整個呼叫拒絕、零寫入）。`nil` 是誠實的未判定狀態，
    /// 不得折成任何預設值——floor 檢查對 nil 照報缺 pages。
    @Option(name: .long,
            help: "「本刊是否使用頁碼」的判定：true＝傳統頁碼刊、false＝article-number 制。必附 --judgement 與 --rests-on（#406）")
    var paginated: Bool?

    @Option(name: .long, help: "paginated 判定的理由（設 --paginated 時必填）")
    var judgement: String?

    @Option(name: .customLong("rests-on"), parsing: .upToNextOption,
            help: "判定所依據的證據 digest（sha256:64hex，至少一個——先用 store-source 存證據拿 digest）")
    var restsOn: [String] = []

    /// 只看 argv 的檢查早於開 store（#654）：與服務在讀 store 之前跑的是同一個函式，參數的對映與 `run()` 相同。
    func validate() throws {
        try argvCheck {
            try AkashicService.checkUpdateVenueArguments(addNames: addName.isEmpty ? nil : addName, type: type,
                                                         addISSN: addISSN.isEmpty ? nil : addISSN,
                                                         addVariant: addVariant.isEmpty ? nil : addVariant,
                                                         authorize: authorize.isEmpty ? nil : authorize,
                                                         paginated: paginated, clearPaginated: clearPaginated,
                                                         judgement: judgement, restsOn: restsOn.isEmpty ? nil : restsOn,
                                                         removeISSN: removeISSN.isEmpty ? nil : removeISSN)
        }
    }

    func run() throws {
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        // 寫入面封閉例外形：只回 service payload（mcp-cli-parity 的既有裁決）
        print(try service.updateVenue(key: key,
                                      addNames: addName.isEmpty ? nil : addName,
                                      note: note, type: type,
                                      addISSN: addISSN.isEmpty ? nil : addISSN,
                                      addVariant: addVariant.isEmpty ? nil : addVariant,
                                      authorize: authorize.isEmpty ? nil : authorize,
                                      paginated: paginated,
                                      clearPaginated: clearPaginated,
                                      judgement: judgement,
                                      restsOn: restsOn.isEmpty ? nil : restsOn,
                                      removeISSN: removeISSN.isEmpty ? nil : removeISSN))
    }
}

struct ResolveVenuesCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resolve-venues",
        abstract: "venue 解析：不帶參數列候選與歧義；--apply 升格 literal 為 key（寫 confirmed verdict；會讓同一 work 兩條邊指同一 venue 的候選逐筆略過並回報 skippedDuplicateVenueEdge；目的 venue 已對該 work 持有另一個 confirmed literal（沒有對應的邊；相等比位元組，同一 literal 的另一個拼法也略過——之後 demote 會還回舊拼法）的候選逐筆略過並回報 skippedConflictingConfirmedLiteral，D38／D43，且在重複邊檢查之後判，D44；同一 work 兩條拼法不同的 literal 邊指向同一 venue 時誰落地由 --apply 的順序決定，先到先寫，D28／D33）；--reject 否決（寫 rejected verdict）；--repoint 改指已歸戶的邊（兩側都寫 verdict）；--demote 退回 literal（原字串從 verdict 取回，#418）。--drop-venue 移除一條邊（理由只進報告，#572）。--repoint／--demote 寫 verdict 時會刪掉同 holder 上同一配對的相反判定（D20，逐筆列在 verdictsRetired、截 20 筆），前提不符整批拒絕零寫入（≥2 個不同 confirmed literal D23；配對由多條邊實例化 D25；被動到的邊與另一條邊同 venue、或同一批同一 literal 且觸及同一 venue D27；改指後目的 venue 會對該 work 持有第二個 confirmed literal——相等比位元組、另一個拼法也算 D38／D43；同一條邊在同一批被指定兩次 R16）。提名的否決抑制以正規化後的 literal 為鍵（R12）：對一個拼法的 --reject／--demote 會壓住同 work 同 venue 的其他拼法，撤回面見 #559。候選所在的 work 或指向的 venue 無法唯一定位（work：\(UnlocatableReason.work)；venue：\(UnlocatableReason.venue)）時 --apply 逐筆略過並回報 skippedUnlocatable，--reject／--repoint（兩端任一）／--demote 整批拒絕（#628／#641／#670）")

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, parsing: .upToNextOption,
            help: "要套用的候選 id（citekey:venueIndex）")
    var apply: [String] = []

    @Option(name: .long, parsing: .upToNextOption,
            help: "要否決的候選 id（同形）——CLI 面維持分兩次呼叫（互動面天然序列；組合腿是 MCP 的 LLM 批次需求，#272 同裁決）")
    var reject: [String] = []

    @Option(name: .long, parsing: .upToNextOption,
            help: "把已歸戶的邊改指到另一個 venue（citekey:venueIndex:newKey）——歸錯戶的退路，#418；退役 from 上的 confirmed 與 to 上的 rejected（D20），改指後不得與本 work 另一條邊指同一 venue（D27）；刪判定記錄之前要求那些 venue 檔已 commit（#573），被刪的全列")
    var repoint: [String] = []

    @Option(name: .long, parsing: .upToNextOption,
            help: "把誤升的邊退回 literal（citekey:venueIndex）——原字串從 verdict 取回，無損，#418；退役該 venue 上這個配對的 confirmed（D20）；刪判定記錄之前要求該 venue 檔已 commit（#573），被刪的全列")
    var demote: [String] = []

    @Option(name: .long, parsing: .upToNextOption,
            help: "記下查過未決（可重複）：citekey:venueIndex:venueKey=查了什麼、為何判不出來。寫一筆 resolution-undecided 到該 venue，邊不動；之後列表標 undecidedChecks。可附 --rests-on。已判定的配對、已歸戶的邊、無法唯一定位的 work 或 venue（work：\(UnlocatableReason.work)；venue：\(UnlocatableReason.venue)）該筆略過並具名。需要 store format ≥ 19；一次超過 200 個 id、20 個 digest 或單句說明超過 4,096 位元組同樣整批拒絕（有界，不截斷）。單獨呼叫（change resolution-verdict-states，#619）")
    var undecided: [String] = []

    @Option(name: .long, parsing: .upToNextOption,
            help: "未決記錄的證據（可重複）：sha256:<64 hex>，先用 store-source 存檔。套用到這次呼叫的每一筆 --undecided——不同配對要附不同證據就分次呼叫。只伴隨 --undecided")
    var restsOn: [String] = []

    @Option(name: .customLong("drop-venue"), parsing: .upToNextOption,
            help: "移除 venue 邊（可重複）：citekey:venueIndex=理由（#572）。index 是原始位置。key 邊只在刪完後本 work 仍有另一條 key 邊指同一 venue 時可刪（否則先 --demote 再刪 literal 邊）；literal 邊一律可刪。理由必填、只印在報告裡——不寫進 store，要留在 git 就寫進 commit message；移除前要求那些 work 檔已 commit、乾淨。格式錯、理由空白、同一條邊兩次、越界、citekey 無法唯一定位，整批拒絕零寫入。刪光一筆 work 的 venue 邊時會具名（migrate-venues 與 Zotero pull 會重新推導）。單獨呼叫")
    var dropVenue: [String] = []

    /// #654：各寫入腿只看參數的檢查（id 的形狀、理由、同一批重複、一次的上限、rests-on 的 digest）在服務裡、讀 store 之前跑；
    /// 這裡呼叫同一個函式，用法錯誤回 64 並早於開 store。--apply／--reject 的 id 要比對這次的候選列表（讀 store），仍是執行期。
    func validate() throws {
        try argvCheck {
            if !undecided.isEmpty { try AkashicService.checkUndecidedArguments(undecided, restsOn: restsOn, indexName: "venueIndex") }
            if !repoint.isEmpty { try AkashicService.checkRepointArguments(repoint) }
            if !demote.isEmpty { try AkashicService.checkDemoteArguments(demote) }
            if !dropVenue.isEmpty { try AkashicService.checkDropVenueArguments(dropVenue) }
        }
    }

    func run() throws {
        if !restsOn.isEmpty && undecided.isEmpty {
            throw ValidationError("--rests-on 只伴隨 --undecided 使用（#619）")
        }
        if !dropVenue.isEmpty {
            guard apply.isEmpty, reject.isEmpty, repoint.isEmpty, demote.isEmpty, undecided.isEmpty else {
                throw ValidationError("--drop-venue 單獨呼叫（不與 --apply／--reject／--repoint／--demote／--undecided 組合）")
            }
            try options.assertDestructiveTargetNamed("resolve-venues", flag: "--drop-venue", hasDryRun: false)
            let store = try options.openStore()
            let service = AkashicService(root: store.root, key: store.key,
                                         environment: ProcessInfo.processInfo.environment)
            print(try service.resolveVenues(apply: nil, drop: dropVenue))
            return
        }
        if !undecided.isEmpty {
            guard apply.isEmpty, reject.isEmpty, repoint.isEmpty, demote.isEmpty else {
                throw ValidationError("--undecided 單獨呼叫（不與 --apply／--reject／--repoint／--demote 組合）")
            }
            // #298／#580：逐 id 的寫入腿同樣要指名目標 store——閘防的是寫錯 store，不是寫錯哪幾筆
            // （從錯的 store 列出來的 id 在錯的 store 上全部對得上）。比照 enrich 的既有裁決。
            try options.assertDestructiveTargetNamed("resolve-venues", flag: "--undecided", hasDryRun: false)
            let store = try options.openStore()
            let service = AkashicService(root: store.root, key: store.key,
                                         environment: ProcessInfo.processInfo.environment)
            try ResolvePeople.printUndecidedResult(try service.resolveVenues(apply: nil, undecided: undecided, restsOn: restsOn))
            return
        }
        // CLI 契約同 resolve-people：apply 與 reject 分兩次呼叫
        if !apply.isEmpty, !reject.isEmpty {
            throw ValidationError("--apply 與 --reject 請分兩次呼叫（組合腿是 MCP 面的契約差異，見 mcp-cli-parity）")
        }
        // **`--repoint` 不與另外兩者組合**：它們解的是不同階段的問題（升格 vs 修正
        // 已升格的），混在一次呼叫裡會讓「哪一批寫了、哪一批沒寫」難以判讀，而改指
        // 本來就是在修一個錯誤——它最需要的是清楚的失敗語意（#418）。
        // **修正類的兩個旗標都單獨呼叫**：它們修的是已歸戶的邊，與升格／否決不同階段，
        // 而混在一次呼叫會讓「哪一批寫了」難以判讀（#418）。
        let fixers = [("--repoint", repoint), ("--demote", demote)].filter { !$0.1.isEmpty }
        if let f = fixers.first, fixers.count > 1 || !apply.isEmpty || !reject.isEmpty {
            throw ValidationError("\(f.0) 請單獨呼叫（它修的是已歸戶的邊，與升格／否決不同階段）")
        }
        // #298／#580：任一寫入腿都要指名目標 store（理由見上方 --undecided 那一處）；不帶旗標的列表不擋
        let writeLeg = [("--apply", apply), ("--reject", reject), ("--repoint", repoint), ("--demote", demote)]
            .first { !$0.1.isEmpty }?.0
        if let leg = writeLeg { try options.assertDestructiveTargetNamed("resolve-venues", flag: leg, hasDryRun: false) }
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        print(try service.resolveVenues(apply: apply.isEmpty ? nil : apply,
                                        reject: reject.isEmpty ? nil : reject,
                                        repoint: repoint.isEmpty ? nil : repoint,
                                        demote: demote.isEmpty ? nil : demote,
                                        retiredLimit: nil))   // #573：CLI 全列被刪掉的判定
    }
}

struct MigrateVenues: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migrate-venues",
        abstract: "從書目字串欄位回填 entry 的 venues literal ref（#304；需另手動 bump format 至 11）")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "實際寫入（預設只預演；只改寫 git 追蹤中的檔）")
    var apply = false

    func run() throws {
        // #298：破壞性寫入前確認目標 store 已被指名。**只在 --apply 時**
        // ——dry-run 不得被擋（它不寫東西，且正是用來確認目標的手段）。
        if apply { try options.assertDestructiveTargetNamed("migrate-venues") }
        let store = try options.openStore()
        // 同 migrate-person-identity 的席 A NEW-3 緩解：破壞性/批次遷移**先回顯目標**
        // ——LibraryLocator 對 CWD 零感知（registry current 決定目標）。
        print("目標 store：\(displaySafe(store.root.path, max: 300))")
        let report = try VenueMigration.run(store: store, apply: apply)
        let prefix = apply ? "✓" : "（dry-run）"
        if report.planned.isEmpty && report.skippedExisting.isEmpty && report.failed.isEmpty {
            print("沒有可回填的 entry——journaltitle／booktitle／publisher 皆無或已有 venues")
        } else {
            print("\(prefix) \(apply ? "已回填" : "將回填") \(report.planned.count) 筆"
                  + "，已有 venues（跳過）\(report.skippedExisting.count) 筆"
                  + "，無載體來源 \(report.noVenueSource.count) 筆")
            for k in report.planned.prefix(20) { print("  \(displaySafe(k, max: 200))") }
            if report.planned.count > 20 { print("  …另 \(report.planned.count - 20) 筆") }
            if !report.failed.isEmpty {
                print("拒寫 \(report.failed.count) 筆（其餘照常；commit 後重跑——遷移是冪等的）：")
                for f in report.failed.prefix(20) {
                    print("  ⚠ \(displaySafeInvisible(f.citekey, max: 200))——\(displaySafeClipOnly(f.reason, max: 4_096))")   // display-safe-exempt: reason 已消毒（建構點 displaySafeInvisible／displaySafeError，R30；R29 verify 第 2 列），只截
                }
            }
        }
        if let next = VenueMigration.nextStep(report: report, apply: apply,
                                              current: try? StoreVersion.read(root: store.root)) {
            print(next)
        }
    }
}
