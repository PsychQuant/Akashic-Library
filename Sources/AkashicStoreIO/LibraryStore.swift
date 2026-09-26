import Foundation
import AkashicCore

public enum StoreIOError: Error, LocalizedError, Equatable, SanitizedErrorDescription {
    case invalidKey(String, String)
    /// #108：root 不是一個 store（無 marker 也無 canonical 目錄）——寫入拒絕。
    /// #101 讓 atomicWrite 自建父目錄後，打錯的 root 曾被安靜實體化成無 marker
    /// 的幽靈 store（之後 ensureLayout 還會把它標成 format 1）。
    case notAStore(String)
    /// 一般性的輸入拒絕（#133 verify F3）：invalidKey 的訊息框架是「不符合 key
    /// 正規式」——把候選數不足、判斷缺依據這類拒絕塞進去，內文正確、框架全錯，
    /// 會把 LLM 呼叫端引去清洗 key。語意歸語意。
    case invalidInput(what: String, why: String)
    /// store 有跨記錄的不一致（重複 UUID / citekey），改寫動作拒絕執行（#35 verify）。
    case inconsistentStore(action: String, issues: [String])
    /// D60（R21）／D61（R22）→ D63（R23）：改名的目的鍵上已有 verdict——`lines` 已逐項以 `displaySafeInvisible` 消毒。**每個 digest 自己一行**
    /// （R21 verify 第 9／11／15 列：CLI 的出口 `displaySafeAssembled` 逐行截 400，R21 把 rests-on 排在行尾、一個一般長度的 judgement 就把
    /// sha256 切成半個——比不印更糟；`inconsistentStore` 則只印前 3 條、每條截 300）；命中至多 20 筆、其餘一句揭露總數（D30 的形，第 7／17／24／28 列）。
    case verdictsAlreadyAtTarget(action: String, key: String, lines: [String])
    /// #631：entities 佈局下，目的檔 `entities/<id>.yaml` 已經存在、卻不是「同一種記錄、同一個 id」——
    /// 被 quarantine 的記錄（舊值、未來格式、手改壞掉）或另一種記錄。以 id 定檔的寫入會把它整個蓋掉。
    /// `id` 決定目的檔路徑（`entities/<UUID>.yaml`，描述端組）；`detail` 在擲出端已消毒（decode error 走 `displaySafeError`）。
    case destinationHoldsAnotherRecord(id: UUID, detail: String)
    /// #631：同一筆記錄**兩份都在**——legacy（`entries/<citekey>.yaml`／`people/<key>.yaml`）與 `entities/<id>.yaml`
    /// 同一個 id。遷移做到一半，兩份可能已經分岔；留哪一份是判定，不替人刪。（只有 legacy 一份時寫入會搬移，不走這裡。）
    /// `file` 是 legacy 檔的相對路徑，含記錄的 key——描述端消毒。
    case legacyCopyPresent(file: String)
    /// #631 R2：legacy 檔只有一份、照理該搬移，但它**不能安全地刪**——key 不合法或與預期不符（load 會隔離它，
    /// 它不是這次寫入內容的來源），或不受 git 追蹤／有未 commit 的修改（刪了就回不來）。`why` 在擲出端已消毒。
    case legacyCopyUnmovable(file: String, why: String)

    /// `verdictsAlreadyAtTarget` 每行的截斷上限＝CLI sink `displaySafeAssembled` 的逐行預設（400）減去 `displaySafe` 的截斷標記長度——
    /// 截過的行連標記一起 ≤ 400，sink 不會再截一次（R22 verify 第 23 列：兩次截讓標記落在 `\u{` 中途）。
    static let refusalLineMax = 400 - "…（已截斷）".count

    public var errorDescription: String? {
        switch self {
        case let .notAStore(path):
            return "「\(displaySafeInvisible(path, max: 300))」不是 Akashic store（無 store.yaml 也無 "
                 + "entities/／entries/）——寫入拒絕。若這是新 store，先跑 "
                 + "akashic doctor --library <path> 建立佈局；若是打錯路徑，這個拒絕正是在救你。"
        case let .invalidInput(what, why):
            // 兩個參數在擲出端就已逐項消毒（`assertNoErrors` 的 key、validate() 的訊息、DivergenceResolve 的候選鍵／statement——
            // `SanitizationBoundaryTests.testInvalidInputThrowSitesSanitizeStoreStrings` 掃全樹），這裡只截：R27 把它換成
            // displaySafeInvisible 是與同一個 enum 另外兩格相反的方向，`fmt` 疊到第三層（R27 verify 第 5／12／14 列）。
            return "\(displaySafeClipOnly(what, max: 960)) 無效：\(displaySafeClipOnly(why, max: 3_200))"   // display-safe-exempt: 已消毒（擲出端），只截——R28 D80
        case let .inconsistentStore(action, issues):
            // action 是呼叫端字面量（"rename"/"resolve-divergence"）、issues 已消毒
            return "store 有 \(issues.count) 個跨記錄不一致，\(action) 拒絕執行"   // display-safe-exempt: action 是呼叫端字面量
                 + "（改寫會刪掉其中一份而留下另一份）："
                 + issues.prefix(3).map { displaySafeClipOnly($0, max: 300) }.joined(separator: "；")   // display-safe-exempt: 已消毒（crossRecordIssues 的訊息在生產端 displaySafeInvisible），只截——displaySafe 不冪等
                 + "。先跑 akashic doctor 看清楚並修好。"
        case let .verdictsAlreadyAtTarget(action, key, lines):
            // key 與 lines 已在 assertNoVerdictAlreadyAt 消毒（displaySafeInvisible）；這裡只截不逃——displaySafe 不冪等。
            // 行長由 CLI sink `displaySafeAssembled` 的逐行 400 決定（R21 寫 1,000 是到不了的死碼——R21 verify 第 15 列）。R22 在這裡寫
            // 「生產端每行本來就不超過」——假的（R22 verify 第 9／23／37 列，DA 真 binary 實測 406 字）：`displaySafeInvisible` 的 `max` 數的是
            // **輸入** scalar，每個被逃脫的 scalar 輸出 8 個字元，value ≤ 200 scalar 逃脫後可到 1,600 字，holder 行**會**被截（截掉的是 literal
            // 的尾巴，不是定位那一行所需的 holder／欄位）；digest 行恆為 71 個 ASCII（`isValidDigest` 釘死 `sha256:` + 64 hex）——那才是「每個
            // digest 自己一行」成立的理由。這裡截在 sink 上限減去截斷標記的長度，讓 sink 不會再截第二次（第二次會把標記切在 `\u{` 中途）。
            return "目的鍵「\(key)」上已有 verdict 指向它——目的鍵此刻不存在，所以它們是死 verdict（#464），"   // display-safe-exempt: 已消毒
                 + "但 \(action) 不替你判定它們在講哪一筆記錄（它們可能是舊 binary 沒遷走、人對另一筆仍存在的記錄親自下的判定）。"   // display-safe-exempt: action 是呼叫端字面量
                 + "請逐筆處置後再重跑——已解析的命中：把那一行的 value 改成它實際描述的記錄的鍵（改該記錄 YAML 的那一行；目的鍵此刻不存在，所以沒有邊可以 repoint）"
                 + "或刪掉那一行；quarantined 檔的命中：修好或移走那個檔。merge 對同一形狀同樣拒絕（D31／D34）。\n"
                 + lines.map { displaySafeClipOnly($0, max: Self.refusalLineMax) }.joined(separator: "\n")   // display-safe-exempt: 已消毒，只截
        case let .destinationHoldsAnotherRecord(id, detail):
            return "目的檔 entities/\(id.uuidString).yaml 已經存在，但它\(displaySafeClipOnly(detail, max: 600))——寫入會把它整個蓋掉，拒絕。"   // display-safe-exempt: detail 已消毒（擲出端），只截
                 + "先看那個檔：修好、移走，或確認它不該存在後刪掉（store 受 git 追蹤，刪檔可還原）。akashic validate 會列出被 quarantine 的檔（#631）"
        case .legacyCopyPresent(let file):
            return "同一筆記錄有兩份：legacy \(displaySafeInvisible(file, max: 300)) 與 entities/ 裡同一個 id 的那份——"
                 + "遷移做到一半，兩份可能已經分岔，拒絕寫入。比對後保留正確的那一份、刪掉另一份"
                 + "（store 受 git 追蹤，刪檔可還原），再重跑（#631）"
        case let .legacyCopyUnmovable(file, why):
            return "legacy \(displaySafeInvisible(file, max: 300)) 只有一份、寫入時照理要搬進 entities/，但它不能安全地刪："
                 + displaySafeClipOnly(why, max: 600) + "——拒絕寫入，檔案不動（#631）"   // display-safe-exempt: why 已消毒（擲出端），只截
        case .invalidKey(let kind, let value):
            // #142：value 是 caller 剛送進來的畸形 key——原始 ESC/bidi 位元組經
            // MCP error 直達 LLM context；kind 是程式字面量
            return "\(kind)「\(displaySafeInvisible(value, max: 200))」不符合 \(StoreKey.pattern)，拒絕寫入"   // display-safe-exempt: kind 是程式字面量、pattern 是常量
        
        }
    }
}

/// **`reason` 在生產端就消毒過一次**（#554 R27 D75；R26 verify security 第 18 列、DA 第 44 列：這裡曾原樣插值 key 與 decode error，sink 再
/// `displaySafe` 一次——TAG／ZWSP 原樣穿過（列舉不收），而 `StoreKey.pattern` 的反斜線被逃成 `\u{005C}`，一句修法指示被改寫成不存在的
/// 正則）：未信任的部分（key、citekey、檔名 stem、decode error 全文）走 `displaySafeInvisible`，程式自己組的部分（pattern、uuid）原樣。
/// sink（CLI `quarantineLines`、MCP doctor）只截不逃——`displaySafe` 不冪等。
/// `reason` **在建構時已消毒一次**（R27 D75 → R28 D80）：key 拒絕支逐項 `displaySafeInvisible`、decode-error 支走 `displaySafeError`
/// （自帶消毒的 `StoreYAMLError` 只截、Yams／I/O 錯誤逃脫一次）。三個 sink（CLI `quarantineLines`、MCP doctor、App `displayReason`）
/// 只截不逃；`file` 是目錄列舉來的原始檔名，**未消毒**——sink 對它 `displaySafeInvisible`。每個建構點由
/// `SanitizationBoundaryTests.testQuarantineAndFormatFailureReasonsAreSanitizedAtConstruction` 掃。
public struct QuarantinedFile: Equatable {
    public var file: String
    public var reason: String

    public init(file: String, reason: String) {
        self.file = file
        self.reason = reason
    }
}

public struct LibraryLoad {
    public var entries: [Entry]
    public var people: [Person]
    /// 機構（第三種一級實體形狀，標籤 `organization:`）。
    public var organizations: [Organization]
    /// 未決的同一性問題（#71，標籤 `divergence:`）。**短暫**——消歧完成即刪除，
    /// 歷史託給版本控制。載入時與其他形狀並列，但它不是被指涉的對象。
    public var divergences: [Divergence]
    /// 發表載體（第五種一級實體形狀，標籤 `venue:`，#304）。
    public var venues: [Venue]
    /// Library registry（#13 membership views）；成員關係在各 entry 的 akashic.libraries
    public var libraries: [Library]
    public var quarantined: [QuarantinedFile]
    /// 含未知欄位（較新 schema 寫入）的檔案清單——#23 tolerant-preserve 的可見性面，
    /// doctor / validate 據此提示升級 binary。R6（L20）：由 load() 以**實際檔名**
    /// 填入（與 quarantined 同慣例）——先前用 key 合成 `.yaml` 檔名，`.YAML` 等
    /// 大小寫別名會被報成不存在的路徑。
    public var unknownFieldFiles: [String]
    /// #645：每筆 person／organization／venue 在 load 時**實際讀到**的位元組數（以記錄 id 為鍵）——與讀取閘
    /// `AliasEventBudget.check` 比對的是同一個 `text.utf8.count`。預算預警讀它，不事後依路徑去 stat：依 format 推回
    /// 路徑會在 legacy `people/`、symlink、檔名大小寫上指錯檔而靜默不報（#645 R3 verify，DA 真 binary 重現）。
    /// 只有經 `load()` 的記錄有值；手工組出來的 `LibraryLoad` 沒有，預警對它們不出聲（沒有位元組可量）。
    public var recordBytes: [UUID: Int] = [:]

    public init(entries: [Entry] = [], people: [Person] = [],
                organizations: [Organization] = [],
                divergences: [Divergence] = [],
                venues: [Venue] = [],
                libraries: [Library] = [], quarantined: [QuarantinedFile] = [],
                unknownFieldFiles: [String] = []) {
        self.entries = entries
        self.people = people
        self.organizations = organizations
        self.divergences = divergences
        self.venues = venues
        self.libraries = libraries
        self.quarantined = quarantined
        self.unknownFieldFiles = unknownFieldFiles
    }
}

/// 檔案為本的 library 存取層。canonical 是 entries/ 與 people/ 的 YAML；
/// .akashic/ 是可重建衍生物。所有寫入走 atomic（temp + rename）。
public final class LibraryStore {
    public let root: URL

    /// **讀取時的記憶體覆寫**（#425 verify）：絕對路徑 → 內容。
    ///
    /// 存在的唯一理由是 `migrate-identifiers` 的乾跑：形狀升級若不寫檔，load 會對
    /// 那些檔 quarantine，於是**乾跑拒跑而 `--apply` 成功**——違反該命令自己寫下的
    /// 契約「乾跑與 apply 得到同一組 blockers」。有了這層，乾跑可以把升級後的文字
    /// 餵給 decode 而**磁碟一個位元組都不動**。
    ///
    /// **不是相容路徑**：它不讀舊格式、不推導缺欄位、不回退目錄。它是一個顯式的
    /// 測試／預演注入點，呼叫端 `grep textOverrides` 一眼看完（目前只有一處）。
    public var textOverrides: [String: String] = [:]

    public var entriesDir: URL { root.appendingPathComponent("entries") }
    public var peopleDir: URL { root.appendingPathComponent("people") }
    public var librariesDir: URL { root.appendingPathComponent("libraries") }
    /// #35：統一的 canonical 目錄。**分類不進路徑**——work / person / organization 與
    /// article / book 是同一個軸上的值，沒有理由前者當目錄、後者當欄位。檔名是不變的
    /// UUID，所以改 citekey 不再需要搬檔案。
    public var entitiesDir: URL { root.appendingPathComponent("entities") }

    public var akashicDir: URL { root.appendingPathComponent(".akashic") }

    /// registry key（`~/.akashic/config.yaml` 的 `files:` 鍵）。nil＝未註冊 store。
    public let key: String?
    let environment: [String: String]

    /// 衍生 index 的位置（#37）。
    ///
    /// - **已註冊 store**（有 registry key）→ `~/.akashic/index/<key>.sqlite`，在
    ///   store root **之外**。理由見 `AkashicHome.indexDirectory`；核心是「store
    ///   root 正是會進 Dropbox / git 的東西，而同步樹裡的 live SQLite 是已知的
    ///   毀檔風險（partial write、conflict copy）」。
    /// - **未註冊 store**（`--library <path>` 直指，多見於測試與一次性檢查）→
    ///   回落 in-store `.akashic/index.sqlite`。那種 store 不在 registry 的治理
    ///   範圍內，強行給它 home 內的位置反而要發明命名規則。
    ///
    /// 雙軌但各自合理：**有 key 就用 key，沒 key 就跟著 store**。
    public var indexURL: URL {
        // **檔名綁化身**（#130 裁決 3）：把 TOCTOU 從「偵測」變成「不可表達」——
        // 驗證與開啟之間有多少檔案存取都無所謂，換掉的 store 的 index 根本不叫
        // 這個名字。同路徑重生時新舊 index 是不同檔案，「舊 index 被誤信」的狀態
        // 不存在。缺席（既有 store 沒有 incarnation 檔）→ 沿用舊檔名，不遷移。
        let tag = StoreIncarnation.shortTag(StoreIncarnation.read(root: root))
        if let key {
            let name = tag.map { "\(key)-\($0)" } ?? key
            return AkashicHome.indexURL(forKey: name, environment: environment)
        }
        let name = tag.map { "index-\($0).sqlite" } ?? "index.sqlite"
        return akashicDir.appendingPathComponent(name)
    }

    /// 本 store 的化身 id（#130）。缺席回 `nil`——既有 store 都沒有，那不是錯誤。
    public var incarnation: String? { StoreIncarnation.read(root: root) }

    /// 同一個 registry key 底下、**不屬於當下化身**的 index 檔（#130）。
    ///
    /// 重生之後舊 index 成為孤兒。**報告不動手刪**（#79 的形狀）——它們可能是
    /// 另一台機器同步過來的、或使用者還想比對的。
    public func orphanedIndexFiles() -> [String] {
        guard let key, let tag = StoreIncarnation.shortTag(incarnation) else { return [] }
        let dir = AkashicHome.indexURL(forKey: key, environment: environment)
            .deletingLastPathComponent()
        let current = "\(key)-\(tag).sqlite"
        let all = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        // **`key-` 之後必須正好是 8 個小寫 hex**（#130 verify A）。
        //
        // 先前只要 `hasPrefix("\(key)-")`，於是 registry key `main` 會把
        // `main-backup-33f46bce.sqlite`——**另一個已註冊 store 正在用的 index**——
        // 報成自己的孤兒。而 `StoreKey.pattern` 允許連字號，所以 `main-backup`
        // 是合法的 key。訊息說「舊 index 不再使用」，照著做就刪掉別人的 live index。
        //
        // （`mainx-….sqlite` 不會誤報：連字號在 prefix 裡。誤報的是**含連字號的
        // key**，那是席位糾正我的——我原本擔心錯了方向。）
        func isOwnIncarnation(_ name: String) -> Bool {
            guard name.hasSuffix(".sqlite"), name.hasPrefix("\(key)-") else { return false }
            let tag = name.dropFirst(key.count + 1).dropLast(".sqlite".count)
            return tag.count == 8 && tag.allSatisfy { $0.isHexDigit && !$0.isUppercase }
        }
        return all.filter {
            $0 != current && ($0 == "\(key).sqlite" || isOwnIncarnation($0))
        }.sorted()
    }

    public init(root: URL, key: String? = nil,
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.root = root
        self.key = key
        self.environment = environment
    }

    /// 建立**這個 store 實際會用到的**目錄（#101）。
    ///
    /// 規則是「只建這個 store 用得到的」。在此之前這裡是一個無條件迴圈，於是 format 5 的 store
    /// 長出 format 1 的 `entries/`／`people/`、已註冊的 store 長出「未註冊 store 專用」
    /// 的 `.akashic/`——每次 `doctor` 都長回來，刪不掉。
    ///
    /// 之所以曾經非無條件不可，是因為 `atomicWrite` 不建父目錄；那個保證已下放到寫入
    /// 咽喉（見 `atomicWrite`），這裡才只剩「宣告佈局」一個職責。
    ///
    /// **順序有意義**：`store.yaml` 必須先寫，下面才讀得到 format。`writeIfAbsent` 只
    /// 需要 `root` 存在；它判定 legacy 的依據是 `entries/`／`people/` 裡**既有的檔案**，
    /// 不需要目錄被先建（原本的順序能運作只是因為 `createDirectory` 對既存目錄是 no-op）。
    public func ensureLayout() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        // #24：新建的 store 自我聲明格式。既有檔不覆寫（可能是較新版本寫的）。
        try StoreVersion.writeIfAbsent(root: root)
        // #130：化身 id。既有檔一律不覆寫——覆寫等於把一個 store 變成另一個化身，
        // 而那正是這個機制要偵測的事件。既有 store 首次被開啟時在此補寫，之後
        // 隨檔案原樣搬移（cp / rsync / Dropbox / git 都是同一份位元組）。
        try StoreIncarnation.writeIfAbsent(root: root)

        // **建佈局走 strict，不走 `usesEntitiesLayout` 的兜底**（#106）。那個兜底是給
        // 寫入路由的（#35：marker 壞掉時猜的方向與資料一致），但建佈局是結構性動作——
        // malformed 的 marker 配上空的 entities/ 會被猜成 legacy，安靜建出 entries/、
        // people/，零訊號；too-new 的 store 則會被 file add 成功註冊。兩者都該在這裡
        // 就拒絕：`read` 對 malformed 擲錯、tooNew 沿 refuse-if-newer（#24）的既有語意。
        // tooNew 與 malformed 的訊息都指路（tooNew「請升級」；malformed 的修復
        // 指引見 StoreVersionError.errorDescription，#118）。
        let format = try StoreVersion.read(root: root)
        guard format <= StoreVersion.supported else {
            throw StoreVersionError.tooNew(found: format, supported: StoreVersion.supported)
        }

        // 佈局目錄依 format 二選一（#102 完成了 #101 的鏡像）：entities 佈局建
        // `entities/`，legacy 建 `entries/`+`people/`——不再有哪個目錄是「兩邊都建」。
        // legacy store 的 `entities/` 由真正需要它的人建：遷移時 `StoreMigration`、
        // 消歧寫入時 `DivergenceResolve`、一般寫入時 `atomicWrite` 的父目錄保證。
        var dirs = [librariesDir]
        if format >= 2 {
            dirs.append(entitiesDir)
        } else {
            dirs += [entriesDir, peopleDir]
        }
        // in-store 的 index 回落位置，只有**沒帶 key 開啟**的 store 用得到（#37）。
        // #105 之後 `--library` 與 `$AKASHIC_LIBRARY` 對已註冊路徑會反查 registry
        // 帶 key 回來——keyless 只剩「真的未註冊」一種情況。
        if key == nil { dirs.append(akashicDir) }

        for dir in dirs {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        // #66：擷取內容的存檔目錄 + 版控排除區塊（idempotent；既有手工區塊不改寫）。
        // 建目錄與寫排除**同一動作**——目錄先於排除存在的窗口，就是內容可能被
        // commit 的窗口。
        try fm.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try ensureSourcesIgnoreBlock()
    }

    /// 佈局殘留（#107）：依當前 format 與 key **不該存在**、且是**空目錄或純衍生物**
    /// 的路徑。**報告用，不動手刪**——形狀沿 #79（讓看不見的變看見，處置留給人）。
    ///
    /// 判準刻意保守：
    /// - **永不報含資料的目錄**（就地遷移到一半的 legacy 檔是資料，不是殘留）
    /// - **`sources/` 絕不列入**——#66 的被指涉內容、只留 local 的唯一一份；
    ///   「0 引用」不等於「不要」（#101 清理時險些誤刪的教訓直接寫進這裡）
    /// - `.akashic/` 只在「帶 key 開啟 + 內容全是衍生物（index.sqlite 與暫存檔）」
    ///   時才報——出現未知檔案就閉嘴
    public func layoutResidue() throws -> [String] {
        let fm = FileManager.default
        // **前提：這裡真的是 store**（#120 verify FP-2）。缺了這條，`doctor --library
        // <任意目錄>` 會把使用者自己的空 `notes/`、`entries/` 報成「migrate 的遺留」
        // ——把 #105 的傷害從「留下垃圾」升級成「建議刪使用者的目錄」。
        guard LibraryStore.isLibraryRoot(root) else { return [] }
        let format = try StoreVersion.read(root: root)
        var out: [String] = []

        /// 目錄本身不是 symlink 的型別檢查（#120 verify FP-1：`fileExists` 跟隨
        /// symlink，`notes -> 外部目錄` 會被報「可刪」，而 `rm -rf notes/` 刪的是
        /// **目標**目錄——殘留判準絕不跨出 store）。
        func isRealDir(_ url: URL) -> Bool {
            guard let type = (try? fm.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType
            else { return false }
            return type == .typeDirectory
        }

        /// **嚴格空**：零子項才算空（#120 verify FP-3 + Codex P1：`.DS_Store` 豁免
        /// 疊在一個已隱形過濾 AppleDouble 的 API 上，且 `.DS_Store` 可以是**目錄**、
        /// 可以裝資料——「永不報含資料的目錄」必須是字面保證。Finder 殘渣讓目錄
        /// 不被報是可接受的 false negative，反向不是）。
        func isEmptyDir(_ url: URL) -> Bool {
            guard isRealDir(url),
                  let contents = try? fm.contentsOfDirectory(atPath: url.path)
            else { return false }
            return contents.isEmpty
        }

        if format >= 2 {
            if isEmptyDir(entriesDir) { out.append("entries/（空——migrate 的遺留，可刪）") }
            if isEmptyDir(peopleDir) { out.append("people/（空——migrate 的遺留，可刪）") }
        } else {
            if isEmptyDir(entitiesDir) { out.append("entities/（空——legacy store 用不到它，可刪）") }
        }
        if isEmptyDir(root.appendingPathComponent("notes")) {
            out.append("notes/（空——#103 已撤下，不再屬於佈局，可刪）")
        }
        if key != nil, isRealDir(akashicDir),
           let contents = try? fm.contentsOfDirectory(atPath: akashicDir.path) {
            if contents.isEmpty {
                out.append(".akashic/（空——本 store 已註冊，index 住 home 的 index/ 下，可刪）")
            } else {
                // **內容逐項驗明是 rebuild 的產物才報**（#120 verify FN-2 + Codex P1）：
                // - 白名單含 SQLite 側車（-wal/-shm/-journal——LibraryIndex 換位後會刪
                //   它們，崩過的孤兒正好是帶著側車的那種）
                // - temp 檔比對 rebuild 的**精確文法**（`.index.sqlite.rebuild-<UUID>`），
                //   不是寬前綴——`.index.sqlite.manual-backup` 是使用者的救援資料，
                //   不是衍生物
                // - 只接受一般檔：目錄／symlink 一律視為未知內容 → 閉嘴
                func isDerivedArtifact(_ name: String) -> Bool {
                    let u = akashicDir.appendingPathComponent(name)
                    guard let type = (try? fm.attributesOfItem(atPath: u.path))?[.type]
                            as? FileAttributeType, type == .typeRegular else { return false }
                    // **檔名文法要跟著 #130 走**（verify B）：in-store index 現在是
                    // `index-<8 碼>.sqlite`，rebuild temp 是
                    // `.index-<8 碼>.sqlite.rebuild-<UUID>`。先前白名單只認字面的
                    // `index.sqlite`，於是**凡是在新 binary 下先 keyless 用過、之後
                    // 才註冊的 store，`.akashic/` 的清理提示從此不出現**（origin/main
                    // 上會出現），崩掉的 rebuild 殘骸也從此沉默。
                    /// `index` 或 `index-<8 小寫 hex>`
                    func isIndexStem(_ stem: Substring) -> Bool {
                        if stem == "index" { return true }
                        guard stem.hasPrefix("index-") else { return false }
                        let tag = stem.dropFirst("index-".count)
                        return tag.count == 8 && tag.allSatisfy { $0.isHexDigit && !$0.isUppercase }
                    }
                    if name.hasPrefix(".") {
                        // rebuild temp：`.<stem>.sqlite.rebuild-<UUID>`
                        let body = name.dropFirst()
                        guard let r = body.range(of: ".sqlite.rebuild-") else { return false }
                        guard isIndexStem(body[body.startIndex..<r.lowerBound]) else { return false }
                        return UUID(uuidString: String(body[r.upperBound...])) != nil
                    }
                    for suffix in [".sqlite", ".sqlite-wal", ".sqlite-shm", ".sqlite-journal"]
                    where name.hasSuffix(suffix) {
                        return isIndexStem(name.dropLast(suffix.count))
                    }
                    return false
                }
                if contents.allSatisfy(isDerivedArtifact) {
                    out.append(".akashic/（keyless 時期的孤兒 index——本 store 已註冊，"
                             + "index 住 home 的 index/ 下；內容全為可重建的 index 衍生物，可刪）")
                }
            }
        }
        return out
    }

    /// #35：format 2 的檔案位置——**檔名是不變的 UUID**，所以改 citekey 不搬檔案。
    public func entityURL(id: UUID) -> URL {
        entitiesDir.appendingPathComponent("\(id.uuidString).yaml")
    }

    /// 這個 store 是否已遷移到 entities/ 佈局（#35）。
    ///
    /// 判準是 **store format**，不是「entities/ 目錄存不存在」——目錄可能因為
    /// `ensureLayout` 或半途中斷而存在卻是空的，用它當判準會讓寫入端在遷移完成前
    /// 就開始往新位置寫，產生兩個佈局並存的爛攤子。
    public var usesEntitiesLayout: Bool {
        do {
            return try StoreVersion.read(root: root) >= 2
        } catch {
            // **marker 讀不到／壞掉時不得靜默當 format 1**（verify HIGH）：寫入端會把
            // 新記錄寫進 `entries/`，而 format 2 的 store 其餘資料都在 `entities/`
            // ——兩個佈局並存，且沒有任何訊號。改以**磁碟事實**兜底：entities/ 有內容
            // 就當 format 2。這仍是猜，但猜的方向與資料一致，而不是與 marker 一致。
            let fm = FileManager.default
            let hasEntities = ((try? fm.contentsOfDirectory(atPath: entitiesDir.path)) ?? [])
                .contains { $0.lowercased().hasSuffix(".yaml") }
            return hasEntities
        }
    }

    public func entryURL(citekey: String) -> URL {
        entriesDir.appendingPathComponent("\(citekey).yaml")
    }

    public func personURL(key: String) -> URL {
        peopleDir.appendingPathComponent("\(key).yaml")
    }

    public func libraryURL(key: String) -> URL {
        librariesDir.appendingPathComponent("\(key).yaml")
    }

    /// **寫入閘**（#108）：canonical 記錄寫入的前提——root 得是一個 store。
    /// `store.yaml` 存在（#24 之後的 store）或 `isLibraryRoot`（pre-#24 legacy：
    /// 無 marker 但 canonical 目錄在）任一成立即放行。兩者皆無＝打錯的路徑——
    /// #101 讓 atomicWrite 自建父目錄後，這裡是唯一擋住「錯字 root 被安靜實體化」
    /// 的所在（CLI 的 openStore 只保護 CLI；MCP/App/外部呼叫端走的就是這些 API）。
    /// 正常路徑零成本：ensureLayout／openOrCreateStore 都寫 marker。
    ///
    /// ⚠️ 插入位置紀律（#136 verify F1（正典計數與三次機械化失敗的量測在 `docs/design-principles-and-philosophy.md` §16——**不要在原始碼裡各自重新計數**，那正是它一直過期的原因））：
    /// 在既有 API 的 attribute 與宣告之間插新函式，
    /// attribute 會綁到新函式上（@discardableResult 綁 Void 函式＝warning，
    /// -warnings-as-errors 下整個模組 build 失敗，且原 API 掉 attribute 生出
    /// 七個呼叫端 warning）。
    func assertStoreRoot() throws {
        guard FileManager.default.fileExists(atPath: StoreVersion.url(in: root).path)
                || LibraryStore.isLibraryRoot(root) else {
            throw StoreIOError.notAStore(root.path)
        }
    }

    /// Library registry 寫入（#13）：metadata-only；key 走 StoreKey write-time 驗證。
    /// entry 的 membership（akashic.libraries）由 writeEntry 一併驗證。
    @discardableResult
    public func writeLibrary(_ library: Library) throws -> URL {
        try assertStoreRoot()
        guard StoreKey.isValid(library.key) else {
            throw StoreIOError.invalidKey("library key", library.key)
        }
        let yaml = try LibraryYAML.encode(library)
        let dest = libraryURL(key: library.key)
        // exclusive-create：registry 無 update 路徑，並發 create 不得靜默互吃
        try atomicWrite(yaml, to: dest, mustCreate: true)
        return dest
    }

    /// `writeEntry`／`writeEntryExclusive` 的**全部非 I/O 前置條件**（#455）：citekey 文法、識別碼 reference ≥13、
    /// membership key 文法與重複、sources ≥9、venues ≥11、organization 作者 ≥12。與 `assertPersonWritable`／
    /// `assertOrganizationWritable`／`assertVenueWritable` 同形——寫入端與批次 create 的 preflight 共用同一個函式，
    /// 兩邊不會漂移。**抽出前 `writeEntryExclusive` 只驗 citekey＋encode**：rename 的目的檔與（本 change 起）批次
    /// create 都走它，format 閘整個缺席——format 10 的 store 能寫進含 venues 的 entry，舊 binary 讀到就靜默漏資料。
    /// `format` 是 lazy 的，理由同 `assertOrganizationWritable`（Codex R2 on #463）。
    public static func assertEntryWritable(_ entry: Entry, format provider: () throws -> Int) throws {
        var cached: Int?
        func format() throws -> Int {
            if let c = cached { return c }
            let f = try provider(); cached = f; return f
        }
        // write-time key 驗證：不合格式的 citekey 絕不進檔名（path traversal 防護）
        guard StoreKey.isValid(entry.citekey) else {
            throw StoreIOError.invalidKey("citekey", entry.citekey)
        }
        // #394 §6：識別碼 reference 需要 format 13。
        if !entry.references.isEmpty {
            try Self.assertIdentifierReferencesWritable(
                entry.references, format: try format(),
                what: "work「\(displaySafeInvisible(entry.citekey, max: 120))」")
        }
        // v16-only 語法的 format gate（#450）：拆分記錄（`field: authors` 的 reference）。
        // format-15 binary 的 `Entry.validateReferenceAttachment` 沒有 `authors` case → 封閉
        // default 擲錯 → **整檔 quarantine**（與 format 15 對 `field: paginated` 同形）——
        // 被拆過的 work 在舊 binary 上整筆消失而 rc=0，所以 marker 必須先擋。
        if entry.references.contains(where: { $0.field == "authors" }) {
            let format = try format()
            guard format >= 16 else {
                throw StoreIOError.invalidInput(
                    what: "entry「\(displaySafeInvisible(entry.citekey, max: 120))」",
                    why: "含作者位記錄（field: authors 的 reference），需要 store format ≥ 16；本 store 是 \(format)——" +
                         "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 format: 改成 16" +
                         "（format-15 binary 讀到會整檔 quarantine，且 rc=0）")
            }
            // v17-only 語法的 format gate（#457）：**移除**記錄。format-16 binary 的 `authors`
            // case 存在，但它只認得拆分文法 → `SplitRecordValue.parse` 回 nil → 一樣整檔
            // quarantine、rc=0。所以 16 這道閘擋不住它，要各自一道。
            if !entry.authorRemovalRecords.isEmpty {
                guard format >= 17 else {
                    throw StoreIOError.invalidInput(
                        what: "entry「\(displaySafeInvisible(entry.citekey, max: 120))」",
                        why: "含作者位**移除**記錄（field: authors、statement 走 `移除：理由`），需要 store format ≥ 17；" +
                             "本 store 是 \(format)——確認會碰這個 store 的 CLI/MCP/App 都已升級後，" +
                             "把 store.yaml 的 format: 改成 17（format-16 binary 讀到會整檔 quarantine，且 rc=0）")
                }
            }
        }
        // v18-only 語法的 format gate（#605）：附加 Zotero 來源。format-17 binary 會保留
        // `provenance_additional:` 卻不拿它比對，再匯入時安靜地重造攣生（見 StoreVersion 18）。
        if !entry.additionalProvenance.isEmpty {
            let format = try format()
            guard format >= 18 else {
                throw StoreIOError.invalidInput(
                    what: "entry「\(displaySafeInvisible(entry.citekey, max: 120))」",
                    why: "含附加 Zotero 來源（provenance_additional），需要 store format ≥ 18；本 store 是 \(format)——" +
                         "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 format: 改成 18" +
                         "（format-17 binary 會保留但不比對附加來源，再匯入時會重新造出攣生）")
            }
        }
        // membership keys（#13）同樣 write-time 驗證——不進路徑，但保 index/query 語意乾淨
        for key in entry.akashic.libraries where !StoreKey.isValid(key) {
            throw StoreIOError.invalidKey("akashic.libraries key", key)
        }
        // membership 是集合語意：重複 key 拒寫（list 計數/index 去重的上游保證）
        guard Set(entry.akashic.libraries).count == entry.akashic.libraries.count else {
            throw StoreIOError.invalidKey("akashic.libraries（重複）",
                                          entry.akashic.libraries.joined(separator: ","))
        }
        // v9-only 語法的 format gate（#223，同 ended/attested gate 的機制與理由）
        if !entry.akashic.sources.isEmpty {
            let format = try format()
            guard format >= 9 else {
                throw StoreIOError.invalidInput(
                        what: "entry「\(displaySafeInvisible(entry.citekey, max: 120))」",
                        why: "含 akashic.sources 副本引用，需要 store format ≥ 9；本 store 是 \(format)——" +
                         "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 " +
                         "format: 改成 9")
            }
        }
        // v11-only 語法的 format gate（#304）：venues ref 邊。舊 binary 對 entry 的
        // venues 鍵走 tolerant-preserve（保留不解讀）——反向查詢靜默漏資料，故仍 gate。
        if !entry.venues.isEmpty {
            let format = try format()
            guard format >= 11 else {
                throw StoreIOError.invalidInput(
                    what: "entry「\(displaySafeInvisible(entry.citekey, max: 120))」",
                    why: "含 venues 引用，需要 store format ≥ 11；本 store 是 \(format)——" +
                         "確認會碰這個 store 的 CLI/MCP/App 都已升級後，先以 migrate-venues " +
                         "遷移既有記錄，再把 store.yaml 的 format: 改成 11")
            }
        }
        // v12-only 語法的 format gate（#323）：organization 作者。舊 binary 對 authors
        // 的未知鍵是 `rejectUnknownKeys` 擲錯 → 上層轉**整檔 quarantine**（實測 rc=0
        // 且該筆整個消失、無訊息，只有 doctor 看得到）。比 venues 的 tolerant-preserve
        // 更嚴重，故同樣 gate。
        if entry.authors.contains(where: { if case .organization = $0 { return true }
                                           else { return false } }) {
            let format = try format()
            guard format >= 12 else {
                throw StoreIOError.invalidInput(
                    what: "entry「\(displaySafeInvisible(entry.citekey, max: 120))」",
                    why: "含 organization 作者，需要 store format ≥ 12；本 store 是 \(format)——" +
                         "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 " +
                         "format: 改成 12（format-11 binary 讀到會整檔 quarantine，" +
                         "且 query 不會報錯）")
            }
        }
    }

    /// #631：entities 佈局下，寫 `entities/<id>.yaml` 之前確認目的檔要嘛不存在、要嘛是**同一種記錄、同一個 id**。
    /// 以 id 定檔的寫入先前一律 `atomicWrite` 覆寫，從不看目的檔原本是什麼——被 quarantine 的記錄（load 不收，
    /// 所以任何以載入母體為準的閘都看不到它）或另一種記錄會被整個蓋掉（#627 R3 verify 真 binary 重現：永久遺失）。
    /// 同種同 id、citekey 不同照樣放行：rename 是原地改稱呼。只拒寫，不刪不修——那是人的判定。
    /// 呼叫端決定要不要問：work／person 只在 entities 佈局下寫 `entities/`；venue／organization／divergence 一律寫那裡。
    public func assertEntitiesDestination(id: UUID, kind: EntityKind) throws {
        let dest = entityURL(id: id)
        guard FileManager.default.fileExists(atPath: dest.path) else { return }
        let found: EntityKind
        let foundID: UUID
        let foundKey: String?
        do {
            let text = try String(contentsOf: dest, encoding: .utf8)
            // 形狀標籤的嚴格度與 load 同一條（format ≥ 3 缺標籤即錯）——寬鬆 peek 會把 load 隔離的無標籤檔
            // 認成同一筆而放行覆寫（#631 R1 verify Codex）
            let strict = ((try? StoreVersion.read(root: root)) ?? 1) >= 3
            found = try EntityKind.peek(text, strict: strict)
            switch found {
            case .work: let e = try EntryYAML.decode(text); foundID = e.id; foundKey = e.citekey
            case .person: let p = try PersonYAML.decode(text); foundID = p.id; foundKey = p.key
            case .organization: let o = try OrganizationYAML.decode(text); foundID = o.id; foundKey = o.key
            case .venue: let v = try VenueYAML.decode(text); foundID = v.id; foundKey = v.key
            case .divergence: foundID = try DivergenceYAML.decode(text).id; foundKey = nil
            }
        } catch {
            throw StoreIOError.destinationHoldsAnotherRecord(
                id: id, detail: "讀不出一筆完整的記錄（可能是被 quarantine 的記錄）：" + displaySafeError(error, max: 300))
        }
        // load 的語意隔離（key 不合法）同樣算「不是一筆完整的記錄」——覆寫它等於靜默修掉一筆被隔離的記錄
        if let foundKey, !StoreKey.isValid(foundKey) {
            throw StoreIOError.destinationHoldsAnotherRecord(
                id: id, detail: "是一筆 key 不合法而被 quarantine 的 \(found.rawValue) 記錄")   // display-safe-exempt: found 是封閉 enum rawValue
        }
        guard found == kind, foundID == id else {
            throw StoreIOError.destinationHoldsAnotherRecord(
                id: id, detail: "是一筆 \(found.rawValue) 記錄（id \(foundID.uuidString)），不是這次要寫的 \(kind.rawValue)")   // display-safe-exempt: found／kind 是封閉 enum rawValue；foundID.uuidString 是解碼出的 UUID（型別保證）
        }
    }

    /// #631：寫一筆 work／person 到 `entities/<id>.yaml` 之前的全部前置檢查——**不寫任何東西**。
    ///
    /// 1. 目的檔檢查（`assertEntitiesDestination`）。
    /// 2. legacy 拷貝（`entries/<citekey>.yaml`／`people/<key>.yaml`）解碼出同一個 id 時：
    ///    - `entities/` 裡**沒有**它 → 只有這一份，回傳它：呼叫端寫完之後刪掉它，完成搬移（使用者 2026-09-24 裁決：
    ///      只有一份時搬移不遺失任何東西——新內容就是從它讀出來再改的；store 受 git 追蹤，可還原）；
    ///    - `entities/` 裡**也有** → 兩份並存、可能已分岔 → 拒絕（留哪一份是判定）。
    ///    讀不出來的 legacy 檔不算——它本來就被 quarantine，寫 entities 不碰它。
    ///
    /// 多檔操作（rename、rename-person、合併、venue apply）在第一次寫入之前對每一筆呼叫它——
    /// 寫到一半才撞上拒絕會把 store 撕成一半（#631 R1 verify 以真 binary 重現）。
    func entitiesWritePlan(id: UUID, kind: EntityKind, legacy: URL?, legacyLabel: String,
                           expectedKey: String) throws -> URL? {
        try assertEntitiesDestination(id: id, kind: kind)
        guard let legacy, FileManager.default.fileExists(atPath: legacy.path),
              let text = try? String(contentsOf: legacy, encoding: .utf8) else { return nil }
        let decoded: (id: UUID, key: String)?
        switch kind {
        case .work: decoded = (try? EntryYAML.decode(text)).map { ($0.id, $0.citekey) }
        case .person: decoded = (try? PersonYAML.decode(text)).map { ($0.id, $0.key) }
        default: decoded = nil
        }
        guard let decoded, decoded.id == id else { return nil }
        if FileManager.default.fileExists(atPath: entityURL(id: id).path) {
            throw StoreIOError.legacyCopyPresent(file: legacyLabel)
        }
        // #631 R2：只有一份時搬移，但刪之前確認兩件事——任一不成立就拒寫、檔案不動：
        // (1) 它是這筆記錄的合法來源：key 合法且與預期一致（R2 verify Codex：只比 UUID 會把 load 隔離的檔當來源刪掉）
        guard StoreKey.isValid(decoded.key), decoded.key == expectedKey else {
            throw StoreIOError.legacyCopyUnmovable(
                file: legacyLabel, why: "它的 key 不合法或與檔名不符（load 會隔離它，它不是這次寫入內容的來源）")
        }
        // (2) 刪了回得來：受 git 追蹤且沒有未 commit 的修改（R2 verify security：合併會收攏 verdict 列，新內容不是舊內容的
        // 超集；「store 受 git 追蹤」這句要驗，不能假設——同 D86 的閘）
        if let bad = Self.filesNotSafelyRecoverable(root: root, relativePaths: [legacyLabel]).first {
            throw StoreIOError.legacyCopyUnmovable(file: legacyLabel, why: displaySafeInvisible(bad.why, max: 400))
        }
        return legacy
    }

    /// work 的寫入前置（不寫）。`legacyCitekey` 省略時查這筆記錄自己的 citekey；rename 傳舊的 citekey。
    public func entryWritePlan(_ entry: Entry, legacyCitekey: String? = nil) throws -> URL? {
        guard usesEntitiesLayout else { return nil }
        let ck = legacyCitekey ?? entry.citekey
        return try entitiesWritePlan(id: entry.id, kind: .work,
                                     legacy: StoreKey.isValid(ck) ? entryURL(citekey: ck) : nil,
                                     legacyLabel: "entries/\(ck).yaml",   // display-safe-exempt: 描述端 displaySafeInvisible
                                     expectedKey: ck)
    }

    /// person 的寫入前置（不寫）。`legacyKey` 省略時查這筆記錄自己的 key；rename-person 傳舊的 key。
    public func personWritePlan(_ person: Person, legacyKey: String? = nil) throws -> URL? {
        guard usesEntitiesLayout else { return nil }
        let k = legacyKey ?? person.key
        return try entitiesWritePlan(id: person.id, kind: .person,
                                     legacy: StoreKey.isValid(k) ? personURL(key: k) : nil,
                                     legacyLabel: "people/\(k).yaml",   // display-safe-exempt: 描述端 displaySafeInvisible
                                     expectedKey: k)
    }

    @discardableResult
    public func writeEntry(_ entry: Entry) throws -> URL {
        try assertStoreRoot()
        try Self.assertEntryWritable(entry, format: { try StoreVersion.read(root: self.root) })
        let moveFrom = try entryWritePlan(entry)   // #631：目的檔檢查；legacy 單份 → 寫完搬移，兩份 → 拒絕
        let yaml = try EntryYAML.encode(entry)
        // #35：format 2 走 entities/<uuid>.yaml，legacy 走 entries/<citekey>.yaml
        let dest = usesEntitiesLayout ? entityURL(id: entry.id) : entryURL(citekey: entry.citekey)
        try atomicWrite(yaml, to: dest)
        if let moveFrom { try FileManager.default.removeItem(at: moveFrom) }   // #631：搬移完成
        return dest
    }

    /// exclusive-create 版 writeEntry：目的檔已存在（含檢查後才出現的並發寫入）
    /// 一律擲錯，絕不靜默覆蓋。rename 的目的檔寫入走這條，關掉 check-then-write
    /// 之間的 TOCTOU 覆寫視窗（moveItem 對既存目的檔是原子性拒絕）。
    @discardableResult
    public func writeEntryExclusive(_ entry: Entry) throws -> URL {
        try assertStoreRoot()
        try Self.assertEntryWritable(entry, format: { try StoreVersion.read(root: self.root) })   // 同一組閘（#455）
        let yaml = try EntryYAML.encode(entry)
        let dest = usesEntitiesLayout ? entityURL(id: entry.id) : entryURL(citekey: entry.citekey)
        try atomicWrite(yaml, to: dest, mustCreate: true)
        return dest
    }

    /// format 11 的 `VenueType` 值域（#324 之前的三值）。**寫死是刻意的**——它記錄的是
    /// 一個**歷史事實**（format 11 的 binary 認得哪些值），不會隨當前列舉演進；用
    /// `allCases` 反而會讓 gate 隨新增值自動放行，等於沒有 gate。
    private static let venueTypesReadableAtFormat11: Set<VenueType> = [
        .conference, .publisher,
    ]


    /// 這筆記錄的 references 有沒有指名識別碼欄位（#394 §6 的 bump 觸發面）。
    ///
    /// **只看 reference，不看識別碼欄位本身。** 識別碼欄位是 additive——頂層未知鍵
    /// 走 tolerant-preserve（2026-08-24 對 format-12 binary 實測）。對它設閘會讓
    /// `migrate-identifiers` 在 bump 之前跑不動，而 design.md 的部署順序要求遷移
    /// **跑在舊解碼器上**、format bump 是最後一步（先有雞先有蛋）。
    static let identifierReferenceFields: Set<String> = ["doi", "pmid", "isbn", "issn", "ror"]

    static func namesIdentifierReference(_ refs: [ProvenanceReference]) -> String? {
        refs.first { identifierReferenceFields.contains($0.field) }?.field
    }

    static func assertIdentifierReferencesWritable(
        _ refs: [ProvenanceReference], format: Int, what: String) throws {
        guard let field = namesIdentifierReference(refs), format < 13 else { return }
        throw StoreIOError.invalidInput(
            what: "\(what) 的 reference（field: \(field)）",   // display-safe-exempt: 值域是上方封閉集合
            why: "識別碼欄位攜帶來源是 format 13 的新能力（#394）；本 store 是 \(format)——" +
                 "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 format: " +
                 "改成 13。**實測依據**（2026-08-24，format-12 binary）：organization 帶 " +
                 "`field: ror` 的 reference 會**整檔 quarantine**；venue 的 `field: issn` " +
                 "與 work 的 `references:` 則落 tolerant-preserve——後兩者併入同一個 bump " +
                 "的理由同 format 11 對 `venues:` 的裁決：保留而不解讀的 reference 不會被" +
                 "附著驗證，於是它可以指向一個不存在的值而沒有人發現")
    }

    /// `writeVenue` 的**全部**前置閘，抽成可單獨呼叫的一份（#394 verify）。
    ///
    /// 存在的理由：`migrate-identifiers` 的 pre-flight 要在**任何寫入之前**判定
    /// venue 寫不寫得成，而它先前只查了兩件事（venue 存在、檔案受追蹤）——
    /// 這裡另外四道閘一道都沒模擬。work 先寫（`fields.issn` 已移除）、venue 後寫，
    /// venue 那格 throw 之後例外穿出 `run()`，於是那個 ISSN **從兩邊同時消失**，
    /// 而 report 在印任何東西之前就被丟棄。
    ///
    /// **抽出來而不是在 pre-flight 複製一份**：閘門清單複製兩份必然分岔，而分岔的
    /// 方向正好是「pre-flight 說可以、實際寫入時 throw」——也就是這個缺陷本身。
    /// format 19 的兩個新形狀（change `resolution-verdict-states`）：未決記錄（#619）與同一配對兩個判定層級並存（#636）。
    ///
    /// 兩者對 format-18 binary 都是安靜的破壞——前者整檔 quarantine，後者在舊鍵的收攏下丟掉一筆理由——所以 refuse-if-newer
    /// 必須在寫入端先 fire。三種 holder（person／organization／venue）共用這一道閘，不各寫一份。
    public static func assertVerdictShapesWritable(_ refs: [ProvenanceReference], format: Int, what: String) throws {
        guard format < 19 else { return }
        if refs.contains(where: { $0.field == ProvenanceReference.resolutionUndecidedField }) {
            throw StoreIOError.invalidInput(
                what: what,
                why: "含未決記錄（resolution-undecided），需要 store format ≥ 19；本 store 是 \(format)——"
                    + "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 format: 改成 19"
                    + "（format-18 binary 讀到這個欄位會整檔 quarantine）")
        }
        var seen: [String: ProvenanceReference.VerdictClass] = [:]
        for r in refs {
            guard let cls = r.verdictClass else { continue }
            let k = ProvenanceReference.verdictEqualityKey(field: r.field, value: r.value)
            if let prior = seen[k], prior != cls {
                throw StoreIOError.invalidInput(
                    what: what,
                    why: "同一配對同時有提名層與逐篇判定兩筆 \(displaySafeInvisible(r.field, max: 40))，需要 store format ≥ 19；"
                        + "本 store 是 \(format)——format-18 binary 的合併會把兩筆收成一筆"
                        + "（確認三個 binary 都已升級後，把 store.yaml 的 format: 改成 19）")
            }
            seen[k] = cls
        }
    }

    public static func assertVenueWritable(_ v: Venue, format: Int) throws {
        guard StoreKey.isValid(v.key) else {
            throw StoreIOError.invalidKey("venue key", v.key)
        }
        // v11 形狀 gate：舊 binary 對未知頂層形狀是**整檔 quarantine**（2026-08-16
        // 實測，見 StoreVersion doc）——refuse-if-newer 必須在寫入端先 fire。
        guard format >= 11 else {
            throw StoreIOError.invalidInput(
                what: "venue「\(displaySafeInvisible(v.key, max: 120))」",
                why: "venue 是 format 11 的新形狀；本 store 是 \(format)——" +
                     "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 " +
                     "format: 改成 11（舊 binary 讀到 venue 檔會整檔 quarantine）")
        }
        // #324：format 11 只認得三值。新值域（periodical 等）要 format 12——
        // format-11 binary 的 VenueType decode 對未知值**整檔拒讀**。
        if !Self.venueTypesReadableAtFormat11.contains(v.type), format < 12 {
            throw StoreIOError.invalidInput(
                what: "venue「\(displaySafeInvisible(v.key, max: 120))」的 type「\(v.type.rawValue)」",   // display-safe-exempt: rawValue 是編譯期常量
                why: "該值是 format 12 的新值域（#324）；本 store 是 \(format)——" +
                     "把 store.yaml 的 format: 改成 12（format-11 binary 讀到未知 " +
                     "venue type 會整檔拒讀）")
        }
        try Self.assertIdentifierReferencesWritable(
            v.references, format: format, what: "venue「\(displaySafeInvisible(v.key, max: 120))」")
        try Self.assertVerdictShapesWritable(
            v.references, format: format, what: "venue「\(displaySafeInvisible(v.key, max: 120))」")
        // #406：兩個世代的能力**分開閘**（R2 verify NEW BUG 1——初版把兩者綁在
        // 同一條 `< 15`，於是一筆合法的 format-14 venue（有頂層 `paginated:`、無
        // reference）連 add_names 這種無關寫入都被拒，破壞舊格式的 read-modify-write）：
        //
        // - 頂層 `paginated:` 值是 **format 14** 的鍵域。對 format-13 binary 它是
        //   **additive**——`VenueYAML.decode` 走 `captureUnknownBlocks` 的 tolerant-preserve，
        //   原樣保留而不解讀（#422 verify R1 更正：第一版寫「`rejectUnknownKeys` 整檔
        //   quarantine」，與程式相反；format 13 那一列早四天就對同一層的 `issn:` 實測過
        //   同一件事）。設閘的理由是「保留而不解讀」的後果：舊 binary 會把**已判定**的刊
        //   當成從未判定、安靜給出錯的 APA7 下限答案。
        //
        //   **`variant` 刻意不設閘**（同 format 13 對識別碼欄位的 doctrine，見 :498-504）：
        //   它有一個必須跑在 bump **之前**的遷移（`migrate-venue-variants`），對它設閘會讓
        //   遷移在 bump 之前跑不動；`paginated` 沒有 pre-bump 遷移，設閘零成本。判準是
        //   「有沒有 pre-bump 遷移」，不是「會不會 quarantine」。**R20 補記**（#554 R19 verify regression
        //   第 24 列）：D41 起 `migrate-venue-variants --apply` 一律拒絕，那條 pre-bump 遷移已不存在，依這個
        //   判準答案變成「沒有」；閘仍不加——live store 已在 16／17、format-13 store 零實例，#567 把命令退場時
        //   一併裁要不要補閘，不在這裡半做。
        if format < 14, v.paginated != nil {
            throw StoreIOError.invalidInput(
                what: "venue「\(displaySafeInvisible(v.key, max: 120))」的 paginated 值",
                why: "paginated 是 format 14 的新欄位（#422／#406）；本 store 是 \(format)——" +
                     "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 " +
                     "format: 改成 14（format-13 binary 讀到會原樣保留而不解讀——" +
                     "把已判定的刊當成從未判定，安靜給錯 APA7 下限）")
        }
        // - **判定 reference**（`field: paginated`）是 **format 15** 的 vocabulary
        //   （R1 verify）：format-14 binary 的附著驗證沒有這個 case，讀到會走封閉
        //   default 擲錯 → **整檔 quarantine**（且輸出與「判定從未發生」不可分辨，
        //   實測 406 個 venue 靜默掉到 373）。service 設值時必同時建 reference，
        //   所以本分支已足以讓新判定在 format 14 上原子失敗。
        if format < 15, v.references.contains(where: { $0.field == "paginated" }) {
            throw StoreIOError.invalidInput(
                what: "venue「\(displaySafeInvisible(v.key, max: 120))」的 paginated 判定",
                why: "paginated 判定 reference 是 format 15 的新能力（#406）；本 store 是 " +
                     "\(format)——確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 " +
                     "store.yaml 的 format: 改成 15。**實測依據**（2026-08-31，format-14 " +
                     "binary）：帶 `field: paginated` reference 的 venue 檔會**整檔 " +
                     "quarantine**，且輸出看起來就像判定從未發生")
        }
        try Self.assertNoErrors(v.validate(), what: "venue", key: v.key)
    }

    /// 發表載體只存在於 entities 佈局（format 11 起，#304）。
    @discardableResult
    public func writeVenue(_ v: Venue) throws -> URL {
        try assertStoreRoot()
        try Self.assertVenueWritable(v, format: try StoreVersion.read(root: root))
        let yaml = try VenueYAML.encode(v)
        try assertEntitiesDestination(id: v.id, kind: .venue)   // #631
        let dest = entityURL(id: v.id)
        try atomicWrite(yaml, to: dest)
        return dest
    }

    /// `writeOrganization` 的**全部非 I/O 前置條件**——寫入端與 `renameEntry` 的前置閘共用同一個函式，
    /// 兩邊不會漂移（#463 verify Codex R1：rename 側只鏡射了 key／validate／encode，漏掉 format 閘，format ≤ 7
    /// 的 store 會在 entry 寫完之後才在 `writeOrganization` 擲錯——撕裂）。`format` 是 **lazy** 的：只在某個閘真的需要它時才讀、讀一次就快取——`writeOrganization` 原本就是按需讀，
    /// 無條件讀會讓一個壞掉的 store.yaml 連沒有任何 gated feature 的 organization 都寫不進（Codex R2）。
    public static func assertOrganizationWritable(_ org: Organization, format provider: () throws -> Int) throws {
        var cached: Int?
        func format() throws -> Int {
            if let c = cached { return c }
            let f = try provider(); cached = f; return f
        }
        guard StoreKey.isValid(org.key) else {
            throw StoreIOError.invalidKey("organization key", org.key)
        }
        // #394 §6：識別碼 reference 需要 format 13。**這一格是硬觸發**——format-12
        // binary 讀到 `field: ror` 的 reference 會整檔 quarantine（2026-08-24 實測）。
        if !org.references.isEmpty {
            try Self.assertIdentifierReferencesWritable(
                org.references, format: try format(),
                what: "organization「\(displaySafeInvisible(org.key, max: 120))」")
        }
        // v6-only 語法的 format gate——理由見 writePerson（#131 verify Codex-H2）
        if org.names.entries.contains(where: \.range.endedUnknown)
            || org.parents.entries.contains(where: \.range.endedUnknown) {
            let format = try format()
            guard format >= 6 else {
                throw StoreIOError.invalidInput(
                        what: "organization「\(displaySafeInvisible(org.key, max: 120))」",
                        why: "含 ended 段，需要 store format ≥ 6；本 store 是 \(format)——" +
                         "升級方式見 writePerson 同型訊息")
            }
        }
        // v7-only（attested，#70）——同上
        if org.names.entries.contains(where: { !$0.range.attested.isEmpty })
            || org.parents.entries.contains(where: { !$0.range.attested.isEmpty }) {
            let format = try format()
            guard format >= 7 else {
                throw StoreIOError.invalidInput(
                        what: "organization「\(displaySafeInvisible(org.key, max: 120))」",
                        why: "含 attested 段，需要 store format ≥ 7；本 store 是 \(format)——" +
                         "升級方式見 writePerson 同型訊息")
            }
        }
        // v8-only（resolution verdict，#232）——同 writePerson 的 v8 gate
        if org.references.contains(where: {
            ProvenanceReference.resolutionVerdictFields.contains($0.field) }) {
            let format = try format()
            guard format >= 8 else {
                throw StoreIOError.invalidInput(
                        what: "organization「\(displaySafeInvisible(org.key, max: 120))」",
                        why: "含 resolution verdict reference，需要 store format ≥ 8；本 store 是 \(format)——" +
                         "升級方式見 writePerson 同型訊息")
            }
            try Self.assertVerdictShapesWritable(
                org.references, format: format, what: "organization「\(displaySafeInvisible(org.key, max: 120))」")
        }
        // 同 writePerson 的閘（#229）——「哪個名字對外」是同一個問題，不該有兩套答案
        try Self.assertNoErrors(org.validate(), what: "organization", key: org.key)
    }

    /// 機構只存在於 entities 佈局（format 4 起）——legacy 佈局沒有它的位置。
    @discardableResult
    public func writeOrganization(_ org: Organization) throws -> URL {
        try assertStoreRoot()
        try Self.assertOrganizationWritable(org, format: { try StoreVersion.read(root: self.root) })
        let yaml = try OrganizationYAML.encode(org)
        try assertEntitiesDestination(id: org.id, kind: .organization)   // #631
        let dest = entityURL(id: org.id)
        try atomicWrite(yaml, to: dest)
        return dest
    }

    /// `writePerson` 的**全部非 I/O 前置條件**——與 `assertOrganizationWritable`／`assertVenueWritable` 同型，寫入端與
    /// rename 的前置閘共用同一個函式（#463 verify DA-3：org 與 venue 的閘抽出後 person 腿仍只 encode，format ≤ 7 的 store 上
    /// `rename` 會在 entry 已改名之後才在 `writePerson` 的 v8 閘擲錯——撕裂，而 person 是三族裡 live verdict 最多的）。
    /// `format` 是 lazy 的，理由同 `assertOrganizationWritable`。
    public static func assertPersonWritable(_ person: Person, format provider: () throws -> Int) throws {
        var cached: Int?
        func format() throws -> Int {
            if let c = cached { return c }
            let f = try provider(); cached = f; return f
        }
        guard StoreKey.isValid(person.key) else {
            throw StoreIOError.invalidKey("person key", person.key)
        }
        // **v6-only 語法的 format gate**（#131 verify Codex-H2）：supported=6 只是本
        // binary 的讀取上限，**不會**讓既有 store 的 marker 自己變 6。若在 format ≤ 5
        // 的 store 寫入含 `ended` 的 person，v5 binary 看 marker 5 照讀 → 對該檔
        // strict-reject → 整檔 quarantine（人檔消失）——refuse-if-newer 完全沒 fire。
        // 拒絕而非自動 bump：升 marker 會讓其餘 binary（MCP/App）突然整庫拒開，
        // 那必須是使用者知情的動作，訊息指路。
        if person.profile.usesEndedUnknown {
            let format = try format()
            guard format >= 6 else {
                throw StoreIOError.invalidInput(
                        what: "person「\(displaySafeInvisible(person.key, max: 120))」",
                        why: "含 ended 段，需要 store format ≥ 6；本 store 是 \(format)——" +
                         "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 " +
                         "format: 改成 6（v6 只新增語法，既有資料不變）")
            }
        }
        // v7-only 語法的 format gate（#70，同 ended gate 的機制與理由）
        if person.profile.usesAttested {
            let format = try format()
            guard format >= 7 else {
                throw StoreIOError.invalidInput(
                        what: "person「\(displaySafeInvisible(person.key, max: 120))」",
                        why: "含 attested 段，需要 store format ≥ 7；本 store 是 \(format)——" +
                         "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 " +
                         "format: 改成 7（v7 只新增語法，既有資料不變）")
            }
        }
        // v8-only 語法的 format gate（#232 verify NEW-2/NEW-3，同 6/7 的機制與理由）：
        // verdict 欄位對 field 白名單是 strict——舊 binary 讀到是整檔 quarantine，
        // 且 quarantine 檔可被 bootstrap 的決定性 UUID 安靜覆寫、判定史全滅。
        // 這道閘是 verdict 寫入與「第二台機器上安靜銷毀 ledger」之間唯一的東西。
        if person.references.contains(where: {
            ProvenanceReference.resolutionVerdictFields.contains($0.field) }) {
            let format = try format()
            guard format >= 8 else {
                throw StoreIOError.invalidInput(
                        what: "person「\(displaySafeInvisible(person.key, max: 120))」",
                        why: "含 resolution verdict reference，需要 store format ≥ 8；本 store 是 \(format)——" +
                         "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 " +
                         "format: 改成 8（v8 只新增 references 欄位對，既有資料不變）")
            }
            try Self.assertVerdictShapesWritable(
                person.references, format: format, what: "person「\(displaySafeInvisible(person.key, max: 120))」")
        }
        // v10-only 形狀的 format gate（#227，同 6/7/8/9 的機制與理由）：巢狀 names
        // 對 v9 binary 是 known 欄位形狀不符 → **整檔 quarantine（人檔消失）**，
        // refuse-if-newer 必須在寫入端先 fire。空 names 的記錄不受此閘——檔上沒有
        // names 鍵，兩代 binary 都讀得懂。
        if !person.names.all.isEmpty {
            let format = try format()
            guard format >= 10 else {
                // #227 verify S5：用 invalidInput 不用 invalidKey——後者的框架是
                // 「不符合 key 正規式」，對合法 key 是假斷言，會把 LLM 呼叫端引去
                // 清洗 key（#133 立 invalidInput 防的正是這形；v6/7/8 舊 gate 沿用
                // 舊形屬既有債，另計）。
                throw StoreIOError.invalidInput(
                    what: "person「\(displaySafeInvisible(person.key, max: 120))」",
                    why: "含巢狀 names，需要 store format ≥ 10；本 store 是 \(format)——" +
                         "確認會碰這個 store 的 CLI/MCP/App 都已升級後，先以 " +
                         "migrate-person-identity 遷移既有記錄，再把 store.yaml 的 " +
                         "format: 改成 10（v10 改變 names 的形狀）")
            }
        }
        try Self.assertNoErrors(person.validate(), what: "person", key: person.key)
    }

    /// **需要 `@discardableResult`**：多數呼叫端隱式丟棄回傳的 URL——它們只在乎
    /// 「寫成功了」，不在乎寫到哪。生產碼裡有兩處：`AkashicService.addPerson`
    /// 與 CLI 的 `bootstrap-people`。
    ///
    /// 本 attribute 曾在 #55 插入 `writeOrganization` 時被誤刪（撞到 duplicate-attribute
    /// 編譯錯誤，刪錯了那一個），於 #59 復原；#463 抽出 `assertPersonWritable` 時**第三次**被文字手術
    /// 移位到 helper 上——pre-push 的 `-warnings-as-errors` 建置擋下（`swift test` 不帶該旗標，全綠仍會漏）。
    @discardableResult
    public func writePerson(_ person: Person) throws -> URL {
        try assertStoreRoot()
        try Self.assertPersonWritable(person, format: { try StoreVersion.read(root: self.root) })
        let yaml = try PersonYAML.encode(person)
        let moveFrom = try personWritePlan(person)   // #631：同 writeEntry
        let dest = usesEntitiesLayout ? entityURL(id: person.id) : personURL(key: person.key)
        try atomicWrite(yaml, to: dest)
        if let moveFrom { try FileManager.default.removeItem(at: moveFrom) }   // #631：搬移完成
        return dest
    }

    /// **`.error` 等級的不變式住在寫入邊界**（#229）。
    ///
    /// `authorized ⊆ names` 與「每書寫系統至多一個」在 spec 是 `SHALL be rejected`，
    /// 但先前只活在 `validate()`——而 `validate()` 由呼叫端自行決定要不要跑。實測 7 個
    /// `writePerson` 呼叫端只有 `UpdatePerson` 補了它（其註解自陳是為了補洞），
    /// `addPerson` / `bootstrap-people --apply` / `ProvenanceMigration` /
    /// `AuthorizedNameMigration` / `DivergenceResolve` 都沒有。
    ///
    /// 不變式必須住在**所有路徑的交會處**，不是靠每個呼叫端記得——與本 repo 的
    /// `jsonBytes`（實測取代手寫估算式）、`rowID`（單一定義取代三份拷貝）同一條紀律：
    /// 把「記得做」換成「做不到不做」。
    ///
    /// ## 判準是嚴重度，不是「validate 回了東西」
    ///
    /// `.warning` **不得**擋寫入。`unknownFields` 產生 warning，而 tolerant-preserve
    /// （#23）是明文功能：較新 schema 寫入的欄位必須被保留而非拒收。若改成「issues
    /// 非空就拒絕」，含未知欄位的記錄會突然寫不進去——那是把相容性功能靜默換成硬錯誤。
    static func assertNoErrors(_ issues: [ValidationIssue], what: String, key: String) throws {
        let errors = issues.filter { $0.severity == .error }
        guard errors.isEmpty else {
            throw StoreIOError.invalidInput(
                what: "\(what) '\(displaySafeInvisible(key, max: 120))'",
                why: errors.map(\.message).joined(separator: "；"))
        }
    }

    private struct CanonicalLoadSource {
        let markerData: Data?
        let markerPath: String
        let paths: (_ directory: String) throws -> [String]
        let data: (_ relativePath: String) throws -> Data

        func text(_ relativePath: String) throws -> String {
            let bytes = try data(relativePath)
            guard let text = String(data: bytes, encoding: .utf8) else {
                throw StoreIOError.invalidInput(
                    what: displaySafeInvisible(relativePath, max: 200), why: "canonical YAML 不是 UTF-8")
            }
            return text
        }
    }

    /// 掃描整個 library。schema 不合的檔案進 quarantined 報告，不靜默略過、
    /// 也不讓單一壞檔中斷整批載入。
    public func load() throws -> LibraryLoad {
        let markerURL = StoreVersion.url(in: root)
        let markerData: Data?
        if FileManager.default.fileExists(atPath: markerURL.path) {
            markerData = try Data(contentsOf: markerURL)
        } else {
            markerData = nil
        }
        let source = CanonicalLoadSource(
            markerData: markerData,
            markerPath: markerURL.path,
            paths: { [self] directory in
                try yamlFiles(in: root.appendingPathComponent(directory)).map {
                    "\(directory)/\($0.lastPathComponent)"
                }
            },
            data: { [root, textOverrides] relativePath in
                // 記憶體覆寫優先（#425 verify）——`migrate-identifiers` 的乾跑靠它把
                // 升級後的文字餵進 decode 而不動磁碟。空字典時行為逐位元不變。
                let url = root.appendingPathComponent(relativePath)

                if let injected = textOverrides[url.path] { return Data(injected.utf8) }
                return try Data(contentsOf: url)
            })
        return try load(from: source)
    }

    /// snapshot 接受 capture 後的純記憶體 decode seam；不得在這條路徑重新讀磁碟。
    func decodeCaptured(_ captured: CapturedCanonicalStore) throws -> LibraryLoad {
        // Swift String equality 會把 NFC/NFD 視為相等；filesystem 與 revision 的 path
        // 身分則是 raw UTF-8。用 String 當 dictionary key，兩個可並存的 raw path 會在
        // `uniqueKeysWithValues` 直接 precondition trap，也會與 digest 的身分邊界分叉。
        let byRawPath = Dictionary(uniqueKeysWithValues: captured.yamlRecords.map {
            (Data($0.path.utf8), $0.bytes)
        })
        let source = CanonicalLoadSource(
            markerData: captured.markerBytes,
            markerPath: StoreVersion.url(in: root).path,
            paths: { directory in
                Array(captured.yamlRecords.lazy
                    .map(\.path)
                    .filter { $0.hasPrefix("\(directory)/") })
            },
            data: { relativePath in
                guard let bytes = byRawPath[Data(relativePath.utf8)] else {
                    throw StoreIOError.invalidInput(
                        what: displaySafeInvisible(relativePath, max: 200), why: "accepted capture 缺少已列舉的 bytes")
                }
                return bytes
            })
        return try load(from: source)
    }

    private func load(from source: CanonicalLoadSource) throws -> LibraryLoad {
        // #24：refuse-if-newer 必須在**逐檔 decode 之前**。等到 decode 現場才發現
        // 不對，使用者拿到的是一堆難解的 per-file 錯誤，而不是一句「請升級 binary」。
        let format = try StoreVersion.read(data: source.markerData, path: source.markerPath)
        guard format <= StoreVersion.supported else {
            throw StoreVersionError.tooNew(found: format, supported: StoreVersion.supported)
        }
        // 形狀標籤的嚴格度由 format 決定（見 EntityKind.peek 的 strict 參數）：
        // format ≥ 3 的檔案是標籤機制之後寫的，缺標籤即錯；舊格式須容忍，否則
        // `akashic migrate` 會連載入都做不到——它正是要來替那些檔貼標籤的。
        let strictLabels = format >= 3
        var result = LibraryLoad()

        // #35：entities/ 是 format 2 的 canonical 目錄。**與 legacy 並存讀取**——
        // 遷移是一次性動作，但舊佈局的 store（含別人的 clone、未遷移的備份）必須照樣讀。
        for path in try source.paths("entities") {
            let name = path
            do {
                let text = try source.text(path)
                let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                // 檔名即身分：stem 必須是合法 UUID 且與記錄的 id 相符。
                // 不符時 quarantine——那代表有人手動改了檔名或 id，兩者都會讓引用錯位。
                guard let stemUUID = UUID(uuidString: stem) else {
                    result.quarantined.append(QuarantinedFile(
                        file: name, reason: "entities/ 的檔名必須是 UUID，實得「\(displaySafeInvisible(stem, max: 120))」"))
                    continue
                }
                switch try EntityKind.peek(text, strict: strictLabels) {
                case .person:
                    let person = try PersonYAML.decode(text)
                    guard person.id == stemUUID else {
                        result.quarantined.append(QuarantinedFile(
                            file: name, reason: "檔名 UUID 與 person.id「\(person.id.uuidString)」不符"))
                        continue
                    }
                    guard StoreKey.isValid(person.key) else {
                        result.quarantined.append(QuarantinedFile(
                            file: name, reason: "person key「\(displaySafeInvisible(person.key, max: 120))」不符合 \(StoreKey.pattern)"))
                        continue
                    }
                    if !person.unknownFields.isEmpty { result.unknownFieldFiles.append(name) }
                    result.recordBytes[person.id] = text.utf8.count
                    result.people.append(person)
                case .organization:
                    let org = try OrganizationYAML.decode(text)
                    guard org.id == stemUUID else {
                        result.quarantined.append(QuarantinedFile(
                            file: name,
                            reason: "檔名 UUID 與 organization.id「\(org.id.uuidString)」不符"))
                        continue
                    }
                    guard StoreKey.isValid(org.key) else {
                        result.quarantined.append(QuarantinedFile(
                            file: name,
                            reason: "organization key「\(displaySafeInvisible(org.key, max: 120))」不符合 \(StoreKey.pattern)"))
                        continue
                    }
                    if !org.unknownFields.isEmpty { result.unknownFieldFiles.append(name) }
                    result.recordBytes[org.id] = text.utf8.count
                    result.organizations.append(org)
                case .venue:
                    let v = try VenueYAML.decode(text)
                    guard v.id == stemUUID else {
                        result.quarantined.append(QuarantinedFile(
                            file: name,
                            reason: "檔名 UUID 與 venue.id「\(v.id.uuidString)」不符"))
                        continue
                    }
                    guard StoreKey.isValid(v.key) else {
                        result.quarantined.append(QuarantinedFile(
                            file: name,
                            reason: "venue key「\(displaySafeInvisible(v.key, max: 120))」不符合 \(StoreKey.pattern)"))
                        continue
                    }
                    if !v.unknownFields.isEmpty { result.unknownFieldFiles.append(name) }
                    result.recordBytes[v.id] = text.utf8.count
                    result.venues.append(v)
                case .divergence:
                    let d = try DivergenceYAML.decode(text)
                    guard d.id == stemUUID else {
                        result.quarantined.append(QuarantinedFile(
                            file: name,
                            reason: "檔名 UUID 與 divergence.id「\(d.id.uuidString)」不符"))
                        continue
                    }
                    // 候選鍵的 load-time 驗證，與其他三個形狀一致。**沒有這道，寫入端的
                    // 守衛會在最壞的位置開火**：一筆手寫的畸形記錄照樣進 store，於是
                    // 每次消歧都在改寫階段才因為它而失敗，而那時倖存者的別名已經寫進
                    // 磁碟了——一筆無關的壞記錄把合法的消歧永久鎖死（#71 R2 DA PROBE 12）。
                    if let bad = d.candidates.first(where: { !StoreKey.isValid($0.key) }) {
                        result.quarantined.append(QuarantinedFile(
                            file: name,
                            reason: "候選 key「\(displaySafeInvisible(bad.key, max: 120))」不符合 \(StoreKey.pattern)"))
                        continue
                    }
                    if !d.unknownFields.isEmpty { result.unknownFieldFiles.append(name) }
                    result.divergences.append(d)
                case .work:
                    let entry = try EntryYAML.decode(text)
                    guard entry.id == stemUUID else {
                        result.quarantined.append(QuarantinedFile(
                            file: name, reason: "檔名 UUID 與 entry.id「\(entry.id.uuidString)」不符"))
                        continue
                    }
                    guard StoreKey.isValid(entry.citekey) else {
                        result.quarantined.append(QuarantinedFile(
                            file: name, reason: "citekey「\(displaySafeInvisible(entry.citekey, max: 120))」不符合 \(StoreKey.pattern)"))
                        continue
                    }
                    if let bad = entry.akashic.libraries.first(where: { !StoreKey.isValid($0) }) {
                        result.quarantined.append(QuarantinedFile(
                            file: name, reason: "akashic.libraries 含不合法 key「\(displaySafeInvisible(bad, max: 120))」"))
                        continue
                    }
                    var e2 = entry
                    var seen = Set<String>()
                    e2.akashic.libraries = entry.akashic.libraries.filter { seen.insert($0).inserted }
                    if !entry.unknownFields.isEmpty { result.unknownFieldFiles.append(name) }
                    result.entries.append(e2)
                }
            } catch {
                result.quarantined.append(QuarantinedFile(
                    file: name,
                    reason: displaySafeError(error, max: 4_096)))
            }
        }

        for path in try source.paths("entries") {
            let name = path
            do {
                let entry = try EntryYAML.decode(try source.text(path))
                // 語意驗證：decode 成功但 key 不合法／與檔名不符 → quarantine。
                // 畸形 citekey 一旦進入 library，之後任何 entryURL 組合（rename 刪除、
                // orphan trash）都是 path traversal 面；檔名不符則造成重複 entry 與錯位刪除。
                let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                guard StoreKey.isValid(entry.citekey) else {
                    result.quarantined.append(QuarantinedFile(
                        file: name,
                        reason: "citekey「\(displaySafeInvisible(entry.citekey, max: 120))」不符合 \(StoreKey.pattern)"))
                    continue
                }
                guard stem == entry.citekey else {
                    result.quarantined.append(QuarantinedFile(
                        file: name,
                        reason: "檔名 stem「\(displaySafeInvisible(stem, max: 120))」與 citekey「\(displaySafeInvisible(entry.citekey, max: 120))」不符"))
                    continue
                }
                // membership 語意驗證（#13 verify）：畸形 key 的 entry 之後任何衍生層
                // 寫入都會被 writeEntry 拒絕（看似可讀、實則鎖死）；重複 key 使計數失真
                if let bad = entry.akashic.libraries.first(where: { !StoreKey.isValid($0) }) {
                    result.quarantined.append(QuarantinedFile(
                        file: name,
                        reason: "akashic.libraries key「\(displaySafeInvisible(bad, max: 120))」不符合 \(StoreKey.pattern)"))
                    continue
                }
                // 純重複（格式合法）→ auto-dedupe 保序（DA 裁決：quarantine 對可用性
                // 過重；集合語意有唯一無歧義修法）。注意：去重在 load 即完成、屬靜默
                // 正規化——validate() 的重複警告只對未正規化的記憶體物件（寫前 lint）有效。
                var entry2 = entry
                var seen = Set<String>()
                entry2.akashic.libraries = entry.akashic.libraries.filter { seen.insert($0).inserted }
                if !entry2.unknownFields.isEmpty || !entry2.akashic.unknownFields.isEmpty {
                    result.unknownFieldFiles.append(name)
                }
                result.entries.append(entry2)
            } catch {
                result.quarantined.append(QuarantinedFile(
                    file: name,
                    reason: displaySafeError(error, max: 4_096)))
            }
        }
        for path in try source.paths("people") {
            let name = path
            do {
                let text = try source.text(path)
                let person = try PersonYAML.decode(text)
                let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                guard StoreKey.isValid(person.key) else {
                    result.quarantined.append(QuarantinedFile(
                        file: name,
                        reason: "person key「\(displaySafeInvisible(person.key, max: 120))」不符合 \(StoreKey.pattern)"))
                    continue
                }
                guard stem == person.key else {
                    result.quarantined.append(QuarantinedFile(
                        file: name,
                        reason: "檔名 stem「\(displaySafeInvisible(stem, max: 120))」與 person key「\(displaySafeInvisible(person.key, max: 120))」不符"))
                    continue
                }
                if !person.unknownFields.isEmpty {
                    result.unknownFieldFiles.append(name)
                }
                result.recordBytes[person.id] = text.utf8.count   // #645：legacy people/ 的記錄同樣量它實際讀到的
                result.people.append(person)
            } catch {
                result.quarantined.append(QuarantinedFile(
                    file: name,
                    reason: displaySafeError(error, max: 4_096)))
            }
        }
        for path in try source.paths("libraries") {
            let name = path
            do {
                let library = try LibraryYAML.decode(try source.text(path))
                let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                guard StoreKey.isValid(library.key) else {
                    result.quarantined.append(QuarantinedFile(
                        file: name,
                        reason: "library key「\(displaySafeInvisible(library.key, max: 120))」不符合 \(StoreKey.pattern)"))
                    continue
                }
                guard stem == library.key else {
                    result.quarantined.append(QuarantinedFile(
                        file: name,
                        reason: "檔名 stem「\(displaySafeInvisible(stem, max: 120))」與 library key「\(displaySafeInvisible(library.key, max: 120))」不符"))
                    continue
                }
                if !library.unknownFields.isEmpty {
                    result.unknownFieldFiles.append(name)
                }
                result.libraries.append(library)
            } catch {
                result.quarantined.append(QuarantinedFile(
                    file: name,
                    reason: displaySafeError(error, max: 4_096)))
            }
        }
        result.entries.sort { $0.citekey < $1.citekey }
        result.people.sort { $0.key < $1.key }
        result.libraries.sort { $0.key < $1.key }
        result.unknownFieldFiles.sort()
        return result
    }

    // MARK: - Internals

    /// Internal listing seam 讓 tests 可在會正規化檔名的 macOS 上，仍以兩個 raw UTF-8
    /// 不同但 canonical-equivalent 的 URL 驗證 production enumeration 邏輯。
    func yamlFiles(
        in dir: URL,
        listing: ((URL) throws -> [URL])? = nil
    ) throws -> [URL] {
        let fm = FileManager.default
        let urls: [URL]
        if let listing {
            urls = try listing(dir)
        } else {
            guard fm.fileExists(atPath: dir.path) else { return [] }
            urls = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        }
        // 副檔名比對大小寫不敏感：macOS 檔案系統多為 case-insensitive，
        // `.YAML` 檔是寫入目的檔的別名，必須被枚舉（否則連 quarantine 都進不了）
        return urls
            .filter { $0.pathExtension.lowercased() == "yaml" && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { rawUTF8Less($0.lastPathComponent, $1.lastPathComponent) }
    }

    private func readUTF8(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// temp 檔寫在同一目錄 + rename 取代——中斷不留半寫檔。
    /// dest 不存在時 `replaceItemAt` 的行為在 Apple docs 未保證（實測可行），
    /// 防禦性改走 moveItem——兩條路徑都是同目錄 rename、同等原子性。
    /// mustCreate = true 時強制走 moveItem——目的檔已存在會原子性擲錯，
    /// 不進 replaceItemAt 的覆蓋分支（exclusive-create 語意）。
    /// `internal` 而非 `private`：`DivergenceResolve.swift` 的 `writeDivergence` 走同一條
    /// 路徑。曾經在那裡複製一份近乎相同的實作，於 #71 R1 verify 被指出——複本的問題
    /// 不是當下行為不同，而是**日後對寫入路徑的加固不會傳到那一份**。
    func atomicWrite(_ content: String, to dest: URL, mustCreate: Bool = false) throws {
        let fm = FileManager.default
        let dir = dest.deletingLastPathComponent()
        // **父目錄由寫入端自己保證**（#101）。在此之前這件事是 `ensureLayout` 的無條件
        // 迴圈順便做掉的，於是那個迴圈不能依 format 條件化——「目錄存在」因此不再代表
        // 「這個佈局在用」。把保證下放到寫入端，兩件事就各自獨立：
        // `ensureLayout` 負責**宣告**佈局，寫入路徑負責**自己能寫**。
        //
        // 這裡涵蓋**所有走 `atomicWrite` 的寫入**（7 個呼叫點）——但它不是全部的寫入
        // 路徑：`StoreMigration` 直接用 Foundation 寫，見下。
        //
        // 讀取端（`yamlFiles`）早就容忍缺目錄（回空陣列）。這裡讓寫入端與它對稱。
        //
        // **它取代的只有 `writeLibrary` 那一處。** 另外兩處性質不同，別照著清：
        //
        // - `StoreMigration.swift:152` — **必要**。它下一行是 `p.yaml.write(to:atomically:)`，
        //   直接走 Foundation 而**不經過本咽喉**，所以目錄仍得自己建。
        // - `DivergenceResolve.swift:166` — 現在確實冗餘（下一行就是 `atomicWrite`），
        //   但留著讓該檔不依賴本函式的內部細節。冗餘無害，刪不刪都對。
        //
        // 這個保證也**不是** root 正確性的驗證——那是寫入 API 的 `assertStoreRoot`（#108）
    /// 的職責：五個寫入 API 前置寫入閘，錯字 root 在到達這裡之前就被拒絕。
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".\(dest.lastPathComponent).tmp-\(UUID().uuidString)")
        try content.write(to: tmp, atomically: false, encoding: .utf8)
        do {
            if !mustCreate && fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: dest)
            }
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }
}

/// 一筆**被改寫的持有記錄**——kind ＋ key（#498）。
///
/// 在此之前三個報告的 `verdictValuesRewritten` 是扁平的 key 清單，混三種記錄形狀
/// （person／organization／venue，#463 起三種都會出現在同一個清單裡）而不帶 kind。
/// 跨型別同名鍵在 live store 實測 **2 個**——那時清單上的一個字串對應兩筆記錄，
/// 使用者無從分辨哪一筆被改寫。
///
/// **為什麼是型別而不是 `"organization:some-org"` 字串。** 那個記法在本 store 已經
///有另一個意思：verdict value 的 `<kind>:<key> :: <literal>` 裡，`person:foo` 說的是
/// 「這條判定**是關於**誰」，而本清單說的是「**哪一筆記錄**被改寫」——同一個記法兩個軸。
/// 用具名欄位讓那個混淆寫不出來。
///
/// 相鄰的 `verdictsCollapsed` 仍是字串，這**不是不一致**：那是一串句子（「…——丟棄 …」），
/// 本型別是一筆記錄的身分。記錄身分值得一個型別，句子不值得。
// 刻意不加 `Sendable`：`EntityKind` 住在 AkashicCore 且未宣告該 conformance，跨 module
// 加上去會讓嚴格建置要求 `@preconcurrency import`（pre-push 的 -warnings-as-errors 實測擋下）。
// 相鄰的 `RenameReport`／`PersonRenameReport` 同樣沒有——要加就整族一起加，不是這裡先偷跑。
public struct HolderRecord: Equatable, Hashable, Comparable {
    /// 只會是 `.person`／`.organization`／`.venue`——三種持得住 verdict 的記錄形狀
    /// （`entity-backlink-completeness` 第 13 條邊）。用 `EntityKind` 而不是自己開一個
    /// 三值 enum：形狀的值域已經有唯一來源，第二份會分岔。
    public let kind: EntityKind
    public let key: String

    public init(_ kind: EntityKind, _ key: String) { self.kind = kind; self.key = key }

    /// 三個呈現面共用的顯示形——`organization「some-org」`。
    ///
    /// **key 在這裡就消毒**（`displaySafe`）：三個面各寫一份格式化就是三份會分岔的規格，
    /// 而其中一份忘了消毒不會有任何跡象。刻意用「」而不是 `:`——後者與 verdict value 的
    /// holder 記法撞號（見型別 doc）。
    public var describedSafely: String {
        "\(kind.rawValue)「\(displaySafeInvisible(key, max: 200))」"
    }

    public static func < (a: HolderRecord, b: HolderRecord) -> Bool {
        (a.kind.rawValue, a.key) < (b.kind.rawValue, b.key)
    }
}

/// person key 改名的回報（#395）。
///
/// **欄位與 `RenameReport` 不同，刻意不共用型別**——兩者的參照集合不同
/// （見 `renamePerson` 的對照表），共用一個型別會逼出「這個欄位對另一邊是什麼意思」
/// 這種答不出來的問題。
public struct PersonRenameReport: Equatable {
    /// `authors[].key` 有被改寫的 work citekeys。
    public var authorEdgesRewritten: [String]
    /// verdict value 的 `person:<key>` 有被改寫的**持有記錄**（person、organization 或 venue——#463 起 venue 也在列）。
    /// #498 起帶 kind：跨型別同名鍵在 live store 實測 2 個，扁平 key 清單分不出是哪一筆。
    public var verdictValuesRewritten: [HolderRecord]
    /// 候選或 `judgement.prefers` 有跟著改名的歧異記錄 id。
    public var divergencesRewritten: [String]
    /// 這次退役操作**沒有掃描到**的 quarantine 檔（#497）。
    ///
    /// 整張 verdict holder 遷移網格（#463）只走 `load()` 解析得出的記錄；被 quarantine 的檔
    /// 對它零可見性。#463 verify DA-7 的 fixture 實測：一筆 `names` 形狀不合法的 organization
    /// 持 `person:doomed-person` verdict，`rename-person` **成功**並印「（無其他記錄引用此 key）」，
    /// 而磁碟上那條 verdict 仍指向已退役的鍵。
    ///
    /// **刻意不掃檔案內文找舊鍵。** 那會印出一個比證據更強的宣稱：quarantine 檔正因為
    /// 解析不了才在那裡，而行級文字比對會漏掉被 YAML 折行的長 value（本 repo 量過的形狀）。
    /// 「沒掃到」是可以誠實斷言的，「掃過且沒有」不是。
    ///
    /// **新鍵方向另有一道閘，而它用的不是行級比對**（D63，R23）：`assertNoVerdictAlreadyAt` 對每個 quarantined 檔做**位元組**比對，
    /// needle `<kind>:<newKey>` 不含空白、本 repo emitter（只在空白處折行）寫出的檔折行打不斷它，出現即拒。它能誠實斷言的是「這個檔的位元組裡沒有 `<kind>:<newKey>`」，
    /// 不是「這個檔沒有指向新鍵的 verdict」（雙引號逃脫仍躲得過——與 merge 隔離檔閘同一個已接受的限制）。R22 的 D61 用 `<kind>:<newKey> ::`
    /// 逐行比對，needle 裡的空白正是 YAML 唯一會折的位置——live store 當時就有 2 筆折在那裡的 value（R22 verify 四席同指）。
    public var quarantinedNotScanned: [String]
    /// 被改寫的 verdict 之間**完全相同**（field、value、judgement、rests-on 全等）的重複被折成一筆時，被丟的那些列（#495 起有回報；
    /// 判準自 R22 D62 起是整筆相等——R21 之前是 (field, value) 位元組、#470 之後一度是 `verdictEqualityKey` 正規化鍵，兩者都會丟掉
    /// judgement 不同的那筆）。**與既有 verdict 同一配對的那一類到不了這裡**：D60 在改名前對目的鍵上既有的 verdict 具名拒絕、零寫入，
    /// 所以這個清單只可能來自被改寫的那一批彼此之間（R22 verify 第 8 列：R22 的 doc 仍寫「與既有 verdict 同一配對」）。
    ///
    /// 形狀與 merge 側的 `ResolveReport.verdictsCollapsed` 同（`<kind>「<持有記錄 key>」：<field> <遷移前的原值>——丟棄 <來源>`，
    /// `describeCollapsedVerdict` 一個生產者；merge 側另有 `describeDedupedVerdict` 描述 #271 的去重，句尾不同）。**但兩條路徑執行的
    /// 不是同一條規則**（R22 verify 第 11 列）：merge 以 `verdictEqualityKey` 分組、`collapseWinner` 選一筆——同鍵而 judgement 不同的收成
    /// 一筆並回報；rename 自 D62 起只折整筆相等的，同鍵而 judgement 不同的**兩筆都留**。所以 rename 之後 store 可以持有 `appendIfAbsent`
    /// 所謂的「重複」（同 holder 同 `verdictEqualityKey` 的 ≥2 筆）——那個狀態由 `StoreHealth.duplicateVerdictRecords` 報出（D64，R23），
    /// 而下一次 merge 會把它收成一筆並列在 `verdictsCollapsed`。
    public var verdictsCollapsed: [String]

    public init(authorEdgesRewritten: [String] = [],
                verdictValuesRewritten: [HolderRecord] = [],
                divergencesRewritten: [String] = [],
                verdictsCollapsed: [String] = [],
                quarantinedNotScanned: [String] = []) {
        self.authorEdgesRewritten = authorEdgesRewritten
        self.verdictValuesRewritten = verdictValuesRewritten
        self.divergencesRewritten = divergencesRewritten
        self.verdictsCollapsed = verdictsCollapsed
        self.quarantinedNotScanned = quarantinedNotScanned
    }
}

public struct RenameReport: Equatable {
    /// relations 有引用被改寫的 citekeys。
    ///
    /// **只有 citekey。** 歧異候選的遷移另計於 `divergenceCandidatesRewritten`——
    /// 把 UUID 混進來會讓庫外呼叫端拿它當 citekey 去查 entry 而查不到（#71 R2 DA）。
    public var relationsRewritten: [String]
    /// 候選有跟著改名的歧異記錄 id（#71）。
    public var divergenceCandidatesRewritten: [String]
    /// verdict reference 的 value 有跟著改名的**持有記錄（person、venue 或 organization）**
    /// （#232 verify NEW-1；#460 起 venue；#463 起 organization）。#498 起帶 kind——
    /// 同名跨型別時扁平 key 清單無從分辨，那是該 issue 的 follow-up 現在落地。
    public var verdictValuesRewritten: [HolderRecord]
    /// 被改寫的 verdict 之間完全相同（含 judgement 與 rests-on）的重複被折成一筆時，被丟的那些列（#495；判準自 R22 D62 起是整筆相等，
    /// 與既有 verdict 同一配對的那一類由 D60 在改名前拒絕、到不了這裡）。形狀與 `PersonRenameReport.verdictsCollapsed` 及 merge 側的
    /// `ResolveReport.verdictsCollapsed` 同——見前者的 doc（含它與 merge 折疊規則的差異）。
    public var verdictsCollapsed: [String]
    /// 這次改名沒有掃描到的 quarantine 檔（#497）——理由見 `PersonRenameReport.quarantinedNotScanned`。
    public var quarantinedNotScanned: [String]

    public init(relationsRewritten: [String] = [],
                divergenceCandidatesRewritten: [String] = [],
                verdictValuesRewritten: [HolderRecord] = [],
                verdictsCollapsed: [String] = [],
                quarantinedNotScanned: [String] = []) {
        self.relationsRewritten = relationsRewritten
        self.divergenceCandidatesRewritten = divergenceCandidatesRewritten
        self.verdictValuesRewritten = verdictValuesRewritten
        self.verdictsCollapsed = verdictsCollapsed
        self.quarantinedNotScanned = quarantinedNotScanned
    }
}

extension LibraryStore {
    /// 改寫前的一致性 gate（#35 verify）。
    ///
    /// **雙佈局並存時同一筆會被讀兩次**（半途遷移、還原的備份、git merge）。在那種狀態
    /// 下做改寫是危險的：`renameEntry` 的刪除路徑只按 **store format** 推算位置，所以它
    /// 會刪掉其中一份而留下另一份——留下的那份還是舊 citekey。
    ///
    /// 讀取面（`load` / `validate` / `doctor`）**刻意不擋**：診斷工具在這種狀態下正是最該
    ///說話的時候。擋的是**寫入面**。
    func assertNoCrossRecordErrors(_ load: LibraryLoad, action: String) throws {
        let errs = load.crossRecordIssues().filter { $0.severity == .error }
        guard errs.isEmpty else {
            throw StoreIOError.inconsistentStore(action: action, issues: errs.map(\.message))
        }
    }

    /// citekey rename（#4）：驗證 → 搬檔 → 全庫 relations 遷移 → 舊檔刪除。
    ///
    /// UUID 不變（雙 ID 的 rename 承諾至此真正成立）。呼叫端負責 reindex。
    ///
    /// **中斷恢復語意（#29，明確化）**——三個階段各有不同的中斷後果：
    ///
    /// | 中斷點 | 磁碟狀態 | 恢復方式 |
    /// |---|---|---|
    /// | pre-encode 預檢失敗 | **完全未動** | 修好那筆記錄再跑一次 |
    /// | 寫新檔／遷移 relations 途中 | 新舊檔並存、部分 relations 已指向新 key | 重跑同一個 rename：目的檔已存在會擲錯，需先手動刪新檔；或改為 rename 回去 |
    /// | 刪舊檔前 | 新舊檔並存、relations 全部已遷移 | 手動刪舊檔即可（新檔是完整的） |
    ///
    /// **設計選擇：先寫後刪**。中斷時頂多多一份檔案，**永遠不丟資料**。反過來
    /// （先刪後寫）在同一個中斷點會直接失去記錄。多一份檔案由 `doctor` 的重複
    /// citekey 檢查可見（#7b 的跨記錄驗證），失去記錄則無從發現。
    ///
    /// **為什麼 relations 遷移途中不做 per-entry 續跑**（與 import 的策略相反）：
    /// import 的每一筆是獨立的，跳過一筆只損失那一筆；rename 的每一筆都是**同一個
    /// 語意動作的一部分**，跳過一筆會留下「一半指向舊 key、一半指向新 key」的
    /// 不一致，比整個中止更難修。pre-encode 預檢已經把可預期的失敗（encode canary）
    /// 移到動磁碟之前，剩下的只有磁碟層錯誤——那種情況下中止是對的。
    ///
    /// **回傳值值得看**：`RenameReport.relationsRewritten` 列出哪些記錄的 relations
    /// 被改寫。
    ///
    /// 本 attribute 在 #11 加入時是直接貼在本函式上的，#35 的 `1f9bacf` 插入
    /// `assertNoCrossRecordErrors` 時把它連同 doc comment 一起奪走（Swift 的 attribute
    /// 綁定只認「下一個宣告」，不管中間夾了幾段註解），於 #59 復原——與 `writePerson`
    /// 完全同型的機制。
    ///
    /// 復原而非順勢移除：這是**意外失去**的，不是誰決定過要拿掉。`AkashicStoreIO`
    /// 經 `AkashicKit` product 對外暴露，庫外的呼叫端不在本 repo 的稽核範圍內；
    /// 若要改成「強制呼叫端明示 `_ =`」，那是一次 API 政策變更，該自己走一次決策，
    /// 不該是修註解的副作用。
    /// quarantined 檔裡有沒有哪一份宣稱這個 citekey；有的話回傳它的相對路徑。
    ///
    /// **刻意用行級文字比對而非 decode**：這些檔案之所以在 quarantine，正是因為
    /// decode 不過或身分不符——要求它們可解析等於什麼都擋不到。`citekey` 在 store
    /// 格式裡是頂層鍵，所以錨在行首（無前導空白）既足夠也不會誤抓巢狀值。
    ///
    /// 讀檔失敗一律**當成佔用**（fail-closed）：讀不到內容時無從判斷它宣稱什麼，
    /// 而放行的代價是延遲爆炸的 citekey 重複，擋下的代價只是使用者去看一眼那個檔。
    func quarantinedFileClaiming(citekey: String, in load: LibraryLoad) -> String? {
        for q in load.quarantined {
            let url = root.appendingPathComponent(q.file)
            guard let text = try? readUTF8(url) else { return q.file }   // fail-closed
            for line in Self.rawLines(text) {   // 三種換行、BOM 剝一次（#464 verify 實測 CRLF 檔整檔一行）
                guard line.hasPrefix("citekey:") else { continue }
                let claimed = line.dropFirst("citekey:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                if claimed == citekey { return q.file }
                break                                  // 頂層 citekey 只有一行
            }
        }
        return nil
    }

    @discardableResult
    public func renameEntry(from oldKey: String, to newKey: String) throws -> RenameReport {
        // oldKey 與 newKey 對稱驗證：oldKey 之後會進 entryURL 組刪除路徑，
        // 磁碟上若有畸形 citekey（load() 已 quarantine，此處縱深防禦）絕不可放行
        guard StoreKey.isValid(oldKey) else {
            throw StoreIOError.invalidKey("citekey", oldKey)
        }
        guard StoreKey.isValid(newKey) else {
            throw StoreIOError.invalidKey("citekey", newKey)
        }
        // R22（R21 verify 第 4／20 列）：`renamePerson` 早有這道守衛而這裡沒有——自我改名會撞 D60、訊息說「目的鍵此刻不存在」，假話
        guard oldKey != newKey else {
            throw StoreIOError.invalidKey("citekey（新舊相同）", newKey)
        }
        // 目的檔不可存在——含 quarantined 檔與 case-insensitive 別名。
        // #35：format 2 的檔名是 UUID 而非 citekey，這個檢查不適用（目的檔就是來源檔）；
        // 「新 citekey 是否已被別的記錄佔用」改由下面的全庫檢查負責。
        if !usesEntitiesLayout,
           FileManager.default.fileExists(atPath: entryURL(citekey: newKey).path) {
            throw StoreIOError.invalidKey("citekey（目的檔已存在）", newKey)
        }
        let load = try store_loadForRename()
        // 動磁碟前先擋——雙佈局並存時 rename 會刪掉其中一份而留下另一份（見上）
        try assertNoCrossRecordErrors(load, action: "rename")
        guard var entry = load.entries.first(where: { $0.citekey == oldKey }) else {
            throw StoreIOError.invalidKey("citekey（來源不存在）", oldKey)
        }
        // #631：entities 佈局下 rename 原地覆寫 entities/<id>.yaml、不刪舊檔——前提是「format 2 沒有舊檔」。
        // legacy 殘留 entries/<舊ck>.yaml 違反這個前提：改名後兩個 citekey 共用同一個 UUID（#627 R2 verify 真 binary 重現）。
        // 在任何寫入之前擋（writeEntry 只查新 citekey 的 legacy 檔，查不到舊的）。
        let oldLegacy = try entryWritePlan(entry, legacyCitekey: oldKey)   // 只有 legacy 一份 → 改名時一併搬移；兩份 → 拒絕
        // #35：檔名不再是 citekey，所以「新 citekey 沒被佔用」不再由檔案系統天然保證。
        // 沒有這個檢查，format 2 會安靜地產生兩筆同 citekey 的記錄。
        if usesEntitiesLayout,
           load.entries.contains(where: { $0.citekey == newKey && $0.id != entry.id }) {
            throw StoreIOError.invalidKey("citekey（已被其他記錄使用）", newKey)
        }
        // #61：**quarantined 檔也佔用 citekey**。legacy 靠 `fileExists` 天然擋下
        // （檔名就是 citekey，能不能解析都擋）；entities 的替代守衛只掃 `load.entries`，
        // 而被 quarantine 的檔在 `load.quarantined` —— 於是這一半保護在遷移時掉了。
        //
        // 後果不是當下壞掉而是**延遲爆炸**：store 裡同時存在一份宣稱該 citekey 的隔離檔
        // 與一筆剛改名成該 citekey 的合法記錄；直到有人修好隔離檔，`crossRecordIssues()`
        // 才突然冒出「citekey 重複」。錯誤出現的時間與成因相隔任意長。
        if usesEntitiesLayout, let occupied = quarantinedFileClaiming(citekey: newKey, in: load) {
            throw StoreIOError.invalidKey(
                "citekey（已被 quarantined 檔「\(displaySafeInvisible(occupied, max: 200))」佔用——修好或移走該檔後再改名）", newKey)
        }

        // 1. 寫新檔（先寫後刪，中斷時頂多多一份檔案，不丟資料）。
        //    exclusive-create：檢查後才出現的並發目的檔會在此擲錯，不被靜默覆蓋。
        //    自身 relations 的 self-reference 也在此一併遷移。
        entry.citekey = newKey
        entry.akashic.relations.cites =
            entry.akashic.relations.cites.map { $0 == oldKey ? newKey : $0 }
        entry.akashic.relations.related =
            entry.akashic.relations.related.map { $0 == oldKey ? newKey : $0 }
        // 2. 全庫 relations 遷移對象（cites/related 引用舊 citekey → 新，
        //    同一陣列的所有出現全部替換；UUID 引用不動）
        var toRewrite: [Entry] = []
        for var other in load.entries where other.citekey != oldKey {
            let cites = other.akashic.relations.cites.map { $0 == oldKey ? newKey : $0 }
            let related = other.akashic.relations.related.map { $0 == oldKey ? newKey : $0 }
            if cites != other.akashic.relations.cites
                || related != other.akashic.relations.related {
                other.akashic.relations.cites = cites
                other.akashic.relations.related = related
                toRewrite.append(other)
            }
        }
        // R6（M9）：encode 自 v1.3 起可 throw（canary fail-closed）。動磁碟前先
        // 對所有要寫的 entry 做 encode 預檢——任何一筆不可寫就整個 rename 不動，
        // 避免中途 throw 留下 relations 半遷移的多檔撕裂。
        // 歧異記錄的候選也是對 citekey 的參照（#71）。不遷移的話，rename 之後那筆
        // 歧異的候選指向一個不存在的 citekey——`resolve-divergence` 只會擲
        // 「找不到對應記錄」，於是它永遠無法被消歧，而 rename 什麼都沒說。
        var divergencesToRewrite: [Divergence] = []
        for var d in load.divergences {
            // `judgement.prefers` 也是對候選 key 的參照（#395 發現的缺口）。
            //
            // 先前只遷 `candidates`，於是一筆「候選沒動、只有 prefers 指著舊 citekey」
            // 的歧異會被下面的 guard 整個跳過——而漏掉的後果是安靜的：
            // `resolve-divergence` 用 `prefers != survivor` 擋下不一致，`prefers` 指著
            // 一個已不存在的 key 時，**任何** survivor 都不等於它，那筆歧異永遠消不掉，
            // 而 rename 什麼都沒說。與本函式下方 verdict value 那段（#232 NEW-1）同型。
            var prefersChanged = false
            if var j = d.judgement, j.prefers == oldKey,
               d.candidates.contains(where: { $0.shape == .work && $0.key == oldKey }) {
                j.prefers = newKey
                d.judgement = j
                prefersChanged = true
            }
            let migrated = d.candidates.map { c in
                (c.shape == .work && c.key == oldKey)
                    ? DivergenceCandidate(key: newKey, shape: c.shape) : c
            }
            guard migrated != d.candidates || prefersChanged else { continue }
            guard migrated != d.candidates else {
                divergencesToRewrite.append(d)          // 只有 prefers 變
                continue
            }
            // 遷移後若兩個候選變成同一個，那筆歧異已被 rename 回答掉，但 rename 不是
            // 消歧——它沒有合併語意、也不該替使用者刪記錄。拒絕並要求先消歧。
            var seen = Set<String>()
            let distinct = migrated.filter { seen.insert("\($0.shape.rawValue)\u{0}\($0.key)").inserted }
            guard distinct.count >= 2 else {
                throw StoreIOError.inconsistentStore(
                    action: "rename",
                    issues: ["歧異記錄 \(d.id.uuidString) 的候選會因這次改名塌縮成一個"
                           + "——rename 沒有合併語意，不會替你刪記錄。能走到這裡代表新 citekey"
                           + "是該記錄的一個懸空候選（它指向的記錄不存在），所以消歧也做不到。"
                           + "請直接編輯 entities/\(d.id.uuidString).yaml：刪掉那個懸空候選，"
                           + "或整筆刪掉這則歧異記錄，再重跑 rename"])
            }
            d.candidates = migrated
            divergencesToRewrite.append(d)
        }

        // D60／D63：目的鍵上已有 verdict（含 quarantined 檔的位元組比對）→ 具名拒絕、零寫入（理由見 `assertNoVerdictAlreadyAt`）。在動任何記錄之前。
        try assertNoVerdictAlreadyAt(newKey, holderKind: .work, in: load, action: "rename")

        // #232 verify NEW-1：verdict reference 的 value 內嵌 citekey（`work:<citekey>
        // :: <literal>`，掛在被判定的 person 上）——rename 不遷移的話，一次否決會
        // 安靜變回待判：否決不再抑制、沉底列消失、同一配對同時計入 rejected 與
        // pending。這打破 #232 自己的「Rejection SHALL be distinct from absence」。
        // 文法解析與 store 閘同源（`VerdictPairingValue`），不另寫第二份。
        var collapsedVerdicts: [String] = []
        var peopleToRewrite: [Person] = []
        for var p in load.people {
            if let m = Self.migratedVerdicts(p.references, from: oldKey, to: newKey, holderKind: .work) {
                p.references = m.refs; peopleToRewrite.append(p)
                collapsedVerdicts.append(contentsOf: m.collapsed.map { "person「\(p.key)」：\($0)" })   // display-safe-exempt: report 是資料面，消毒在 sink（CLI displaySafeInvisible(max: 1_000)、App displaySafeInvisible(max: 1_000)）；在這裡先消毒會被 sink 二次逃脫——displaySafe 不冪等
            }
        }
        // venue 同型（#460）：#304 之後 venue 也持 `work:` holder 的 verdict
        // （resolve-venues 的 confirmed／rejected 落被判定的 venue 記錄，
        // `entity-backlink-completeness` 第 13 條邊）——#232 修本迴圈時它尚不存在，
        // 漏掉的後果與 person 側完全同構：rejected stale ⇒ 否決安靜變回待判。
        var venuesToRewrite: [Venue] = []
        for var vn in load.venues {
            if let m = Self.migratedVerdicts(vn.references, from: oldKey, to: newKey, holderKind: .work) {
                vn.references = m.refs; venuesToRewrite.append(vn)
                collapsedVerdicts.append(contentsOf: m.collapsed.map { "venue「\(vn.key)」：\($0)" })   // display-safe-exempt: report 是資料面，消毒在 sink（CLI displaySafeInvisible(max: 1_000)、App displaySafeInvisible(max: 1_000)）；在這裡先消毒會被 sink 二次逃脫——displaySafe 不冪等
            }
        }
        // organization 同型（#463，網格的 rename×org 格）：#443／OrgResolver 在 organization 記錄上落
        // `work:` holder 的 verdict（live store 9 條）。#460 補 venue 迴圈時漏了它——一次合法的 rename
        // 就會留下死 verdict（#464 verify 實測兩次 rename 得 4 條）。機制完全鏡射上方 venue 迴圈。
        var orgsToRewrite: [Organization] = []
        for var org in load.organizations {
            if let m = Self.migratedVerdicts(org.references, from: oldKey, to: newKey, holderKind: .work) {
                org.references = m.refs; orgsToRewrite.append(org)
                collapsedVerdicts.append(contentsOf: m.collapsed.map { "organization「\(org.key)」：\($0)" })   // display-safe-exempt: report 是資料面，消毒在 sink（CLI displaySafeInvisible(max: 1_000)、App displaySafeInvisible(max: 1_000)）；在這裡先消毒會被 sink 二次逃脫——displaySafe 不冪等
            }
        }

        _ = try EntryYAML.encode(entry)
        for other in toRewrite { _ = try EntryYAML.encode(other) }
        // #631：每一筆要寫的記錄在第一次寫入之前過同一道目的檔／legacy 檢查——寫到一半才撞上拒絕會把 store 撕成一半
        // （#631 R1 verify：rename 已改寫本筆、其他 work 的 relation 仍指舊 citekey）
        for other in toRewrite { _ = try entryWritePlan(other) }
        for p in peopleToRewrite { _ = try personWritePlan(p) }
        for vn in venuesToRewrite { try assertEntitiesDestination(id: vn.id, kind: .venue) }
        for o in orgsToRewrite { try assertEntitiesDestination(id: o.id, kind: .organization) }
        // **完整鏡射寫入端的前置條件**，不只 encode。只鏡射一半就是 R2 DA 實測到的
        // 撕裂：entry 全部寫完之後才在 writeDivergence 擲錯，磁碟上 rename 已完成、
        // 呼叫端卻收到錯誤、索引永遠不重建。
        for d in divergencesToRewrite {
            try assertDivergenceWritable(d)
            _ = try DivergenceYAML.encode(d)
        }
        // 三腿的寫入閘與各自的寫入端**同一個函式**——person 腿是 DA-3 補的（#232 起只 encode、不跑 format 閘）。
        // format 只在真的有 gated 記錄要驗時才讀、讀一次共用（#463 verify Codex R3 N3：無條件讀會讓一個
        // 壞掉的 store.yaml 擋住完全不需要 format 閘的 rename——R2 對 writeOrganization 修過的同一件事，換個位置）。
        // 後置條件（#488）：遷移完的**整份**快照裡不得再有指向舊鍵的 verdict。
        // 在寫入之前算，所以失敗零寫入。未被任一迴圈改到的記錄用原值——那正是要驗的：
        // 「沒被改到」必須是因為它本來就沒有指向舊鍵，不是因為某一腿不存在。
        do {
            let mp = Dictionary(peopleToRewrite.map { ($0.key, $0) }, uniquingKeysWith: { _, b in b })
            let mv = Dictionary(venuesToRewrite.map { ($0.key, $0) }, uniquingKeysWith: { _, b in b })
            let mo = Dictionary(orgsToRewrite.map { ($0.key, $0) }, uniquingKeysWith: { _, b in b })
            var post: [(kind: String, key: String, refs: [ProvenanceReference])] = []
            post += load.people.map { ("person", $0.key, (mp[$0.key] ?? $0).references) }
            post += load.venues.map { ("venue", $0.key, (mv[$0.key] ?? $0).references) }
            post += load.organizations.map { ("organization", $0.key, (mo[$0.key] ?? $0).references) }
            try Self.assertNoVerdictLeftBehind(
                Self.verdictsStillPointingAt(oldKey, holderKind: .work, in: post),
                oldKey: oldKey, action: "rename")
        }
        let gateFormat = lazyStoreFormat()
        for p in peopleToRewrite {
            try Self.assertPersonWritable(p, format: gateFormat)
            _ = try PersonYAML.encode(p)
        }
        for vn in venuesToRewrite {
            try Self.assertVenueWritable(vn, format: try gateFormat())
            _ = try VenueYAML.encode(vn)
        }
        // organization 的寫入前置條件與 `writeOrganization` **同一個函式**（含 format 閘：識別碼 ≥13、ended ≥6、
        // attested ≥7、verdict ≥8）——只鏡射一半就是 #35 R2 DA 實測過的撕裂（Codex R1 在本張再抓一次）。
        for o in orgsToRewrite {
            try Self.assertOrganizationWritable(o, format: gateFormat)
            _ = try OrganizationYAML.encode(o)
        }
        // 3. 寫記錄本身。
        //
        // **#35：format 2 下 rename 不搬檔案。** 檔名是 UUID，而 rename 不改 UUID——
        // 改的是 citekey 這個「稱呼」。所以目的檔就是來源檔，原地覆寫即可；用
        // exclusive-create 反而會撞上「目的檔已存在」（那是它自己）。
        //
        // 這是 entities 佈局最直接的好處：**改稱呼不再是一次多檔搬移**，
        // 也就沒有「新舊並存」這個中斷態要處理（見本函式開頭的表格）。
        if usesEntitiesLayout {
            try writeEntry(entry)
            // #631：只有舊 citekey 的 legacy 一份 → 改名同時完成搬移（writeEntry 只查新 citekey 的 legacy 檔）
            if let oldLegacy { try FileManager.default.removeItem(at: oldLegacy) }
        } else {
            try writeEntryExclusive(entry)
        }
        var rewritten: [String] = []
        var divergenceIDs: [String] = []
        for other in toRewrite {
            try writeEntry(other)
            rewritten.append(other.citekey)
        }
        for d in divergencesToRewrite {
            try writeDivergence(d)
            divergenceIDs.append(d.id.uuidString)
        }
        var verdictKeys: [HolderRecord] = []
        for p in peopleToRewrite {
            try writePerson(p)
            verdictKeys.append(HolderRecord(.person, p.key))
        }
        for vn in venuesToRewrite {
            _ = try writeVenue(vn)
            verdictKeys.append(HolderRecord(.venue, vn.key))
        }
        for o in orgsToRewrite {
            _ = try writeOrganization(o)
            verdictKeys.append(HolderRecord(.organization, o.key))
        }
        // 4. 刪舊檔（僅 legacy 佈局——format 2 沒有舊檔，見上）
        if !usesEntitiesLayout {
            try FileManager.default.removeItem(at: entryURL(citekey: oldKey))
        }
        return RenameReport(relationsRewritten: rewritten.sorted(),
                            divergenceCandidatesRewritten: divergenceIDs.sorted(),
                            verdictValuesRewritten: verdictKeys.sorted(),
                            verdictsCollapsed: collapsedVerdicts.sorted(),
                            quarantinedNotScanned: load.quarantined.map(\.file).sorted())
    }


    // MARK: - person key 改名（#395）

    /// person key 改名：搬 key + 全庫參照遷移（UUID 不變）。
    ///
    /// **不是「照抄 `renameEntry`」。** 兩者的參照集合不同，各自窮舉——
    /// `entity-backlink-completeness` 的封閉列舉表是那份窮舉的來源：
    ///
    /// | 參照面 | citekey（`renameEntry`）| person key（本函式）|
    /// |---|---|---|
    /// | 主體 | `Entry.citekey` | `Person.key` |
    /// | 作品側邊 | `relations.cites`／`related` | **`Entry.authors[].key`**（第 1 條）|
    /// | verdict value | `work:<citekey>` | **`person:<key>`**（第 13 條，holder kind 不同）|
    /// | verdict 掛在哪 | person 的 `references` | **person 與 organization 兩處** |
    /// | divergence | `candidates[].key`（shape `.work`）| `candidates[].key`（shape `.person`）|
    /// | divergence 判斷 | `judgement.prefers` | `judgement.prefers` |
    ///
    /// **`prefers` 是 `renameEntry` 漏掉的一格**（本函式一併補上它那半，見
    /// `migratePrefers`）——漏掉的後果是安靜的：`resolve-divergence` 會拿
    /// `prefers != survivor` 去擋，而 `prefers` 指著一個已不存在的 key 時，
    /// **任何** survivor 都不等於它，於是那筆歧異永遠消不掉。
    ///
    /// **`person:` verdict 目前零實例**（實測 1296 筆 verdict 全是 `work:`），但
    /// `resolve-organizations` 的程式路徑會產生它。依 `zero-instance-guards` 第 1 列
    /// （失敗不可見）處理：不處理就是 #232 verify NEW-1 那個「否決安靜變回待判」的同型。
    @discardableResult
    public func renamePerson(from oldKey: String, to newKey: String) throws -> PersonRenameReport {
        guard StoreKey.isValid(oldKey) else { throw StoreIOError.invalidKey("person key", oldKey) }
        guard StoreKey.isValid(newKey) else { throw StoreIOError.invalidKey("person key", newKey) }
        guard oldKey != newKey else {
            throw StoreIOError.invalidKey("person key（新舊相同）", newKey)
        }
        // legacy 佈局的 person 檔名就是 key，改名要搬檔——那條路徑沒有測試覆蓋，
        // 而 format 12 的 store 一律是 entities 佈局。**拒絕並指路**，不假裝支援。
        guard usesEntitiesLayout else {
            throw StoreIOError.inconsistentStore(
                action: "rename-person",
                issues: ["legacy 佈局（people/<key>.yaml）不支援 person key 改名——"
                       + "先跑 akashic migrate 遷到 entities 佈局再改名"])
        }
        let load = try store_loadForRename()
        try assertNoCrossRecordErrors(load, action: "rename-person")

        guard var person = load.people.first(where: { $0.key == oldKey }) else {
            throw StoreIOError.invalidKey("person key（來源不存在）", oldKey)
        }
        if load.people.contains(where: { $0.key == newKey && $0.id != person.id }) {
            throw StoreIOError.invalidKey("person key（已被其他記錄使用）", newKey)
        }
        // person 與 organization 的 key **可以合法同名**（#166），所以佔用檢查
        // 只看 people——不看 organizations。
        if let occupied = quarantinedFileClaiming(personKey: newKey, in: load) {
            throw StoreIOError.invalidKey(
                "person key（已被 quarantined 檔「\(displaySafeInvisible(occupied, max: 200))」佔用——修好或移走該檔後再改名）",
                newKey)
        }

        // D60／D63：目的鍵上已有 verdict → 具名拒絕、零寫入——三種 holder 與 quarantined 檔（位元組比對）都掃，含被改名的那一筆自己。
        try assertNoVerdictAlreadyAt(newKey, holderKind: .person, in: load, action: "rename-person")

        // 1. 作品側的 authors 邊（封閉列舉第 1 條）
        var entriesToRewrite: [Entry] = []
        for var e in load.entries {
            let migrated = e.authors.map { a -> Author in
                if case .key(let k) = a, k == oldKey { return .key(newKey) }
                return a
            }
            guard migrated != e.authors else { continue }
            e.authors = migrated
            entriesToRewrite.append(e)
        }

        // 2. verdict value 的 `person:<key>`（第 13 條）——**person 與 organization 兩處**
        var collapsedVerdicts: [String] = []
        var peopleToRewrite: [Person] = []
        for var p in load.people where p.key != oldKey {
            if let m = Self.migratedVerdicts(p.references, from: oldKey, to: newKey, holderKind: .person) {
                p.references = m.refs
                peopleToRewrite.append(p)
                collapsedVerdicts.append(contentsOf: m.collapsed.map { "person「\(p.key)」：\($0)" })   // display-safe-exempt: report 是資料面，消毒在 sink（CLI displaySafeInvisible(max: 1_000)、App displaySafeInvisible(max: 1_000)）；在這裡先消毒會被 sink 二次逃脫——displaySafe 不冪等
            }
        }
        var orgsToRewrite: [Organization] = []
        for var o in load.organizations {
            if let m = Self.migratedVerdicts(o.references, from: oldKey, to: newKey, holderKind: .person) {
                o.references = m.refs
                orgsToRewrite.append(o)
                collapsedVerdicts.append(contentsOf: m.collapsed.map { "organization「\(o.key)」：\($0)" })   // display-safe-exempt: report 是資料面，消毒在 sink（CLI displaySafeInvisible(max: 1_000)、App displaySafeInvisible(max: 1_000)）；在這裡先消毒會被 sink 二次逃脫——displaySafe 不冪等
            }
        }
        // venue 同型（#463，verify security 席：venue 記錄今天只由 resolve-venues 落 `work:` holder，但寫入閘收任何
        // holderKind——「結構上不會有」對 person 記錄同樣成立而 person 迴圈仍在，同型兩格不該處置相反）
        var venuesToRewrite: [Venue] = []
        for var vn in load.venues {
            if let m = Self.migratedVerdicts(vn.references, from: oldKey, to: newKey, holderKind: .person) {
                vn.references = m.refs
                venuesToRewrite.append(vn)
                collapsedVerdicts.append(contentsOf: m.collapsed.map { "venue「\(vn.key)」：\($0)" })   // display-safe-exempt: report 是資料面，消毒在 sink（CLI displaySafeInvisible(max: 1_000)、App displaySafeInvisible(max: 1_000)）；在這裡先消毒會被 sink 二次逃脫——displaySafe 不冪等
            }
        }
        // 被改名的那一筆自己也可能持有指向自己的 verdict
        if let m = Self.migratedVerdicts(person.references, from: oldKey, to: newKey, holderKind: .person) {
            person.references = m.refs
            // 標 `newKey`：這筆記錄正在改名，寫舊鍵會讓使用者去找一個改完就不存在的 key。
            collapsedVerdicts.append(contentsOf: m.collapsed.map { "person「\(newKey)」：\($0)" })   // display-safe-exempt: report 是資料面，消毒在 sink（CLI displaySafeInvisible(max: 1_000)、App displaySafeInvisible(max: 1_000)）；在這裡先消毒會被 sink 二次逃脫——displaySafe 不冪等
        }

        // 3. divergence 的候選與 prefers（第 9、10 條）
        var divergencesToRewrite: [Divergence] = []
        for var d in load.divergences {
            var changed = false
            let migrated = d.candidates.map { c -> DivergenceCandidate in
                (c.shape == .person && c.key == oldKey)
                    ? DivergenceCandidate(key: newKey, shape: c.shape) : c
            }
            if migrated != d.candidates {
                // 與 renameEntry 同一條紀律：塌縮成一個候選時拒絕——改名沒有合併語意
                var seen = Set<String>()
                let distinct = migrated.filter {
                    seen.insert("\($0.shape.rawValue)\u{0}\($0.key)").inserted
                }
                guard distinct.count >= 2 else {
                    throw StoreIOError.inconsistentStore(
                        action: "rename-person",
                        issues: ["歧異記錄 \(d.id.uuidString) 的候選會因這次改名塌縮成一個"
                               + "——rename 沒有合併語意，不會替你刪記錄。請先消歧"
                               + "（akashic resolve-divergence），或編輯 entities/"
                               + "\(d.id.uuidString).yaml 移除懸空候選，再重跑"])
                }
                d.candidates = migrated
                changed = true
            }
            // **prefers 是 renameEntry 漏掉的那一格。** 它指向候選之一；不遷移的話
            // `resolve-divergence` 的 `prefers != survivor` 檢查會對**任何** survivor
            // 都成立，那筆歧異永遠消不掉，而改名什麼都沒說。
            if var j = d.judgement, j.prefers == oldKey {
                j.prefers = newKey
                d.judgement = j
                changed = true
            }
            if changed { divergencesToRewrite.append(d) }
        }

        // 4. 動磁碟前**完整鏡射寫入端的前置條件**（不只 encode）——只鏡射一半就是
        //    R2 DA 實測到的撕裂：前面寫完了才在後面擲錯，磁碟半遷移而呼叫端收到錯誤。
        person.key = newKey
        // 三腿（person／organization／venue）的前置閘與各自的寫入端同一個函式（#463 verify regression F2：抽出
        // `assertOrganizationWritable` 後這裡只接了 encode——三個呼叫點只接了兩個，實測撕裂；person 腿是 DA-3 補的）。
        // 同 renameEntry：format lazy、讀一次共用（Codex R3 N3）。
        let gateFormat = lazyStoreFormat()
        do {
            let mp = Dictionary(peopleToRewrite.map { ($0.key, $0) }, uniquingKeysWith: { _, b in b })
            let mv = Dictionary(venuesToRewrite.map { ($0.key, $0) }, uniquingKeysWith: { _, b in b })
            let mo = Dictionary(orgsToRewrite.map { ($0.key, $0) }, uniquingKeysWith: { _, b in b })
            var post: [(kind: String, key: String, refs: [ProvenanceReference])] = []
            // 被改名的那一筆用手上這份（它的 references 已在上面遷移過），其餘 person 走對照表。
            post.append(("person", newKey, person.references))
            post += load.people.filter { $0.key != oldKey }.map { ("person", $0.key, (mp[$0.key] ?? $0).references) }
            post += load.venues.map { ("venue", $0.key, (mv[$0.key] ?? $0).references) }
            post += load.organizations.map { ("organization", $0.key, (mo[$0.key] ?? $0).references) }
            try Self.assertNoVerdictLeftBehind(
                Self.verdictsStillPointingAt(oldKey, holderKind: .person, in: post),
                oldKey: oldKey, action: "rename-person")
        }
        try Self.assertPersonWritable(person, format: gateFormat)
        _ = try PersonYAML.encode(person)
        for e in entriesToRewrite { _ = try EntryYAML.encode(e) }
        for p in peopleToRewrite {
            try Self.assertPersonWritable(p, format: gateFormat)
            _ = try PersonYAML.encode(p)
        }
        for o in orgsToRewrite {
            try Self.assertOrganizationWritable(o, format: gateFormat)
            _ = try OrganizationYAML.encode(o)
        }
        for vn in venuesToRewrite {
            try Self.assertVenueWritable(vn, format: try gateFormat())
            _ = try VenueYAML.encode(vn)
        }
        for d in divergencesToRewrite {
            try assertDivergenceWritable(d)
            _ = try DivergenceYAML.encode(d)
        }
        // #631：每一筆要寫的記錄在第一次寫入之前過目的檔／legacy 檢查（#631 R1 verify：rename-person 寫完 person 與
        // 第一筆 work 才撞上拒絕，留下指向不存在 person 的作者 key）。舊 key 的 legacy 單份 → 改名同時搬移
        let oldLegacy = try personWritePlan(person, legacyKey: oldKey)
        for e in entriesToRewrite { _ = try entryWritePlan(e) }
        for p in peopleToRewrite { _ = try personWritePlan(p) }
        for o in orgsToRewrite { try assertEntitiesDestination(id: o.id, kind: .organization) }
        for vn in venuesToRewrite { try assertEntitiesDestination(id: vn.id, kind: .venue) }
        for d in divergencesToRewrite { try assertEntitiesDestination(id: d.id, kind: .divergence) }

        // 5. 寫入。entities 佈局的檔名是 UUID，改 key 不搬檔（同 renameEntry 的 #35）。
        try writePerson(person)
        if let oldLegacy { try FileManager.default.removeItem(at: oldLegacy) }
        var entryKeys: [String] = []
        for e in entriesToRewrite { try writeEntry(e); entryKeys.append(e.citekey) }
        var verdictHolders: [HolderRecord] = []
        for p in peopleToRewrite { try writePerson(p); verdictHolders.append(HolderRecord(.person, p.key)) }
        for o in orgsToRewrite { try writeOrganization(o); verdictHolders.append(HolderRecord(.organization, o.key)) }
        for vn in venuesToRewrite { _ = try writeVenue(vn); verdictHolders.append(HolderRecord(.venue, vn.key)) }
        var divergenceIDs: [String] = []
        for d in divergencesToRewrite { try writeDivergence(d); divergenceIDs.append(d.id.uuidString) }

        return PersonRenameReport(authorEdgesRewritten: entryKeys.sorted(),
                                  verdictValuesRewritten: verdictHolders.sorted(),
                                  divergencesRewritten: divergenceIDs.sorted(),
                                  verdictsCollapsed: collapsedVerdicts.sorted(),
                                  quarantinedNotScanned: load.quarantined.map(\.file).sorted())
    }

    /// 後置條件：這次改名不得留下任何指向舊鍵的 verdict（#488）。
    ///
    /// 三個遷移迴圈各自正確**不蘊含**整體正確——#463 的網格就是「補了兩腿漏第三腿」漏了兩輪
    /// （#460 補 venue 時漏 organization，#464 verify 的 DA 在 live store 副本上 rename 兩次得 4 條
    /// 死 verdict，而 `rename` 印 `✓`）。逐腿的測試在**新的一腿長出來時**不會紅，因為沒有測試
    /// 知道那一腿存在；這條問的是結果而不是機制，所以新 holder 形狀第一次被走到時它就會出聲。
    ///
    /// **在寫任何東西之前跑**，所以失敗是零寫入的——與同段三個寫入閘同一條紀律（只鏡射一半
    /// 就是 #35 R2 DA 實測過的撕裂）。
    ///
    /// ## 誠實邊界：quarantined 記錄看不到
    ///
    /// 被 quarantine 的檔不在 `load` 裡，所以它持有的 verdict 既不會被遷移、也不會被這條看到。
    /// 那是「讀不到」不是「已處理」——`StoreHealth` 的死 verdict 掃描（#464）會在 quarantine
    /// 解除後報出來，而那條掃描正是本條的對照面：它掃**既成事實**，本條擋**新增**。
    static func verdictsStillPointingAt(
        _ oldKey: String, holderKind: ProvenanceReference.VerdictHolderKind,
        in records: [(kind: String, key: String, refs: [ProvenanceReference])]) -> [String] {
        var out: [String] = []
        for r in records {
            for ref in r.refs {
                guard ProvenanceReference.resolutionVerdictFields.contains(ref.field),
                      let v = ref.value,
                      let p = ProvenanceReference.VerdictPairingValue.parse(v),
                      p.holderKind == holderKind, p.holder == oldKey else { continue }
                out.append("\(r.kind)「\(displaySafeInvisible(r.key, max: 120))」的 \(ref.field)")
            }
        }
        return out
    }

    /// `verdictsStillPointingAt` 非空即擲——訊息說得出是哪幾筆，以及這代表遷移少了一腿。
    static func assertNoVerdictLeftBehind(
        _ stragglers: [String], oldKey: String, action: String) throws {
        guard stragglers.isEmpty else {
            throw StoreIOError.inconsistentStore(
                action: action,
                issues: ["改名會留下 \(stragglers.count) 條指向舊鍵「\(displaySafeInvisible(oldKey, max: 120))」的 verdict，"
                       + "它們在改名後指向一個不存在的鍵（死 verdict，#464）。"
                       + "這表示遷移少了一腿——請補上對應的 holder 迴圈，不要繞過本檢查。"]
                    + stragglers.map { "  · \($0)" })   // display-safe-exempt: $0 是 verdictsStillPointingAt 逐項 displaySafeInvisible 過的行
        }
    }

    /// **D60（R21；R20 verify 五席）**：改名之前，任一 holder 已持有配對指向**新鍵**（同 holderKind、不論 field 與拼法）的 verdict 時
    /// 具名拒絕、零寫入。目的鍵在 rename 之前不存在，所以它們是死 verdict（#464）——但「死」只說它們現在指不到東西，不說它們在講誰：
    /// R20 verify DA 第 5 列真 binary 造出的那筆，是舊 binary 的 rename 沒遷走、人對另一筆仍存在的 work 親自下的判定（帶 rests-on），正確處置是
    /// 改指而不是刪。R18 D53／R19 D55／R20 D58 三輪都在「rename 替你丟掉它」這個方向上修——R20 還漏掉「holder 只持有死 verdict」的形
    /// （四席同指 `migratedVerdicts` 第一段後的早退讓 `|| anyDead` 成為死碼），而即使修好也是無乾跑、無逆操作、無 git 閘的判定刪除。
    /// 與 merge 的 D31／D34 對齊：**rename 不做判定的刪除**（`two-kinds-of-edits`：程式編輯不得銷毀判定編輯的產物；`zero-instance-guards`
    /// 第 13 列：死 verdict 的處置是人的重新消歧）。
    ///
    /// **D61（R22；R21 verify 第 1／8／12／16／36 列）→ D63（R23）**：母體含 **quarantined 檔**——那些檔不在 `load.people`／`venues`／
    /// `organizations` 裡，R21 對它們是盲的：一個 quarantined 的 holder 持有指向新鍵的 verdict 時 rename 照過，修好那個檔之後那筆從未對這筆記錄
    /// 做過的判定生效，而且沒有任何面會報（rename 前 `validate` 會報它是死 verdict，rename 後全綠——DA 席真 binary 前後對照）。
    /// R22 的 D61 用**行級**比對 `<kind>:<newKey> ::`——needle 裡的空白正是 YAML 唯一會折行的位置：本 repo 的 emitter（Yams，libyaml 預設寬度 80）
    /// 把長 value 折在 ` :: ` 之前，live store 2026-09-16 就有 2 筆，DA 真 binary 讓一筆折行的 quarantined verdict 穿過 rename、且三處通知說
    /// 「已擋過」（R22 verify 四席同指第 1／2／3／4 列）。**D63**：改成與 merge 隔離檔閘（`DivergenceResolve` 的 `doomedKeyBytes`）同一種紀律
    /// ——讀原始位元組、不切行、不 decode，needle 是 `<kind>:<newKey>` 的位元組：kind token 是 ASCII 字母、StoreKey 是 `[a-z0-9][a-z0-9-]*`，
    /// 整段不含空白，本 repo emitter 的折行（只在空白處）打不斷它；命中的下一個位元組不得是 StoreKey 字元（`work:new2020a` 不因 `work:new2020a-2` 誤擋）、前一個不得是
    /// 識別字字元。方向與 merge 閘相同：**可能偽陽性**（那段字面出現在 note 或 judgement 裡也算，多擋一筆），**本 repo emitter 寫出的檔不會因折行偽陰性**（手改的雙引號 scalar 用 `\`＋換行續行可以在任意位置切斷 needle——R24 verify security 第 28 列，與下面的逃脫同一類已接受的限制）；
    /// 已接受的限制也相同——雙引號 `\x`／`\u` 逃脫能躲過字面比對。訊息因此只說「位元組裡出現」，不說「含指向新鍵的 verdict」。
    /// 讀不到即 fail-closed（entities 佈局下這一支到不了：更早的 `quarantinedFileClaiming` 對讀不到的檔已先以「佔用」拒絕——R22 verify DA
    /// 第 19 列；留著是 legacy 佈局與縱深防禦）。**quarantined 命中排在已解析的命中之前**：它們是唯一沒有其他面看得到的一類（`validate` 的
    /// 死 verdict 掃描依設計不掃 quarantined 記錄），R22 把它們排在最後、25 筆 organization 就把那一筆擠出上限（R22 verify DA 第 18 列）。
    ///
    /// **訊息的形**（R21 verify 第 7／9／11／15／17／24／28 列）：每筆命中拆成多行——holder／欄位／value 一行、judgement 一行、**每個 digest 自己一行**
    /// （CLI 的出口逐行截 400，digest 排在行尾會被切成半個 sha256）；至多列 `Entry.perRecordWarningCap` 筆命中、其餘一句揭露總數（D30 的形）。
    /// 出路不指 `resolve-venues --repoint`：目的鍵此刻不存在，被拒的每一筆都沒有邊可改指（第 3／10／25 列）——已解析的命中改那一行的 value
    /// 或刪掉它，quarantined 命中修好或移走那個檔。
    func assertNoVerdictAlreadyAt(
        _ newKey: String, holderKind: ProvenanceReference.VerdictHolderKind,
        in load: LibraryLoad, action: String) throws {
        // **只渲染前 `cap` 筆、其餘只計數**（R32；R31 verify 第 3 列：R31 對每一筆命中都先逃 value／judgement／digest 再 `prefix(cap)`，
        // 一次必然拒絕的 rename 對 1,352 筆 verdict 的 holder 付全部渲染成本——與同輪在 `assertNoNewViolations` 修掉的「渲染後才截」同型）。
        let cap = Entry.perRecordWarningCap   // 同一條「訊息則數要有上限」的紀律、同一個數（R22 verify 第 22 列：R22 寫死兩個 20）
        var rendered: [[String]] = []; var total = 0
        func hit(_ block: () -> [String]) { total += 1; if rendered.count < cap { rendered.append(block()) } }
        // quarantined 檔先掃、先列（D63）：位元組比對、不切行、不 decode；讀不到 fail-closed（與 quarantinedFileClaiming 同）
        let needle = Array("\(holderKind.rawValue):\(newKey)".utf8)
        for q in load.quarantined {
            let url = root.appendingPathComponent(q.file)
            guard let data = try? Data(contentsOf: url) else {
                hit { ["  · quarantined 檔「\(displaySafeInvisible(q.file, max: 300))」讀不到——無從判斷它是否持有指向新鍵的 verdict（fail-closed）"] }; continue
            }
            if Self.bytesContainKeyToken(Array(data), needle) {
                hit { ["  · quarantined 檔「\(displaySafeInvisible(q.file, max: 300))」的位元組裡出現「\(holderKind.rawValue):\(displaySafeInvisible(newKey, max: 120))」"
                       + "——未解析：可能是指向新鍵的 verdict、也可能是別的欄位（位元組比對不會被 YAML 折行擊穿，但分不出它是什麼）；修好或移走該檔後再改名"] }
            }
        }
        var records: [(kind: String, key: String, refs: [ProvenanceReference])] = []
        records += load.people.map { ("person", $0.key, $0.references) }
        records += load.venues.map { ("venue", $0.key, $0.references) }
        records += load.organizations.map { ("organization", $0.key, $0.references) }
        for r in records {
            for ref in r.refs {
                guard ProvenanceReference.resolutionVerdictFields.contains(ref.field),
                      let v = ref.value,
                      let p = ProvenanceReference.VerdictPairingValue.parse(v),
                      p.holderKind == holderKind, p.holder == newKey else { continue }
                hit {
                    var block = ["  · \(r.kind)「\(displaySafeInvisible(r.key, max: 120))」的 \(ref.field) \(displaySafeInvisible(v, max: 200))"]
                    if case .judgement(let statement, let restsOn) = ref.kind {
                        block.append("      判定「\(displaySafeInvisible(statement, max: 200))」")
                        for d in restsOn.prefix(3) { block.append("      rests-on：\(displaySafeInvisible(d, max: 80))") }
                        if restsOn.count > 3 { block.append("      rests-on 另有 \(restsOn.count - 3) 筆") }
                    }
                    return block
                }
            }
        }
        guard total == 0 else {
            var lines: [String] = ["共 \(total) 條："]
            for block in rendered { lines.append(contentsOf: block) }
            if total > cap { lines.append("  …另有 \(total - cap) 條未列（共 \(total) 條）") }
            throw StoreIOError.verdictsAlreadyAtTarget(action: action, key: displaySafeInvisible(newKey, max: 120), lines: lines)
        }
    }

    /// `needle`（`<kind>:<key>` 的 UTF-8）是否出現在 `bytes` 裡，且命中的**前一個位元組不是識別字字元、下一個不是 StoreKey 字元**
    /// （D63）：`work:new2020a` 不得因為 `work:new2020a-2`／`network:new2020a` 而命中。純位元組、不切行——這正是它不會被 YAML 折行擊穿
    /// 的理由（needle 不含空白，而 YAML 只在空白處折行）。與 `DivergenceResolve` 的 `doomedKeyBytes` 比對同一種紀律。
    static func bytesContainKeyToken(_ bytes: [UInt8], _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, bytes.count >= needle.count else { return false }
        func isKeyByte(_ b: UInt8) -> Bool { (0x61...0x7A).contains(b) || (0x30...0x39).contains(b) || b == 0x2D }   // [a-z0-9-]
        func isIdentByte(_ b: UInt8) -> Bool { isKeyByte(b) || (0x41...0x5A).contains(b) || b == 0x5F }             // ＋ [A-Z_]
        var i = 0
        while i + needle.count <= bytes.count {
            if bytes[i..<(i + needle.count)].elementsEqual(needle) {
                let before = i == 0 ? nil : bytes[i - 1]
                let after = i + needle.count < bytes.count ? bytes[i + needle.count] : nil
                if !(before.map(isIdentByte) ?? false), !(after.map(isKeyByte) ?? false) { return true }
            }
            i += 1
        }
        return false
    }

    /// rename 側 verdict holder 的遷移＋收攏；沒有任何改動時回 `nil`。`holderKind` 是 `.person`（`renamePerson`，
    /// #395 的原形）或 `.work`（`renameEntry`——#232 person／#460 venue／#463 organization 三個迴圈曾是逐字相同的
    /// 三份複本，verify security 席指出同一 commit 剛用「不漂移」證立另一個抽出，這裡沒有理由例外）。
    ///
    /// 文法解析與 store 閘同源（`VerdictPairingValue`），不另寫第二份——那正是 #232 D3 自認過的
    /// grammar-in-string 漂移。收攏**只及於這次改寫動到的鍵**（R18 D53、R19 D55；早已指向新鍵的 verdict 由 `assertNoVerdictAlreadyAt` 在改名前
    /// 拒絕，R21 D60——#232 的原語意是可解析 verdict 的全量 (field, value) dedup，R17 verify DA 第 10 列指出那讓不相干 work 的重複由 YAML 順序決定留哪個）；**被收攏的列逐筆回報、印遷移前的原值**（#495 補上——在此之前 rename 側是靜默的，
    /// #461 只修了 merge 側而 #463 把這一面擴到 organization 與 venue 使缺口同步變大）。描述由
    /// `describeCollapsedVerdict` 產生，與 merge 側**同一個函式**——同一種列的形狀，第二份描述會分岔。**但兩條路徑的折疊規則不同**
    /// （R22 verify 第 11 列）：merge 以 `verdictEqualityKey` 分組、`collapseWinner` 選一筆；rename 自 D62 起只折整筆相等的重複，同鍵而
    /// judgement 不同的兩筆都留——rename 之後 store 可以持有 `appendIfAbsent` 所謂的「重複」，由 `StoreHealth.duplicateVerdictRecords`
    /// 報出（D64）。呼叫端負責加上持有記錄的 kind 與 key——本函式只看得到 references 陣列，看不到它掛在誰身上。
    ///
    /// **非 verdict 的 reference 原樣通過、不 dedup**（#463 verify Codex R3 N2）：抽 helper 前 renameEntry 的三個迴圈
    /// 就是這樣，而 #395 的 renamePerson 版本對**每一筆** reference 做 (field, value) dedup——一次與此無關的 rename 會
    /// 靜默丟掉兩筆同 (field, value) 但不同來源（不同 `kind`）的 affiliation／識別碼 reference，且把那筆記錄算進
    /// `verdictValuesRewritten`（`lossless-intake`：丟棄必須可見）。統一到窄的那一邊：renamePerson 因此只會少收攏。
    /// value 為 nil 或文法不合的 verdict 在載入後的記錄上**到不了這裡**（三族 `validate()` 都擋，load 會 quarantine），
    /// 這條 guard 的可觀察效果在非 verdict 欄位。
    private static func migratedVerdicts(_ refs: [ProvenanceReference],
                                         from oldKey: String,
                                         to newKey: String,
                                         holderKind: ProvenanceReference.VerdictHolderKind)
        -> (refs: [ProvenanceReference], collapsed: [String])? {
        // 第一段：改寫（索引與 `refs` 對齊）
        let rewritten: [(ref: ProvenanceReference, touched: Bool, isVerdict: Bool)] = refs.map { r in
            guard ProvenanceReference.resolutionVerdictFields.contains(r.field),
                  let v = r.value,
                  let pairing = ProvenanceReference.VerdictPairingValue.parse(v) else { return (r, false, false) }
            guard pairing.holderKind == holderKind, pairing.holder == oldKey else { return (r, false, true) }
            return (ProvenanceReference(field: r.field,
                                        value: ProvenanceReference.VerdictPairingValue(holderKind: holderKind, holder: newKey,
                                                                                       literal: pairing.literal).encoded,
                                        kind: r.kind), true, true)
        }
        guard rewritten.contains(where: \.touched) else { return nil }
        // 第二段（R18 D53 → R19 D55 → R21 D60）。早已指向新鍵的 verdict **到不了這裡**——`assertNoVerdictAlreadyAt` 在改名前具名拒絕
        // （R20 D58 曾在這裡丟掉它們：四席同指第一段後的早退讓「只持有死 verdict 的 holder」原樣通過、rename 後復活，DA 另指丟掉的
        // 可能是人對另一筆記錄親自下的判定——rename 不做判定的刪除）。所以本段只處理**被改寫的**：
        //  · 全留；**完全相同**（field、value、judgement、rests-on 全等）的重複只留一筆——零資訊損失（D62，R22；R21 verify DA 第 14 列真 binary：
        //    R20／R21 以 (field, value, 拼法位元組) 折疊、不看 kind，兩筆同拼法而 judgement／rests-on 不同的被折成一筆，被丟那筆的 digest 永久消失，
        //    而 validate 事前不出聲——正是撤掉 D58 的同一句話。rename 自此不呼叫 `collapseWinner`，#468 的血統層只在 merge 跑）；
        //  · 拼法不同的都留——第 27 列的第二半只掃 venue×work，其餘六格（person／organization 持 work、三種 holder 持 person）
        //    沒有掃描面也沒有揭露面，rename 不替它判定（R19 verify requirements 第 4 列：誠實邊界，寫在 §3.5）；
        //  · 留下的每一筆待在原位置，不相干 reference 的相對順序不變（R19 verify regression 第 23 列：整組前移會重排）。
        // 重複的判準是**整筆 `ProvenanceReference` 逐位元組相同**（field、value、judgement、rests-on 的 UTF-8 位元組；`byteExactKey`，D65，R24）。
        // R23 以合成的 `Hashable` 當字典鍵——Swift `String` 的相等是 canonical equivalence，NFC 的 `Sankhyā` 與 NFD 的 `Sankhya\u{0304}`
        // 被折成一筆、其中一種拼法永久消失，而 R23 的旁註「value 相等已蘊含拼法位元組相等」正是那句假話（R23 verify Codex 第 1 列 HIGH；
        // R16 D42 在第二半掃描上修過同一個缺陷）。每筆一次組鍵、O(N)；同鍵分組不需要——位元組相同的兩筆必然同鍵。
        var firstSeen: [[[UInt8]]: Int] = [:]
        var winnerOf: [Int: Int] = [:]                 // 被改寫的索引 → 留下的那筆的索引（首見；位元組相同的重複之間沒有東西可選）
        for (i, item) in rewritten.enumerated() where item.touched {
            let k = item.ref.byteExactKey
            if let first = firstSeen[k] { winnerOf[i] = first } else { firstSeen[k] = i; winnerOf[i] = i }
        }
        var out: [ProvenanceReference] = []
        var collapsed: [String] = []
        for (i, item) in rewritten.enumerated() {
            guard item.touched else { out.append(item.ref); continue }
            let w = winnerOf[i]!
            if w == i { out.append(item.ref) } else { collapsed.append(Self.describeCollapsedVerdict(original: refs[i], kept: rewritten[w].ref)) }
        }
        return (out, collapsed)
    }

    /// 一次性快取的 `StoreVersion.read`：**第一次被呼叫時才讀**、之後回同一個值。rename 的 venue／organization
    /// format 閘共用一份——沒有任何 gated 記錄要驗時整個 rename 不碰 store.yaml（Codex R3 N3）。
    func lazyStoreFormat() -> () throws -> Int {
        var cached: Int?
        let root = self.root
        return {
            if let c = cached { return c }
            let f = try StoreVersion.read(root: root); cached = f; return f
        }
    }

    /// quarantined 檔裡有沒有哪一份宣稱這個 person key。
    ///
    /// 與 `quarantinedFileClaiming(citekey:)` 同一條紀律（行級文字比對而非 decode，
    /// 讀檔失敗 fail-closed），但**錨在不同的鍵**：person 記錄的頂層鍵是 `key:`。
    /// 為避免誤抓 work／organization／venue 的同名頂層鍵，額外要求該檔含
    /// `person:` 形狀標籤。
    func quarantinedFileClaiming(personKey: String, in load: LibraryLoad) -> String? {
        for q in load.quarantined {
            let url = root.appendingPathComponent(q.file)
            guard let text = try? readUTF8(url) else { return q.file }   // fail-closed
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            guard lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == "person:" })
            else { continue }
            for line in lines where line.hasPrefix("key:") {
                let claimed = line.dropFirst("key:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                if claimed == personKey { return q.file }
                break                                  // 頂層 key 只有一行
            }
        }
        return nil
    }

    /// quarantined 檔裡有沒有哪一份宣稱這個 organization key——與 `quarantinedFileClaiming(personKey:)`
    /// 同一條紀律（行級文字比對而非 decode、讀檔失敗當佔用），只換頂層標頭。#464 的死 verdict 掃描
    /// 需要它分辨「holder 的檔被 quarantine」與「沒有任何檔宣稱它」。
    func quarantinedFileClaiming(orgKey: String, in load: LibraryLoad) -> String? {
        quarantinedFileClaiming(topLevel: "organization:", key: orgKey, in: load)
    }

    /// person／organization 共用的實作：頂層標頭 ＋ 第一個 `key:` 行。
    ///
    /// 標頭要**從第 0 欄開始**（`organization:`／`person:` 在 store 格式裡是頂層鍵，錨在行首與
    /// `citekey:` 版同一條紀律）——縮排的同名鍵（巢狀值裡的 `organization:`）不算，否則一個被 quarantine
    /// 的別種檔會因為巢狀鍵而被當成宣稱者、再配上檔內第一個不相干的 `key:`（Codex R2）。
    /// **但不要求整行位元組相等**：檔首 BOM、CRLF／CR 換行、標頭後的水平空白都是合法 YAML 排版，
    /// 拒絕它們會把「檔在、被 quarantine」誤報成「沒有任何檔宣稱」（Codex R3／R4）。換行與 BOM 在
    /// `rawLines` 處理；這裡只看「第 0 欄開始、其後只剩水平空白」。
    private func quarantinedFileClaiming(topLevel marker: String, key: String, in load: LibraryLoad) -> String? {
        for q in load.quarantined {
            let url = root.appendingPathComponent(q.file)
            guard let text = try? readUTF8(url) else { return q.file }   // fail-closed
            let lines = Self.rawLines(text)   // 三種換行、BOM 剝一次（見 rawLines）
            guard lines.contains(where: { Self.isTopLevelMarkerLine($0, marker: marker) }) else { continue }
            for line in lines where line.hasPrefix("key:") {
                let claimed = line.dropFirst("key:".count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                if claimed == key { return q.file }
                break                                  // 頂層 key 只有一行
            }
        }
        return nil
    }

    /// YAML 的三種換行都是換行：`\n`、`\r\n`（Swift 把它當**一個** Character）、單獨的 `\r`（classic Mac）。
    /// 只用 `"\n"` 切，CRLF 檔整檔會是一行——#464 verify 實測；單獨 `\r` 是 Codex R4 補的。
    static func isLineBreak(_ c: Character) -> Bool { c == "\n" || c == "\r\n" || c == "\r" }

    /// 把 quarantined 檔的原文切成行：檔首 BOM 只剝**一次**（它是串流開頭的標記，不是每行的），
    /// 再以三種換行切。行級啟發式查詢（`quarantinedFileClaiming` 一族）都從這裡取行。
    static func rawLines(_ text: String) -> [Substring] {
        let body = text.hasPrefix("\u{FEFF}") ? text.dropFirst() : Substring(text)
        return body.split(omittingEmptySubsequences: false, whereSeparator: isLineBreak)
    }

    /// 一行是不是頂層標頭：從第 0 欄開始是 `marker`，其後只剩水平空白（換行已在 `rawLines` 切掉）。
    static func isTopLevelMarkerLine(_ line: Substring, marker: String) -> Bool {
        guard line.hasPrefix(marker) else { return false }
        return line.dropFirst(marker.count).allSatisfy { $0 == " " || $0 == "\t" }
    }

    private func store_loadForRename() throws -> LibraryLoad {
        try load()
    }
}

// MARK: - 跨記錄驗證（#7b）

public extension LibraryLoad {
    /// 跨記錄的一致性檢查——**單筆 `validate()` 看不到的那一層**。
    ///
    /// 每個 `Entry.validate()` / `Person.validate()` 只看自己，所以「兩筆 entry 用了
    /// 同一個 UUID」「作者的 `.key` 指向不存在的 person」這類問題**結構上不可能**在單筆
    /// 驗證中被發現。它們的後果也不是立刻可見的：重複 UUID 讓 index 的 `PRIMARY KEY`
    /// 靜默丟掉其中一筆（查詢少一筆但不報錯），懸空的 `.key` 讓 person 頁面永遠是空的。
    ///
    /// **檔名 ↔ citekey 一致性不在這裡**——`load()` 已經在讀取時 quarantine 不符的檔，
    /// 走到這裡的記錄都已對齊。
    /// 沒有指定對外名字的記錄（#81）。
    ///
    /// **這是報告，不是錯誤。** 實測 868 位 person 中 734 位（84.6%）目前只有索引系統
    /// 產生的引用形，沒有可稱呼的名字。設成 validate 錯誤會讓 store 當場無法通過驗證，
    /// 而修復需要的資訊（正確的對外名字）**無法自動取得**——那等於把一件不可自動化的
    /// 工作變成載入的前置條件。
    ///
    /// 回傳的 key 依字典序排序，讓報告在不同機器上一致。
    func recordsWithoutAuthorizedName() -> (people: [String], organizations: [String]) {
        (people: people.filter { $0.names.authorized.isEmpty }.map(\.key).sorted(),
         organizations: organizations.filter { $0.authorized.isEmpty }.map(\.key).sorted())
    }

    /// 指定的對外名字**本身就是索引系統產生的引用形**的記錄（#81 / #82）。
    ///
    /// migration 對「某書寫系統只有一個候選」的人直接採用那個候選——即使它是引用形，
    /// 因為那是我們手上唯一的名字，印它仍比印 kebab key 好。但那讓「這個人其實沒有
    /// 真正的名字」這個訊號**從缺口報告裡消失**（實測 migration 後未指定者由 734 掉到 1）。
    ///
    /// 這條把訊號找回來：缺的不是指定，是**名字本身**。
    func recordsAuthorizedOnlyByCitationForm() -> [String] {
        people.filter { p in
            !p.names.authorized.isEmpty
                && p.names.authorized.allSatisfy { NameForm.isCitationForm($0) }
        }.map(\.key).sorted()
    }

    /// 已記錄逝世、卻仍有**開放**隸屬段的記錄（#67）。
    ///
    /// 兩者只有一個是對的，而**哪一個對無法自動判斷**：可能是死於任內、隸屬的結束日
    /// 漏記；也可能是離職多年後才過世，開放段只是資料缺漏。把隸屬的結束日設成死亡日
    /// 是一個**推論**，而這裡的紀律與 `TimelineOf.overlappingPairs()` 相同——
    /// 回報而非代為裁決，判斷屬於使用端。
    ///
    /// 這**不是**錯誤：不進 quarantine、不阻擋載入。它只是一個值得有人看一眼的矛盾。
    ///
    /// 回傳的 key 依字典序排序，讓報告在不同機器上一致。
    func recordsDeceasedWithOpenAffiliation() -> [String] {
        people.filter { p in
            // 空值視同缺席（decode 已在邊界正規化；這裡是對程式內直接賦值的防禦）。
            // 判準與 `fieldsLostByMerging` 的 `check` 一致——同一個概念不該有兩套判準。
            p.died?.isEmpty == false && p.profile.affiliations.entries.contains { $0.range.isOpen }
        }.map(\.key).sorted()
    }

    /// 日期樣欄位不合 ISO 8601 前綴值域的值（#85，裁決 (c)：不驗證但報告）。
    ///
    /// **這是報告，不是錯誤**：`2004-13-99` 是歷史資料裡真實會出現的東西（民國年、
    /// 手誤、來源系統的格式），fail-closed 會讓一筆可疑值變成整檔 quarantine
    /// （#131 實測的同型災難）。報告帶原值——修復需要知道原本寫了什麼。
    ///
    /// **缺席不是異常**：`endedUnknown` 段的 `end` 缺席是合法（#63），`start` 缺席
    /// 也是——只看「在場但不合值域」（#131 F1 的同型教訓：用語意判準，不裸看 nil）。
    ///
    /// 掃描清單手寫、由測試以反射計數防腐（`PersonProfile` 新增 timeline 維度時
    /// 測試變紅提醒接線）——同 `fieldsLostByMerging` 的紀律。
    func dateFieldAnomalies() -> [(key: String, field: String, value: String)] {
        var out: [(key: String, field: String, value: String)] = []
        func check(_ v: String?, key: String, field: String) {
            guard let v, !v.isEmpty, !ISO8601Prefix.isValid(v) else { return }
            out.append((key: key, field: field, value: v))
        }
        // timeline 段走統一走訪器（#100：census 與 anomalies **一份維度清單**——
        // 各自維護就必有一份漏，#144 R1 的實測教訓）；純量欄位另列
        forEachTimelineSegment { key, _, dim, i, range in
            check(range.start, key: key, field: "\(dim)[\(i)].start")
            check(range.end, key: key, field: "\(dim)[\(i)].end")
        }
        for p in people.sorted(by: { $0.key < $1.key }) {
            check(p.died, key: p.key, field: "died")
        }
        for o in organizations.sorted(by: { $0.key < $1.key }) {
            check(o.founded, key: o.key, field: "founded")
            check(o.dissolved, key: o.key, field: "dissolved")
        }
        return out
    }

    /// 全部 timeline 維度的統一走訪器。`shape` 是 person/organization、`dim` 不帶
    /// 前綴（contacts 帶子鍵：`contacts.email`）。**維度清單只有這一份**——
    /// 反射防腐（`DateFieldReportTests`）守 PersonProfile 的維度數。
    func forEachTimelineSegment(
        _ visit: (_ key: String, _ shape: String, _ dim: String,
                  _ index: Int, _ range: DateRange) -> Void) {
        for p in people.sorted(by: { $0.key < $1.key }) {
            func scan<V>(_ t: TimelineOf<V>, _ dim: String) {
                for (i, seg) in t.entries.enumerated() {
                    visit(p.key, "person", dim, i, seg.range)
                }
            }
            scan(p.profile.affiliations, "affiliations")
            scan(p.profile.ranks, "ranks")
            scan(p.profile.administrative, "administrative")
            scan(p.profile.appointments, "appointments")
            scan(p.profile.fields, "fields")
            for (name, t) in p.profile.contacts.sorted(by: { $0.key < $1.key }) {
                scan(t, "contacts.\(name)")
            }
        }
        for o in organizations.sorted(by: { $0.key < $1.key }) {
            func scan<V>(_ t: TimelineOf<V>, _ dim: String) {
                for (i, seg) in t.entries.enumerated() {
                    visit(o.key, "organization", dim, i, seg.range)
                }
            }
            scan(o.names, "names")
            scan(o.parents, "parents")
        }
    }

    /// 逐維度的日期普查（#100）：「range 相同」經常不是「真的同時」而是
    /// 「這個維度根本沒記過時間」（實測 175 組相同 range **全部**無日期；
    /// names/fields/ranks **從來沒有**日期）。census 讓這件事可見——排序默默
    /// 製造的順序沒有現實根據時，系統要說，不是靜默 fallback。
    /// `endedUnknown` 算有時間資訊（一等的知識狀態，#63）。
    func timelineDateCensus() -> [(dimension: String, dated: Int, undated: Int)] {
        var tally: [String: (dated: Int, undated: Int)] = [:]
        forEachTimelineSegment { _, shape, dim, _, range in
            let name = "\(shape).\(dim)"
            var t = tally[name] ?? (0, 0)
            // attested（#70）算有時間資訊——它是「觀測到的時點」，與 endedUnknown
            // 同屬一等知識狀態（#150/#151 verify F1/F4：DateRange 層有 attested 就是
            // 有時點，census 不該當它沒日期而誤報「zero dates」）
            if range.start != nil || range.end != nil || range.endedUnknown
                || !range.attested.isEmpty {
                t.dated += 1
            } else {
                t.undated += 1
            }
            tally[name] = t
        }
        return tally.sorted { $0.key < $1.key }
            .map { (dimension: $0.key, dated: $0.value.dated, undated: $0.value.undated) }
    }

    /// public（#76）：MCP doctor 也要看得到跨記錄警告——「同一個 store 從兩個
    /// consumer 看到不同的事實」是 #71 第 7 條（承載必須可觀察）的直接違反。
    func crossRecordIssues() -> [ValidationIssue] {
        var out: [ValidationIssue] = []

        func duplicates<T: Hashable>(_ values: [T]) -> [T] {
            var seen = Set<T>(), dup = Set<T>()
            for v in values { if !seen.insert(v).inserted { dup.insert(v) } }
            return Array(dup)
        }

        for u in duplicates(entries.map(\.id)).sorted(by: { $0.uuidString < $1.uuidString }) {
            let keys = entries.filter { $0.id == u }.map { displaySafeInvisible($0.citekey, max: 200) }.sorted()
            out.append(ValidationIssue(
                severity: .error,
                message: "UUID \(u.uuidString) 被 \(keys.count) 筆 entry 共用（\(keys.joined(separator: ", "))）"
                       + "——index 的 PRIMARY KEY 會靜默丟掉其中一筆"))
        }
        for k in duplicates(entries.map(\.citekey)).sorted() {
            out.append(ValidationIssue(severity: .error,
                message: "citekey「\(displaySafeInvisible(k, max: 200))」重複"))
        }
        for k in duplicates(people.map(\.key)).sorted() {
            out.append(ValidationIssue(severity: .error,
                message: "person key「\(displaySafeInvisible(k, max: 200))」重複"))
        }
        for k in duplicates(libraries.map(\.key)).sorted() {
            out.append(ValidationIssue(severity: .error,
                message: "library key「\(displaySafeInvisible(k, max: 200))」重複"))
        }

        // **organization 階層的環**（#179）。先前**沒有任何地方**偵測它：載入不查、
        // 這裡不查、`validate`／`doctor` 不查、型別層當然也擋不住。環造出來會
        // **安靜存在**，直到某個沿 parents 走的消費端無限迴圈或堆疊溢位。
        //
        // **warning 而非 error**，與 `ISO8601Prefix` 的既有裁決一致：fail-closed 的
        // 內容驗證會讓一筆壞資料使整個 store 載入不了，而環是**可回溯的**（檔案都在
        // 版控裡）。`assertNoCrossRecordErrors` 鎖住寫入面對這件事太重。
        //
        // #166 已在**歸戶端**（`resolve-organizations`）擋下會閉環的候選——那是製造
        // 環最容易的路徑，防護放在製造點成本最低。但那不涵蓋手寫 YAML、批次改寫、
        // 或**從別台機器同步進來的檔案**（#23 的前提：store 內容未信任）。最後一條
        // 特別重要：環可能不是這台機器造出來的，所以「所有寫入點都擋」永遠不完整。
        //
        // 只報**每個環一次**（取環上字典序最小的 key 當代表），否則 n 個節點的環
        // 會產生 n 則說同一件事的警告。
        var parentEdges: [String: [String]] = [:]
        for org in organizations {
            parentEdges[org.key] = org.parents.entries.compactMap {
                if case let .key(p) = $0.value { return p } else { return nil }
            }
        }
        var cycleReported = Set<String>()

        /// 從 `start` 沿 parents 找一條回到 `start` 的路徑（含自環）；找不到回 nil。
        ///
        /// **持久的 `visited` 集合，不是「當前路徑」集合。** 第一版用
        /// `path.contains(node)`——那只擋**當前路徑**上的重訪，於是有分支的圖會走遍
        /// 所有**路徑**而不是所有**節點**：實測 n=40 → 0.007s、n=80 → 2.3s、
        /// **n=120 → 543s**，指數爆炸。
        ///
        /// 那是我把兩份狀態「收成一份」時**留錯了那一份**：先前同時有 `path` 陣列與
        /// `onPath` 集合，mutation 顯示拿掉 `onPath.remove(node)` 全綠——我讀成「兩份
        /// 冗餘」，但那個 survived mutation 其實揭露的是**正確且高效的版本**（不移除
        /// ＝持久 visited）。對「start 能否走回 start」這個查詢，任何能到 start 的
        /// 節點在它**唯一一次**被探索時就會發現，所以 visited 可以跨分支持久。
        ///
        /// 複雜度 O(V+E) per start。路徑用 BFS 的 predecessor 回溯，所以報出來的環
        /// 不含通往它的前綴（`a→b`、`b→c`、`c→b` 報 `b → c → b`，`a` 不在內）。
        func findCycle(from start: String) -> [String]? {
            if (parentEdges[start] ?? []).contains(start) { return [start] }
            var visited: Set<String> = [start]
            var pred: [String: String] = [:]
            var queue: [String] = []
            for c in parentEdges[start] ?? [] where visited.insert(c).inserted {
                pred[c] = start
                queue.append(c)
            }
            var head = 0
            while head < queue.count {
                let node = queue[head]; head += 1
                for next in parentEdges[node] ?? [] {
                    if next == start {
                        var chain = [node], cur = node
                        while let p = pred[cur], p != start { chain.append(p); cur = p }
                        return [start] + chain.reversed()
                    }
                    if visited.insert(next).inserted { pred[next] = node; queue.append(next) }
                }
            }
            return nil
        }

        for start in organizations.map(\.key).sorted() where !cycleReported.contains(start) {
            guard let cycle = findCycle(from: start) else { continue }
            cycleReported.formUnion(cycle)
            out.append(ValidationIssue(
                severity: .warning,
                message: "organization 階層有環：\(cycle.map { displaySafeInvisible($0, max: 200) }.joined(separator: " → "))"
                       + " → \(displaySafeInvisible(start, max: 200))"
                       + "——沿 parents 走的消費端會無限迴圈。改掉其中一條 parents 邊"))
        }

        // 重複 DOI（#79）。**warning 而非 error**：重複本身不毀資料，而且「同一篇在
        // 個人庫與群組庫各一份」是真實且合理的狀態（Zotero 匯入器的身分是
        // `(library_id, zotero_key)`，兩筆依設計就是兩個 item）。用 error 會讓
        // `assertNoCrossRecordErrors` 鎖住整個寫入面。
        //
        // **處置留給人。** 這些正是 divergence 形狀承接的東西（兩個候選、同形狀、
        // 未決的同一性），但不自動建——「線上先行 vs 出刊」算不算同一筆是編目判斷，
        // 不是資料判斷。
        //
        // DOI 依規格**大小寫不敏感**，且同一個 DOI 有多種儲存形式——
        // `https://doi.org/10.x/y`、`doi:10.x/y`、裸 `10.x/y`。只 trim+lowercase
        // 會讓「兩筆存法不同的同一個 DOI」逃掉（真實案例：同一篇 Methods in
        // Psychology 論文一筆存 URL 形式、一筆存裸 DOI）。這些前綴的剝除與小寫
        // 現在住在 `DOI.init?`，本地不再重做一份——**同一份規格的兩個副本必然分岔**。
        //
        // **讀 `canonicalDOIs` 而不是 `fields["doi"]`**（#394 verify）。曾經讀後者，
        // 而 §8 的遷移把 664 筆的 `fields.doi` 移除之後這條檢查恆為空：18 組共用 DOI
        // 的警告全滅，其中 15 組改由下面那條印成「標題與年份相同但 **DOI 不同**」
        // ——而那 15 組的 DOI 逐字相同。**一條檢查變瞎不只是少報，它讓另一條開始說謊。**
        var byDOI: [String: [String]] = [:]
        for e in entries {
            // 同一筆 work 的多個 DOI 正規化後可能相同（例：URL 形式 ＋ 裸形式），
            // 去重，否則「被 N 筆 work 共用」會把同一個 citekey 數兩次。
            for d in Set(e.canonicalDOIs.map(\.normalized)) where !d.isEmpty {
                byDOI[d, default: []].append(e.citekey)
            }
        }
        var reportedByDOI = Set<String>()
        for (doi, cites) in byDOI.sorted(by: { $0.key < $1.key }) where cites.count > 1 {
            let names = cites.sorted().map { displaySafeInvisible($0, max: 200) }
            reportedByDOI.formUnion(cites)
            out.append(ValidationIssue(
                severity: .warning,
                message: "DOI「\(displaySafeInvisible(doi, max: 200))」被 \(names.count) 筆 work 共用"
                       + "（\(names.joined(separator: ", "))）"
                       + "——通常是同一出版品的多筆記錄（不同 Zotero library、線上先行 vs 出刊、"
                       + "更正啟事），不是資料損壞；要不要視為同一筆是編目判斷，"
                       + "可用 record-divergence 記下未決的同一性"))
        }

        // 同標題同年但 **DOI 不同**——DOI 那條結構上看不到，而這是真實且大量的：
        // JSTOR DOI vs 出版商 DOI、arXiv 預印本 vs 正式版、期刊換過 DOI 規則、
        // 同一篇被 Cambridge 與 Project Euclid 各給一個。
        //
        // **已被 DOI 抓到的組不重報**——同一件事出兩則是雜訊不是訊號。
        // 年份必須相同：同名不同年（年度報告、系列作）不是重複。
        func titleKey(_ e: Entry) -> String? {
            let t = e.title.lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }.joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: "'\"“”‘’"))
            guard !t.isEmpty else { return nil }
            guard let d = e.date,
                  let r = d.range(of: "[0-9]{4}", options: .regularExpression) else { return nil }
            return "\(t)|\(d[r])"
        }
        var byTitleYear: [String: [String]] = [:]
        for e in entries {
            guard let k = titleKey(e) else { continue }
            byTitleYear[k, default: []].append(e.citekey)
        }
        for (k, cites) in byTitleYear.sorted(by: { $0.key < $1.key }) where cites.count > 1 {
            // 整組都已被 DOI 那條涵蓋 → 跳過
            if cites.allSatisfy({ reportedByDOI.contains($0) }) { continue }
            let names = cites.sorted().map { displaySafeInvisible($0, max: 200) }
            let title = String(k.split(separator: "|").dropLast().joined(separator: "|"))
            out.append(ValidationIssue(
                severity: .warning,
                message: "標題與年份相同但 DOI 不同的 \(names.count) 筆 work"
                       + "（\(names.joined(separator: ", "))）：「\(displaySafeInvisible(title, max: 120))」"
                       + "——常見成因是同一篇有多個 DOI（JSTOR vs 出版商、arXiv 預印本 vs 正式版）；"
                       + "處置同上，留給編目判斷"))
        }

        // 參照存在性。**warning 不是 error**：懸空參照讓畫面少東西，但不毀資料，
        // 而且解析中途（resolve-people 尚未 apply）本來就會有——擋下反而卡住工作流。
        let personKeys = Set(people.map(\.key))
        var danglingAuthors: [String: Set<String>] = [:]
        for e in entries {
            for a in e.authors {
                if case let .key(k) = a, !personKeys.contains(k) {
                    danglingAuthors[k, default: []].insert(e.citekey)
                }
            }
        }
        // key 本身不是合法 StoreKey 時另外說——那條邊**不可能**對應任何記錄（記錄的 key 在 load 時就驗過），
        // 是手改或舊 binary 寫的；「沒有對應的檔」會讓人去找一個不存在的檔（#579）
        func invalidNote(_ k: String) -> String {
            StoreKey.isValid(k) ? "" : "；這個 key 不是合法的 StoreKey（只能是小寫英數與連字號、英數開頭），不可能對應任何記錄——手改或舊 binary 寫的"
        }
        for (k, cites) in danglingAuthors.sorted(by: { $0.key < $1.key }) {
            out.append(ValidationIssue(severity: .warning,
                message: "作者 key「\(displaySafeInvisible(k, max: 200))」沒有對應的 people 檔"
                       + "（\(cites.count) 筆引用，如 \(displaySafeInvisible(cites.sorted().first ?? "", max: 200))\(invalidNote(k))）"))
        }

        // 團體作者與 venue 邊的懸空參照（#652、#579）。在此之前只有 person 那一半有檢查：懸空的 `.organization`
        // 作者 key 與懸空的 `venues[].key` 在 validate／doctor／App 都不出聲。warning 的理由同上。
        let orgKeys = Set(organizations.map(\.key))
        let venueKeys = Set(venues.map(\.key))
        var danglingOrgAuthors: [String: Set<String>] = [:]
        var danglingVenues: [String: Set<String>] = [:]
        for e in entries {
            for a in e.authors {
                if case let .organization(k) = a, !orgKeys.contains(k) {
                    danglingOrgAuthors[k, default: []].insert(e.citekey)
                }
            }
            for v in e.venues {
                if case let .key(k) = v, !venueKeys.contains(k) {
                    danglingVenues[k, default: []].insert(e.citekey)
                }
            }
        }
        for (k, cites) in danglingOrgAuthors.sorted(by: { $0.key < $1.key }) {
            out.append(ValidationIssue(severity: .warning,
                message: "團體作者 key「\(displaySafeInvisible(k, max: 200))」沒有對應的 organization 檔"
                       + "（\(cites.count) 筆引用，如 \(displaySafeInvisible(cites.sorted().first ?? "", max: 200))\(invalidNote(k))）"))
        }
        for (k, cites) in danglingVenues.sorted(by: { $0.key < $1.key }) {
            out.append(ValidationIssue(severity: .warning,
                message: "venue key「\(displaySafeInvisible(k, max: 200))」沒有對應的 venue 檔"
                       + "（\(cites.count) 筆引用，如 \(displaySafeInvisible(cites.sorted().first ?? "", max: 200))\(invalidNote(k))）"))
        }

        // 歧異的候選同樣要被看見（#71 R1 verify）。**warning 而非 error**，理由與
        // 上面的懸空作者相同。DA 的更正指出它的實際後果不是安全問題（候選鍵從未進過
        // 任何路徑），而是**那筆記錄永遠無法被消歧**——`resolveDivergence` 只會擲
        // `candidateMissing`，而在這條檢查之前沒有任何輸出說它壞了。
        let entityKeys: [EntityKind: Set<String>] = [
            .person: Set(people.map(\.key)),
            .work: Set(entries.map(\.citekey)),
            .organization: Set(organizations.map(\.key)),
            // 歧異記錄沒有 key（身分是 UUID），所以以它為形狀的候選永遠對不到任何
            // 東西。給它一個空集合會讓每一筆都被誤報懸空——那是雜訊不是訊號；
            // 這種候選的正確處置是 decode 就拒收（見 DivergenceYAML.decode）。
            .divergence: [],
        ]
        var danglingCandidates: [String: Int] = [:]
        for d in divergences {
            for c in d.candidates where !(entityKeys[c.shape]?.contains(c.key) ?? false) {
                danglingCandidates["\(c.shape.rawValue) 「\(displaySafeInvisible(c.key, max: 200))」",
                                   default: 0] += 1
            }
        }
        for (k, n) in danglingCandidates.sorted(by: { $0.key < $1.key }) {
            out.append(ValidationIssue(severity: .warning,
                message: "歧異候選「\(displaySafeInvisible(k, max: 200))」沒有對應的記錄（\(n) 筆歧異引用）"
                       + "——這筆歧異無法被消歧，`resolve-divergence` 會擲「找不到對應記錄」"))
        }

        let libraryKeys = Set(libraries.map(\.key))
        var danglingLibs: [String: Int] = [:]
        for e in entries {
            for l in e.akashic.libraries where !libraryKeys.contains(l) {
                danglingLibs[l, default: 0] += 1
            }
        }
        for (l, n) in danglingLibs.sorted(by: { $0.key < $1.key }) {
            out.append(ValidationIssue(severity: .warning,
                message: "akashic.libraries 的「\(displaySafeInvisible(l, max: 200))」沒有對應的 registry 檔"
                       + "（\(n) 筆引用）"))
        }
        return out
    }
}
