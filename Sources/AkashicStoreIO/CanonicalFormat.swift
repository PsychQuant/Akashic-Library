import Foundation
import AkashicCore

/// 讓 encoder 以外的寫入者能把記錄對齊 canonical form（#69）。
///
/// ## 這不是「第二份 canonical form 的定義」
///
/// design D3 明文否決了獨立的 normalizer 型別——encoder 已是 canonical form 的唯一
/// 定義，第二份定義漂移時無人能判斷誰對，那正是本 change 要修的病。
///
/// 這個型別**沒有定義任何東西**：正規化就是字面上的 `encode(decode(x))`，寫在下面的
/// `normalized(_:)` 裡一行一個 case。它是**走訪器**——知道 store 有哪些目錄、檔案怎麼
/// 分派到哪個 decoder、失敗怎麼累積。把那些從命令搬進 library 的理由是可測試性：
/// executable target 的符號測試 target 匯入不到（沿用 `AuthorizedNameMigration` 的
/// 既有形狀）。
public enum CanonicalFormat {

    public struct Failure: Equatable {
        public let file: String
        public let reason: String
    }

    public struct Report: Equatable, CustomStringConvertible {
        /// 走訪過的檔案數。
        public var scanned: Int = 0
        /// 偏離 canonical form 的檔名（`apply` 與否都會填）。
        public var deviating: [String] = []
        /// 實際被改寫的檔名（`apply: false` 時必為空）。
        public var rewritten: [String] = []
        /// 讀不進來或寫不出去的檔案。
        public var failures: [Failure] = []

        /// 退出碼該不該非零。**偏離也算問題**——`--check` 的用途正是當關卡。
        public var hasProblems: Bool { !deviating.isEmpty || !failures.isEmpty }

        public var description: String {
            "Report(scanned: \(scanned), deviating: \(deviating), "
            + "rewritten: \(rewritten), failures: \(failures))"
        }
    }

    /// 走訪 store 的所有記錄，回報（或改寫）偏離 canonical form 者。
    ///
    /// - Parameter apply: `false` ＝ 只比對，**不開啟任何檔案的寫入控制代碼**。
    ///
    /// **單筆失敗不中止整輪**：一個壞檔會讓其餘幾百筆的正規化全部做不成，而使用者
    /// 拿到的訊息只有第一個錯誤。失敗累積在 `failures`，由呼叫端決定退出碼。
    public static func scan(store: LibraryStore, apply: Bool) throws -> Report {
        var report = Report()
        for url in try recordFiles(in: store) {
            report.scanned += 1
            let name = url.lastPathComponent
            let original: String
            do {
                original = try String(contentsOf: url, encoding: .utf8)
            } catch {
                report.failures.append(Failure(file: name, reason: "讀不到檔案：\(describe(error))"))
                continue
            }
            let canonical: String
            do {
                canonical = try normalized(original)
            } catch {
                report.failures.append(Failure(file: name, reason: describe(error)))
                continue
            }
            guard canonical != original else { continue }
            report.deviating.append(name)
            guard apply else { continue }
            do {
                try store.atomicWrite(canonical, to: url)
                report.rewritten.append(name)
            } catch {
                report.failures.append(Failure(file: name, reason: "寫不回去：\(describe(error))"))
            }
        }
        report.deviating.sort()
        report.rewritten.sort()
        return report
    }

    /// 正規化 ＝ `encode(decode(x))`。**這裡沒有第二份定義**，只有分派。
    static func normalized(_ yaml: String) throws -> String {
        switch try EntityKind.peek(yaml, strict: true) {
        case .work:
            let e = try EntryYAML.decode(yaml)
            try LibraryStore.assertNoErrors(e.validate(), what: "work", key: e.citekey)   // D79，理由見 .divergence
            return try EntryYAML.encode(e)
        case .person:
            // **語意驗證，不只 canonical encode**（#297 item 2）。
            //
            // `fmt --apply` 走 `store.atomicWrite` 直接落盤，**繞過 `writePerson`**
            // ——而語意約束（`authorized` ⊆ `names`、每書寫系統至多一個、兩分割互斥）
            // 只活在 `person.validate()` 裡，由呼叫端自行決定要不要跑。
            //
            // 這是與遷移同族的「第二條繞過寫入邊界的路」：遷移已在 #227 R1 修復納管，
            // `fmt` 當時漏了。沒有這道驗證，一個語意矛盾的 person 檔會被 `fmt` 原樣
            // 重排後寫回——排版對齊了，矛盾還在，而且現在看起來像是工具背書過的。
            //
            // 驗在這裡而非呼叫端：`normalized()` 是「解出型別值」與「寫回位元組」
            // 之間**唯一的交會點**，也是 `fmt` 對每個檔必經之處。放呼叫端就會有
            // 第三條繞過路。
            let person = try PersonYAML.decode(yaml)
            try LibraryStore.assertNoErrors(person.validate(), what: "person", key: person.key)
            return try PersonYAML.encode(person)
        case .organization:
            // 與 `.person`／`.venue` 同一條紀律（#554 R12 verify regression 第 32 列）：`Organization.validate()` 走 `AuthorizedNames.validate`
            // （authorized ⊆ names 等 error 級內容不變式），`assertOrganizationWritable` 用同一句收尾——三個同形的 shape 不能只修兩個。
            let org = try OrganizationYAML.decode(yaml)
            try LibraryStore.assertNoErrors(org.validate(), what: "organization", key: org.key)
            return try OrganizationYAML.encode(org)
        case .divergence:
            // 五個 shape 同一條紀律（R27 D79；R26 verify regression 第 39 列：R5／R12 說「三個同形的 shape 不能只修兩個」，那句指的是走 `AuthorizedNames`
            // 的三個，而 work／divergence 的 error 級檢查（citekey／候選 key 的形狀）對 fmt 仍不生效——`fmt --check` 對一筆 error 級不合法的 divergence
            // 印「✓ 全部已是 canonical form」）。判準不是「有沒有 AuthorizedNames」，是「validate() 有沒有 error 級檢查」：五個都有。
            let d = try DivergenceYAML.decode(yaml)
            try LibraryStore.assertNoErrors(d.validate(), what: "divergence", key: d.id.uuidString)
            return try DivergenceYAML.encode(d)
        case .venue:
            // 與 `.person` 同一條紀律（#554 R5 verify 第 9 列）：R5 之前這裡是裸 `encode(decode)`，
            // `validate` 報 2 條 error 的 store，`fmt --check` 印「✓ 全部已是 canonical form」、
            // `fmt --apply` 把髒 venue 原樣寫回 rc=0——D8 說「手改的在下一次寫入被擋」，
            // 對 fmt 是反例。上面那段對 person 的理由對 venue 一字不差。
            let venue = try VenueYAML.decode(yaml)
            try LibraryStore.assertNoErrors(venue.validate(), what: "venue", key: venue.key)
            return try VenueYAML.encode(venue)
        }
    }

    /// canonical 樹裡的所有記錄檔。
    ///
    /// **兩種佈局都走**：format ≥ 2 的 `entities/`，以及 legacy 的 `entries/` 與
    /// `people/`。判準不是「store 宣稱哪個 format」而是「磁碟上有什麼」——遷移中途
    /// 的 store 兩邊都有檔案，只走一邊會讓另一邊永遠對不齊。
    ///
    /// `libraries/` 不在內：registry 形狀沒有 timeline、不是 entity。把它納進來
    /// 要先回答「registry 的 canonical form 是什麼」，那是另一件事。
    static func recordFiles(in store: LibraryStore) throws -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for dir in [store.entitiesDir, store.entriesDir, store.peopleDir] {
            guard let items = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else { continue }
            out += items.filter { $0.pathExtension.lowercased() == "yaml" }
        }
        return out.sorted { $0.path < $1.path }
    }

    /// `Failure.reason` 在這裡消毒一次（R28 D80）：`invalidInput`／`StoreYAMLError` 自帶消毒、只截；讀寫的 I/O 錯誤逃脫一次。sink 只截。
    private static func describe(_ error: Error) -> String { displaySafeError(error, max: 512) }
}
