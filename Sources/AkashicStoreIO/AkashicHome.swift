import Foundation

/// Akashic home（`~/.akashic`）—— 機器本地的設定與衍生物之家（#37）。
///
/// **與 store root 的關係**：home 底下的 `entities/` 等 canonical 目錄屬於
/// **預設 store**（registry key `main`），亦即 `~/.akashic` 本身既是 home 也是
/// 該 store 的 root。設定與衍生物（`config.yaml`、`index/`）與 canonical 同層，
/// 由 store repo 的 `.gitignore` 排除——那是每個 data repo 都在做的標準做法，
/// 與 #37 反對的「一整個 git repo 巢狀在另一個 repo 目錄裡」不是同一件事。
///
/// **已知後果（照實記載）**：因為 `~/.akashic` 就是 `main` 的 store root（也是
/// git repo 根），**其他 store 不能放在 `~/.akashic/` 底下**——那會讓它們的
/// canonical 落進 `main` 的版控樹。額外 store 一律由 `akashic file add <key> <path>`
/// 指定 home 之外的路徑（Phase 4c 的 `path` 本來就是必填，不提供預設）。
public enum AkashicHome {
    /// `~/.akashic`。`$AKASHIC_HOME` 可覆寫（測試與多帳號情境的 escape hatch）。
    public static func directory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment["AKASHIC_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".akashic")
    }

    /// `~/.akashic/config.yaml`——registry（Phase 4c schema v2）。
    public static func configURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        directory(environment: environment).appendingPathComponent("config.yaml")
    }

    /// `~/.akashic/index/`——**已註冊** store 的衍生 index 之家。
    ///
    /// 為什麼不放在 store root 內（#37 裁定，推翻先前傾向）：
    /// 1. index 可重建（實測 536 entries 約 0.55 s）——帶著走沒有價值，而帶著
    ///    **過期**的 index 比沒有更糟。
    /// 2. store repo 本來就 `.gitignore` 掉它——那等於承認它不屬於 store；
    ///    搬出去只是讓實體符合概念。
    /// 3. **決定性理由**：store root 正是會進 Dropbox / git 的東西，而在同步樹裡
    ///    放 live SQLite 是已知的毀檔風險（partial write、conflict copy）。
    public static func indexDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        directory(environment: environment).appendingPathComponent("index")
    }

    /// 已註冊 store 的 index 路徑：`~/.akashic/index/<key>.sqlite`。
    ///
    /// 依 **registry key** 命名而非 path hash：registry 已是「誰住哪」的 single
    /// source，依 key 命名與它對齊，`ls ~/.akashic/index/` 一眼看得懂屬於誰。
    /// path hash 雖對未註冊 store 也成立，但代價是整個目錄不可讀——為罕見情境
    /// 犧牲常見情境。未註冊 store 改走 in-store 回落（見 `LibraryStore.indexURL`）。
    public static func indexURL(
        forKey key: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        indexDirectory(environment: environment).appendingPathComponent("\(key).sqlite")
    }
}
