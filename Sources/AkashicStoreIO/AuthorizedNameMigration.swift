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
/// | 多個候選、恰一個非引用形 | 提名 | 引用形是索引系統的產物，不是他的名字 |
/// | 仍然多於一個 | 留空並報告 | 那是真的要人判斷 |
///
/// 形狀與既有的補資料紀律一致：**答案唯一就做，多選一就停下給人看**。預設 dry-run。
public enum AuthorizedNameMigration {

    /// 對一組名字的提名結果。
    public struct Proposal: Equatable {
        /// 該書寫系統只有一個候選——直接採用。
        public var adopted: [String] = []
        /// 多個候選中恰一個非引用形——提名。
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
            if real.count == 1 {
                out.nominated.append(real[0])
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
    @discardableResult
    public static func run(store: LibraryStore, apply: Bool = false) throws -> Report {
        let load = try store.load()
        // #227 verify S1：quarantined 檔在 → 本工具**看不見**那些人（load 已把它們
        // 排除），迭代 0 人、回報成功、末尾把 marker bump 到 supported——在未遷移的
        // store 上那會鎖死唯一還讀得懂資料的舊 binary，而且**回報成功**。fail-fast，
        // 兩種模式都擋（dry-run 的報告對看不見的記錄同樣是誤導）。
        guard load.quarantined.isEmpty else {
            throw StoreIOError.invalidInput(
                what: "authorize-names",
                why: "store 有 \(load.quarantined.count) 個讀不進來的檔（可能是未遷移的"
                   + "舊形狀 person）——本工具看不見它們，跑完會誤把 marker 升到 "
                   + "\(StoreVersion.supported)。先跑 akashic migrate-person-identity，"
                   + "再跑本工具（akashic doctor 可看每個檔的原因）")
        }
        var report = Report()
        report.total = load.people.count
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
            guard apply, !plan.authorized.isEmpty else { continue }
            var updated = person
            // #227：指定是把名字**搬進** authorized 分割，不是複製——同一字串留在
            // variant 會在序列化裡出現兩次，違反「每個名字恰好出現一次」。
            updated.names.authorized = plan.authorized
            updated.names.variant = updated.names.variant.filter { !plan.authorized.contains($0) }
            _ = try store.writePerson(updated)
        }
        report.undecidedKeys.sort()
        // 寫入後 store 就**帶著新語意**了：`authorized` 指定了對外名字，而 `names` 的順序
        // 不再帶語意。marker 必須跟上——否則舊 binary 會載入這個 store 並繼續把 `names[0]`
        // 當顯示名（按舊語意解讀新格式），正是 refuse-if-newer 要擋的情境。
        //
        // `ensureLayout` 刻意不覆寫既有 marker（那可能是更新的版本寫的），所以升級只能
        // 由這裡這種**明確的遷移動作**做。
        if apply {
            try StoreVersion.write(root: store.root, format: StoreVersion.supported)
        }
        return report
    }
}
