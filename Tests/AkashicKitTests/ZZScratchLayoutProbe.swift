import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicIndex

/// SCRATCH — review probe, delete after running.
final class ZZScratchLayoutProbe: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func entry(_ ck: String, id: UUID = UUID()) -> Entry {
        Entry(id: id, citekey: ck, type: "article", title: "T",
              authors: [.literal("X")], date: "2020")
    }
    private func legacyStore() throws -> LibraryStore {
        let fm = FileManager.default
        for d in ["entries", "people", "libraries"] {
            try fm.createDirectory(at: root.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        try StoreVersion.write(root: root, format: 1)
        return LibraryStore(root: root)
    }

    /// A fresh `git clone` of a migrated store has NO entries/ dir (git drops empty dirs).
    func testClonedFormat2StoreIsNotRecognisedAsLibrary() throws {
        let store = try legacyStore()
        try store.writeEntry(entry("a2020a"))
        try store.writePerson(Person(key: "p-one", names: ["A"]))
        _ = try StoreMigration.toEntities(store: store)
        // simulate git clone: empty dirs are not tracked, so they do not exist
        try FileManager.default.removeItem(at: store.entriesDir)
        try FileManager.default.removeItem(at: store.peopleDir)
        print("PROBE-F isLibraryRoot(migrated clone) = \(LibraryStore.isLibraryRoot(root))")
        print("PROBE-F load() still works: entries=\(try store.load().entries.count)")
    }

    /// MCP staleness detector watches entries/ + people/ only.
    func testStalenessDetectorBlindToEntities() throws {
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writeEntry(entry("a2020a"))
        _ = try LibraryIndex(store: store).rebuild()
        let fm = FileManager.default
        Thread.sleep(forTimeInterval: 1.1)
        // external change: a new entity file appears (git pull / CLI / App)
        try store.writeEntry(entry("b2021b"))
        let indexM = (try fm.attributesOfItem(atPath: store.indexURL.path)[.modificationDate]) as! Date
        var newest = Date.distantPast
        for dir in [store.entriesDir, store.peopleDir] {
            if let d = (try? fm.attributesOfItem(atPath: dir.path)[.modificationDate]) as? Date, d > newest { newest = d }
            for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                if let m = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, m > newest { newest = m }
            }
        }
        print("PROBE-G indexMtime=\(indexM) newestWatched=\(newest) → wouldRebuild=\(newest > indexM)")
        print("PROBE-G actual store now has \(try store.load().entries.count) entries; index has 1")
    }

    /// Migration with a pre-existing duplicate UUID in legacy entries/.
    func testMigrationCollapsesDuplicateUUIDs() throws {
        let store = try legacyStore()
        let shared = UUID()
        try store.writeEntry(entry("a2020a", id: shared))
        try store.writeEntry(entry("b2021b", id: shared))
        print("PROBE-H before: entries=\(try store.load().entries.count) files=\(try FileManager.default.contentsOfDirectory(atPath: store.entriesDir.path).sorted())")
        let r = try StoreMigration.toEntities(store: store)
        print("PROBE-H report entriesMoved=\(r.entriesMoved)")
        print("PROBE-H after: entities files=\(try FileManager.default.contentsOfDirectory(atPath: store.entitiesDir.path).sorted())")
        print("PROBE-H after: load entries=\(try store.load().entries.map(\.citekey))")
    }

    /// Migration when legacy deletion fails (read-only legacy file / locked by sync).
    func testMigrationSwallowsLegacyDeleteFailure() throws {
        let store = try legacyStore()
        try store.writeEntry(entry("a2020a"))
        let fm = FileManager.default
        // make entries/ non-writable so removeItem fails
        try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: store.entriesDir.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.entriesDir.path) }
        let r = try StoreMigration.toEntities(store: store)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.entriesDir.path)
        print("PROBE-I report=\(r) format=\(try StoreVersion.read(root: root))")
        print("PROBE-I entries/ leftover=\(try fm.contentsOfDirectory(atPath: store.entriesDir.path))")
        let load = try store.load()
        print("PROBE-I load entries=\(load.entries.count) quarantined=\(load.quarantined.count)")
        do { _ = try LibraryIndex(store: store).rebuild(); print("PROBE-I rebuild OK") }
        catch { print("PROBE-I rebuild THREW: \(error)") }
    }
}
