import Foundation
import AkashicCore
import AkashicStoreIO

public struct ImportReport: Equatable {
    public var created: [String] = []
    public var updated: [String] = []
    public var orphaned: [String] = []
    /// Zotero 端復原、orphan 標記被清除的 entries。
    public var orphanCleared: [String] = []
    public var unchanged: Int = 0
    /// 解析過的作者被保留、未跟 Zotero 同步的 entries（資訊性）。
    public var authorsPreserved: [String] = []
    /// 未映射而被捨棄的 Zotero 欄位（欄位名 → 出現次數）。不靜默流失。
    public var droppedFields: [String: Int] = [:]
    /// 寫入目的檔是 quarantined 檔而被拒寫的 citekeys（損壞 store，人工處理）。
    public var quarantineConflicts: [String] = []

    public init() {}
}

/// Zotero → Akashic 單向 pull。
///
/// Diff 規則（spec §6.1）：
/// - 新 zotero_key → 建新 entry（citekey 生成、UUID 配發、tags seed）
/// - 已有 key 且 Zotero 版本較新 → 只更新 biblatex 欄位 + provenance；akashic 不動
/// - store 有、Zotero 已刪 → 標 orphaned（不自動刪，人工裁決）
/// - 版本相同 → unchanged
public struct ZoteroImporter {
    let store: LibraryStore

    public init(store: LibraryStore) {
        self.store = store
    }

    public func run(zoteroDB: URL, now: Date = Date()) throws -> ImportReport {
        let items = try ZoteroReader.readItems(dbPath: zoteroDB.path)
        let load = try store.load()

        var report = ImportReport()
        var byZoteroKey: [String: Entry] = [:]
        var existingCitekeys = Set<String>()
        for entry in load.entries {
            existingCitekeys.insert(entry.citekey)
            if let key = entry.provenance?.zoteroKey {
                byZoteroKey[key] = entry
            }
        }
        // quarantined 檔的 basename 佔住 citekey——否則新 entry 生成同名 key
        // 時會覆寫使用者的（暫時損壞的）檔案。這是 canonical data-loss 防線。
        // lowercase 比對：macOS 檔案系統常見 case-insensitive，大寫 basename
        // 與 lowercase citekey 仍指向同一檔案。
        var quarantinedBasenames = Set<String>()
        for q in load.quarantined where q.file.hasPrefix("entries/") {
            let basename = String(q.file.dropFirst("entries/".count))
            if basename.hasSuffix(".yaml") {
                let stem = String(basename.dropLast(".yaml".count))
                quarantinedBasenames.insert(stem.lowercased())
                existingCitekeys.insert(stem.lowercased())
            }
        }
        // 每一次寫入前的 destination guard：目的檔屬 quarantined 集合 → 拒寫、報告。
        // 不能只靠 citekey allocator——update/orphan 路徑不經 allocator。
        func guardedWrite(_ entry: Entry, report: inout ImportReport) throws -> Bool {
            if quarantinedBasenames.contains(entry.citekey.lowercased()) {
                if !report.quarantineConflicts.contains(entry.citekey) {
                    report.quarantineConflicts.append(entry.citekey)
                }
                return false
            }
            try store.writeEntry(entry)
            return true
        }

        let zoteroKeys = Set(items.map(\.key))

        for item in items {
            for dropped in ZoteroMapping.unmappedFields(of: item) {
                report.droppedFields[dropped, default: 0] += 1
            }
            if var existing = byZoteroKey[item.key] {
                guard let prov = existing.provenance else { continue }
                // Zotero 端存在＝非 orphan：不論版本，先清 orphan 標記（存在性獨立於版本比較）
                var orphanWasCleared = false
                if prov.orphanedAt != nil {
                    var restored = existing
                    restored.provenance?.orphanedAt = nil
                    if try guardedWrite(restored, report: &report) {
                        existing = restored
                        report.orphanCleared.append(existing.citekey)
                        orphanWasCleared = true
                    }
                }
                if item.version > prov.zoteroVersion {
                    let hadResolvedAuthors = existing.authors.contains {
                        if case .key = $0 { return true } else { return false }
                    }
                    ZoteroMapping.applyBiblatexFields(from: item, to: &existing)
                    if hadResolvedAuthors {
                        // 解析成果（person key）是使用者確認過的衍生知識，pull 不摧毀
                        report.authorsPreserved.append(existing.citekey)
                    } else {
                        existing.authors = item.authors.map { .literal($0.display) }
                    }
                    existing.provenance = Provenance(
                        zoteroKey: item.key, zoteroVersion: item.version,
                        importedAt: now, orphanedAt: nil)
                    if try guardedWrite(existing, report: &report) {
                        report.updated.append(existing.citekey)
                    }
                } else if !orphanWasCleared {
                    report.unchanged += 1
                }
            } else {
                let citekey = Citekey.generate(
                    familyName: item.authors.first?.family,
                    year: item.fields["date"],
                    title: item.fields["title"],
                    existing: existingCitekeys)
                existingCitekeys.insert(citekey)
                var entry = Entry(id: UUID(), citekey: citekey, type: "misc", title: "")
                ZoteroMapping.applyBiblatexFields(from: item, to: &entry)
                entry.authors = item.authors.map { .literal($0.display) }
                entry.provenance = Provenance(
                    zoteroKey: item.key, zoteroVersion: item.version, importedAt: now)
                entry.akashic.tags = item.tags   // 只在建檔時 seed；後續 pull 不動
                if try guardedWrite(entry, report: &report) {
                    report.created.append(citekey)
                }
            }
        }

        // Orphan 偵測：store 有 provenance 但 Zotero 已無此 key
        for entry in load.entries {
            guard var prov = entry.provenance, !zoteroKeys.contains(prov.zoteroKey),
                  prov.orphanedAt == nil else { continue }
            var orphan = entry
            prov.orphanedAt = now
            orphan.provenance = prov
            if try guardedWrite(orphan, report: &report) {
                report.orphaned.append(orphan.citekey)
            }
        }

        report.created.sort()
        report.updated.sort()
        report.orphaned.sort()
        report.orphanCleared.sort()
        report.authorsPreserved.sort()
        report.quarantineConflicts.sort()
        return report
    }
}
