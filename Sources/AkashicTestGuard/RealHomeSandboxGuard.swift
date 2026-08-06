import Foundation
import XCTest

/// Process-level 沙箱守衛（#124）：整輪測試期間，真實 `~/.akashic` 的**任何異動**
/// 都讓 run 立即失敗，並指出發生在哪個測試區間。
///
/// **為什麼需要 process 層**：既有守衛全是測試側的（正面斷言 `indexURL` 目的地、
/// `sandboxStore` 統一構造）——擋得住「測試自己構造錯」，擋不住**模型側**回歸
/// （被測程式內部重新構造 `LibraryStore` 時弄丟 environment → 寫入先打中真實
/// index，測試才在沙箱檔缺席上變紅——損害已造成）。本週三次逃逸 + #123 verify
/// F6/F7 都是同一形狀。本守衛不在乎逃逸從哪條路來：真實 home 動了就是動了。
///
/// **兩層偵測**：
/// - 逐測輕量探針（少數關鍵路徑的 mtime/size）——`testCaseWillStart` 時比對，
///   異動立即 `onViolation`（預設 `fatalError`，stop-the-world：讓後續測試
///   繼續跑只會擴大污染、稀釋歸因）
/// - bundle 結束全樹指紋——抓輕量探針漏掉的深層變動（成本一輪只付一次）
///
/// **基線在首次啟用時記錄**：activation class（各 test target 的
/// `AAASandboxGuardActivationTests`，AAA 前綴讓字母序最先跑）觸發註冊。
/// 真實 home 不存在（CI runner）也是合法基線——結束時「長出來了」同樣是逃逸。
public final class RealHomeSandboxGuard: NSObject, XCTestObservation {
    public static let shared = RealHomeSandboxGuard()

    /// 違規處置。預設 stop-the-world；測試（守衛自測）可注入收集版。
    public var onViolation: (String) -> Void = { message in
        fatalError("🚨 真實 ~/.akashic 在測試期間被改動——沙箱逃逸\n\(message)")
    }

    private let guarded: URL
    private var registered = false
    private var quickBaseline: [String: String] = [:]
    private var fullBaseline: [String: String] = [:]
    private var lastBoundary = "（第一個測試之前）"

    override private init() {
        guarded = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".akashic")
        super.init()
    }

    /// 冪等註冊 + 基線記錄（首次呼叫時）。
    public func activate() {
        guard !registered else { return }
        registered = true
        quickBaseline = Self.quickProbe(root: guarded)
        fullBaseline = Self.fingerprint(root: guarded)
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    // MARK: - XCTestObservation

    public func testCaseWillStart(_ testCase: XCTestCase) {
        let now = Self.quickProbe(root: guarded)
        if now != quickBaseline {
            violate(diff: Self.describeDiff(baseline: quickBaseline, current: now),
                    layer: "輕量探針")
        }
        lastBoundary = testCase.name
    }

    public func testBundleDidFinish(_ testBundle: Bundle) {
        let now = Self.fingerprint(root: guarded)
        if now != fullBaseline {
            violate(diff: Self.describeDiff(baseline: fullBaseline, current: now),
                    layer: "全樹指紋")
        }
    }

    private func violate(diff: String, layer: String) {
        onViolation("""
            偵測層：\(layer)
            最後通過檢查的邊界：\(lastBoundary) 之後
            \(diff)
            """)
    }

    // MARK: - 指紋（純函式，可測）

    /// 少數關鍵路徑的便宜探針（逐測付得起）：root/index 目錄與三個高風險檔。
    static func quickProbe(root: URL) -> [String: String] {
        let targets = [root,
                       root.appendingPathComponent("index"),
                       root.appendingPathComponent("index/main.sqlite"),
                       root.appendingPathComponent("config.yaml"),
                       root.appendingPathComponent("store.yaml"),
                       root.appendingPathComponent(".akashic")]
        var out: [String: String] = [:]
        for url in targets {
            out[url.lastPathComponent + ":" + url.path] = stamp(url)
        }
        return out
    }

    /// 全樹 (relative path → mtime/size)。root 不存在 → 空表（合法基線——
    /// 結束時長出任何東西都是逃逸）。
    static func fingerprint(root: URL) -> [String: String] {
        var out: [String: String] = [:]
        guard let e = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: []) else { return out }
        for case let url as URL in e {
            let rel = url.path.dropFirst(root.path.count)
            out[String(rel)] = stamp(url)
        }
        return out
    }

    private static func stamp(_ url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return "absent"
        }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
        let size = (attrs[.size] as? Int) ?? -1
        return "\(mtime)/\(size)"
    }

    /// 兩份指紋的差異描述（新增/消失/變動各列前幾筆，供違規訊息歸因）。
    static func describeDiff(baseline: [String: String], current: [String: String]) -> String {
        let added = Set(current.keys).subtracting(baseline.keys).sorted()
        let removed = Set(baseline.keys).subtracting(current.keys).sorted()
        let changed = baseline.keys.filter { current[$0] != nil && current[$0] != baseline[$0] }.sorted()
        func head(_ xs: [String], _ label: String) -> String {
            xs.isEmpty ? "" : "\(label)（\(xs.count)）：\(xs.prefix(5).joined(separator: ", "))\n"
        }
        let body = head(added, "新增") + head(removed, "消失") + head(changed, "變動")
        return body.isEmpty ? "（無可列差異——指紋不等但集合相同？）" : body
    }
}
