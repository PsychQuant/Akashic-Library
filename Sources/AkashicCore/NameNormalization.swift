import Foundation

/// 名字的配對用正規化（#81 Expected 四）。
///
/// **用於配對，永不用於判定。** `matchingKey` 的輸出是比對鍵，不是資料：同 key
/// 只代表「值得提名給人看」（`PersonResolver` 的候選層），不代表同一人；任何寫回
/// store 的路徑都必須用原字串。#81 的三層區分——正規化（可機械）／身分（要人判斷）
/// ／正規形（要權威指定）——這裡只做第一層，越界即違反「絕不自動合併」鐵律。
///
/// 消費端（下游報表）各自手刻 `gsub` 的狀態由此退役：正規化只有這一份定義
/// （`PersonResolver.normalize` 與 `PersonBootstrap.normalize` 都指到這裡——
/// #140 verify F1 抓過 bootstrap 自留舊版造成的主流程死結）。
public enum NameNormalization {

    /// NFKC → 連字號家族統一 → 空白收斂 → 大小寫摺疊。
    ///
    /// 連字號要**顯式**映射：NFKC 對 U+2010–U+2014 與 U+2212 是恆等（相容分解
    /// 只處理全形與相容字元），而 WoS／出版商匯出裡這些變體全部實際出現過——
    /// `Chang, Y‐H.`（U+2010）與 `Chang, Y-H.`（ASCII）在位元組上是兩個字串，
    /// 在命名上是同一個寫法。
    public static func matchingKey(_ s: String) -> String {
        let nfkc = s.precomposedStringWithCompatibilityMapping
        // U+2015 HORIZONTAL BAR 與 2010–2014 同區塊、NFKC 同樣恆等（#140 verify F2）。
        // 其餘落選者（U+2E3A/2E3B、U+30FC、U+058A、U+05BE…）刻意不收——拉丁人名
        // 用不到，收進來只擴大誤塌縮面。U+00AD SOFT HYPHEN 的語意（映 - vs 刪除）
        // 本身有歧義，與其他不可見字元一起屬 follow-up。
        let hyphenFamily: Set<Character> = ["\u{2010}", "\u{2011}", "\u{2012}",
                                            "\u{2013}", "\u{2014}", "\u{2015}",
                                            "\u{2212}"]
        let unified = String(nfkc.map { hyphenFamily.contains($0) ? "-" : $0 })
        // 格式字元（Cf：ZWSP/ZWNJ/ZWJ/WORD JOINER/BOM/LRM/SOFT HYPHEN…）刪除
        // （#140 verify F3）：畫面上看不見、NFKC 恆等、isWhitespace 為 false——
        // 兩個顯示相同的字串永遠配不起來且無任何診斷。BOM 尤其實際：UTF-8-BOM
        // CSV 樸素解析後第一欄帶著 U+FEFF。SOFT HYPHEN 也是 Cf（斷字位置無語意，
        // 刪除即正解——「映成 - 還是刪」的歧義由類別歸屬解決）。
        let visible = unified.unicodeScalars.filter {
            $0.properties.generalCategory != .format
        }
        // split(whereSeparator:) 吃所有 Unicode 空白（NBSP 已被 NFKC 轉普通空格，
        // 但 ideographic space 等仍靠這裡收斂）——同時完成 trim 與塌縮
        return String(String.UnicodeScalarView(visible)).lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
