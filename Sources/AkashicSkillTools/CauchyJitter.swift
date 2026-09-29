import Foundation

/// 雙截斷柯西分布的請求間隔（秒）（#629 由 `jitter.py` 移植）。
///
/// 只在安裝的 safari-browser 沒有 `wait --jitter cauchy` 時用（PsychQuant/safari-browser#182）。同一個分布與預設值：
/// 區間 [2, 60] 秒、截斷後的中位數 3 秒、尺度 0.8 秒。區間外的質量**丟棄後重新正規化**，絕不夾住（clamp）。舊版
/// SKILL.md 的一行公式用 `max(2, …)` 夾住，10⁶ 次模擬裡有 22.3% 的間隔剛好是 2.0 秒（safari-browser#182）；不要用它。
public enum CauchyJitter {
    public struct Parameters: Equatable {
        public var min = 2.0
        public var max = 60.0
        public var median = 3.0
        public var scale = 0.8
        public init() {}
        public init(min: Double, max: Double, median: Double, scale: Double) {
            self.min = min; self.max = max; self.median = median; self.scale = scale
        }
    }

    static func cdf(_ x: Double, _ mu: Double, _ s: Double) -> Double { 0.5 + atan((x - mu) / s) / Double.pi }
    static func quantile(_ u: Double, _ mu: Double, _ s: Double) -> Double { mu + s * tan(Double.pi * (u - 0.5)) }
    /// 截斷到 [a, b] 之後的中位數。
    static func truncatedMedian(_ mu: Double, _ s: Double, _ a: Double, _ b: Double) -> Double {
        quantile((cdf(a, mu, s) + cdf(b, mu, s)) / 2, mu, s)
    }

    public struct Calibrated: Equatable {
        public var mu: Double
        public var lowerMedian: Double
        public var upperMedian: Double
    }

    /// 驗證參數並求出位置參數 μ 使截斷後的中位數等於 `median`。失敗時回傳給人看的一句話。
    public static func calibrate(_ p: Parameters) -> Result<Calibrated, JitterError> {
        guard 0 <= p.min, p.min < p.median, p.median < p.max, 0 < p.scale, p.scale <= 100 * (p.max - p.min) else {
            return .failure(JitterError("need 0 <= min < median < max and 0 < scale <= 100*(max-min)"))
        }
        let lo = truncatedMedian(p.min, p.scale, p.min, p.max), hi = truncatedMedian(p.max, p.scale, p.min, p.max)
        guard lo <= p.median, p.median <= hi else {
            return .failure(JitterError("median \(p.median) unreachable with scale \(p.scale); achievable "
                + "\(String(format: "%.3f", lo))..\(String(format: "%.3f", hi))"))
        }
        var l = p.min, h = p.max   // 截斷中位數在 [min, max] 上對 μ 單調
        for _ in 0..<200 {
            let m = (l + h) / 2
            if truncatedMedian(m, p.scale, p.min, p.max) < p.median { l = m } else { h = m }
        }
        return .success(Calibrated(mu: (l + h) / 2, lowerMedian: lo, upperMedian: hi))
    }

    public struct JitterError: Error, Equatable {
        public let message: String
        init(_ message: String) { self.message = message }
    }

    /// 抽一個間隔。`unit` 提供 [0, 1) 的均勻亂數（測試用固定序列）。64 次都落在區間外時退回中位數（不會發生：區間質量遠大於 0）。
    public static func draw(_ p: Parameters, _ c: Calibrated, unit: () -> Double = { Double.random(in: 0..<1) }) -> Double {
        let fa = cdf(p.min, c.mu, p.scale), fb = cdf(p.max, c.mu, p.scale)
        for _ in 0..<64 {
            let x = quantile(fa + (fb - fa) * unit(), c.mu, p.scale)
            if p.min < x, x < p.max { return x }
        }
        return p.median
    }
}
