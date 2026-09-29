import Foundation

/// Python `difflib.SequenceMatcher` 的移植（#629）——只含 `ratio()` 與 `find_longest_match()`。
///
/// **為什麼不用別的相似度演算法**：`crossref_match.py` 的四個門檻（標題 0.92／0.85、期刊 0.75／0.95／0.70）與
/// `verify_pdf.py` 的 CJK 回報分數，都是拿 `SequenceMatcher` 的輸出量出來的。換一個相似度（Levenshtein、Jaccard）
/// 等於把所有門檻作廢重新校準；照搬演算法才能讓「移植後行為不變」有意義。
///
/// 逐行對應 CPython 3.13 的 `Lib/difflib.py`：
/// - `__chain_b`：建 `b2j`（元素 → 在 b 出現的位置，升冪）；`autojunk` 開且 `len(b) >= 200` 時，出現次數超過
///   `len(b) // 100 + 1` 的元素視為「熱門」、從 `b2j` 刪掉（但不算 junk，仍可在最長比對的兩端延伸）；
/// - `find_longest_match`：在 `[alo, ahi) × [blo, bhi)` 內找最長比對，平手取最早的 `i` 再取最早的 `j`；
/// - `get_matching_blocks`：遞迴切左右兩半、排序、合併相鄰區塊；
/// - `ratio`：`2.0 * matches / (len(a) + len(b))`，兩邊皆空時為 1.0。
///
/// 元素是 Unicode scalar（Python `str` 的元素是 code point）。沒有 `isjunk` 參數——兩個呼叫端都傳 `None`。
struct PySequenceMatcher {
    let a: [UInt32]
    let b: [UInt32]
    private var b2j: [UInt32: [Int]] = [:]

    init(_ a: Scalars, _ b: Scalars, autojunk: Bool = true) {
        self.a = a.map(\.value)
        self.b = b.map(\.value)
        for (i, e) in self.b.enumerated() { b2j[e, default: []].append(i) }
        let n = self.b.count
        if autojunk, n >= 200 {
            let ntest = n / 100 + 1
            for (e, idxs) in b2j where idxs.count > ntest { b2j[e] = nil }
        }
    }

    struct Match: Equatable { var a: Int; var b: Int; var size: Int }

    func findLongestMatch(alo: Int, ahi: Int, blo: Int, bhi: Int) -> Match {
        var besti = alo, bestj = blo, bestsize = 0
        var j2len: [Int: Int] = [:]
        var i = alo
        while i < ahi {
            var newj2len: [Int: Int] = [:]
            if let js = b2j[a[i]] {
                for j in js {
                    if j < blo { continue }
                    if j >= bhi { break }
                    let k = (j2len[j - 1] ?? 0) + 1
                    newj2len[j] = k
                    if k > bestsize {
                        besti = i - k + 1
                        bestj = j - k + 1
                        bestsize = k
                    }
                }
            }
            j2len = newj2len
            i += 1
        }
        // 沒有 junk 元素（isjunk=None），Python 的兩段「吸收 junk」迴圈都是空操作；
        // 但「熱門」元素不在 b2j 裡，兩端延伸要把它們接回來。
        while besti > alo, bestj > blo, a[besti - 1] == b[bestj - 1] {
            besti -= 1; bestj -= 1; bestsize += 1
        }
        while besti + bestsize < ahi, bestj + bestsize < bhi, a[besti + bestsize] == b[bestj + bestsize] {
            bestsize += 1
        }
        return Match(a: besti, b: bestj, size: bestsize)
    }

    func matchingBlocks() -> [Match] {
        var queue = [(0, a.count, 0, b.count)]
        var blocks: [Match] = []
        while let (alo, ahi, blo, bhi) = queue.popLast() {
            let m = findLongestMatch(alo: alo, ahi: ahi, blo: blo, bhi: bhi)
            if m.size > 0 {
                blocks.append(m)
                if alo < m.a, blo < m.b { queue.append((alo, m.a, blo, m.b)) }
                if m.a + m.size < ahi, m.b + m.size < bhi { queue.append((m.a + m.size, ahi, m.b + m.size, bhi)) }
            }
        }
        blocks.sort { ($0.a, $0.b, $0.size) < ($1.a, $1.b, $1.size) }
        var merged: [Match] = []
        var cur = Match(a: 0, b: 0, size: 0)
        for m in blocks {
            if cur.a + cur.size == m.a, cur.b + cur.size == m.b {
                cur.size += m.size
            } else {
                if cur.size > 0 { merged.append(cur) }
                cur = m
            }
        }
        if cur.size > 0 { merged.append(cur) }
        return merged
    }

    func ratio() -> Double {
        let total = a.count + b.count
        guard total > 0 else { return 1.0 }
        let matches = matchingBlocks().reduce(0) { $0 + $1.size }
        return 2.0 * Double(matches) / Double(total)
    }
}
