import Foundation
import AkashicCore

/// 把 `TemporalValue.source` 裡的 `sha256:` 摘要搬進 `references:`（#146）。
///
/// ## 為什麼存在這個第三種狀態
///
/// #66（`references:`）落地**之前**，手工路徑已經把 digest 塞進了 `source`——那個
/// 欄位的設計形式是**裸 URL**。digest 進去之後，隨之而來的 `retrieved`／`media-type`
/// ／`origin` 沒有地方放，於是另外長出 `sources/index.jsonl` 這個手工 sidecar。
/// 結果是「provenance 記在哪一層」有兩個答案——**正是 #66 要消除的病，在實作前就
/// 先發生了**。
///
/// ## 它們是 `judgement`，不是 `retrieval`（讀了資料才知道）
///
/// 直覺會說「有 digest 有 retrieved，那就是擷取型」。**錯的。** 真實資料（2026-08-08
/// 唯讀盤點，22 筆）每一筆的 `note` 都以「由…推得」開頭：
///
///     source: sha256:0a9a79d3…
///     note:   由論文作者機構字串推得：Bioinformatics Program, Institute of
///             Statistical Science…。統計所是該學程的 host institute；此為學程
///             關係、非所內研究人員任用，未宣稱任期區間
///
/// 那是**對一份證據的推理**，不是一次擷取——`note` 是斷言、digest 是它所依據的
/// 內容。對應 `Kind.judgement(statement:restsOn:)`，一對一。
///
/// 而且擷取型**也裝不下它們**：`retrieval` 要求 `url` 與 `status`，但 `index.jsonl`
/// 的 7 筆沒有一筆有 URL（`origin` 是散文、`acquisition` 是 `file`／`api`／`api+web`）。
/// 「圖書館寄來的檔案」沒有 URL 可言，「以 DOI 逐筆查詢 Europe PMC 與 Crossref」
/// 也不是單一 URL。**先前判斷這需要第三種 Kind，是只看 `index.jsonl` 的形狀、
/// 沒讀 `note` 得出的結論。讀了資料就不需要新 Kind。**
///
/// ## 不動的東西
///
/// - **裸 URL 形式的 `source` 一律不動**（實測 137 筆）。#66 的 D7 Non-Goal 明列
///   不改 `TemporalValue.source` 的既有用法；本次只清掉**不屬於那個欄位**的形式。
/// - **`sources/index.jsonl` 不動。** 它描述的是 **blob 本身**（bytes／media-type
///   ／取得方式），不是「某個欄位的 provenance」——那是**目錄**，與 `references:`
///   不是同一種東西。22 筆共用同一個 digest，把 blob 的描述複寫 22 次才是錯的。
///   它該從手工 sidecar 升格為設計內的產物，那是另一個 change（見 #146 收工說明）。
/// - **格式不變。** `references:` 自 #66 起就在 format 7 的契約內，本遷移只搬內容，
///   不 bump `StoreVersion`——舊 binary 讀得懂遷移後的檔案（`§5.0` 的判準是
///   「舊 binary 會不會誤讀」，不是「後果多嚴重」）。
public enum ProvenanceMigration {

    public struct Skip: Equatable {
        public let record: String
        public let field: String
        public let reason: String
    }

    public struct Report: Equatable {
        /// 搬成 reference 的 temporal value 數。
        public var migrated: Int = 0
        /// 被改寫的記錄 key（排序）。
        public var records: [String] = []
        /// **搬不動的，逐筆列出而不是靜默略過。** 靜默略過會讓「遷移完成」與
        /// 「遷移完成但有 N 筆還在舊形式」看起來一樣。
        public var skipped: [Skip] = []
    }

    /// 一筆待搬的 digest source。
    private struct Pending {
        let field: String
        let value: String
        let digest: String
        let statement: String
    }

    /// 從一條 timeline 抽出待搬項，並就地清掉它們的 `source`／`note`。
    ///
    /// 泛型是必要的而非炫技：`affiliations`／`parents` 是 `TimelineOf<OrgRef>`、
    /// 其餘是 `TimelineOf<String>`。**只處理 `affiliations` 會留下靜默缺口**——
    /// 真實資料目前只有那裡有 digest，但那是今天的事實，不是不變式。
    private static func drain<V>(_ timeline: inout TimelineOf<V>, field: String,
                                 record: String, display: (V) -> String,
                                 into pending: inout [Pending],
                                 skipped: inout [Skip]) {
        for i in timeline.entries.indices {
            guard let source = timeline.entries[i].source,
                  source.hasPrefix("sha256:") else { continue }
            let value = display(timeline.entries[i].value)
            guard ProvenanceReference.isValidDigest(source) else {
                skipped.append(Skip(record: record, field: field,
                                    reason: "digest 形狀不合法（sha256: + 64 小寫 hex）："
                                            + displaySafe(source, max: 120)))
                continue
            }
            // **沒有 note 就不搬。** `judgement` 要求 statement 非空，而斷言的內容
            // 只能來自人——這裡憑空生一句（「來源為 <digest>」之類）會製造一筆看起來
            // 有依據、實際上什麼都沒說的 provenance，比留在舊形式更糟。
            guard let note = timeline.entries[i].note, !note.isEmpty else {
                skipped.append(Skip(record: record, field: field,
                                    reason: "沒有 note——judgement 需要斷言，"
                                            + "而斷言的內容不能由遷移程式代寫"))
                continue
            }
            pending.append(Pending(field: field, value: value,
                                   digest: source, statement: note))
            timeline.entries[i].source = nil
            timeline.entries[i].note = nil
        }
    }

    private static func references(from pending: [Pending]) throws -> [ProvenanceReference] {
        try pending.map {
            // 走 throwing 建構器而非 `.init(field:value:kind:)`——驗證住在那裡，
            // 繞過它等於讓遷移寫出一筆載入時會被拒的記錄（#66 D6）。
            try ProvenanceReference(
                field: $0.field, value: $0.value,
                url: nil, retrieved: nil, status: nil, mediaType: nil, content: nil,
                judgement: $0.statement, restsOn: [$0.digest])
        }
    }

    /// 掃描整個 store，把 digest 形式的 `source` 搬進 `references:`。
    ///
    /// `dryRun` 只回報、不寫檔。**先跑 dry-run 是建議而非強制**——這個遷移是
    /// 內容改寫，store 的消歧 gate 那種「tracked 且 clean」的前提在這裡不適用，
    /// 所以可回溯性由使用者的版控負責，而 CLI 會提醒。
    public static func digestSourcesToReferences(store: LibraryStore,
                                                 dryRun: Bool) throws -> Report {
        var report = Report()
        let load = try store.load()

        for var person in load.people {
            var pending: [Pending] = []
            // **欄位名帶 `profile.` 前綴**——那是 `validateReferenceAttachment` 的
            // 白名單用的形式（#66 task 3.3）。用不帶前綴的名字寫出來的 reference
            // 在載入時會被拒；這是寫測試時被那道驗證抓出來的，不是讀 code 想到的。
            drain(&person.profile.affiliations, field: "profile.affiliations", record: person.key,
                  display: { $0.displayName }, into: &pending, skipped: &report.skipped)
            drain(&person.profile.ranks, field: "profile.ranks", record: person.key,
                  display: { $0 }, into: &pending, skipped: &report.skipped)
            drain(&person.profile.administrative, field: "profile.administrative", record: person.key,
                  display: { $0 }, into: &pending, skipped: &report.skipped)
            drain(&person.profile.appointments, field: "profile.appointments", record: person.key,
                  display: { $0 }, into: &pending, skipped: &report.skipped)
            drain(&person.profile.fields, field: "profile.fields", record: person.key,
                  display: { $0 }, into: &pending, skipped: &report.skipped)
            // **contacts 搬不了，而且不是疏漏。** `validateReferenceAttachment` 的
            // 白名單沒有 `profile.contacts.*`，且**加進去會讓舊 binary 拒絕載入**
            // 整個 store（unknown field → throw），那比誤讀更嚴重，需要格式 bump。
            // 格式 bump 不在 #146 的範圍。真實資料裡 contacts 沒有 digest，所以
            // 這是一條理論上的路徑——**但要報出來，不能靜默略過**。
            for key in person.profile.contacts.keys.sorted() {
                for e in person.profile.contacts[key]!.entries
                where e.source?.hasPrefix("sha256:") == true {
                    report.skipped.append(Skip(
                        record: person.key, field: "profile.contacts.\(key)",
                        reason: "references: 的欄位白名單不含 contacts——加進去會讓舊 binary "
                                + "拒絕載入，需要格式 bump（見 #146 收工說明）"))
                }
            }
            guard !pending.isEmpty else { continue }
            person.references += try references(from: pending)
            report.migrated += pending.count
            report.records.append(person.key)
            if !dryRun { try store.writePerson(person) }
        }

        for var org in load.organizations {
            var pending: [Pending] = []
            drain(&org.names, field: "names", record: org.key,
                  display: { $0 }, into: &pending, skipped: &report.skipped)
            drain(&org.parents, field: "parents", record: org.key,
                  display: { $0.displayName }, into: &pending, skipped: &report.skipped)
            guard !pending.isEmpty else { continue }
            org.references += try references(from: pending)
            report.migrated += pending.count
            report.records.append(org.key)
            if !dryRun { try store.writeOrganization(org) }
        }

        report.records.sort()
        return report
    }

    /// 殘留檢查（`doctor` 用）：還有哪些 `source` 是 digest 形式。
    ///
    /// 遷移之後這應該回空。**它與遷移分開存在**是刻意的——遷移是一次性動作，
    /// 而「`TemporalValue.source` 只放裸 URL」是一條要**持續**成立的不變式，
    /// 新寫入隨時可能再破壞它。
    public static func residualDigestSources(load: LibraryLoad) -> [Skip] {
        var out: [Skip] = []
        func scan<V>(_ t: TimelineOf<V>, field: String, record: String) {
            for e in t.entries where e.source?.hasPrefix("sha256:") == true {
                out.append(Skip(record: record, field: field,
                                reason: "source 是 digest 形式，應改記於 references:（#146）"))
            }
        }
        for p in load.people {
            scan(p.profile.affiliations, field: "profile.affiliations", record: p.key)
            scan(p.profile.ranks, field: "profile.ranks", record: p.key)
            scan(p.profile.administrative, field: "profile.administrative", record: p.key)
            scan(p.profile.appointments, field: "profile.appointments", record: p.key)
            scan(p.profile.fields, field: "profile.fields", record: p.key)
            for k in p.profile.contacts.keys.sorted() {
                scan(p.profile.contacts[k]!, field: "profile.contacts.\(k)", record: p.key)
            }
        }
        for o in load.organizations {
            scan(o.names, field: "names", record: o.key)
            scan(o.parents, field: "parents", record: o.key)
        }
        return out
    }
}
