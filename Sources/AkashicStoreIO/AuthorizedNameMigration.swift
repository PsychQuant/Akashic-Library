import Foundation
import AkashicCore

/// 為既有記錄補上對外可稱呼的名字（#81）。
///
/// **`authorized` 是指定，不是推導。** 但提名可以機械化，而且**判斷只在候選多於一個時
/// 才發生**——這條區分是本工具存在的理由：
///
/// | 情況 | 處置 | 為什麼 |
/// |---|---|---|
/// | 某書寫系統只有一個候選 | 直接採用 | 沒有可挑的餘地，不構成判斷 |
/// | 多個候選、消去**引用形與縮寫形**後恰一個 | 提名 | 兩者都是索引／排版系統的產物，不是他的名字（#552）|
/// | 存活者只差排印（大小寫／標點／連字號） | 提名一個寫法 | 沒有第二個名字可挑，只有第二種寫法 |
/// | 仍然多於一個 | 留空並報告 | 那是真的要人判斷 |
///
/// 形狀與既有的補資料紀律一致：**答案唯一就做，多選一就停下給人看**。預設 dry-run。
public enum AuthorizedNameMigration {

    /// 對一組名字的提名結果。
    public struct Proposal: Equatable {
        /// 該書寫系統只有一個候選——直接採用。
        public var adopted: [String] = []
        /// 消去引用形與縮寫形（#552）後恰一個名字——提名。只差排印的一組也走這裡。
        public var nominated: [String] = []
        /// 仍然歧義的書寫系統——留空，交給人。
        public var undecided: [WritingSystem] = []

        /// 可以寫進記錄的 `authorized`（採用 ＋ 提名）。
        public var authorized: [String] { adopted + nominated }
    }

    /// 對一組名字提名 `authorized`。**純函數**——不碰 store，方便單獨測。
    public static func propose(names: [String]) -> Proposal {
        var byScript: [WritingSystem: [String]] = [:]
        for n in names where !n.trimmingCharacters(in: .whitespaces).isEmpty {
            byScript[WritingSystem.of(n), default: []].append(n)
        }
        var out = Proposal()
        // 依 rawValue 排序讓輸出在不同機器上一致（Dictionary 沒有順序）。
        for (script, candidates) in byScript.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            if candidates.count == 1 {
                out.adopted.append(candidates[0])
                continue
            }
            let real = candidates.filter { !NameForm.isCitationForm($0) }
            // #552：**縮寫形與引用形是同一種東西**——都是索引／排版系統的產物，不是
            // 他的名字。上面那張表的第二列理由逐字適用，所以在同一個位置消去。
            let survivors = real.filter { c in
                !real.contains { $0 != c && NameForm.isAbbreviation(c, of: $0) }
            }
            if survivors.count == 1 {
                out.nominated.append(survivors[0])
            } else if survivors.count > 1,
                      survivors.dropFirst().allSatisfy({ NameForm.rendersSameName($0, survivors[0]) }) {
                // 存活者只差排印——**沒有第二個名字可挑，只有第二種寫法**。留空等於
                // 要人回答一個沒有內容的問題。挑哪一種寫法的順序見 `preferredRendering`。
                if let pick = NameForm.preferredRendering(among: survivors) {
                    out.nominated.append(pick)
                } else {
                    out.undecided.append(script)
                }
            } else {
                out.undecided.append(script)
            }
        }
        return out
    }

    /// 全 store 的執行結果。
    public struct Report: Equatable {
        public var adopted = 0
        public var nominated = 0
        public var undecided = 0
        /// 已經有 `authorized` 的記錄——不重複提名，也不覆寫既有指定。
        public var alreadyDesignated = 0
        /// 掃過的 person 記錄總數。
        ///
        /// **與上面三個計數不能直接相加**：那三個是**逐書寫系統**的（一個雙語的人會同時
        /// 貢獻一筆採用與一筆提名），這裡是**逐人**的。可相加的是下面三個逐人計數。
        public var total = 0
        // 下面四個逐人計數**互斥且窮盡**：相加等於 `total`。
        /// 每個書寫系統都有指定、沒有留下歧義的人數。
        public var peopleFullyDesignated = 0
        /// 至少一個書寫系統仍歧義的人數（可能同時已拿到別的書寫系統的指定）。
        public var peopleUndecided = 0
        /// 完全沒有可用名字的人數（`names` 全空）。
        public var peopleWithoutNames = 0
        /// 仍然歧義的記錄 key（依字典序），給報告用。
        public var undecidedKeys: [String] = []
    }

    /// 對整個 store 跑一次提名。`apply: false`（預設）只回報，不寫。
    ///
    /// **不覆寫既有的 `authorized`**：那是人做過的判斷，機械提名沒有資格推翻它。
    ///
    /// **判定記錄**（#564）：`apply: true` 必附 `judgement`（整批一句——本面沒有逐人或逐名的形式），每個寫入的 person、每個被採用或
    /// 提名的名字各一筆 `field: authorized` 的「指定：理由」（`NameClassificationRecord`），不帶證據（一個批次共用同一組 digest 等於宣稱每個人的
    /// 名字都依據同一份文件）。需要 store format ≥ 22——寫入閘擋，而且在任何一筆寫入之前（preflight）。乾跑不需要理由。
    @discardableResult
    public static func run(store: LibraryStore, apply: Bool = false, judgement: String? = nil) throws -> Report {
        let reason = judgement?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if apply {
            try checkApplyJudgement(judgement)
        }
        let load = try store.load()
        // #227 verify S1：quarantined 檔在 → 本工具**看不見**那些人（load 已把它們
        // 排除），迭代 0 人而**回報成功**（當時 apply 末尾還會把 marker bump 到 supported，
        // #564 起不再寫 marker）。fail-fast，兩種模式都擋；訊息依模式說各自真實的後果
        // （R2 C7），並先指路 doctor（quarantine 未必是舊形狀 person——可能是損壞的
        // work/org，先看原因再決定跑哪支）。
        guard load.quarantined.isEmpty else {
            // #564 起本工具不再寫 marker——apply 的後果不再是「升 marker」，而是那些人不會被指定、報告照樣不完整
            let consequence = apply
                ? "跑完它們不會被指定、報告也漏掉它們（看起來全部處理完了）"
                : "報告會漏掉它們（誤導性的不完整）"
            throw StoreIOError.invalidInput(
                what: "authorize-names",
                why: "store 有 \(load.quarantined.count) 個讀不進來的檔——本工具看不見它們，"
                   + "\(consequence)。先跑 akashic doctor 看每個檔的原因；"
                   + "若是未遷移的舊形狀 person，跑 akashic migrate-person-identity 後再回來")
        }
        var report = Report()
        report.total = load.people.count
        var toWrite: [Person] = []   // 先算完整個寫入集合，才決定寫不寫（#641）
        for person in load.people {
            guard person.names.authorized.isEmpty else {
                report.alreadyDesignated += 1
                continue
            }
            let plan = propose(names: person.names.all)
            report.adopted += plan.adopted.count
            report.nominated += plan.nominated.count
            // 互斥分類：歧義優先（有歧義就算歧義，即使別的書寫系統已指定），
            // 其次「全部指定完」，最後「根本沒有名字」。
            if !plan.undecided.isEmpty {
                report.undecided += plan.undecided.count
                report.peopleUndecided += 1
                report.undecidedKeys.append(person.key)
            } else if !plan.authorized.isEmpty {
                report.peopleFullyDesignated += 1
            } else {
                report.peopleWithoutNames += 1
            }
            guard !plan.authorized.isEmpty else { continue }
            var updated = person
            // #227：指定是把名字**搬進** authorized 分割，不是複製——同一字串留在
            // variant 會在序列化裡出現兩次，違反「每個名字恰好出現一次」。
            updated.names.authorized = plan.authorized
            updated.names.variant = updated.names.variant.filter { !plan.authorized.contains($0) }
            if apply {
                NameClassificationRecord.append(plan.authorized.map {
                    NameClassificationRecord.make(field: NameClassificationRecord.authorizedField, name: $0,
                                                  action: .designate, reason: reason, restsOn: [])
                }, to: &updated.references)
            }
            toWrite.append(updated)
        }
        // #641：apply 逐筆寫 person、最後才 bump marker。其中一筆寫入時被 #631 拒絕（legacy 殘留加上 quarantine、兩份並存、
        // 不能安全搬移），前面的指定已經落盤而 marker 沒 bump——舊 binary 會照舊語意讀新格式，正是 marker 要擋的情境。
        // 寫入集合裡有無法唯一定位的，就在第一次寫入之前整批拒絕（乾跑照常出報告：它看得到那些人，報告是完整的）。
        if apply {
            let unlocatable = load.people.unlocatablePersonKeys
            let blocked = toWrite.map(\.key).filter { unlocatable.contains($0) }
            guard blocked.isEmpty else {
                let shown = blocked.prefix(20).map { displaySafeInvisible($0, max: 120) }.joined(separator: "、")
                throw StoreIOError.invalidInput(
                    what: "authorize-names",
                    why: "要寫的 person 裡有 \(blocked.count) 筆無法唯一定位（\(UnlocatableReason.person)）："   // display-safe-exempt: blocked.count 是 Int；UnlocatableReason 是常數字面
                       + "\(shown)\(blocked.count > 20 ? "…" : "")——寫到一半會留下已指定卻沒 bump marker 的 store，"   // display-safe-exempt: shown 已逐項 displaySafeInvisible
                       + "整批拒絕、零寫入；先修好再跑（#641）")
            }
            // #648 C2b verify：writePerson 在寫入當下跑的每一道（含 encode 與讀取上限）先對整個寫入集合跑一次——上面只擋了
            // #641 的那一類，一筆寫出後超過讀取上限的 person 仍會在中途被拒、前面的指定已落盤而 marker 沒 bump
            for updated in toWrite { try store.preflightWrite(updated) }
            for updated in toWrite { _ = try store.writePerson(updated) }
        }
        report.undecidedKeys.sort()
        // **不再寫 marker**（#564）。這裡原本在結尾無條件把 marker 寫成 `StoreVersion.supported`——#81 的理由是寫入之後 store 帶著
        // format 5 的語意（`authorized` 指定對外名字、`names` 的順序不再帶語意）。那一步如今對正確性已無作用：person 的寫入閘保證
        // 任何寫入都發生在 format ≥ 10 的 store（巢狀 names，涵蓋 5 的語意），名字分類記錄又要求 ≥ 22；留著它，在沒有人要寫的 store
        // 上（2026-10-01 live store 4,575/4,575 已有 authorized）`--apply` 會把 marker 從 18 安靜地升到 22——跳過 19–21 的升級前置、
        // 鎖掉還沒升級的 binary，而升 marker 是使用者的動作（部署順序：三個 binary 先升，再手動改 marker）。
        return report
    }

    /// `--apply` 的理由檢查（#564）——CLI 的 `validate()` 呼叫同一個函式，用法錯誤早於開 store（#654）。
    public static func checkApplyJudgement(_ judgement: String?) throws {
        let reason = judgement?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !reason.isEmpty else {
            throw StoreIOError.invalidInput(
                what: "authorize-names --apply",
                why: "必附 --judgement（#564）：每個寫入的名字各留一筆「指定：理由」的判定記錄（field: authorized）；"
                    + "本面沒有逐人或逐名的形式，這一句套用到整批。乾跑不需要理由")
        }
        guard reason.utf8.count <= LibraryStore.maxStatementBytes else {
            throw StoreIOError.invalidInput(
                what: "authorize-names --judgement",
                why: "超過 \(LibraryStore.maxStatementBytes) 位元組（實得 \(reason.utf8.count)）——精簡它；不截斷")   // display-safe-exempt: LibraryStore.maxStatementBytes 與 reason.utf8.count 都是 Int
        }
    }
}
