import Foundation
import AkashicCore
import AkashicStoreIO

public struct ImportReport: Equatable {
    public var created: [String] = []
    public var updated: [String] = []
    public var orphaned: [String] = []
    public var unchanged: Int = 0
    /// 解析過的作者被保留、未跟 Zotero 同步的 entries（資訊性）。
    public var authorsPreserved: [String] = []

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

        let zoteroKeys = Set(items.map(\.key))

        for item in items {
            if var existing = byZoteroKey[item.key] {
                guard let prov = existing.provenance else { continue }
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
                    try store.writeEntry(existing)
                    report.updated.append(existing.citekey)
                } else {
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
                try store.writeEntry(entry)
                report.created.append(citekey)
            }
        }

        // Orphan 偵測：store 有 provenance 但 Zotero 已無此 key
        for entry in load.entries {
            guard var prov = entry.provenance, !zoteroKeys.contains(prov.zoteroKey),
                  prov.orphanedAt == nil else { continue }
            var orphan = entry
            prov.orphanedAt = now
            orphan.provenance = prov
            try store.writeEntry(orphan)
            report.orphaned.append(orphan.citekey)
        }

        report.created.sort()
        report.updated.sort()
        report.orphaned.sort()
        report.authorsPreserved.sort()
        return report
    }
}
