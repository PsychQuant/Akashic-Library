/// 日期範圍在某個精確 valid day 上的四態判定。
///
/// `indeterminate` 是合法但資訊不足；`invalidEvidence` 是 shape 或日期本身矛盾。
/// 兩者不得互換，也不得降格成 `Bool`。
public enum TemporalContainment: Equatable, Hashable, Sendable {
    case definitelyContains
    case definitelyExcludes
    case indeterminate(TemporalIndeterminacyReason)
    case invalidEvidence(TemporalInvalidEvidenceReason)
}

/// 合法 temporal evidence 無法給出確定答案的具名原因。
public enum TemporalIndeterminacyReason: Equatable, Hashable, Sendable {
    case impreciseStart
    case impreciseEnd
    case impreciseAttestation
    case unknownStart
    case unknownEnd
}

/// Temporal evidence 不能被解讀的具名結構錯誤。
public enum TemporalInvalidEvidenceReason: Equatable, Hashable, Sendable {
    case mixedAttestationAndRange
    case endAndEndedUnknown
    case malformedStart
    case malformedEnd
    case malformedAttestation
    case endBeforeStart
}

extension DateRange {
    /// 在一個精確 `ValidDay` 判定此範圍，保留來源精度並對未知／矛盾資料 fail closed。
    public func assess(at day: ValidDay) -> TemporalContainment {
        if !attested.isEmpty {
            return assessAttestations(at: day)
        }

        if end != nil && endedUnknown {
            return .invalidEvidence(.endAndEndedUnknown)
        }

        let startInterval: GregorianDayInterval?
        if let start {
            guard let parsed = GregorianDayRules.interval(start) else {
                return .invalidEvidence(.malformedStart)
            }
            startInterval = parsed
        } else {
            startInterval = nil
        }

        let endInterval: GregorianDayInterval?
        if let end {
            guard let parsed = GregorianDayRules.interval(end) else {
                return .invalidEvidence(.malformedEnd)
            }
            endInterval = parsed
        } else {
            endInterval = nil
        }

        if let startInterval, let endInterval,
           endInterval.latest < startInterval.earliest {
            return .invalidEvidence(.endBeforeStart)
        }

        let query = day.point

        // 缺席 start 是未知，不是負無限；但若 query 已晚於最晚可能 end，仍可確定排除。
        guard let startInterval else {
            if let endInterval, endInterval.latest < query {
                return .definitelyExcludes
            }
            return .indeterminate(.unknownStart)
        }

        if query < startInterval.earliest {
            return .definitelyExcludes
        }
        // 已晚於所有可能 end 時，排除是確定的；不能讓 start 的粗精度先把它降格成
        // indeterminate（例如 start=2020-12、end=2020-12-15、query=2020-12-20）。
        if let endInterval, endInterval.latest < query {
            return .definitelyExcludes
        }
        // 一個 range 同時約束 actual start ≤ actual end。兩端的可能日有重疊時，
        // 不一致的配對不是另一個合法世界：end 的最晚日會截短 start 的可能上界。
        let effectiveLatestStart = endInterval.map {
            min(startInterval.latest, $0.latest)
        } ?? startInterval.latest
        if query < effectiveLatestStart {
            return .indeterminate(.impreciseStart)
        }

        // endedUnknown 不延伸到正無限。唯一必然成立的點，是已知為完整日的 inclusive
        // start 本身；更晚的日期都可能已經在未知的 end 之後。
        if endedUnknown {
            if startInterval.precision == .day, query == startInterval.earliest {
                return .definitelyContains
            }
            return .indeterminate(.unknownEnd)
        }

        // end 缺席且沒有 endedUnknown 才表示真正 open end。
        guard let endInterval else { return .definitelyContains }

        // 對稱地，start 的最早日會抬高一致配對裡 end 的可能下界。query 落在這兩個
        // 條件化邊界之間時，每一組一致配對都包含它。
        let effectiveEarliestEnd = max(endInterval.earliest, startInterval.earliest)
        if effectiveEarliestEnd < query {
            return .indeterminate(.impreciseEnd)
        }
        return .definitelyContains
    }

    private func assessAttestations(at day: ValidDay) -> TemporalContainment {
        guard start == nil, end == nil, !endedUnknown else {
            return .invalidEvidence(.mixedAttestationAndRange)
        }

        var observations: [GregorianDayInterval] = []
        observations.reserveCapacity(attested.count)
        for rawValue in attested {
            guard let observation = GregorianDayRules.interval(rawValue) else {
                return .invalidEvidence(.malformedAttestation)
            }
            observations.append(observation)
        }

        let query = day.point
        if observations.contains(where: {
            $0.precision == .day && $0.earliest == query
        }) {
            return .definitelyContains
        }
        if observations.contains(where: {
            $0.precision != .day && $0.earliest <= query && query <= $0.latest
        }) {
            return .indeterminate(.impreciseAttestation)
        }
        return .definitelyExcludes
    }
}
