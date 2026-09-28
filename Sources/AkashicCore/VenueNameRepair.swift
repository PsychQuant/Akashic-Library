import Foundation

/// venue 名字不變式（`docs/store-format.md` §5.7，#554 D8）的**機械修復計畫**（#575，使用者 2026-09-28 裁決）。
///
/// ## 為什麼需要它
///
/// `Venue.validate()` 對名字內容的違反是 error 級，而 `assertVenueWritable` 以 error 收尾——一筆違反的 venue **所有**寫入面都關門；
/// `fmt` 也拒絕帶 error 的記錄（它的語意是對齊 canonical 序列化，不是修內容）。於是舊 binary 寫出來的 `"Psychometrika "`、NFD 位元組
/// 的名字，唯一的修法是手改 YAML——`replace-endnote-and-zotero` 第 4 條要記成缺口的那種。
///
/// ## 只改確定性的那一類（封閉：四個條件同時成立，規範文字在 §5.7——兩處要一起改）
///
/// 1. 字串違反的是第 1 條（不是 canonical 形），而且**只**有它——`NameIdentity.canonical` 的結果非空、通過 `wellFormednessIssue`；
/// 2. 沒有 `field: names`／`field: authorized` 的 reference 指著這個拼法（位元組相同）——改寫會讓那筆 provenance 的 value 對不上，
///    而它要不要跟著改是判斷（程式不替人改判定，#554 R33 對 `authorize` 的同一立場）；
/// 3. 這一筆 venue **全部**確定性改寫做完之後，`Venue.validate()` 沒有 error——沒有造出近重複（第 4 條，連同沿革段的豁免都照
///    store 自己的定義判）、authorized ⊆ names 與兩個分割的互斥都還成立。一筆記錄只要還有一項 error，它就寫不進去，
///    所以那筆的確定性改寫**全部延後**、一起列出來；
/// 4. 改寫之後 reference 的附著驗證仍通過（第 2 條擋位元組相同的；這一條接住只差 canonical 等價、改寫後就對不上的那幾筆）。
///
/// 其餘——不可見或控制字元、沒有字母數字、空白、近重複對、正規化之後仍不合法、同一筆記錄的其他 error——**只具名與理由，不改**。
///
/// NFC 的**單一碼位替換**（CJK 相容表意文字 U+FA10 → U+585A 一類）是位元組層有損的——它仍是 canonical 形的定義、仍算確定性，
/// 但改動說明逐碼位說出來（`singletonReplacements`），讓乾跑過目的人知道自己同意的是換碼位，不只是換編碼。
///
/// ## 為什麼是程式編輯（`two-kinds-of-edits`）
///
/// canonical 形的改寫同輸入必得同輸出：空白不是名字的一部分、NFC 不改 Swift 的相等（`NameIdentity` 的收錄條件）。
/// 改完的記錄再跑一次得到空計畫（冪等）。要判斷的東西——刪哪個字元、近重複留哪一筆、reference 要不要跟著改——不在這裡做。
///
/// 本檔只算計畫（純函式，`Venue -> Plan?`）；載入、寫入閘、git 可回溯閘、落盤在 `AkashicService.repairVenueNames`。
public enum VenueNameRepair {

    /// 一筆確定性改寫。`before`／`after` 是 store 的原字串——**未消毒**，輸出面自己逃脫。
    public struct Rewrite: Equatable {
        /// `names`／`authorized`／`variant`
        public let list: String
        /// 在那張清單裡的位置（`names` 是時間軸 entries 的序列化順序）
        public let index: Int
        public let before: String
        public let after: String
        /// 改了什麼（人讀、固定句）：未 NFC、前導空白、尾隨空白、內部空白
        public let changes: [String]
    }

    /// 一項要人判斷、本命令不改的東西。
    public struct Judgment: Equatable {
        public enum Subject: Equatable {
            /// 某張清單裡的一個字串——`value` 是 store 的原字串，**未消毒**
            case value(list: String, index: Int, value: String)
            /// 整筆記錄層級（validate 的其他 error、reference 附著）
            case record
        }
        public let subject: Subject
        /// 理由。來源只有兩種，都已經是可以直接印的文字：`NameIdentity.wellFormednessIssue` 的固定訊息（含 U+ 十六進位），
        /// 或 `Venue.validate()` 的訊息（生產端已逐項 `displaySafeInvisible`）。
        public let reason: String
    }

    public struct Plan: Equatable {
        public let key: String
        public let id: UUID
        /// 確定性改寫。`repaired == nil` 時它們**延後**——同一筆記錄還有判斷項，寫不進去。
        public let rewrites: [Rewrite]
        public let judgments: [Judgment]
        /// 套用全部改寫之後的記錄——只在沒有任何判斷項、且至少有一筆改寫時有值（那時它通過 `validate()`）。
        public let repaired: Venue?
    }

    static let lists = ["names", "authorized", "variant"]

    /// 三張清單的 store 原字串（清單名 → 字串，`names` 依時間軸 entries 的序列化順序）。計畫的內部資料，不是輸出面。
    static func values(_ v: Venue) -> [String: [String]] {
        ["names": v.names.entries.map(\.value), "authorized": v.authorized, "variant": v.variant]   // display-safe-exempt: 計畫的內部資料（清單名 → store 原字串），不進任何輸出面；輸出面各自逃脫
    }

    /// 一筆 venue 的修復計畫。名字內容沒有違反（沒有字串違反第 1–3 條、三張清單都沒有 canonical 相同的兩筆）時回 `nil`；
    /// 只因為 `names` 有 canonical 相同的沿革段而進來、validate 又沒有 error 的，同樣回 `nil`。
    public static func plan(_ venue: Venue) -> Plan? {
        let before = values(venue)
        var rewrites: [Rewrite] = []
        var judgments: [Judgment] = []
        var replacement: [String: [Int: String]] = [:]
        for label in lists {
            for (i, s) in (before[label] ?? []).enumerated() {
                guard let why = NameIdentity.wellFormednessIssue(s) else { continue }
                let c = NameIdentity.canonical(s)
                // 空白、或本來就是 canonical 形（違反的是第 2／3 條）：它的理由就是那一句
                guard !c.isEmpty, Array(c.utf8) != Array(s.utf8) else {
                    judgments.append(Judgment(subject: .value(list: label, index: i, value: s), reason: why))
                    continue
                }
                if let still = NameIdentity.wellFormednessIssue(c) {
                    judgments.append(Judgment(subject: .value(list: label, index: i, value: s),
                                              reason: "正規化（空白、NFC）之後仍不合法：" + still))
                    continue
                }
                let pinned = venue.references.filter { r in
                    r.field == label && r.value.map { Array($0.utf8) == Array(s.utf8) } == true
                }
                if !pinned.isEmpty {
                    judgments.append(Judgment(
                        subject: .value(list: label, index: i, value: s),
                        reason: "有 \(pinned.count) 筆 `field: \(label)` 的 reference 指著這個拼法——改寫會讓它的 value 對不上；"   // display-safe-exempt: pinned.count 是 Int；label 是本函式的字面常量
                            + "reference 要不要跟著改是判斷（程式不替人改判定），先改或刪那幾筆 reference 的 value 再跑"))
                    continue
                }
                rewrites.append(Rewrite(list: label, index: i, before: s, after: c, changes: changes(from: s)))
                replacement[label, default: [:]][i] = c
            }
        }
        let collision = lists.contains { label in
            var seen = Set<String>()
            return (before[label] ?? []).contains { !seen.insert(NameIdentity.canonical($0)).inserted }
        }
        guard !rewrites.isEmpty || !judgments.isEmpty || collision else { return nil }

        var repaired = venue
        repaired.names = TimelineOf(venue.names.entries.enumerated().map { i, seg in
            guard let c = replacement["names"]?[i] else { return seg }
            var s = seg; s.value = c; return s
        })
        repaired.authorized = venue.authorized.enumerated().map { replacement["authorized"]?[$0.offset] ?? $0.element }
        repaired.variant = venue.variant.enumerated().map { replacement["variant"]?[$0.offset] ?? $0.element }

        // 改完之後仍然留著的 error 就是判斷項。逐字串的那幾則上面已經以更精確的理由具名過（例如「正規化之後仍含不可見字元」，
        // validate 會先說「不是 canonical 形」），用同一個訊息生產者辨認出來、不重報；「另有 N 個名字含不合法字元」的概括句同理。
        var perValue = Set<String>()
        let after = values(repaired)
        for label in lists {
            for s in after[label] ?? [] {
                if let why = NameIdentity.wellFormednessIssue(s) {
                    perValue.insert(Venue.wellFormednessMessage(key: venue.key, label: label, value: s, why: why))
                }
            }
        }
        let remaining = repaired.validate().filter { $0.severity == .error }
        for issue in remaining {
            if perValue.contains(issue.message) { continue }
            if issue.message.hasPrefix(Entry.perRecordCapSummaryPrefix) && issue.message.contains("個名字含不合法字元或形式") { continue }
            judgments.append(Judgment(subject: .record, reason: issue.message))
        }
        // 上面略過的那幾則，前提是「逐字串的迴圈已經具名過它們」。改完之後 validate 仍有 error 而一項判斷都沒有，就是那個前提
        // 不成立——照實列出、不寫，不讓一筆 validate 不過的記錄冒充可改（負控時真的走到過：拿掉「正規化之後仍不合法」那一支，
        // 改寫後的不可見字元被當成已具名而略過，計畫宣稱可寫）
        if judgments.isEmpty && !remaining.isEmpty {
            judgments += remaining.map { Judgment(subject: .record, reason: $0.message) }
        }
        // 附著驗證的安全網：上面的第 2 條擋的是位元組相同的 reference；Swift 的 `==` 另有 canonical 相等，這裡照 decode 的判準再問一次
        if judgments.isEmpty && !rewrites.isEmpty {
            do { try repaired.validateReferenceAttachment() } catch {
                judgments.append(Judgment(
                    subject: .record,
                    reason: "改寫之後這筆記錄的 reference 附著驗證不過（\(displaySafeError(error, max: 1_000))）——"
                        + "reference 要不要跟著改是判斷，本命令不動它"))
            }
        }
        guard !rewrites.isEmpty || !judgments.isEmpty else { return nil }
        return Plan(key: venue.key, id: venue.id, rewrites: rewrites, judgments: judgments,
                    repaired: judgments.isEmpty && !rewrites.isEmpty ? repaired : nil)
    }

    /// 人讀的改動說明。`s` 與 `canonical(s)` 的位元組不同時至少有一項——canonical 只做 NFC 與空白兩件事。
    static func changes(from s: String) -> [String] {
        var out: [String] = []
        let nfc = s.precomposedStringWithCanonicalMapping
        if Array(nfc.utf8) != Array(s.utf8) {
            let swaps = singletonReplacements(in: s)
            if swaps.isEmpty {
                out.append("未 NFC（改成預組形）")
            } else {
                let shown = swaps.prefix(5).joined(separator: "、") + (swaps.count > 5 ? "…共 \(swaps.count) 個" : "")   // display-safe-exempt: swaps 是十六進位碼位對（U+[0-9A-F]+→U+[0-9A-F]+），不是 store 字串
                out.append("未 NFC，含單一碼位替換 \(shown)——原碼位的區別不保留（位元組層有損；Swift 的相等早已視為同一個）")   // display-safe-exempt: shown 是十六進位碼位對
            }
        }
        let scalars = Array(nfc.unicodeScalars)
        if let f = scalars.first, f.properties.isWhitespace { out.append("前導空白") }
        if let l = scalars.last, l.properties.isWhitespace { out.append("尾隨空白") }
        var run: [Unicode.Scalar] = []
        var seenNonSpace = false
        var inner = false
        for u in scalars {
            if u.properties.isWhitespace {
                if seenNonSpace { run.append(u) }
                continue
            }
            if seenNonSpace && !run.isEmpty && !(run.count == 1 && run[0] == " ") { inner = true }
            run = []
            seenNonSpace = true
        }
        if inner { out.append("內部空白（連續、tab 或非 U+0020 的空白）收成一個 U+0020") }
        return out
    }

    /// NFC 把**單一碼位**換成另一個的地方（canonical singleton：CJK 相容表意文字 U+FA10 塚 → U+585A、Ohm U+2126 → U+03A9、
    /// Angstrom U+212B → U+00C5）。一般的「分解形 → 預組形」只是同一個字的另一種編碼；這一類是**換了碼位**，原碼位的區別不保留
    /// ——`NameIdentity.canonical` 的誠實邊界（位元組層有損、Swift `==` 早已視為相等）。兩者在終端機上常常看起來一樣，
    /// 所以乾跑逐碼位說出來，讓過目的人知道自己同意的是什麼。
    static func singletonReplacements(in s: String) -> [String] {
        func hex(_ u: Unicode.Scalar) -> String {
            let h = String(u.value, radix: 16, uppercase: true)
            return "U+" + String(repeating: "0", count: max(0, 4 - h.count)) + h
        }
        var seen = Set<UInt32>()
        return s.unicodeScalars.compactMap { u in
            let n = Array(String(u).precomposedStringWithCanonicalMapping.unicodeScalars)
            guard n.count == 1, n[0] != u, seen.insert(u.value).inserted else { return nil }
            return hex(u) + "→" + hex(n[0])
        }
    }
}
