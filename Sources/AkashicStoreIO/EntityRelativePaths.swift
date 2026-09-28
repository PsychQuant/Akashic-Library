import Foundation

public extension LibraryStore {
    /// `entities/` 裡每個以 UUID 為名的記錄檔：id → 以 store root 為基準的相對路徑，檔名保留磁碟上的大小寫（#573 R1）。
    ///
    /// 可回溯性閘（`filesNotSafelyRecoverable`）要的是**磁碟上的實際檔名**：load 接受小寫 UUID 檔名，git 的 pathspec 分大小寫，
    /// 由 id 拼成大寫會對一個已 commit 的檔永遠回「未被追蹤」。原本住在 `AkashicService`；#609 讓 App 的裁決台也要用同一支閘，
    /// 搬到這裡——兩份列舉會分岔（`no-compat-fallback` §「同一件事只能有一份描述」）。
    static func entityRelativePaths(root: URL) -> [UUID: String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("entities").path)) ?? []
        var out: [UUID: String] = [:]
        for name in names where name.lowercased().hasSuffix(".yaml") {
            if let id = UUID(uuidString: String(name.dropLast(5))) { out[id] = "entities/" + name }
        }
        return out
    }
}
