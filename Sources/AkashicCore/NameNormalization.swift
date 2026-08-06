import Foundation

/// 名字的配對用正規化（#81 Expected 四）。
///
/// **用於配對，永不用於判定。** `matchingKey` 的輸出是比對鍵，不是資料：同 key
/// 只代表「值得提名給人看」（`PersonResolver` 的候選層），不代表同一人；任何寫回
/// store 的路徑都必須用原字串。#81 的三層區分——正規化（可機械）／身分（要人判斷）
/// ／正規形（要權威指定）——這裡只做第一層，越界即違反「絕不自動合併」鐵律。
///
/// 消費端（下游報表）各自手刻 `gsub` 的狀態由此退役：正規化只有這一份定義。
public enum NameNormalization {

    /// NFKC → 連字號家族統一 → 空白收斂 → 大小寫摺疊。
    ///
    /// 連字號要**顯式**映射：NFKC 對 U+2010–U+2014 與 U+2212 是恆等（相容分解
    /// 只處理全形與相容字元），而 WoS／出版商匯出裡這些變體全部實際出現過——
    /// `Chang, Y‐H.`（U+2010）與 `Chang, Y-H.`（ASCII）在位元組上是兩個字串，
    /// 在命名上是同一個寫法。
    public static func matchingKey(_ s: String) -> String {
        let nfkc = s.precomposedStringWithCompatibilityMapping
        let hyphenFamily: Set<Character> = ["\u{2010}", "\u{2011}", "\u{2012}",
                                            "\u{2013}", "\u{2014}", "\u{2212}"]
        let unified = String(nfkc.map { hyphenFamily.contains($0) ? "-" : $0 })
        // split(whereSeparator:) 吃所有 Unicode 空白（NBSP 已被 NFKC 轉普通空格，
        // 但 ideographic space 等仍靠這裡收斂）——同時完成 trim 與塌縮
        return unified.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
