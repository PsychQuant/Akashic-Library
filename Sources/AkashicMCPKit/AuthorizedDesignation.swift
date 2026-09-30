import Foundation
import AkashicCore

/// 「哪個名字對外」的寫入核心——venue 的 `authorize`（#554）與 `unauthorize`（#559）、organization 的 `authorize`（#557）共用這一份。
///
/// venue 與 organization 的 `authorized` 是同一個問題（`AuthorizedNames` 的 doc：兩種實體不該有兩套答案），兩者都是從 `names` 時間軸裡
/// 指定的頂層扁平清單，所以替換與撤回的語意只能有一份（`no-compat-fallback` §同一件事只能有一份描述）。person 不走這裡：它的 names
/// 是巢狀分割，指定面是 `authorize-names`。organization 沒有 `variant` 分割，傳空陣列。
///
/// **純值運算**：只改傳進來的 `names`／`authorized`／`variant`，不讀 store、不寫檔。載入、定位、寫入閘（`Venue.validate()`／
/// `Organization.validate()` 的子集、每書寫系統至多一個、分割互斥）與 index 重建是呼叫端的事，這裡不重造那些檢查。
///
/// **判定記錄**：兩個動作都是判定（`two-kinds-of-edits` 的 AI 欄）。目前不留 judgement；#564 已於 2026-10-01 裁決要留，另案落地
/// （需要 store format bump）。報告的各桶就是那筆記錄要記的內容（誰成為對外形、誰被換下、誰被撤回），落地時呼叫端依報告寫
/// reference，替換與撤回的邏輯不必改。
struct AuthorizedDesignation {
    var names: TimelineOf<String>
    var authorized: [String]
    var variant: [String]
    /// 檢查 `field: authorized` 的 reference 用（移出 authorized 之後它們成孤兒）；本結構不改它。
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
        /// 原本在 variant、被抬進 authorized 的（organization 恆空）
        var liftedFromVariant: [String] = []
        /// 本來就是對外形（冪等，但要說）
        var alreadyAuthorized: [String] = []
        /// 同名而位元組不同的舊指定換成 canonical 形——唯一宣告 store 位元組被改寫的桶
        var authorizedRewritten: [String] = []
    }

    /// 解析成 store 拼法：canonical 相等的 names 條目（在不變式下至多一筆）；沒有就 nil。
    func storedSpelling(_ requested: String) -> String? {
        let key = NameIdentity.canonical(requested)
        return names.entries.first { NameIdentity.canonical($0.value) == key }?.value
    }

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
    /// 被 `field: authorized` 的 reference 指著的也拒（同 `authorize` 換下舊指定那一格）。回傳被撤回的 store 拼法。
    ///
    /// 呼叫端在 `authorize` **之前**跑它：成員資格以呼叫前的 authorized 為準，「撤回 A、指定 B」在同一次呼叫裡不因順序而變。
    mutating func unauthorize(_ requested: [String]) throws -> [String] {
        var withdrawn: [String] = []
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
            withdrawn.append(contentsOf: hits)
        }
        return withdrawn
    }

    /// `y` 將被移出 authorized（`replacedBy` 非 nil＝被 `authorize` 換下；nil＝被 `unauthorize` 撤回）而 `field: authorized` 的 reference 指著它：
    /// 具名拒絕、零寫入並指路。出路依動作不同——換下來的可以把 reference 的 value 改成新的對外形，撤回的沒有新的對外形可指。
    private func refuseIfPinned(_ y: String, replacedBy x: String?) throws {
        let pinned = references.filter { $0.field == "authorized" && $0.value == y }
        guard !pinned.isEmpty else { return }
        let removal = owner.referenceRemoval ?? "手改 YAML 刪掉它們（\(owner.noun) 的 reference 沒有移除面）"   // display-safe-exempt: owner.noun 與 referenceRemoval 是呼叫端的編譯期常量
        let subject = x.map { "authorize「\(displaySafeInvisible($0, max: 120))」會把「\(displaySafeInvisible(y, max: 120))」移出 authorized" }
            ?? "unauthorize「\(displaySafeInvisible(y, max: 120))」會把它移出 authorized"
        let remedy = x == nil ? "請先\(removal)" : "請先把那幾筆 reference 的 value 改成新的對外形（手改 YAML）、或\(removal)"   // display-safe-exempt: removal 是呼叫端的編譯期常量
        throw ServiceError.invalid(
            "\(subject)，但這筆 \(owner.noun) 有 \(pinned.count) 筆 `field: authorized` 的 reference 指著它——移出後它們成孤兒、寫入會被拒；"   // display-safe-exempt: subject 的名字逐項 displaySafeInvisible；owner.noun 是編譯期常量；count 是 Int
            + "程式不替人改判定。\(remedy)，再重跑")   // display-safe-exempt: remedy 由字面常量與呼叫端的編譯期常量組成
    }
}

extension AkashicService {
    /// 同一個名字既 `authorize` 又 `unauthorize` 是兩句矛盾的話（#559）——整批拒絕、零寫入。相等看 `NameIdentity.canonical`，與兩條腿的
    /// 定位同一條。venue 與 organization 的入口共用（`updateVenueArguments`／`updateOrganizationArguments`）。
    static func refuseAuthorizeUnauthorizeOverlap(authorizeIn: [String], unauthorizeIn: [String]) throws {
        let withdrawKeys = Set(unauthorizeIn.map(NameIdentity.canonical))
        let both = authorizeIn.filter { withdrawKeys.contains(NameIdentity.canonical($0)) }
        guard !both.isEmpty else { return }
        throw ServiceError.invalid(
            "「\(Self.listCapped(both) { displaySafeInvisible($0, max: 120) })」"
            + "同時被送進 authorize 與 unauthorize——那是兩句矛盾的話，請只說一句")
    }
}
