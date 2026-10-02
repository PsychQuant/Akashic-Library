import Foundation
import AkashicCore

/// 「哪個名字對外」的寫入核心——venue 的 `authorize`（#554）與 `unauthorize`（#559）、organization 的 `authorize`（#557）共用這一份。
/// organization 沒有 `unauthorize`（#557 R1 verify 之後拿掉，理由見 `OrganizationUpdate.swift` 的檔頭）：`unauthorize` 只有 venue 的入口呼叫。
///
/// venue 與 organization 的 `authorized` 是同一個問題（`AuthorizedNames` 的 doc：兩種實體不該有兩套答案），兩者都是從 `names` 時間軸裡
/// 指定的頂層扁平清單，所以替換與撤回的語意只能有一份（`no-compat-fallback` §同一件事只能有一份描述）。person 不走這裡：它的 names
/// 是巢狀分割，指定面是 `authorize-names`。organization 沒有 `variant` 分割，傳空陣列。
///
/// **純值運算**：只改傳進來的 `names`／`authorized`／`variant`，不讀 store、不寫檔。載入、定位、寫入閘（`Venue.validate()`／
/// `Organization.validate()` 的子集、每書寫系統至多一個、分割互斥）與 index 重建是呼叫端的事，這裡不重造那些檢查。
///
/// **判定記錄**（#564，2026-10-01 落地）：兩個動作都是判定（`two-kinds-of-edits` 的 AI 欄）。替換與撤回的邏輯不讀理由；呼叫端把報告
/// 交給 `judgementRecords` 換成名字分類記錄（`NameClassificationRecord`）再 append 到 references——報告的各桶就是記錄要記的內容
/// （誰成為對外形、誰被確認、誰被換下、誰被抬出 variant、誰被撤回）。記錄的文法與錨定見 `NameClassificationRecord` 的 doc。
struct AuthorizedDesignation {
    var names: TimelineOf<String>
    var authorized: [String]
    var variant: [String]
    /// 檢查 `field: authorized` 的 reference 用（移出 authorized 之後它們成孤兒）；本結構不改它。名字分類記錄（#564）不算——
    /// 它們錨定 names，名字離開 authorized 之後仍合法。
    let references: [ProvenanceReference]
    let owner: Owner

    /// 拒絕訊息要說的那兩件事：這是哪一種記錄、`field: authorized` 的 reference 用什麼面刪。
    struct Owner {
        /// `venue`／`organization`
        let noun: String
        /// 刪掉 `field: authorized` reference 的面（完整片語，如「用 update-venue --remove-reference 刪掉它們（#673）」）；
        /// `nil`＝這個實體的 reference 沒有移除面，只能手改 YAML。
        let referenceRemoval: String?
    }

    /// `authorize` 的結果。桶的名字就是 payload 的鍵（`authorizedAdded`…）。
    struct AuthorizeReport {
        /// 不在 names、這次一併加進 names 的（canonical 形）
        var namesAdded: [String] = []
        var authorizedAdded: [String] = []
        /// 同書寫系統被換下來的舊指定——留在 names、不標 variant
        var authorizedRemoved: [String] = []
        /// 被換下的舊指定與換下它的名字（`authorizedRemoved` 的每一項各一對，順序相同）——撤回記錄的理由要說出是誰換下的（#564）
        var displaced: [(removed: String, by: String)] = []
        /// 原本在 variant、被抬進 authorized 的（organization 恆空）
        var liftedFromVariant: [String] = []
        /// 本來就是對外形（冪等，但要說）
        var alreadyAuthorized: [String] = []
        /// 同名而位元組不同的舊指定換成 canonical 形——唯一宣告 store 位元組被改寫的桶
        var authorizedRewritten: [String] = []
    }

    /// 撤回的一筆：store 拼法，以及它在**呼叫前**的 `authorized` 裡的位置（0 起算；一次撤回多個時位置都以呼叫前的清單算）。
    /// 位置是撤回唯一會丟掉的資訊：名字與分類都留在 names，`authorize` 指定回來時卻接在 authorized 尾端（R1 verify #559 第 5／9／11／18／23 列）。
    struct Withdrawn: Equatable {
        let name: String
        let index: Int
    }

    /// 解析成 store 拼法：canonical 相等的 names 條目（在不變式下至多一筆）；沒有就 nil。
    /// **相等與查找只有這一份**（R1 verify 第 30 列）：`updateVenue` 的 `add_names`／`add_variant` 也走它，不另寫一份 closure。
    static func storedSpelling(_ requested: String, in entries: [TemporalValue<String>]) -> String? {
        let key = NameIdentity.canonical(requested)
        return entries.first { NameIdentity.canonical($0.value) == key }?.value
    }

    func storedSpelling(_ requested: String) -> String? { Self.storedSpelling(requested, in: names.entries) }

    /// 同書寫系統原子替換（#554 的語意，原樣從 `updateVenue` 搬出）。`requested` 已經過入口的 vetting（canonical、逐項驗、去重），
    /// 兩句矛盾的話（同一次兩個同書寫系統的名字、同一個名字又是 add_variant／unauthorize）已在入口擋。
    mutating func authorize(_ requested: [String]) throws -> AuthorizeReport {
        var report = AuthorizeReport()
        for r in requested {
            // 解析成 store 拼法；names 沒有的，以 canonical 形加進 names（分割是對 names 的標記）
            let x: String
            if let existing = storedSpelling(r) {
                x = existing
            } else {
                x = r                                                   // vetted 已是 canonical
                names = Timeline(names.entries + [TemporalValue(value: x)])
                report.namesAdded.append(x)
            }
            let key = NameIdentity.canonical(x)
            let script = WritingSystem.of(x)
            let already = authorized.contains { NameIdentity.canonical($0) == key }
            // 重建 authorized：移出 (a) 同 `WritingSystem` 的**其他**指定——留在 names、不進 variant
            // （D1：程式不替呼叫端多說「它是異寫」）、(b) 與 x canonical-相等但拼法不同的（修正
            // 拼法；R3 第 1 列 (d)(e)：報告不得宣稱 store 沒有的字串、守衛說「請選一個」選了就要修好）。
            // x **插回第一個被動到的位置**（R3 第 2 列：remove＋append 會重排，`displayName` 取
            // `first`，雙語記錄的預設顯示名會換書寫系統）。
            var kept: [String] = []
            var insertAt: Int? = nil
            var rewrote = false
            for y in authorized {
                let sameName = NameIdentity.canonical(y) == key
                if sameName || WritingSystem.of(y) == script {
                    if insertAt == nil { insertAt = kept.count }
                    // 同名不同**位元組**（手改成 NFD 的舊 authorized——`String ==` 是 canonical
                    // equivalence，看不出來）也要出聲：authorized 的位元組變了，報告不能說 no-op
                    // （R4 verify 第 6 列）。這是不變式唯一的自我修復路：新狀態是 canonical、validate 過。
                    // 它報在自己的桶 `authorizedRewritten`——R9 讓同一個可見字串同時落在 `alreadyAuthorized`
                    // 與 `authorizedRemoved`、`authorizedAdded` 空，操作者看不出改了什麼（R9 verify logic 第 23 列）。
                    if !sameName {
                        // 舊指定被 `field: authorized` 的 reference 指著時具名拒絕、零寫入（R33；R32 verify Codex 第 2 列）：移出之後那些
                        // reference 成孤兒，`validateReferenceAttachment` 會在寫入時以「不在 authorized 清單內」拒絕——fail-closed 但不說是哪筆、
                        // 也不說出路。程式不替人改判定（D60 同向）：value 改成新的對外形或刪掉它，都是人的事。
                        try refuseIfPinned(y, replacedBy: x)
                        report.authorizedRemoved.append(y)
                        report.displaced.append((y, x))
                    }
                    else if Array(y.utf8) != Array(x.utf8) { rewrote = true }
                    continue
                }
                kept.append(y)
            }
            kept.insert(x, at: insertAt ?? kept.count)
            authorized = kept
            // X 若原本是 variant（例如被 #553 降過去的），從那個分割移出——全部 canonical-相等的
            // 條目都移（R3 第 3 列：只移一筆會留下第二筆、守衛以錯的訊息拒）。organization 沒有 variant，恆空。
            let lifted = variant.filter { NameIdentity.canonical($0) == key }
            if !lifted.isEmpty {
                variant.removeAll { NameIdentity.canonical($0) == key }
                report.liftedFromVariant.append(contentsOf: lifted)
            }
            if rewrote { report.authorizedRewritten.append(x) }
            else if already { report.alreadyAuthorized.append(x) }
            else { report.authorizedAdded.append(x) }   // 冪等，但要說
        }
        return report
    }

    /// 撤回（#559）：把現有的對外形移出 `authorized`，**留在 names、不標 variant**——記錄回到「不作任何宣稱」的誠實狀態
    /// （`venue-entity` spec 的未標）。比照 `clear_paginated`（#500）與 `demote`（#418）：撤回回到未判定，而撤回本身是判定。
    ///
    /// 每個名字都必須是現有的 authorized 成員（相等看 `NameIdentity.canonical`，同 `authorize`），否則整批拒絕、零寫入——撤回一個
    /// 不是對外形的名字不是 no-op，是呼叫端弄錯了對象（與 `authorize` 的冪等不同：那一句仍然成立，這一句不成立）。
    /// 被 `field: authorized` 的 reference 指著的也拒（同 `authorize` 換下舊指定那一格）。回傳被撤回的 store 拼法與它原本的位置。
    ///
    /// **撤回不是 `authorize` 的精確逆操作**：名字與分類（未標）都留在 names，但 `authorize` 對「不在 authorized 裡」的名字一律接在尾端
    /// （只有同書寫系統替換才插回第一個被動到的位置），而 `displayName` 在沒指定書寫系統時取 `authorized.first`——撤回再指定回來，
    /// 多書寫系統記錄的預設顯示名可能換書寫系統。所以回傳位置，讓報告能說出「原本在第幾個」。
    ///
    /// 呼叫端在 `authorize` **之前**跑它：成員資格以呼叫前的 authorized 為準，「撤回 A、指定 B」在同一次呼叫裡不因順序而變。
    mutating func unauthorize(_ requested: [String]) throws -> [Withdrawn] {
        let before = authorized
        var withdrawn: [Withdrawn] = []
        for r in requested {
            let key = NameIdentity.canonical(r)
            let hits = authorized.filter { NameIdentity.canonical($0) == key }
            guard !hits.isEmpty else {
                let current = authorized.isEmpty ? "無" : AkashicService.listCapped(authorized) { "「\(displaySafeInvisible($0, max: 120))」" }
                throw ServiceError.invalid(
                    "unauthorize「\(displaySafeInvisible(r, max: 120))」不是這筆 \(owner.noun) 目前的 authorized（現有：\(current)）"   // display-safe-exempt: owner.noun 是編譯期常量；current 由 listCapped 逐項消毒
                    + "——撤回只收現有的對外形；整批拒絕、零寫入")
            }
            for y in hits { try refuseIfPinned(y, replacedBy: nil) }
            authorized.removeAll { NameIdentity.canonical($0) == key }
            for (i, y) in before.enumerated() where NameIdentity.canonical(y) == key { withdrawn.append(Withdrawn(name: y, index: i)) }
        }
        return withdrawn
    }

    /// `y` 將被移出 authorized（`replacedBy` 非 nil＝被 `authorize` 換下；nil＝被 `unauthorize` 撤回）而 `field: authorized` 的 reference 指著它：
    /// 具名拒絕、零寫入並指路。出路依動作不同——換下來的可以把 reference 的 value 改成新的對外形，撤回的沒有新的對外形可指。
    private func refuseIfPinned(_ y: String, replacedBy x: String?) throws {
        let pinned = references.filter { $0.field == "authorized" && $0.value == y && !NameClassificationRecord.isRecord($0) }
        guard !pinned.isEmpty else { return }
        let removal = owner.referenceRemoval ?? "手改 YAML 刪掉它們（\(owner.noun) 的 reference 沒有移除面）"   // display-safe-exempt: owner.noun 與 referenceRemoval 是呼叫端的編譯期常量
        let subject = x.map { "authorize「\(displaySafeInvisible($0, max: 120))」會把「\(displaySafeInvisible(y, max: 120))」移出 authorized" }
            ?? "unauthorize「\(displaySafeInvisible(y, max: 120))」會把它移出 authorized"
        let remedy = x == nil ? "請先\(removal)" : "請先把那幾筆 reference 的 value 改成新的對外形（手改 YAML）、或\(removal)"   // display-safe-exempt: removal 是呼叫端的編譯期常量
        throw ServiceError.invalid(
            "\(subject)，但這筆 \(owner.noun) 有 \(pinned.count) 筆 `field: authorized` 的 reference 指著它——移出後它們成孤兒、寫入會被拒；"   // display-safe-exempt: subject 的名字逐項 displaySafeInvisible；owner.noun 是編譯期常量；count 是 Int
            + "程式不替人改判定。\(remedy)，再重跑")   // display-safe-exempt: remedy 由字面常量與呼叫端的編譯期常量組成
    }

    /// 一次呼叫的判定理由與證據（#564）：理由套用到該次寫下的每一筆記錄，證據也同。入口已驗過非空、上限與 digest 形狀。
    struct Judgement {
        let reason: String
        let restsOn: [String]
    }

    /// 撤回與指定的報告 → 名字分類記錄（#564）。順序與動作的順序相同：撤回先（`unauthorize` 先跑），再逐個指定——被換下的舊指定、
    /// 被抬出 variant 的名字各一筆撤回（理由由程式在前面說出原因），然後是被指定或被確認的名字本身。
    /// 只差位元組而被換成 canonical 的舊指定（`authorizedRewritten`）是對同一個名字再說一次，寫「確認」。
    static func judgementRecords(withdrawn: [String], authorize report: AuthorizeReport,
                                 judgement: Judgement) -> [ProvenanceReference] {
        func record(_ field: String, _ name: String, _ action: NameClassificationRecord.Action, _ reason: String) -> ProvenanceReference {
            NameClassificationRecord.make(field: field, name: name, action: action, reason: reason, restsOn: judgement.restsOn)
        }
        let authorized = NameClassificationRecord.authorizedField
        var out = withdrawn.map { record(authorized, $0, .withdraw, judgement.reason) }
        for (removed, by) in report.displaced {
            // 新名字截 200 個 scalar（#557 R2 verify 第 27 列：全文內嵌時一個 5,000 字的名字就讓這句超過理由的 4,096 位元組上限，
            // 而這句不經入口的理由檢查；記錄的 value 欄已經是被換下的名字，新名字在 authorized 裡，這裡只需要認得出是誰）
            let shownBy = by.unicodeScalars.count > 200 ? String(String.UnicodeScalarView(by.unicodeScalars.prefix(200))) + "…" : by
            out.append(record(authorized, removed, .withdraw, "同書寫系統改指定「\(shownBy)」——\(judgement.reason)"))
        }
        for lifted in report.liftedFromVariant {
            out.append(record(NameClassificationRecord.variantField, lifted, .withdraw, "改指定為 authorized——\(judgement.reason)"))
        }
        out += report.authorizedAdded.map { record(authorized, $0, .designate, judgement.reason) }
        out += (report.alreadyAuthorized + report.authorizedRewritten).map { record(authorized, $0, .confirm, judgement.reason) }
        return out
    }
}

extension AkashicService {
    /// 同一個名字既 `authorize` 又 `unauthorize` 是兩句矛盾的話（#559）——整批拒絕、零寫入。相等看 `NameIdentity.canonical`，與兩條腿的
    /// 定位同一條。只有 venue 的入口用它（`updateVenueArguments`；organization 沒有 `unauthorize`）。
    static func refuseAuthorizeUnauthorizeOverlap(authorizeIn: [String], unauthorizeIn: [String]) throws {
        let withdrawKeys = Set(unauthorizeIn.map(NameIdentity.canonical))
        let both = authorizeIn.filter { withdrawKeys.contains(NameIdentity.canonical($0)) }
        guard !both.isEmpty else { return }
        throw ServiceError.invalid(
            "「\(Self.listCapped(both) { displaySafeInvisible($0, max: 120) })」"
            + "同時被送進 authorize 與 unauthorize——那是兩句矛盾的話，請只說一句")
    }
}

extension AkashicService {
    /// 同一次呼叫兩個同 `WritingSystem` 的名字是兩句矛盾的話（#554 R1 verify 第 1 列，四席各自重現）：迴圈逐一處理時第 N+1 輪會把
    /// 第 N 輪剛升上去的當舊指定移出——陣列順序決勝，而 `validateWritingSystems` 對這個形狀的裁決是「未決的問題，不是指定；請選一個」。
    /// 桶依 rawValue 排序、全部衝突桶一次印、印呼叫端的原字串（R2 第 7 列、R3 第 14 列）。venue 與 organization 的入口共用（#557 從
    /// `updateVenueArguments` 原樣搬出，訊息逐字不變）。
    static func refuseSameScriptClash(_ authorizeIn: [String]) throws {
        let clashes = Dictionary(grouping: authorizeIn, by: WritingSystem.of)
            .filter { $0.value.count > 1 }
            .sorted { $0.key.rawValue < $1.key.rawValue }
        guard !clashes.isEmpty else { return }
        let described = clashes.map { bucket in
            "\(bucket.key.rawValue)：「\(Self.listCapped(bucket.value) { displaySafeInvisible($0, max: 120) })」"   // display-safe-exempt: WritingSystem.rawValue 是 enum 常數（han／latn／other），不是 store 字串；名字性質式（R32；R31 verify 第 2／8 列：私用區 Co 與合法 joiner 過得了名字驗證、列舉式不逃）
        }.joined(separator: "；")
        throw ServiceError.invalid(
            "同一個書寫系統送了兩個以上的名字——" + described
            + "——每書寫系統至多一個對外形，那是未決的問題，不是指定；請選一個")
    }
}

extension AkashicService {
    /// 名字分類的寫入面一次至多幾個名字（使用者 2026-10-02 裁決 #564 第 4 點）：一次 `--add-variant` 帶上千個名字會把同一句理由
    /// 複製成上千筆記錄（R1 verify 實測 1,500 筆撐到 6 MB），而記錄只追加。**不另立數字**：取其他寫入腿的一次上限（`maxSpecsPerCall`，
    /// 未決腿的 id 數）。超過即整批拒絕、零寫入、不截斷。數的是呼叫端給的項數（空白項也算）——在 vetting 之前擋，一萬個名字不必先逐項正規化。
    static var maxNamesPerClassificationCall: Int { maxSpecsPerCall }

    /// 上面那個上限的檢查——venue（add_variant／authorize／unauthorize 合計）、organization（authorize）、person（names 的兩個分割合計）共用。
    static func refuseTooManyClassifiedNames(_ count: Int, legs: String) throws {
        guard count > maxNamesPerClassificationCall else { return }
        throw ServiceError.invalid(
            "名字分類一次至多 \(maxNamesPerClassificationCall) 個名字（\(legs) 合計，這次 \(count) 個）——分次送；"   // display-safe-exempt: maxNamesPerClassificationCall 與 count 是 Int；legs 是呼叫端的字面參數名
            + "每個名字各寫一筆判定記錄、記錄只追加（#564）；整批拒絕、零寫入，不截斷")
    }

    /// 名字分類腿的理由與證據（#564）——venue（`updateVenueArguments`）與 organization（`updateOrganizationArguments`）的入口共用，讀 store 之前跑。
    ///
    /// `classifying`＝這次至少有一個非空白的名字要分類（全部空白的腿沒有分類，不需要理由；空白項照舊回報在 *Dropped）。
    /// 理由去空白後非空、至多 `maxStatementBytes`；證據可空、至多 `maxRestsOnPerCall` 個，形狀走 `ProvenanceReference` 的平面 init
    /// （單一驗證入口，空內容的 digest 以 #654 的原句拒絕）。回 nil＝這次沒有分類——`judgement`／`rests_on` 單獨出現要不要拒，由各入口決定。
    static func nameClassificationJudgement(classifying: Bool, judgement: String?,
                                            restsOn: [String]?) throws -> AuthorizedDesignation.Judgement? {
        guard classifying else { return nil }
        let reason = judgement?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !reason.isEmpty else {
            throw ServiceError.invalid(
                "名字分類是判定——judgement（--judgement）必填：每次指定、確認、撤回、標異寫都在 references 留一筆判定記錄"
                + "（field: authorized／variant，#564）；證據 rests_on 可省略。整批拒絕、零寫入")
        }
        guard reason.utf8.count <= Self.maxStatementBytes else {
            throw ServiceError.invalid("judgement 超過 \(Self.maxStatementBytes) 位元組（實得 \(reason.utf8.count)）——精簡它；整批拒絕、零寫入，不截斷")   // display-safe-exempt: Self.maxStatementBytes 與 reason.utf8.count 都是 Int
        }
        // 理由的形狀（#564 R1 verify security 第 6／19 列）：開頭的組合符號會讓記錄讀不出來、只有不可見字元的理由什麼都沒說——
        // 判準只有一份（`NameClassificationRecord.reasonIssue`，authorize-names 與 person 的 names 腿共用）
        if let why = NameClassificationRecord.reasonIssue(reason) {
            throw ServiceError.invalid("judgement \(why)——整批拒絕、零寫入")   // display-safe-exempt: why 是 reasonIssue 的固定訊息（碼位是十六進位）
        }
        let digests = restsOn ?? []
        guard digests.count <= Self.maxRestsOnPerCall else {
            throw ServiceError.invalid("rests_on 一次最多 \(Self.maxRestsOnPerCall) 個 digest（這次 \(digests.count) 個）——整批拒絕、零寫入")   // display-safe-exempt: Self.maxRestsOnPerCall 與 digests.count 都是 Int
        }
        do {
            _ = try ProvenanceReference(field: NameClassificationRecord.authorizedField, value: "x", url: nil, retrieved: nil,
                                        status: nil, mediaType: nil, content: nil,
                                        judgement: NameClassificationRecord.statement(.designate, reason: reason), restsOn: digests)
        } catch {
            throw ServiceError.invalid("rests_on 不合法：\(displaySafeError(error, max: 400))——整批拒絕、零寫入")
        }
        return AuthorizedDesignation.Judgement(reason: reason, restsOn: digests)
    }
}
