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
        case .work:         return try EntryYAML.encode(try EntryYAML.decode(yaml))
        case .person:       return try PersonYAML.encode(try PersonYAML.decode(yaml))
        case .organization: return try OrganizationYAML.encode(try OrganizationYAML.decode(yaml))
        case .divergence:   return try DivergenceYAML.encode(try DivergenceYAML.decode(yaml))
        }
    }

    /// canonical 樹裡的所有記錄檔。
    ///
    /// **兩種佈局都走**：format ≥ 2 的 `entities/`，以及 legacy 的 `entries/` 與
    /// `people/`。判準不是「store 宣稱哪個 format」而是「磁碟上有什麼」——遷移中途
    /// 的 store 兩邊都有檔案，只走一邊會讓另一邊永遠對不齊。
    ///
    /// `libraries/` 與 `notes/` 不在內：前者的 registry 形狀沒有 timeline、後者不是
    /// entity。把它們一起走要先回答「它們的 canonical form 是什麼」，那是另一件事。
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

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
