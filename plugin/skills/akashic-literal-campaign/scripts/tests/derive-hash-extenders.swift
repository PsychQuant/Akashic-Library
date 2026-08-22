// 列舉「緊跟在 `#` 後面會讓 Swift 的 hasPrefix("#") 變成 false」的 code point。
//
// 為什麼要生成而不是手寫
// ======================
// 讀端判註解用 `line.hasPrefix("#")`，而 Swift 的 String 比較以 **Character
// （grapheme cluster）** 為單位。census 是 Python，標準庫沒有 grapheme 分段。
//
// #407 的第 9 輪用「Unicode general category（Mn/Mc/Me）＋ 四段硬編範圍」去近似，
// 並在旁邊寫下「那正是分歧的充要形狀」。跨模型審查把它兩個方向都否證了：
//
//   * 漏 103 個（fail-open：讀端拒開的 store 被印得跟健康的逐字相同）
//     —— U+200C ZWNJ（Cf）、U+0E33/U+0EB3 泰／寮文 SARA AM（Lo，GB9a SpacingMark）、
//        U+1F3FB–FF emoji modifier（Sk）、U+FF9E/FF9F 半形濁音（Lm）…
//   * 多含 31 個 Mc（反向誤擋：叫使用者去修一個完全健康的檔）
//     —— Unicode 把這 31 個 Mc 排除在 GCB=SpacingMark 之外，讀端不併入 cluster。
//
// **加不完，而且會隨 Unicode 版本漂移。** 所以改成：由 Swift 自己生成那個集合，
// Python 端讀生成的表，另有一支測試每次重新生成並比對——漂移會變紅，不會安靜。
//
// 用法
// ====
//   swift derive-hash-extenders.swift > hash-merging-ranges.txt
//
// **只有這一種模式。** 早期的註解還寫過 `--check <表>` 可以比對漂移，而實作從頭
// 到尾沒讀過 CommandLine.arguments——傳什麼參數都只是重印一次表並以 0 結束。
// 一個照著註解跑 `--check` 的維護者會以為「檢查過了、沒問題」，即使表已經漂移
// （#407 R10 verify）。比對由 tests/hash-table-drift.sh 用重導向 + diff 做。
import Foundation

var ranges: [(UInt32, UInt32)] = []
var start: UInt32?
var prev: UInt32 = 0

for cp in UInt32(1)...0x10FFFF {
    // surrogate 不是合法 scalar，跳過
    guard let scalar = Unicode.Scalar(cp) else { continue }
    let probe = "#" + String(scalar) + "x"
    let merged = !probe.hasPrefix("#")
    if merged {
        if start == nil { start = cp }
        prev = cp
    } else if let s = start {
        ranges.append((s, prev))
        start = nil
    }
}
if let s = start { ranges.append((s, prev)) }

let total = ranges.reduce(0) { $0 + Int($1.1 - $1.0 + 1) }
print("# 由 derive-hash-extenders.swift 生成——**不要手改**。")
print("# 語意：這些 code point 緊跟在 `#` 後面時，Swift 的 hasPrefix(\"#\") 為 false，")
print("# 也就是讀端**不**把那一行當註解（→ 未知的頂層行 → 整檔拒開）。")
print("# 共 \(ranges.count) 段 / \(total) 個 code point。")
print("# 格式：每行兩個十六進位（含端點）。")
for (lo, hi) in ranges {
    print(String(format: "%X %X", lo, hi))
}
