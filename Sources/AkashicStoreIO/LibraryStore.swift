import Foundation
import AkashicCore

public enum StoreIOError: Error, LocalizedError, Equatable {
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

    public var errorDescription: String? {
        switch self {
        case let .notAStore(path):
            return "「\(displaySafe(path, max: 300))」不是 Akashic store（無 store.yaml 也無 "
                 + "entities/／entries/）——寫入拒絕。若這是新 store，先跑 "
                 + "akashic doctor --library <path> 建立佈局；若是打錯路徑，這個拒絕正是在救你。"
        case let .invalidInput(what, why):
            return "\(displaySafe(what, max: 120)) 無效：\(displaySafe(why, max: 400))"
        case let .inconsistentStore(action, issues):
            // action 是呼叫端字面量（"rename"/"resolve-divergence"）、issues 已消毒
            return "store 有 \(issues.count) 個跨記錄不一致，\(action) 拒絕執行"   // display-safe-exempt: action 是呼叫端字面量
                 + "（改寫會刪掉其中一份而留下另一份）："
                 + issues.prefix(3).map { displaySafe($0, max: 300) }.joined(separator: "；")
                 + "。先跑 akashic doctor 看清楚並修好。"
        case .invalidKey(let kind, let value):
            // #142：value 是 caller 剛送進來的畸形 key——原始 ESC/bidi 位元組經
            // MCP error 直達 LLM context；kind 是程式字面量
            return "\(kind)「\(displaySafe(value, max: 200))」不符合 \(StoreKey.pattern)，拒絕寫入"   // display-safe-exempt: kind 是程式字面量、pattern 是常量
        
        }
    }
}

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

    @discardableResult
    public func writeEntry(_ entry: Entry) throws -> URL {
        try assertStoreRoot()
        // write-time key 驗證：不合格式的 citekey 絕不進檔名（path traversal 防護）
        guard StoreKey.isValid(entry.citekey) else {
            throw StoreIOError.invalidKey("citekey", entry.citekey)
        }
        // #394 §6：識別碼 reference 需要 format 13。
        if !entry.references.isEmpty {
            try Self.assertIdentifierReferencesWritable(
                entry.references, format: try StoreVersion.read(root: root),
                what: "work「\(displaySafe(entry.citekey, max: 120))」")
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
            let format = try StoreVersion.read(root: root)
            guard format >= 9 else {
                throw StoreIOError.invalidKey(
                    "entry（含 akashic.sources 副本引用，需要 store format ≥ 9；本 store 是 \(format)）——" +
                    "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 " +
                    "format: 改成 9", entry.citekey)
            }
        }
        // v11-only 語法的 format gate（#304）：venues ref 邊。舊 binary 對 entry 的
        // venues 鍵走 tolerant-preserve（保留不解讀）——反向查詢靜默漏資料，故仍 gate。
        if !entry.venues.isEmpty {
            let format = try StoreVersion.read(root: root)
            guard format >= 11 else {
                throw StoreIOError.invalidInput(
                    what: "entry「\(displaySafe(entry.citekey, max: 120))」",
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
            let format = try StoreVersion.read(root: root)
            guard format >= 12 else {
                throw StoreIOError.invalidInput(
                    what: "entry「\(displaySafe(entry.citekey, max: 120))」",
                    why: "含 organization 作者，需要 store format ≥ 12；本 store 是 \(format)——" +
                         "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 " +
                         "format: 改成 12（format-11 binary 讀到會整檔 quarantine，" +
                         "且 query 不會報錯）")
            }
        }
        let yaml = try EntryYAML.encode(entry)
        // #35：format 2 走 entities/<uuid>.yaml，legacy 走 entries/<citekey>.yaml
        let dest = usesEntitiesLayout ? entityURL(id: entry.id) : entryURL(citekey: entry.citekey)
        try atomicWrite(yaml, to: dest)
        return dest
    }

    /// exclusive-create 版 writeEntry：目的檔已存在（含檢查後才出現的並發寫入）
    /// 一律擲錯，絕不靜默覆蓋。rename 的目的檔寫入走這條，關掉 check-then-write
    /// 之間的 TOCTOU 覆寫視窗（moveItem 對既存目的檔是原子性拒絕）。
    @discardableResult
    public func writeEntryExclusive(_ entry: Entry) throws -> URL {
        try assertStoreRoot()
        guard StoreKey.isValid(entry.citekey) else {
            throw StoreIOError.invalidKey("citekey", entry.citekey)
        }
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
    public static func assertVenueWritable(_ v: Venue, format: Int) throws {
        guard StoreKey.isValid(v.key) else {
            throw StoreIOError.invalidKey("venue key", v.key)
        }
        // v11 形狀 gate：舊 binary 對未知頂層形狀是**整檔 quarantine**（2026-08-16
        // 實測，見 StoreVersion doc）——refuse-if-newer 必須在寫入端先 fire。
        guard format >= 11 else {
            throw StoreIOError.invalidInput(
                what: "venue「\(displaySafe(v.key, max: 120))」",
                why: "venue 是 format 11 的新形狀；本 store 是 \(format)——" +
                     "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 " +
                     "format: 改成 11（舊 binary 讀到 venue 檔會整檔 quarantine）")
        }
        // #324：format 11 只認得三值。新值域（periodical 等）要 format 12——
        // format-11 binary 的 VenueType decode 對未知值**整檔拒讀**。
        if !Self.venueTypesReadableAtFormat11.contains(v.type), format < 12 {
            throw StoreIOError.invalidInput(
                what: "venue「\(displaySafe(v.key, max: 120))」的 type「\(v.type.rawValue)」",   // display-safe-exempt: rawValue 是編譯期常量
                why: "該值是 format 12 的新值域（#324）；本 store 是 \(format)——" +
                     "把 store.yaml 的 format: 改成 12（format-11 binary 讀到未知 " +
                     "venue type 會整檔拒讀）")
        }
        try Self.assertIdentifierReferencesWritable(
            v.references, format: format, what: "venue「\(displaySafe(v.key, max: 120))」")
        // #406：兩個世代的能力**分開閘**（R2 verify NEW BUG 1——初版把兩者綁在
        // 同一條 `< 15`，於是一筆合法的 format-14 venue（有頂層 `paginated:`、無
        // reference）連 add_names 這種無關寫入都被拒，破壞舊格式的 read-modify-write）：
        //
        // - 頂層 `paginated:` 值是 **format 14** 的鍵域（format-13 binary 的
        //   `rejectUnknownKeys` 對它整檔 quarantine）。
        if format < 14, v.paginated != nil {
            throw StoreIOError.invalidInput(
                what: "venue「\(displaySafe(v.key, max: 120))」的 paginated 值",
                why: "paginated 是 format 14 的新欄位（#422／#406）；本 store 是 \(format)——" +
                     "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 " +
                     "format: 改成 14（format-13 binary 讀到會整檔 quarantine）")
        }
        // - **判定 reference**（`field: paginated`）是 **format 15** 的 vocabulary
        //   （R1 verify）：format-14 binary 的附著驗證沒有這個 case，讀到會走封閉
        //   default 擲錯 → **整檔 quarantine**（且輸出與「判定從未發生」不可分辨，
        //   實測 406 個 venue 靜默掉到 373）。service 設值時必同時建 reference，
        //   所以本分支已足以讓新判定在 format 14 上原子失敗。
        if format < 15, v.references.contains(where: { $0.field == "paginated" }) {
            throw StoreIOError.invalidInput(
                what: "venue「\(displaySafe(v.key, max: 120))」的 paginated 判定",
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
        let dest = entityURL(id: v.id)
        try atomicWrite(yaml, to: dest)
        return dest
    }

    /// 機構只存在於 entities 佈局（format 4 起）——legacy 佈局沒有它的位置。
    @discardableResult
    public func writeOrganization(_ org: Organization) throws -> URL {
        try assertStoreRoot()
        guard StoreKey.isValid(org.key) else {
            throw StoreIOError.invalidKey("organization key", org.key)
        }
        // #394 §6：識別碼 reference 需要 format 13。**這一格是硬觸發**——format-12
        // binary 讀到 `field: ror` 的 reference 會整檔 quarantine（2026-08-24 實測）。
        if !org.references.isEmpty {
            try Self.assertIdentifierReferencesWritable(
                org.references, format: try StoreVersion.read(root: root),
                what: "organization「\(displaySafe(org.key, max: 120))」")
        }
        // v6-only 語法的 format gate——理由見 writePerson（#131 verify Codex-H2）
        if org.names.entries.contains(where: \.range.endedUnknown)
            || org.parents.entries.contains(where: \.range.endedUnknown) {
            let format = try StoreVersion.read(root: root)
            guard format >= 6 else {
                throw StoreIOError.invalidKey(
                    "organization（含 ended 段，需要 store format ≥ 6；本 store 是 \(format)）——" +
                    "升級方式見 writePerson 同型訊息", org.key)
            }
        }
        // v7-only（attested，#70）——同上
        if org.names.entries.contains(where: { !$0.range.attested.isEmpty })
            || org.parents.entries.contains(where: { !$0.range.attested.isEmpty }) {
            let format = try StoreVersion.read(root: root)
            guard format >= 7 else {
                throw StoreIOError.invalidKey(
                    "organization（含 attested 段，需要 store format ≥ 7；本 store 是 \(format)）——" +
                    "升級方式見 writePerson 同型訊息", org.key)
            }
        }
        // v8-only（resolution verdict，#232）——同 writePerson 的 v8 gate
        if org.references.contains(where: {
            ProvenanceReference.resolutionVerdictFields.contains($0.field) }) {
            let format = try StoreVersion.read(root: root)
            guard format >= 8 else {
                throw StoreIOError.invalidKey(
                    "organization（含 resolution verdict reference，需要 store format ≥ 8；本 store 是 \(format)）——" +
                    "升級方式見 writePerson 同型訊息", org.key)
            }
        }
        // 同 writePerson 的閘（#229）——「哪個名字對外」是同一個問題，不該有兩套答案
        try Self.assertNoErrors(org.validate(), what: "organization", key: org.key)
        let yaml = try OrganizationYAML.encode(org)
        let dest = entityURL(id: org.id)
        try atomicWrite(yaml, to: dest)
        return dest
    }

    /// **需要 `@discardableResult`**：多數呼叫端隱式丟棄回傳的 URL——它們只在乎
    /// 「寫成功了」，不在乎寫到哪。生產碼裡有兩處：`AkashicService.addPerson`
    /// 與 CLI 的 `bootstrap-people`。
    ///
    /// 本 attribute 曾在 #55 插入 `writeOrganization` 時被誤刪（撞到 duplicate-attribute
    /// 編譯錯誤，刪錯了那一個），於 #59 復原。
    @discardableResult
    public func writePerson(_ person: Person) throws -> URL {
        try assertStoreRoot()
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
            let format = try StoreVersion.read(root: root)
            guard format >= 6 else {
                throw StoreIOError.invalidKey(
                    "person（含 ended 段，需要 store format ≥ 6；本 store 是 \(format)）——" +
                    "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 " +
                    "format: 改成 6（v6 只新增語法，既有資料不變）", person.key)
            }
        }
        // v7-only 語法的 format gate（#70，同 ended gate 的機制與理由）
        if person.profile.usesAttested {
            let format = try StoreVersion.read(root: root)
            guard format >= 7 else {
                throw StoreIOError.invalidKey(
                    "person（含 attested 段，需要 store format ≥ 7；本 store 是 \(format)）——" +
                    "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 " +
                    "format: 改成 7（v7 只新增語法，既有資料不變）", person.key)
            }
        }
        // v8-only 語法的 format gate（#232 verify NEW-2/NEW-3，同 6/7 的機制與理由）：
        // verdict 欄位對 field 白名單是 strict——舊 binary 讀到是整檔 quarantine，
        // 且 quarantine 檔可被 bootstrap 的決定性 UUID 安靜覆寫、判定史全滅。
        // 這道閘是 verdict 寫入與「第二台機器上安靜銷毀 ledger」之間唯一的東西。
        if person.references.contains(where: {
            ProvenanceReference.resolutionVerdictFields.contains($0.field) }) {
            let format = try StoreVersion.read(root: root)
            guard format >= 8 else {
                throw StoreIOError.invalidKey(
                    "person（含 resolution verdict reference，需要 store format ≥ 8；本 store 是 \(format)）——" +
                    "確認會碰這個 store 的 CLI/MCP/App 都已升級後，把 store.yaml 的 " +
                    "format: 改成 8（v8 只新增 references 欄位對，既有資料不變）", person.key)
            }
        }
        // v10-only 形狀的 format gate（#227，同 6/7/8/9 的機制與理由）：巢狀 names
        // 對 v9 binary 是 known 欄位形狀不符 → **整檔 quarantine（人檔消失）**，
        // refuse-if-newer 必須在寫入端先 fire。空 names 的記錄不受此閘——檔上沒有
        // names 鍵，兩代 binary 都讀得懂。
        if !person.names.all.isEmpty {
            let format = try StoreVersion.read(root: root)
            guard format >= 10 else {
                // #227 verify S5：用 invalidInput 不用 invalidKey——後者的框架是
                // 「不符合 key 正規式」，對合法 key 是假斷言，會把 LLM 呼叫端引去
                // 清洗 key（#133 立 invalidInput 防的正是這形；v6/7/8 舊 gate 沿用
                // 舊形屬既有債，另計）。
                throw StoreIOError.invalidInput(
                    what: "person「\(displaySafe(person.key, max: 120))」",
                    why: "含巢狀 names，需要 store format ≥ 10；本 store 是 \(format)——" +
                         "確認會碰這個 store 的 CLI/MCP/App 都已升級後，先以 " +
                         "migrate-person-identity 遷移既有記錄，再把 store.yaml 的 " +
                         "format: 改成 10（v10 改變 names 的形狀）")
            }
        }
        try Self.assertNoErrors(person.validate(), what: "person", key: person.key)
        let yaml = try PersonYAML.encode(person)
        let dest = usesEntitiesLayout ? entityURL(id: person.id) : personURL(key: person.key)
        try atomicWrite(yaml, to: dest)
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
                what: "\(what) '\(displaySafe(key, max: 120))'",
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
                    what: relativePath, why: "canonical YAML 不是 UTF-8")
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
                        what: relativePath, why: "accepted capture 缺少已列舉的 bytes")
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
                        file: name, reason: "entities/ 的檔名必須是 UUID，實得「\(stem)」"))
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
                            file: name, reason: "person key「\(person.key)」不符合 \(StoreKey.pattern)"))
                        continue
                    }
                    if !person.unknownFields.isEmpty { result.unknownFieldFiles.append(name) }
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
                            reason: "organization key「\(org.key)」不符合 \(StoreKey.pattern)"))
                        continue
                    }
                    if !org.unknownFields.isEmpty { result.unknownFieldFiles.append(name) }
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
                            reason: "venue key「\(v.key)」不符合 \(StoreKey.pattern)"))
                        continue
                    }
                    if !v.unknownFields.isEmpty { result.unknownFieldFiles.append(name) }
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
                            reason: "候選 key「\(bad.key)」不符合 \(StoreKey.pattern)"))
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
                            file: name, reason: "citekey「\(entry.citekey)」不符合 \(StoreKey.pattern)"))
                        continue
                    }
                    if let bad = entry.akashic.libraries.first(where: { !StoreKey.isValid($0) }) {
                        result.quarantined.append(QuarantinedFile(
                            file: name, reason: "akashic.libraries 含不合法 key「\(bad)」"))
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
                    reason: (error as? LocalizedError)?.errorDescription ?? String(describing: error)))
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
                        reason: "citekey「\(entry.citekey)」不符合 \(StoreKey.pattern)"))
                    continue
                }
                guard stem == entry.citekey else {
                    result.quarantined.append(QuarantinedFile(
                        file: name,
                        reason: "檔名 stem「\(stem)」與 citekey「\(entry.citekey)」不符"))
                    continue
                }
                // membership 語意驗證（#13 verify）：畸形 key 的 entry 之後任何衍生層
                // 寫入都會被 writeEntry 拒絕（看似可讀、實則鎖死）；重複 key 使計數失真
                if let bad = entry.akashic.libraries.first(where: { !StoreKey.isValid($0) }) {
                    result.quarantined.append(QuarantinedFile(
                        file: name,
                        reason: "akashic.libraries key「\(bad)」不符合 \(StoreKey.pattern)"))
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
                    reason: String(describing: error)))
            }
        }
        for path in try source.paths("people") {
            let name = path
            do {
                let person = try PersonYAML.decode(try source.text(path))
                let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                guard StoreKey.isValid(person.key) else {
                    result.quarantined.append(QuarantinedFile(
                        file: name,
                        reason: "person key「\(person.key)」不符合 \(StoreKey.pattern)"))
                    continue
                }
                guard stem == person.key else {
                    result.quarantined.append(QuarantinedFile(
                        file: name,
                        reason: "檔名 stem「\(stem)」與 person key「\(person.key)」不符"))
                    continue
                }
                if !person.unknownFields.isEmpty {
                    result.unknownFieldFiles.append(name)
                }
                result.people.append(person)
            } catch {
                result.quarantined.append(QuarantinedFile(
                    file: name,
                    reason: String(describing: error)))
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
                        reason: "library key「\(library.key)」不符合 \(StoreKey.pattern)"))
                    continue
                }
                guard stem == library.key else {
                    result.quarantined.append(QuarantinedFile(
                        file: name,
                        reason: "檔名 stem「\(stem)」與 library key「\(library.key)」不符"))
                    continue
                }
                if !library.unknownFields.isEmpty {
                    result.unknownFieldFiles.append(name)
                }
                result.libraries.append(library)
            } catch {
                result.quarantined.append(QuarantinedFile(
                    file: name,
                    reason: String(describing: error)))
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

/// person key 改名的回報（#395）。
///
/// **欄位與 `RenameReport` 不同，刻意不共用型別**——兩者的參照集合不同
/// （見 `renamePerson` 的對照表），共用一個型別會逼出「這個欄位對另一邊是什麼意思」
/// 這種答不出來的問題。
public struct PersonRenameReport: Equatable {
    /// `authors[].key` 有被改寫的 work citekeys。
    public var authorEdgesRewritten: [String]
    /// verdict value 的 `person:<key>` 有被改寫的**持有記錄** key（person 或 organization）。
    public var verdictValuesRewritten: [String]
    /// 候選或 `judgement.prefers` 有跟著改名的歧異記錄 id。
    public var divergencesRewritten: [String]

    public init(authorEdgesRewritten: [String] = [],
                verdictValuesRewritten: [String] = [],
                divergencesRewritten: [String] = []) {
        self.authorEdgesRewritten = authorEdgesRewritten
        self.verdictValuesRewritten = verdictValuesRewritten
        self.divergencesRewritten = divergencesRewritten
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
    /// verdict reference 的 value 有跟著改名的 person key（#232 verify NEW-1）。
    public var verdictValuesRewritten: [String]

    public init(relationsRewritten: [String] = [],
                divergenceCandidatesRewritten: [String] = [],
                verdictValuesRewritten: [String] = []) {
        self.relationsRewritten = relationsRewritten
        self.divergenceCandidatesRewritten = divergenceCandidatesRewritten
        self.verdictValuesRewritten = verdictValuesRewritten
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
    @discardableResult
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
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
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

    public func renameEntry(from oldKey: String, to newKey: String) throws -> RenameReport {
        // oldKey 與 newKey 對稱驗證：oldKey 之後會進 entryURL 組刪除路徑，
        // 磁碟上若有畸形 citekey（load() 已 quarantine，此處縱深防禦）絕不可放行
        guard StoreKey.isValid(oldKey) else {
            throw StoreIOError.invalidKey("citekey", oldKey)
        }
        guard StoreKey.isValid(newKey) else {
            throw StoreIOError.invalidKey("citekey", newKey)
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
                "citekey（已被 quarantined 檔「\(occupied)」佔用——修好或移走該檔後再改名）", newKey)
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

        // #232 verify NEW-1：verdict reference 的 value 內嵌 citekey（`work:<citekey>
        // :: <literal>`，掛在被判定的 person 上）——rename 不遷移的話，一次否決會
        // 安靜變回待判：否決不再抑制、沉底列消失、同一配對同時計入 rejected 與
        // pending。這打破 #232 自己的「Rejection SHALL be distinct from absence」。
        // 文法解析與 store 閘同源（`VerdictPairingValue`），不另寫第二份。
        var peopleToRewrite: [Person] = []
        for var p in load.people {
            var changed = false
            var migrated: [ProvenanceReference] = []
            var seenVerdicts = Set<String>()
            for r in p.references {
                guard ProvenanceReference.resolutionVerdictFields.contains(r.field),
                      let v = r.value,
                      let pairing = ProvenanceReference.VerdictPairingValue.parse(v) else {
                    migrated.append(r)
                    continue
                }
                var out = r
                if pairing.holderKind == .work, pairing.holder == oldKey {
                    out = ProvenanceReference(
                        field: r.field,
                        value: ProvenanceReference.VerdictPairingValue(
                            holderKind: .work, holder: newKey,
                            literal: pairing.literal).encoded,
                        kind: r.kind)
                    changed = true
                }
                // 遷移後與既有 verdict 同 (field, value) → 收攏成一筆（寫入邊界
                // 冪等的鏡射——store 永不持有重複 verdict）
                guard seenVerdicts.insert("\(out.field)\u{0}\(out.value ?? "")").inserted else {
                    changed = true
                    continue
                }
                migrated.append(out)
            }
            if changed { p.references = migrated; peopleToRewrite.append(p) }
        }

        _ = try EntryYAML.encode(entry)
        for other in toRewrite { _ = try EntryYAML.encode(other) }
        // **完整鏡射寫入端的前置條件**，不只 encode。只鏡射一半就是 R2 DA 實測到的
        // 撕裂：entry 全部寫完之後才在 writeDivergence 擲錯，磁碟上 rename 已完成、
        // 呼叫端卻收到錯誤、索引永遠不重建。
        for d in divergencesToRewrite {
            try assertDivergenceWritable(d)
            _ = try DivergenceYAML.encode(d)
        }
        for p in peopleToRewrite { _ = try PersonYAML.encode(p) }
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
        var verdictKeys: [String] = []
        for p in peopleToRewrite {
            try writePerson(p)
            verdictKeys.append(p.key)
        }
        // 4. 刪舊檔（僅 legacy 佈局——format 2 沒有舊檔，見上）
        if !usesEntitiesLayout {
            try FileManager.default.removeItem(at: entryURL(citekey: oldKey))
        }
        return RenameReport(relationsRewritten: rewritten.sorted(),
                            divergenceCandidatesRewritten: divergenceIDs.sorted(),
                            verdictValuesRewritten: verdictKeys.sorted())
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
                "person key（已被 quarantined 檔「\(occupied)」佔用——修好或移走該檔後再改名）",
                newKey)
        }

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
        var peopleToRewrite: [Person] = []
        for var p in load.people where p.key != oldKey {
            if let migrated = Self.migratedVerdicts(p.references, from: oldKey, to: newKey) {
                p.references = migrated
                peopleToRewrite.append(p)
            }
        }
        var orgsToRewrite: [Organization] = []
        for var o in load.organizations {
            if let migrated = Self.migratedVerdicts(o.references, from: oldKey, to: newKey) {
                o.references = migrated
                orgsToRewrite.append(o)
            }
        }
        // 被改名的那一筆自己也可能持有指向自己的 verdict
        if let migrated = Self.migratedVerdicts(person.references, from: oldKey, to: newKey) {
            person.references = migrated
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
        _ = try PersonYAML.encode(person)
        for e in entriesToRewrite { _ = try EntryYAML.encode(e) }
        for p in peopleToRewrite { _ = try PersonYAML.encode(p) }
        for o in orgsToRewrite { _ = try OrganizationYAML.encode(o) }
        for d in divergencesToRewrite {
            try assertDivergenceWritable(d)
            _ = try DivergenceYAML.encode(d)
        }

        // 5. 寫入。entities 佈局的檔名是 UUID，改 key 不搬檔（同 renameEntry 的 #35）。
        try writePerson(person)
        var entryKeys: [String] = []
        for e in entriesToRewrite { try writeEntry(e); entryKeys.append(e.citekey) }
        var verdictHolders: [String] = []
        for p in peopleToRewrite { try writePerson(p); verdictHolders.append(p.key) }
        for o in orgsToRewrite { try writeOrganization(o); verdictHolders.append(o.key) }
        var divergenceIDs: [String] = []
        for d in divergencesToRewrite { try writeDivergence(d); divergenceIDs.append(d.id.uuidString) }

        return PersonRenameReport(authorEdgesRewritten: entryKeys.sorted(),
                                  verdictValuesRewritten: verdictHolders.sorted(),
                                  divergencesRewritten: divergenceIDs.sorted())
    }

    /// verdict reference 的 `person:<key>` 遷移；沒有任何改動時回 `nil`。
    ///
    /// 文法解析與 store 閘同源（`VerdictPairingValue`），不另寫第二份——
    /// 那正是 #232 D3 自認過的 grammar-in-string 漂移。
    private static func migratedVerdicts(_ refs: [ProvenanceReference],
                                         from oldKey: String,
                                         to newKey: String) -> [ProvenanceReference]? {
        var changed = false
        var out: [ProvenanceReference] = []
        var seen = Set<String>()
        for r in refs {
            var kept = r
            if ProvenanceReference.resolutionVerdictFields.contains(r.field),
               let v = r.value,
               let pairing = ProvenanceReference.VerdictPairingValue.parse(v),
               pairing.holderKind == .person, pairing.holder == oldKey {
                kept = ProvenanceReference(
                    field: r.field,
                    value: ProvenanceReference.VerdictPairingValue(
                        holderKind: .person, holder: newKey,
                        literal: pairing.literal).encoded,
                    kind: r.kind)
                changed = true
            }
            // 遷移後與既有 verdict 同 (field, value) → 收攏（store 永不持有重複 verdict）
            guard seen.insert("\(kept.field)\u{0}\(kept.value ?? "")").inserted else {
                changed = true
                continue
            }
            out.append(kept)
        }
        return changed ? out : nil
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
            let keys = entries.filter { $0.id == u }.map { displaySafe($0.citekey, max: 200) }.sorted()
            out.append(ValidationIssue(
                severity: .error,
                message: "UUID \(u.uuidString) 被 \(keys.count) 筆 entry 共用（\(keys.joined(separator: ", "))）"
                       + "——index 的 PRIMARY KEY 會靜默丟掉其中一筆"))
        }
        for k in duplicates(entries.map(\.citekey)).sorted() {
            out.append(ValidationIssue(severity: .error,
                message: "citekey「\(displaySafe(k, max: 200))」重複"))
        }
        for k in duplicates(people.map(\.key)).sorted() {
            out.append(ValidationIssue(severity: .error,
                message: "person key「\(displaySafe(k, max: 200))」重複"))
        }
        for k in duplicates(libraries.map(\.key)).sorted() {
            out.append(ValidationIssue(severity: .error,
                message: "library key「\(displaySafe(k, max: 200))」重複"))
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
                message: "organization 階層有環：\(cycle.map { displaySafe($0, max: 200) }.joined(separator: " → "))"
                       + " → \(displaySafe(start, max: 200))"
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
            let names = cites.sorted().map { displaySafe($0, max: 200) }
            reportedByDOI.formUnion(cites)
            out.append(ValidationIssue(
                severity: .warning,
                message: "DOI「\(displaySafe(doi, max: 200))」被 \(names.count) 筆 work 共用"
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
            let names = cites.sorted().map { displaySafe($0, max: 200) }
            let title = String(k.split(separator: "|").dropLast().joined(separator: "|"))
            out.append(ValidationIssue(
                severity: .warning,
                message: "標題與年份相同但 DOI 不同的 \(names.count) 筆 work"
                       + "（\(names.joined(separator: ", "))）：「\(displaySafe(title, max: 120))」"
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
        for (k, cites) in danglingAuthors.sorted(by: { $0.key < $1.key }) {
            out.append(ValidationIssue(severity: .warning,
                message: "作者 key「\(displaySafe(k, max: 200))」沒有對應的 people 檔"
                       + "（\(cites.count) 筆引用，如 \(displaySafe(cites.sorted().first ?? "", max: 200))）"))
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
                danglingCandidates["\(c.shape.rawValue) 「\(displaySafe(c.key, max: 200))」",
                                   default: 0] += 1
            }
        }
        for (k, n) in danglingCandidates.sorted(by: { $0.key < $1.key }) {
            out.append(ValidationIssue(severity: .warning,
                message: "歧異候選 \(k) 沒有對應的記錄（\(n) 筆歧異引用）"
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
                message: "akashic.libraries 的「\(displaySafe(l, max: 200))」沒有對應的 registry 檔"
                       + "（\(n) 筆引用）"))
        }
        return out
    }
}
