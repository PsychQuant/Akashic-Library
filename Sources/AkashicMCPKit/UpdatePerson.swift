import Foundation
import Yams
import AkashicCore
import AkashicStoreIO
import AkashicIndex

/// #68：person 的部分更新入口。
///
/// 外部 pipeline 手刻 YAML 合併是一個私有下游 repo 五輪 verify 的實證病灶——合併該由
/// 既有的 decoder → 改 → encoder 走完，tolerant-preserve 與 canary 白拿。
///
/// 契約：**提及的欄位整個換、未提及一律不動**。timeline 的「只加一段」刻意不做
/// ——增量語意（同 range 段替換還是並存）是 #100/#75 的未決區，在定案前給增量
/// API 會把未決語意焊進參數形狀（diagnosis 裁決）。
public extension AkashicService {

    /// - Parameters:
    ///   - fields: 結構化欄位值（JSON object）。純量欄位收 String 或 null（null＝
    ///     清除，與「未提及」不同）；`names` 收 `{authorized:[…], variant:[…]}` object
    ///     （全量替換；#227 巢狀化後平坦陣列拒收）；
    ///     `profile` 收維度 object（**維度級**覆寫——提及的維度全量替換、未提及的
    ///     維度保留），段的形狀與 YAML 相同（value/start/end/ended/source/note）。
    ///   - dryRun: true 時零寫入，回報會改什麼 + gate 預演。
    /// #308：JSON 陣列 → ProvenanceReference 逐筆 append（冪等；verdict 欄位對拒收）。
    /// 回傳實際附加筆數。
    ///
    /// 解析與驗證是 `update_venue` 的 references **同一個函式**（`parseReferenceObjects`，#674）：鍵名嚴格、`status` 必填不預設 200、
    /// `url` 只收 http／https 且不含帳密、有界——契約在 `ReferenceWriteParsing.swift`。person 自己的政策只有一條：
    /// verdict 欄位對（封閉三值）不收手供，只能經 resolve 流程寫。空陣列拒絕，與 venue 同一句（#695；先前是 no-op，見 `parseReferenceObjects`）。
    private static func appendReferences(_ raw: Any, to person: inout Person) throws -> Int {
        guard let arr = raw as? [Any] else {
            throw ServiceError.invalid("references 必須是 object 陣列（append-only）")
        }
        var added = 0
        for ref in try parseReferenceObjects(arr, policy: personReferencePolicy) {
            // #564：名字分類的判定記錄只經名字分類面寫（person 的是 `authorize-names` 與 `fields.names` 帶 `judgement`）——通用面寫進去，一筆「指定」
            // 就能把一個機械值說成人判定過的，而那正是合併端要分辨的東西。帶 rests-on 的一般判斷（statement 不符名字分類文法）照收。
            guard !NameClassificationRecord.isRecord(ref) else {
                throw ServiceError.invalid(
                    "references 裡有一筆名字分類的判定記錄（field: \(displaySafeInvisible(ref.field, max: 60))、statement「指定／確認／撤回：…」）"
                    + "——它只經名字分類面寫（authorize-names，或 fields.names 附 judgement，#564），通用面不收；整批拒絕、零寫入")
            }
            // append-only 的去重比**位元組**（R26 D73；R25 verify 第 7／25／29 列：三個 `==` 全是 canonical，只差 NFC／NFD 的一筆曾被靜默吞掉）
            guard !person.references.contains(where: { $0.byteExactKey == ref.byteExactKey }) else { continue }
            person.references.append(ref)
            added += 1
        }
        return added
    }

    /// person 收哪些 field：verdict 以外的都收（附著由 `Person.validateReferenceAttachment` 在寫入時驗）。
    private static let personReferencePolicy = ReferenceHolderPolicy(admitField: { field, at in
        guard !ProvenanceReference.resolutionVerdictFields.contains(field) else {
            throw ServiceError.invalid(
                "\(at) 的欄位對「\(displaySafeInvisible(field, max: 60))」是 resolution verdict——"   // display-safe-exempt: at 是字面＋Int
                + "只能經 resolve 流程（apply／reject）寫，不收手供")
        }
    })

    /// CLI 的 `validate()` 用（#654）：`--fields`（argv）只看參數的檢查——欄位名在白名單內、各欄位的形狀（純量／null、names 的兩個分割、
    /// profile 的段、references 的形狀）。套在一筆空白的暫存記錄上，與服務套在既有記錄上的是同一個函式；要合併到既有記錄才判得出來的
    /// （authorized ⊆ names 等 `validate()` 的 error）不在這裡。同一份 JSON 從 stdin 來時是 argv 以外，仍是執行期（#549 邊界 1）。
    static func checkUpdatePersonFields(_ fields: [String: Any]) throws {
        var scratch = Person(key: "argv-check")
        _ = try applyUpdateFields(fields, to: &scratch)
    }

    /// `update_person` 只看參數的結果（#564 修正輪：使用者 2026-10-02 裁決第 1、2 點）。
    internal struct UpdatePersonArguments {
        /// `fields.names` 帶來的理由與證據；nil＝沒給（名字分類有改時在讀 store 之後拒絕）
        let judgement: AuthorizedDesignation.Judgement?
        /// `remove_names`（`--remove-name`）：給了就是單獨呼叫
        let removals: [NameRemovalSpec]
    }

    /// CLI 的 `validate()` 用：`--judgement`／`--rests-on`／`--remove-name` 與 `--fields` 的組合、理由的形狀、名字數上限——只看參數，早於開 store。
    /// `fields` 是 argv 的 `--fields`（stdin 來的 JSON 在服務裡檢查，#549 邊界 1）；nil＝沒給 `--fields`。
    static func checkUpdatePersonArguments(fields: [String: Any]?, judgement: String?, restsOn: [String]?,
                                                  removeNames: [String]?) throws {
        _ = try updatePersonArguments(fields: fields ?? [:], fieldsGiven: fields != nil, judgement: judgement,
                                      restsOn: restsOn, removeNames: removeNames)
    }

    /// - `remove_names` 單獨呼叫：不與 `fields`、`judgement`、`rests_on` 組合（刪名字的理由只進報告、`fields.names` 的理由寫進記錄）。
    /// - `judgement`／`rests_on` 只伴隨 `fields.names`（沒有名字分類就沒有判定的理由）；給了就照 venue 的同一個入口驗（`nameClassificationJudgement`：
    ///   非空白、至多 4,096 位元組、`reasonIssue`、rests_on 至多 20 個且形狀合法）。理由**是否必填**要看 store 裡現在的 authorized（讀 store 之後）。
    /// - `fields.names` 的 authorized 至多 `maxNamesPerClassificationCall` 個名字（#564 第 4 點；variant 不寫記錄、不計，R2 verify）。
    internal static func updatePersonArguments(fields: [String: Any], fieldsGiven: Bool, judgement: String?, restsOn: [String]?,
                                      removeNames: [String]?) throws -> UpdatePersonArguments {
        if removeNames != nil {
            var others: [String] = []
            if fieldsGiven { others.append("fields") }
            if judgement != nil { others.append("judgement") }
            if restsOn != nil { others.append("rests_on") }
            guard others.isEmpty else {
                throw ServiceError.invalid(
                    "remove_names（--remove-name）單獨呼叫——不與 \(others.joined(separator: "、")) 組合（刪名字的理由只進報告、fields.names 的理由寫進記錄）；整批拒絕、零寫入")   // display-safe-exempt: others 是本函式的字面參數名
            }
            return UpdatePersonArguments(judgement: nil,
                                         removals: try parseNameRemovalSpecs(removeNames, parameter: "remove_names（--remove-name）"))
        }
        // 上限數的是會寫判定記錄的那一份——authorized（#564 R2 verify：b29 V1 第 9 列）：person 的 variant 不寫任何記錄，先前把它也算進來，
        // 一筆有 231 個別名的 person 連只動 variant 的替換都被「同一句理由被複製成上千筆記錄」的理由拒絕，而那句話對它不成立。讀 store 之後
        // 另以這次真的要寫的記錄數再擋一次（`recordPersonNameClassification`：撤回的名字來自 store 裡原本的 authorized）。
        if let names = fields["names"] as? [String: Any] {
            try refuseTooManyClassifiedNames((names["authorized"] as? [Any])?.count ?? 0, legs: "fields.names 的 authorized")
        }
        guard judgement != nil || restsOn != nil else { return UpdatePersonArguments(judgement: nil, removals: []) }
        guard fields["names"] != nil else {
            throw ServiceError.invalid(
                "judgement／rests_on 只伴隨 fields.names（名字分類的判定記錄，#564）——這次沒有 names，沒有判定就沒有判定的理由；整批拒絕、零寫入")
        }
        return UpdatePersonArguments(judgement: try nameClassificationJudgement(classifying: true, judgement: judgement, restsOn: restsOn),
                                     removals: [])
    }

    /// store format 低於名字分類記錄的門檻時，拒絕訊息另說的一句（寫入閘與升級路徑）。到門檻以上回空字串。
    /// **自成一行**（開頭是換行）：兩面的錯誤出口逐行截 400，接在一則長拒絕的尾端時升級路徑會被截掉（真 binary：「先確認會碰這個 store 的
    /// CLI／MCP／App…（已截斷）」），所以呼叫端把它接在「整批拒絕、零寫入」之後。
    static func nameClassificationGateNote(storeFormat: Int) -> String {
        let need = StoreVersion.nameClassificationRecordFormat
        guard storeFormat < need else { return "" }
        return "\n另外：這個 store 是 format \(storeFormat)，名字分類的判定記錄要 format ≥ \(need)——照上面的出口做，只要那一步有記錄要寫（指定、撤回）仍會被寫入閘擋下；"   // display-safe-exempt: Int
            + "先確認會碰這個 store 的 CLI／MCP／App 都已升級，再把 store.yaml 的 format: 改成 \(need)"   // display-safe-exempt: Int
    }

    /// `fields.names` 替換之後的名字分類記錄（#564；使用者 2026-10-02 裁決第 1 點，2026-10-05 裁決第 1–3 點）：**動到 authorized 就要理由**，
    /// 並比照 venue 寫記錄——**只替有變動的名字寫**：
    ///
    /// | 情形 | 記錄（`field: authorized`） |
    /// |---|---|
    /// | 原本不在 authorized、替換後在 | `指定：理由` |
    /// | 原本在、替換後不在但仍在 names（移到 variant） | `撤回：理由` |
    /// | 原本就在、替換後仍在 | 不寫（2026-10-05 第 2 點：留下沒動的不寫「確認」——先前附了理由就對每一個都寫一筆確認，理由說的是別的名字時，那筆確認的依據是錯的，b33 X1 第 3 列） |
    ///
    /// person 的 `variant` 分割是「其他名字」（所有不是對外形的名字），不是 venue 那種「標成異寫」的判定——只動 variant 的替換不需要理由、
    /// 不寫記錄，也沒有 `field: variant` 的記錄（store 不收，`Person.validateReferenceAttachment`；2026-10-05 第 3 點確認這個讀法）。
    /// 相等用 `String ==`（canonical equivalence），與記錄的錨定（`validateReferenceAttachment`）同一把。
    ///
    /// 拒絕（零寫入）：
    /// - **對外形整個離開 names**（有沒有記錄都一樣，2026-10-05 第 1 點）：移出 authorized 要寫一筆「撤回：理由」，而記錄錨定 names——名字
    ///   要留在 names（放在 variant）。之後要刪掉它，用 `--remove-name`（只收最後一筆是撤回的名字）。R2 曾讓沒有記錄的對外形一步離開 names、
    ///   理由不入庫（b33 X1 第 0／2／3／8／11／13／18／23 列：理由既不在 store 也不在回應、format < 22 的寫入閘因為沒有記錄要寫而沒觸發、
    ///   也沒有移除面一族的 git 閘）。
    /// - 替換拿掉一個名字而它有記錄錨定在那個拼法上（記錄會成孤兒）；出口是先移到 variant 寫撤回、再 `--remove-name`（#564 第 2 點）。
    /// - authorized 有改而沒給理由（store format < 22 時訊息另說寫入閘與升級路徑，`nameClassificationGateNote`）。
    /// - 給了理由，authorized 卻沒有任何名字進出——沒有要記的判定，理由就沒有地方放（先前寫一句「確認」到每個對外形上；現在不寫，所以拒絕而不是靜默丟掉理由）。
    /// - 這次要寫的記錄超過 `maxNamesPerClassificationCall`。
    ///
    /// 回傳寫下的筆數；nil＝沒有給理由也沒有改 authorized（不出現在報告）。
    internal static func recordPersonNameClassification(before: PersonNames, person: inout Person,
                                                         judgement: AuthorizedDesignation.Judgement?, key: String,
                                                         storeFormat: Int) throws -> Int? {
        let after = person.names
        let afterAll = Set(after.all)
        let holder = "person「\(displaySafeInvisible(key, max: 200))」"
        func list(_ xs: [String]) -> String { listCapped(xs) { "「\(displaySafeInvisible($0, max: 120))」" } }
        let gate = nameClassificationGateNote(storeFormat: storeFormat)
        let authorizedGone = before.authorized.filter { !afterAll.contains($0) }
        guard authorizedGone.isEmpty else {
            throw ServiceError.invalid(
                "fields.names 的替換讓\(holder)的對外形 \(list(authorizedGone)) 整個離開 names——移出 authorized 要寫一筆「撤回：理由」"   // display-safe-exempt: holder 已消毒；list 逐項以 displaySafeInvisible 消毒 authorizedGone
                + "（有沒有記錄都一樣，#564 使用者 2026-10-05 裁決），而判定記錄錨定 names：把它放在 variant、附 --judgement（寫撤回；進入 authorized 的寫指定）。"
                + "之後要整個刪掉它，用 --remove-name（MCP remove_names）'<名字>=<理由>'：只收最後一筆記錄是撤回的名字，記錄隨名字一起刪、理由只進報告、檔案要先 commit。"
                + "這次整批拒絕、零寫入" + gate)   // display-safe-exempt: gate 只含 Int 與字面
        }
        // 記錄錨定在**拼法**上（`String ==`，與 `validateReferenceAttachment` 同一把）：替換後 names 沒有那個拼法的記錄會成孤兒
        // 順序照記錄第一次出現的位置（訊息用），去重另用一個集合——先前以陣列的 contains 去重，O(記錄數 × 孤兒數)（#564 b36 Y1 第 8 列：
        // 一萬個名字各一筆撤回時這一圈佔掉 2.4 秒）
        var orphaned: [String] = []
        var orphanedSeen = Set<String>()
        for r in person.references where NameClassificationRecord.isRecord(r) {
            if let v = r.value, !afterAll.contains(v), orphanedSeen.insert(v).inserted { orphaned.append(v) }
        }
        guard orphaned.isEmpty else {
            throw ServiceError.invalid(
                "fields.names 的替換拿掉了\(holder)的 \(list(orphaned))，而它們有名字分類的判定記錄（錨定 names 上的那個拼法，#564）——"   // display-safe-exempt: holder 已消毒；list 逐項以 displaySafeInvisible 消毒 orphaned
                + "刪名字用 --remove-name（MCP remove_names）'<名字>=<理由>'：只收最後一筆記錄是「撤回」的名字，記錄隨名字一起刪、理由只進報告、檔案要先 commit。"
                + "這次整批拒絕、零寫入")
        }
        let entering = after.authorized.filter { !before.authorized.contains($0) }
        let leaving = before.authorized.filter { !after.authorized.contains($0) }   // 上一道保證：都還在 names（variant）
        guard let judgement else {
            guard entering.isEmpty, leaving.isEmpty else {
                throw ServiceError.invalid(
                    "fields.names 改了\(holder)的 authorized（"   // display-safe-exempt: holder 已消毒
                    + (entering.isEmpty ? "" : "成為對外形：\(list(entering))") + (entering.isEmpty || leaving.isEmpty ? "" : "；")   // display-safe-exempt: list 逐項以 displaySafeInvisible 消毒 entering；entering.isEmpty 與 leaving.isEmpty 是 Bool
                    + (leaving.isEmpty ? "" : "移到 variant：\(list(leaving))")   // display-safe-exempt: list 逐項以 displaySafeInvisible 消毒 leaving
                    + "）——名字分類是判定，judgement（--judgement）必填：進入的寫「指定」、移出的寫「撤回」，各在 references 留一筆判定記錄（field: authorized，#564）；"
                    + "證據 rests_on 可省略。只動 variant 的替換不必附理由。整批拒絕、零寫入" + gate)   // display-safe-exempt: gate 只含 Int 與字面
            }
            return nil
        }
        func record(_ name: String, _ action: NameClassificationRecord.Action) -> ProvenanceReference {
            NameClassificationRecord.make(field: NameClassificationRecord.authorizedField, name: name, action: action,
                                          reason: judgement.reason, restsOn: judgement.restsOn)
        }
        let records = leaving.map { record($0, .withdraw) } + entering.map { record($0, .designate) }
        guard !records.isEmpty else {
            throw ServiceError.invalid(
                "給了 judgement，但這次替換沒有讓任何名字進出\(holder)的 authorized——判定記錄只替有變動的名字寫（進入的寫指定、移出的寫撤回；"   // display-safe-exempt: holder 已消毒
                + "仍在 authorized 的不寫「確認」，#564 使用者 2026-10-05 裁決），沒有要記的判定，理由就沒有地方放。只動 variant 的替換不必附理由；整批拒絕、零寫入")
        }
        try refuseTooManyClassifiedNames(records.count, legs: "fields.names 這次要寫的判定記錄")
        return NameClassificationRecord.append(records, to: &person.references)
    }

    /// `fields` 的逐欄套用（#654 從 `updatePerson` 抽出，逐字不變）：回傳 `changes`（欄位 → 原值）。
    static func applyUpdateFields(_ fields: [String: Any], to person: inout Person) throws -> [String: Any] {
        // 白名單由 decoder 的 known keys **推導**，不手寫清單——手寫清單就是
        // 「第二份定義」：#75 的 prefers、#66 的 references 落地時自動納入，
        // 不必記得回來改這裡（diagnosis 的設計裁決）。
        let updatable = PersonYAML.updatableKeys
        var changes: [String: Any] = [:]

        for (k, raw) in fields.sorted(by: { $0.key < $1.key }) {
            guard updatable.contains(k) else {
                throw ServiceError.invalid(
                    "不認得的欄位「\(displaySafeInvisible(k, max: 120))」——可更新："
                    + updatable.sorted().joined(separator: "、")
                    + "（id／key／type 是結構性鍵，不可經部分更新改動）")
            }
            switch k {
            case "orcid":
                // 寫入面驗證即拒絕（design.md 的寫入契約）：形狀不合法的值不得
                // 進 store，錯誤具名該值與預期形狀——與讀取面 fail-closed 同方向，
                // 但這裡是使用者當下能看到並修正的錯誤，不是事後才發現的 quarantine。
                if let raw = try scalarOrNull(raw, field: k) {
                    guard let o = ORCID(raw) else {
                        throw ServiceError.invalid(
                            "欄位「orcid」的值「\(displaySafeInvisible(raw, max: 120))」不是合法的 ORCID"
                            + "（\(ORCID.shapeDescription)）")   // display-safe-exempt: ORCID.shapeDescription：型別的靜態常數（預期形狀說明），非 store 內容
                    }
                    person.orcid = o
                } else {
                    person.orcid = nil
                }
                changes[k] = raw
            case "openalex":
                person.openalex = try scalarOrNull(raw, field: k)
                changes[k] = raw
            case "died":
                person.died = try scalarOrNull(raw, field: k)
                changes[k] = raw
            case "note":
                person.note = try scalarOrNull(raw, field: k)
                changes[k] = raw
            case "names":
                // #227：巢狀形狀（{authorized:[…], variant:[…]}，全量替換）。平坦
                // 陣列是舊形狀——與 decoder 同紀律，拒絕而非靜默解讀。
                person.names = try personNames(raw, field: k)
                changes[k] = raw
            case "profile":
                guard let dims = raw as? [String: Any] else {
                    throw ServiceError.invalid("profile 必須是 object（維度 → 段清單）")
                }
                for (dim, segs) in dims.sorted(by: { $0.key < $1.key }) {
                    let node = try Self.jsonToNode(segs)
                    // 與 YAML decode **同一條路**：形狀驗證、ended 矛盾防線、
                    // null-face 拒收全部白拿——同一個概念只有一套判準
                    try PersonYAML.decodeProfileDimension(dim, node: node, into: &person.profile)
                    changes["profile.\(dim)"] = segs
                }
            case "references":
                // #308：**append-only**——與其他欄位「提及即整換」的契約刻意不同，
                // 因為 references 同時持有 resolution verdict（封閉欄位對 #232）：
                // 全量替換等於洗掉判定史。verdict 欄位對在此拒收（只能經 resolve
                // 流程寫）；append 以 (field, value) 冪等（appendIfAbsent 同款）。
                let added = try appendReferences(raw, to: &person)
                changes[k] = "append \(added)"
            default:
                // updatableKeys 推導自 decoder；decoder 認得而這裡沒接的欄位
                // **大聲說**，不靜默吞——推導超前實作時這是唯一的誠實出口
                throw ServiceError.invalid(
                    "欄位「\(displaySafeInvisible(k, max: 200))」是 decoder 認得、但部分更新入口尚未支援的欄位")
            }
        }
        return changes
    }

    /// - Parameters:
    ///   - judgement／restsOn：`fields.names` 動到 authorized 時的理由與證據（#564 修正輪）；理由**是否必填**要看 store 裡現在的 authorized。
    ///   - removeNames：`<名字>=<理由>`——刪最後一筆記錄是撤回的名字（#564 第 2 點，`removePersonNames`）；給了就是單獨呼叫。
    func updatePerson(key: String, fields: [String: Any], dryRun: Bool, fieldsGiven: Bool = true,
                      judgement: String? = nil, restsOn: [String]? = nil, removeNames: [String]? = nil) throws -> String {
        // #654：只看參數的檢查在讀 store 之前跑，與 CLI 的 validate() 同一個函式（C2c R1 verify：MCP 面先前會先報
        // 「找不到 person」，蓋掉參數錯誤）
        let args = try Self.updatePersonArguments(fields: fields, fieldsGiven: fieldsGiven, judgement: judgement,
                                                  restsOn: restsOn, removeNames: removeNames)
        if !args.removals.isEmpty { return try removePersonNames(key: key, specs: args.removals, dryRun: dryRun) }
        try Self.checkUpdatePersonFields(fields)
        let load = try store.load()   // 寫前重讀（同 AppState.mutate 的防 lost-update 語意）
        // 兩筆**不同**的 person（id 不同）共用這個 key：寫進哪一筆是猜（#564 b36 Y1 第 2／14 列：這條 fields 路徑先前沒有，名字分類記錄與一般欄位
        // 都寫進先載入的那一筆）。乾跑同樣拒（在分岔之前）。同一筆記錄的 legacy 拷貝（id 相同，`crossRecordIssues` 報 warning 的那一種）與其他
        // 「load 判定它的檔寫入時會被拒」的（`unlocatablePersonKeys` 的第 2 類，#641）不在這裡擋：那是給**多檔**寫入者在第一次寫入之前擋撕裂用的；
        // 這裡只寫一個檔，那幾類由寫入當下的 #631 前置擋下（零寫入），而且訊息說得更準——同一個操作稍早寫過這一筆時說出來、並把那一筆標成之後的
        // 寫入沒套用（#705，`WrittenWithLegacyCopyR2Tests`；第一版照 `remove_names` 問整個 `unlocatablePersonKeys`，全套測試抓到它擋在那之前）
        guard Set(load.people.lazy.filter { $0.key == key }.map(\.id)).count <= 1 else {
            throw ServiceError.invalid("person「\(displaySafeInvisible(key, max: 200))」無法唯一定位（person key 有不只一筆記錄——akashic validate 以跨記錄 error 列出）——整批拒絕、零寫入")
        }
        guard var person = load.people.first(where: { $0.key == key }) else {
            throw ServiceError.notFound("person「\(displaySafeInvisible(key, max: 200))」")
        }
        let namesBefore = person.names
        let changes = try Self.applyUpdateFields(fields, to: &person)
        // #564：names 動到 authorized 就要理由、寫判定記錄（2026-10-02 裁決第 1 點；2026-10-05 裁決第 1–3 點）
        var judgementsRecorded: Int?
        if fields["names"] != nil {
            judgementsRecorded = try Self.recordPersonNameClassification(before: namesBefore, person: &person,
                                                                         judgement: args.judgement, key: key,
                                                                         storeFormat: try StoreVersion.read(root: root))
            // 替換不把 person 刪到沒有名字（b33 X1 第 19／40 列）：`remove_names`、organization、venue 都拒絕這一格，替換先前是唯一的例外
            // ——載入與 validate 都過，export 與作者比對卻沒有可顯示的名字。原本就沒有名字的不擋（不是這次造成的）
            guard !person.names.all.isEmpty || namesBefore.all.isEmpty else {
                throw ServiceError.invalid(
                    "fields.names 的替換會讓 person「\(displaySafeInvisible(key, max: 200))」沒有任何名字——person 至少要有一個名字（remove_names、organization、venue 同）；整批拒絕、零寫入")
            }
        }

        // #148 verify F4：names 全量替換可讓 authorized 懸空（authorized ⊆ names 的
        // 不變式只活在 Person.validate()，writePerson 不跑它）。部分更新是獨特的
        // 暴露面——替換 names 的呼叫端本來就沒在想 authorized。error 等級拒絕，
        // dry-run 一併預演。
        let validationErrors = person.validate().filter { $0.severity == .error }
        if dryRun {
            var out: [String: Any] = [
                "dryRun": true,
                "key": displaySafe(key, max: 200),
                // #156 × #158 交會後浮現：`changes` 的 key 是 `k`，而 `k` 已被
                // `guard updatable.contains(k)` + 下方 `switch k { case "orcid" … }`
                // 雙重約束成那六個**字面量**之一（`updatableKeys` 由 `knownPersonKeys`
                // 這個字面 Set 推導）。不是 store 內容。
                "wouldChange": changes.keys.sorted(),   // display-safe-exempt: changes.keys：key 受 updatable 白名單約束成字面量
            ]
            // #564：會寫幾筆名字分類記錄；寫得進去要 store format ≥ 22——不預演的話 dry-run 說「會改」而實跑被擋
            if let n = judgementsRecorded {
                out["judgementsToRecord"] = n   // display-safe-exempt: Int
                let format = try StoreVersion.read(root: root)
                if n > 0, format < StoreVersion.nameClassificationRecordFormat {
                    out["blockedByNameClassificationGate"] =
                        "real run 會被拒：名字分類的判定記錄需要 store format ≥ \(StoreVersion.nameClassificationRecordFormat)（本 store 是 \(format)）"   // display-safe-exempt: Int
                        + "——確認所有 binary 已升級後把 store.yaml 的 format: 改成 \(StoreVersion.nameClassificationRecordFormat)"   // display-safe-exempt: Int
                }
            }
            if !validationErrors.isEmpty {
                out["blockedByValidation"] = validationErrors.prefix(5)
                    .map { displaySafeClipOnly($0.message, max: 300) }   // display-safe-exempt: 已消毒（validate() 的訊息在生產端 displaySafeInvisible，R28 D80），只截——R27 verify 第 17 列
            }
            // gate 預演（#131 的 v6 gate）：不預演的 dry-run 會說「會改」而
            // real run 被擋——dry-run 就成了謊言（diagnosis 明列的要求）
            if person.profile.usesEndedUnknown {
                let format = try StoreVersion.read(root: root)
                if format < 6 {
                    out["blockedByFormatGate"] =
                        "real run 會被拒：ended 段需要 store format ≥ 6（本 store 是 \(format)）"
                        + "——確認所有 binary 已升級後把 store.yaml 的 format: 改成 6"
                }
            }
            return try jsonString(out)
        }

        guard validationErrors.isEmpty else {
            throw ServiceError.invalid(
                "更新後的記錄無法通過驗證（error 等級），拒絕寫入：\n"
                + validationErrors.prefix(5).map { "- " + displaySafeClipOnly($0.message, max: 300) }   // display-safe-exempt: message 由 validate() 生產端消毒，只截（R32：註記要具名 binding）
                    .joined(separator: "\n"))
        }
        try store.writePerson(person)   // v6 gate／canary／tolerant-preserve 全在這條路上
        try LibraryIndex(store: store).rebuild()
        var result: [String: Any] = ["key": displaySafe(key, max: 200),
                                     "updated": changes.keys.sorted()]   // display-safe-exempt: changes.keys：同上，key 受白名單約束
        if let n = judgementsRecorded { result["judgementsRecorded"] = n }   // display-safe-exempt: Int
        return try jsonString(result)
    }

    // MARK: - JSON 邊界

    private static func scalarOrNull(_ v: Any, field: String) throws -> String? {
        if v is NSNull { return nil }
        guard let s = v as? String else {
            throw ServiceError.invalid("欄位「\(field)」必須是字串或 null")   // display-safe-exempt: field 是呼叫端已過 updatable/switch 白名單的字面量，非 store 內容
        }
        return s
    }

    /// #227：names 的巢狀形狀。平坦陣列給出**點名新形狀**的錯誤——與 YAML decoder
    /// 對平坦 `names:` 的拒絕同紀律，兩個入口不得有兩套答案。
    private static func personNames(_ v: Any, field: String) throws -> PersonNames {
        if v is [Any] {
            throw ServiceError.invalid(
                "欄位「\(field)」收 object（{authorized:[…], variant:[…]}，全量替換）"   // display-safe-exempt: field 是白名單字面量
                + "——平坦字串陣列是 format < 10 的舊形狀，不靜默解讀")
        }
        guard let dict = v as? [String: Any] else {
            throw ServiceError.invalid("欄位「\(field)」必須是 object（{authorized:[…], variant:[…]}）")   // display-safe-exempt: field 是呼叫端字面欄位名（R32：註記要具名 binding）
        }
        var names = PersonNames(authorized: [], variant: [])
        for (kk, vv) in dict.sorted(by: { $0.key < $1.key }) {
            switch kk {
            case "authorized":
                names.authorized = try stringList(vv, field: "\(field).authorized")
            case "variant":
                names.variant = try stringList(vv, field: "\(field).variant")
            default:
                throw ServiceError.invalid(
                    "names 只有 authorized 與 variant 兩個分割，不認得「\(displaySafeInvisible(kk, max: 120))」")
            }
        }
        // #227 verify R1：分割互斥在入口早擋（validate 也會擋，但這裡能給更準的訊息）
        if let dup = names.authorized.first(where: Set(names.variant).contains) {
            throw ServiceError.invalid(
                "「\(displaySafeInvisible(dup, max: 120))」同時出現在 authorized 與 variant——"
                + "一個名字只屬於一個分割；指定是搬移，不是複製")
        }
        return names
    }

    private static func stringList(_ v: Any, field: String) throws -> [String] {
        guard let arr = v as? [Any], let strings = arr as? [String] else {
            throw ServiceError.invalid("欄位「\(field)」必須是字串陣列（全量替換）")   // display-safe-exempt: field 是呼叫端字面欄位名（R32：註記要具名 binding）
        }
        return strings
    }

    /// JSON 值 → Yams Node（遞迴）。**Bool 判定先於 Int**：JSON 的 true/false 進
    /// `[String: Any]` 後是 NSNumber，`as? Int` 對它也成立——順序反了 `ended: true`
    /// 會變成 `ended: 1` 被 decode 拒收。
    ///
    /// **深度上限 64**（#148 verify F3）：fields 是本 MCP 面唯一收任意巢狀 JSON 的
    /// 參數，200–700 層的巢狀會炸掉遞迴堆疊、整個 server 進程無聲死亡——而 SDK 的
    /// transport 守衛（~800 層才擋）比這裡鬆。合法 profile 段深度 ≤ 4，64 綽綽有餘。
    static func jsonToNode(_ v: Any, depth: Int = 0) throws -> Node {
        guard depth <= 64 else {
            throw ServiceError.invalid("fields 的巢狀深度超過 64——合法欄位結構深度 ≤ 4，"
                + "這不是任何可更新欄位的形狀")
        }
        if v is NSNull { return Node("null", Tag(.null)) }
        if let num = v as? NSNumber {
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                // style 顯式 .plain：ended 的 decode 只收裸寫 true/false（#131 F4 慣例）
                return .scalar(.init(num.boolValue ? "true" : "false", Tag(.bool), .plain))
            }
            if let i = v as? Int { return Node("\(i)", Tag(.int)) }
            return Node("\(num)", Tag(.float))
        }
        if let s = v as? String { return Node(s) }
        if let arr = v as? [Any] { return try Node(arr.map { try jsonToNode($0, depth: depth + 1) }) }
        if let dict = v as? [String: Any] {
            return try Node(dict.sorted { $0.key < $1.key }
                .map { (Node($0.key), try jsonToNode($0.value, depth: depth + 1)) })
        }
        throw ServiceError.invalid("無法轉換的 JSON 值型別：\(type(of: v))")   // display-safe-exempt: type(of: v)：Swift 型別名，非資料
    }
}
