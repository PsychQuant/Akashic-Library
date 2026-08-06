import Foundation
import XCTest

/// Process-level 沙箱偵測器（#124）：測試期間，真實 `~/.akashic` 的異動讓 run
/// 立即失敗並盡可能歸因。
///
/// **為什麼需要 process 層**：既有守衛全是測試側的（正面斷言 `indexURL` 目的地、
/// `sandboxStore` 統一構造）——擋得住「測試自己構造錯」，擋不住**模型側**回歸
/// （被測程式內部重新構造 `LibraryStore` 時弄丟 environment → 寫入先打中真實
/// index，測試才在沙箱檔缺席上變紅——損害已造成）。本週三次逃逸 + #123 verify
/// F6/F7 都是同一形狀。本偵測器不在乎逃逸從哪條路來：真實 home 動了就是動了。
///
/// **啟用機制（#124 verify F1/F5）**：`AkashicTestGuardLoader` 的 C constructor
/// 在 test bundle 載入時呼叫 `akashic_test_guard_activate`——早於 XCTest 排程、
/// 涵蓋 `--filter` 與 `--parallel`（每個 worker process 各自啟用、各自記基線）。
/// 曾經用「字母序最先的 activation 測試」啟用：`--filter` 沒選中它＝零保護、
/// `--parallel` 下 activation 自己住一個 process＝其餘 720+ 測試全裸奔——皆靜默。
///
/// **兩層偵測**：
/// - 逐測輕量探針（root 與 `index/` 的**淺層內容**動態枚舉——不寫死檔名；
///   #101 的靶心是 `index/<key>.sqlite`，key 是什麼都要抓到）——
///   `testCaseWillStart` 比對，違規即 `onViolation`（預設 `fatalError`）
/// - bundle 結束全樹指紋（root 自身含在內；`absent`／`error` 是不同的 sentinel，
///   「不存在」「空目錄」「枚舉失敗」三態不混同）
///
/// **誠實邊界（一個偵測器能與不能的事，#124 verify 兩席收斂）**：
/// - **這是 best-effort detector，不是完備 boundary。** 完備要靠寫入阻斷
///   （OS sandbox／專用測試帳號）；`homeDirectoryForCurrentUser` 走 getpwuid、
///   不看 `$HOME`，測試 process 內無法整體改道
/// - 指紋是 (mtime, size)：**改寫後復原**、metadata-preserving 的同尺寸覆寫、
///   xattr/權限變更，偵測不到
/// - `testBundleDidFinish` 不是 finally：run 中途 crash 時全樹兜底不會跑
///   （逐測探針涵蓋到 crash 點為止）
/// - **symlink 目標不追蹤**（enumerator 不進 symlinked 目錄、stat 是 lstat）
///   ——cycle／跨裝置風險大於現況收益；真實 home 目前零 symlink
/// - `.git/` **刻意排除**：真實 `~/.akashic` 是 live git repo，`git status`
///   這類「唯讀」操作都會動 `.git/index`——把使用者在另一個終端的正常操作
///   當逃逸殺掉整輪，比漏掉 `.git` 內的異動更糟（測試沒有理由碰它）
/// - 違規**來源未知**：可能是測試逃逸，也可能是外部程序（編輯器／同步／
///   使用者操作 store）。訊息如實說，不預設有罪
/// - swift-testing（`@Test`）在獨立 process 跑，不在本偵測器保護內
public final class RealHomeSandboxGuard: NSObject, XCTestObservation {
    public static let shared = RealHomeSandboxGuard()

    /// 違規處置。預設 stop-the-world（本 process）；守衛自測可注入收集版。
    /// 註：`--parallel` 下只殺當前 worker——那正是「detector 非 boundary」的一例。
    public var onViolation: (String) -> Void = { message in
        fatalError("""
            🚨 真實 ~/.akashic 在測試期間被改動
            \(message)
            來源未知：可能是測試的沙箱逃逸，也可能是外部程序（git／編輯器／同步／
            你自己在另一個終端動了 store）。若確定是後者，重跑即可；若無法排除
            前者，先找出是哪個測試——不要停用守衛。
            """)
    }

    /// constructor 接線是否完成（activation 測試以此釘住 loader 的存活）。
    public private(set) var isActive = false

    private let guarded: URL
    private let lock = NSLock()
    private var quickBaseline: [String: String] = [:]
    private var fullBaseline: [String: String] = [:]
    private var lastBoundary = "（第一個測試之前）"
    private var activatedAt = "（未啟用）"

    override private init() {
        // resolvingSymlinksInPath：/var vs /private/var 這類前綴差異會讓相對鍵
        // 被錯切（#128 verify F7）——真實 home 無此問題，但守衛不該依賴這點
        guarded = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".akashic").resolvingSymlinksInPath()
        super.init()
    }

    /// 冪等啟用：基線兩層**連續**拍完才註冊 observer（順序反過來會有
    /// 「自認註冊了、observer 還不在」的窗口——#128 verify Codex-8）。
    public func activate() {
        lock.lock()
        defer { lock.unlock() }
        guard !isActive else { return }
        quickBaseline = Self.quickProbe(root: guarded)
        fullBaseline = Self.fingerprint(root: guarded)
        activatedAt = ISO8601DateFormatter().string(from: Date())
        XCTestObservationCenter.shared.addTestObserver(self)
        isActive = true
    }

    // MARK: - XCTestObservation

    public func testCaseWillStart(_ testCase: XCTestCase) {
        let now = Self.quickProbe(root: guarded)
        if now != quickBaseline {
            onViolation("""
                偵測層：輕量探針（root 與 index/ 淺層）
                區間：「\(lastBoundary)」之後、「\(testCase.name)」之前
                \(Self.describeDiff(baseline: quickBaseline, current: now))
                """)
        }
        lastBoundary = testCase.name
    }

    public func testBundleDidFinish(_ testBundle: Bundle) {
        let now = Self.fingerprint(root: guarded)
        if now != fullBaseline {
            // 全樹層自啟用後沒有中途檢查點——可歸因區間就是整輪，
            // 用 lastBoundary 會指控無辜的最後一個測試（#128 verify Codex-12）
            onViolation("""
                偵測層：全樹指紋（兜底）
                區間：啟用（\(activatedAt)）至 bundle 結束之間的某時點
                \(Self.describeDiff(baseline: fullBaseline, current: now))
                """)
        }
    }

    // MARK: - 指紋（純函式，可測）

    /// 便宜探針（逐測付得起）：root 自身 + root 淺層子項 + `index/` 淺層子項。
    /// **動態枚舉，不寫死檔名**——#101 的靶心是 `index/<key>.sqlite`，寫死
    /// `main.sqlite` 只在 key 恰好叫 main 時抓得到（#128 verify F3）。
    static func quickProbe(root rawRoot: URL) -> [String: String] {
        // resolvingSymlinksInPath 在**純函式內**做（不只 init）：/var vs /private/var
        // 這類前綴差異會把相對鍵錯切（#128 verify F7）——自測跑在 temp 路徑上，
        // 正是這個形狀；健壯性屬於函式自己，不屬於呼叫端的自律
        let root = rawRoot.resolvingSymlinksInPath()
        var out: [String: String] = ["/": stamp(root)]
        for dir in [root, root.appendingPathComponent("index")] {
            let children = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for name in children where name != ".git" {
                let url = dir.appendingPathComponent(name)
                out[String(url.path.dropFirst(root.path.count))] = stamp(url)
            }
        }
        return out
    }

    /// 全樹 (相對路徑 → stamp)。root 自身以 `"/"` 為鍵——「不存在」「空目錄」
    /// 「枚舉失敗」是三個**不同**的值，不得都塌縮成空表（#128 verify Codex-6）。
    /// `.git/` 子樹排除（見類別 doc 的誠實邊界）。
    static func fingerprint(root rawRoot: URL) -> [String: String] {
        let root = rawRoot.resolvingSymlinksInPath()   // 同 quickProbe 的 F7 理由
        var out: [String: String] = ["/": stamp(root)]
        guard FileManager.default.fileExists(atPath: root.path) else { return out }
        guard let e = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: []) else {
            out["/"] = "enumeration-error"
            return out
        }
        while let item = e.nextObject() {
            guard let url = item as? URL else { continue }
            let rel = String(url.resolvingSymlinksInPath().path.dropFirst(root.path.count))
            if rel == "/.git" || rel.hasPrefix("/.git/") {
                e.skipDescendants()
                continue
            }
            out[rel] = stamp(url)
        }
        return out
    }

    private static func stamp(_ url: URL) -> String {
        // attributesOfItem 是 lstat——symlink 記的是連結自身（目標不追蹤，見誠實邊界）
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return FileManager.default.fileExists(atPath: url.path) ? "stat-error" : "absent"
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

/// C constructor 的進入點（`AkashicTestGuardLoader/loader.c`）。
@_cdecl("akashic_test_guard_activate")
public func akashicTestGuardActivate() {
    RealHomeSandboxGuard.shared.activate()
}
