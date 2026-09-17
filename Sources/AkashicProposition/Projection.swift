import Foundation
import AkashicCore
import AkashicStoreIO

/// 依 predicate 分型的 identity 投射。成功 case 會在型別中保存 role 方向；未解析或
/// 類型錯誤的引數絕不會變成部分成功的投射。
public enum Projection: Equatable {
    case authored(person: Person, work: Entry)
    case affiliated(person: Person, organization: Organization)
    case unprojectable(UnprojectableReason)
}

public enum UnprojectableReason: Equatable {
    case unresolvedSymbol(role: String, literal: String)
    case unknownIdentity(role: String, key: String)
    case wrongEntityKind(role: String, key: String, expected: String)
}

/// 開放世界真值。`authored` 只有在 exact canonical author-list completeness witness
/// 授權 fully-resolved exclusion 時才能產生 `fails`；`affiliated` 仍沒有 negative gate。
public enum TruthValue:
    Equatable, CustomStringConvertible, CustomDebugStringConvertible
{
    case holds
    case fails
    case undetermined(UndeterminedReason)

    public var description: String {
        switch self {
        case .holds:
            return "holds"
        case .fails:
            return "fails"
        case .undetermined(let reason):
            return boundedTruthRendering("undetermined(\(reason.safeDescription))")
        }
    }

    public var debugDescription: String { description }
}

public enum UndeterminedReason:
    Equatable, CustomStringConvertible, CustomDebugStringConvertible
{
    case notProjectable(UnprojectableReason)
    case noSupportingEvidence
    case supportingEvidenceUnresolved(literal: String)
    /// 存在尚未歸戶、但沒有直接名稱匹配的作者槽；仍不得由字面差異推成反證。
    case authorIdentityUnresolved(literal: String)
    case temporalEvidenceIndeterminate
    case invalidTemporalEvidence
    /// 相容 completions 對此 binary subformula 的結果不一致；payload 依 canonical
    /// atom bytes 排序且保持完整，只有人類可見 rendering 受限。
    case supervaluationInconclusive(atoms: [Proposition])

    public var description: String {
        boundedTruthRendering(safeDescription)
    }

    public var debugDescription: String { description }
}

public enum PropositionEvaluationError:
    Error,
    Equatable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case supervaluationCompletionLimitExceeded(
        undeterminedAtomCount: Int,
        maximumCompletions: Int
    )

    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case let .supervaluationCompletionLimitExceeded(actual, maximum):
            return "supervaluation 含有 \(actual) 個未定原子，超過固定的 \(maximum) 個 completions 上限" // display-safe-exempt: 兩項皆為 bounded 整數
        }
    }

    public var debugDescription: String { description }
}

private extension UndeterminedReason {
    var safeDescription: String {
        switch self {
        case .notProjectable(let reason):
            return "notProjectable(\(reason.safeDescription))" // display-safe-exempt: safeDescription 已逐欄以 displaySafe 限制
        case .noSupportingEvidence:
            return "noSupportingEvidence"
        case .supportingEvidenceUnresolved(let literal):
            return "supportingEvidenceUnresolved(\(displaySafeInvisible(literal, max: 120)))"
        case .authorIdentityUnresolved(let literal):
            return "authorIdentityUnresolved(\(displaySafeInvisible(literal, max: 120)))"
        case .temporalEvidenceIndeterminate:
            return "temporalEvidenceIndeterminate"
        case .invalidTemporalEvidence:
            return "invalidTemporalEvidence"
        case .supervaluationInconclusive(let atoms):
            let displayed = atoms.prefix(5).map(propositionTruthDisplay)
                .joined(separator: "、")
            let omitted = max(0, atoms.count - 5)
            return "supervaluationInconclusive(atoms: [\(displayed)]，另 \(omitted) 個)"
        }
    }
}

private extension UnprojectableReason {
    var safeDescription: String {
        switch self {
        case let .unresolvedSymbol(role, literal):
            return "unresolvedSymbol(role: \(displaySafeInvisible(role, max: 40)), literal: \(displaySafeInvisible(literal, max: 120)))"
        case let .unknownIdentity(role, key):
            return "unknownIdentity(role: \(displaySafeInvisible(role, max: 40)), key: \(displaySafeInvisible(key, max: 120)))"
        case let .wrongEntityKind(role, key, expected):
            return "wrongEntityKind(role: \(displaySafeInvisible(role, max: 40)), key: \(displaySafeInvisible(key, max: 120)), expected: \(displaySafeInvisible(expected, max: 40)))"
        }
    }
}

private func propositionTruthDisplay(_ proposition: Proposition) -> String {
    switch proposition {
    case let .authored(person, work):
        return "authored(\(referenceTruthDisplay(person)), \(referenceTruthDisplay(work)))" // display-safe-exempt: helper 已逐一以 displaySafe 限制 reference
    case let .affiliated(person, organization):
        return "affiliated(\(referenceTruthDisplay(person)), \(referenceTruthDisplay(organization)))" // display-safe-exempt: helper 已逐一以 displaySafe 限制 reference
    }
}

private func referenceTruthDisplay(_ reference: EntityRef) -> String {
    switch reference {
    case .key(let value):
        return "key(\(displaySafeInvisible(value, max: 120)))"
    case .literal(let value):
        return "literal(\(displaySafeInvisible(value, max: 120)))"
    }
}

private func boundedTruthRendering(_ value: String) -> String {
    displaySafeClipOnly(displaySafeInvisible(value, max: 2_048), max: 2_048)   // display-safe-exempt: 已逃一次，輸出上限 2,048、退讓到完整的逃脫序列（R30）
}

/// 將 Core binding issue 定位回 canonical Entry；citekey 只供診斷與排序，真正 binding
/// 仍由不可變 work UUID 與 ordered raw author snapshot 決定。
public struct PropositionModelAuthorListCompletenessIssue:
    Equatable, Hashable, Sendable
{
    public let entryCitekey: String
    public let entryID: UUID
    public let issue: AuthorListCompletenessBindingIssue

    init(
        entryCitekey: String,
        entryID: UUID,
        issue: AuthorListCompletenessBindingIssue
    ) {
        self.entryCitekey = entryCitekey
        self.entryID = entryID
        self.issue = issue
    }
}

/// 命題求值所用 canonical model 的 aggregate refusal。Typed payload 保持完整；只有
/// 給人看的訊息受固定筆數與長度上限約束。
public struct PropositionModelValidationError:
    Error, Equatable, LocalizedError,
    SanitizedErrorDescription, CustomStringConvertible, CustomDebugStringConvertible
{
    public let duplicateEntryCitekeys: [String]
    public let duplicatePersonKeys: [String]
    public let duplicateOrganizationKeys: [String]
    public let authorListCompletenessBindingIssues:
        [PropositionModelAuthorListCompletenessIssue]

    init(
        duplicateEntryCitekeys: [String],
        duplicatePersonKeys: [String],
        duplicateOrganizationKeys: [String],
        authorListCompletenessBindingIssues: [PropositionModelAuthorListCompletenessIssue]
    ) {
        self.duplicateEntryCitekeys = duplicateEntryCitekeys
        self.duplicatePersonKeys = duplicatePersonKeys
        self.duplicateOrganizationKeys = duplicateOrganizationKeys
        self.authorListCompletenessBindingIssues = authorListCompletenessBindingIssues
    }

    public var errorDescription: String? {
        let displayLimit = 5

        // `displaySafeInvisible(max: 120)` 限制的是輸入 scalar；控制字元跳脫後仍可能膨脹。
        // 再施加一層固定顯示上限，避免大量反斜線把三類聚合診斷放大；不改上方完整的
        // machine-readable payload。
        func boundedKey(_ key: String) -> String {
            displaySafeClipOnly(displaySafeInvisible(key, max: 120), max: 120)   // display-safe-exempt: 已逃一次，輸出上限 120、退讓到完整的逃脫序列（R30；R29 verify 第 20 列：prefix(119) 切在 \u{ 中間）
        }

        func summary(label: String, keys: [String]) -> String {
            let displayed = keys.prefix(displayLimit)
                .map { "「\(boundedKey($0))」" }
                .joined(separator: "、")
            let omitted = max(0, keys.count - displayLimit)
            if omitted > 0 {
                return "\(label)（共 \(keys.count) 筆，僅列前 \(displayLimit) 筆；另 \(omitted) 筆未顯示）：\(displayed)"
            }
            return "\(label)（共 \(keys.count) 筆；另 0 筆未顯示）：\(displayed)"
        }

        var problems: [String] = []
        if !duplicateEntryCitekeys.isEmpty {
            problems.append(summary(label: "重複 entry citekey", keys: duplicateEntryCitekeys))
        }
        if !duplicatePersonKeys.isEmpty {
            problems.append(summary(label: "重複 person key", keys: duplicatePersonKeys))
        }
        if !duplicateOrganizationKeys.isEmpty {
            problems.append(summary(
                label: "重複 organization key",
                keys: duplicateOrganizationKeys
            ))
        }
        if !authorListCompletenessBindingIssues.isEmpty {
            let displayed = authorListCompletenessBindingIssues.prefix(displayLimit)
                .map { located -> String in
                    let kind: String
                    switch located.issue.kind {
                    case .workID: kind = "work UUID"
                    case .authorSnapshot: kind = "author snapshot"
                    }
                    return "「\(boundedKey(located.entryCitekey))」(\(kind))"
                }
                .joined(separator: "、")
            let omitted = max(0, authorListCompletenessBindingIssues.count - displayLimit)
            problems.append(
                "失效 author-list completeness witness（共 \(authorListCompletenessBindingIssues.count) 筆；另 \(omitted) 筆未顯示）：\(displayed)"
            )
        }
        let message = "PropositionModel canonical 輸入無效，拒絕構造："
            + problems.joined(separator: "；")
        return displaySafeClipOnly(message, max: 2_000)   // display-safe-exempt: 各段已逃一次，只截（R30；R29 verify 第 20 列）
    }

    public var description: String {
        errorDescription ?? "PropositionModel canonical 輸入無效，拒絕構造"
    }

    public var debugDescription: String { description }
}

/// 從單一可信 StoreIO snapshot 取得的不可變 model view。
public struct PropositionModel {
    public let snapshotID: StoreSnapshotID
    public let entriesByKey: [String: Entry]
    public let peopleByKey: [String: Person]
    public let organizationsByKey: [String: Organization]
    let snapshotQuarantine: [QuarantinedFile]

    /// 唯一 production 構造路徑：identity 與 model bytes 都來自 StoreIO 回傳的同一份
    /// 可信 `LibrarySnapshot`。
    public init(snapshot: LibrarySnapshot) throws {
        try self.init(
            snapshotID: snapshot.id,
            entries: snapshot.load.entries,
            people: snapshot.load.people,
            organizations: snapshot.load.organizations,
            snapshotQuarantine: snapshot.load.quarantined
        )
    }

    /// 供 mutation／回歸測試使用的 module-internal 組裝縫。外部 production caller
    /// 無法用它把合成 revision 貼到任意陣列。
    init(
        snapshotID: StoreSnapshotID,
        entries: [Entry],
        people: [Person],
        organizations: [Organization],
        snapshotQuarantine: [QuarantinedFile] = []
    ) throws {
        let duplicateEntryCitekeys = Self.duplicates(entries.map(\.citekey))
        let duplicatePersonKeys = Self.duplicates(people.map(\.key))
        let duplicateOrganizationKeys = Self.duplicates(organizations.map(\.key))
        let authorListCompletenessBindingIssues = Self.completenessBindingIssues(
            in: entries
        )
        guard duplicateEntryCitekeys.isEmpty,
              duplicatePersonKeys.isEmpty,
              duplicateOrganizationKeys.isEmpty,
              authorListCompletenessBindingIssues.isEmpty else {
            throw PropositionModelValidationError(
                duplicateEntryCitekeys: duplicateEntryCitekeys,
                duplicatePersonKeys: duplicatePersonKeys,
                duplicateOrganizationKeys: duplicateOrganizationKeys,
                authorListCompletenessBindingIssues: authorListCompletenessBindingIssues
            )
        }

        self.snapshotID = snapshotID
        self.entriesByKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.citekey, $0) })
        self.peopleByKey = Dictionary(uniqueKeysWithValues: people.map { ($0.key, $0) })
        self.organizationsByKey = Dictionary(
            uniqueKeysWithValues: organizations.map { ($0.key, $0) }
        )
        self.snapshotQuarantine = snapshotQuarantine
    }

    public func context(validAt: ValidDay) -> ValuationContext {
        ValuationContext(model: self, validAt: validAt)
    }

    private static func duplicates(_ values: [String]) -> [String] {
        func rawUTF8Less(_ lhs: String, _ rhs: String) -> Bool {
            lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
        }
        func stableRepresentative(_ lhs: String, _ rhs: String) -> String {
            rawUTF8Less(lhs, rhs) ? lhs : rhs
        }

        // Swift String equality 會合併 canonical-equivalent Unicode 拼法。每個 equality
        // class 取 raw UTF-8 最小代表，確保反轉輸入既不改 typed payload bytes，也不改
        // 人讀診斷。
        var firstByEqualityClass: [String: String] = [:]
        var duplicateByEqualityClass: [String: String] = [:]
        for value in values {
            guard let first = firstByEqualityClass[value] else {
                firstByEqualityClass[value] = value
                continue
            }
            let representative = stableRepresentative(first, value)
            firstByEqualityClass[value] = representative
            if let previous = duplicateByEqualityClass[value] {
                duplicateByEqualityClass[value] = stableRepresentative(previous, representative)
            } else {
                duplicateByEqualityClass[value] = representative
            }
        }
        return duplicateByEqualityClass.values.sorted(by: rawUTF8Less)
    }

    private static func completenessBindingIssues(
        in entries: [Entry]
    ) -> [PropositionModelAuthorListCompletenessIssue] {
        var located: [PropositionModelAuthorListCompletenessIssue] = []
        for entry in entries {
            guard let witness = entry.akashic.authorListCompleteness else { continue }
            do {
                try witness.validateBinding(workID: entry.id, authors: entry.authors)
            } catch let binding as AuthorListCompletenessBindingError {
                located.append(contentsOf: binding.issues.map {
                    PropositionModelAuthorListCompletenessIssue(
                        entryCitekey: entry.citekey,
                        entryID: entry.id,
                        issue: $0
                    )
                })
            } catch {
                preconditionFailure("validateBinding 只會回傳 typed binding error")
            }
        }

        func rawUTF8Less(_ lhs: String, _ rhs: String) -> Bool {
            lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
        }
        func issueLess(
            _ lhs: PropositionModelAuthorListCompletenessIssue,
            _ rhs: PropositionModelAuthorListCompletenessIssue
        ) -> Bool {
            if lhs.entryCitekey != rhs.entryCitekey {
                return rawUTF8Less(lhs.entryCitekey, rhs.entryCitekey)
            }
            if lhs.entryID != rhs.entryID {
                return lhs.entryID.uuidString < rhs.entryID.uuidString
            }
            if lhs.issue.kind != rhs.issue.kind {
                return lhs.issue.kind.rawValue < rhs.issue.kind.rawValue
            }
            switch (lhs.issue, rhs.issue) {
            case let (.workID(leftWitness, leftCurrent), .workID(rightWitness, rightCurrent)):
                if leftWitness != rightWitness {
                    return leftWitness.uuidString < rightWitness.uuidString
                }
                return leftCurrent.uuidString < rightCurrent.uuidString
            case let (
                .authorSnapshot(leftAttested, leftCurrent),
                .authorSnapshot(rightAttested, rightCurrent)
            ):
                if leftAttested != rightAttested {
                    return leftAttested.digest < rightAttested.digest
                }
                return leftCurrent.digest < rightCurrent.digest
            case (.workID, .authorSnapshot), (.authorSnapshot, .workID):
                preconditionFailure("kind 已在 payload 比較前分流")
            }
        }
        return Array(Set(located)).sorted(by: issueLess)
    }
}

/// Context 不能由互不相關的零件拆配：initializer 是 module-internal，descriptor 一律
/// 從它保存的不可變 model 推出。
public struct ValuationContext: Equatable {
    public let snapshotID: StoreSnapshotID
    public let validAt: ValidDay
    let model: PropositionModel

    init(model: PropositionModel, validAt: ValidDay) {
        self.snapshotID = model.snapshotID
        self.validAt = validAt
        self.model = model
    }

    public static func == (lhs: ValuationContext, rhs: ValuationContext) -> Bool {
        lhs.snapshotID == rhs.snapshotID && lhs.validAt == rhs.validAt
    }
}

public enum PredicateScope: Equatable {
    /// Predicate 只讀一份不可變 snapshot，不解讀 valid-time timeline。
    case snapshotScopedTimeInvariant
    /// Predicate 在 context 明示的有效日解讀 temporal evidence。
    case validTimeScoped
}

public enum EvidenceProjection: Equatable {
    case authored(personKey: String, workKey: String)
    case affiliated(personKey: String, organizationKey: String)
    case unprojectable(UnprojectableReason)
}

public enum AuthorSlotAssessment: Equatable {
    case supports
    case unresolvedCandidate
    case identityUnresolved
    case doesNotSupport
}

public enum AffiliationIdentityAssessment: Equatable {
    case resolvedMatch
    case unresolvedCandidate
    case differentIdentity
}

public enum EvidenceItem: Equatable {
    case authorSlot(slot: Author, assessment: AuthorSlotAssessment)
    case authorListCompleteness(witness: AuthorListCompletenessWitness)
    case affiliationSegment(
        segment: TemporalValue<OrgRef>,
        identity: AffiliationIdentityAssessment,
        temporal: TemporalContainment
    )
}

/// Atomic predicate 的完整 typed evidence。Operator trace 只能包住它，不能改寫它。
public struct AtomicEvidenceTrace: Equatable {
    public let scope: PredicateScope
    public let projection: EvidenceProjection
    public let evidence: [EvidenceItem]
    public let snapshotQuarantine: [QuarantinedFile]
    public let conclusion: TruthValue

    init(
        scope: PredicateScope,
        projection: EvidenceProjection,
        evidence: [EvidenceItem],
        snapshotQuarantine: [QuarantinedFile],
        conclusion: TruthValue
    ) {
        self.scope = scope
        self.projection = projection
        self.evidence = evidence
        self.snapshotQuarantine = snapshotQuarantine
        self.conclusion = conclusion
    }

    /// Atomic uncertainty 的原始 typed refusal；operator aggregate 不會覆寫它。
    public var refusal: UndeterminedReason? {
        guard case .undetermined(let reason) = conclusion else { return nil }
        return reason
    }
}

public struct SupervaluationSummary: Equatable {
    public let completionCount: Int
    public let observedTrue: Bool
    public let observedFalse: Bool

    init(completionCount: Int, observedTrue: Bool, observedFalse: Bool) {
        self.completionCount = completionCount
        self.observedTrue = observedTrue
        self.observedFalse = observedFalse
    }
}

/// Expression 每個 syntax occurrence 的唯讀稽核樹。Storage／constructors 留在 module
/// 內，外部 caller 不能把任意 conclusion 配到另一份 context 或 children。
public struct EvidenceTrace: Equatable {
    public enum Kind: Equatable {
        case atom
        case not
        case and
        case or
        case implies
        case nor
    }

    private indirect enum Storage {
        case atom(
            expression: PropositionExpression,
            context: ValuationContext,
            evidence: AtomicEvidenceTrace
        )
        case operation(
            kind: Kind,
            expression: PropositionExpression,
            context: ValuationContext,
            children: [Storage],
            summary: SupervaluationSummary,
            conclusion: TruthValue
        )
    }

    private let storage: Storage

    private init(storage: Storage) {
        self.storage = storage
    }

    static func atom(
        expression: PropositionExpression,
        context: ValuationContext,
        evidence: AtomicEvidenceTrace
    ) -> EvidenceTrace {
        EvidenceTrace(storage: .atom(
            expression: expression,
            context: context,
            evidence: evidence
        ))
    }

    static func operation(
        kind: Kind,
        expression: PropositionExpression,
        context: ValuationContext,
        children: [EvidenceTrace],
        summary: SupervaluationSummary,
        conclusion: TruthValue
    ) -> EvidenceTrace {
        let expectedChildren = kind == .not ? 1 : 2
        precondition(kind != .atom && children.count == expectedChildren)
        precondition(children.allSatisfy { $0.context == context })
        return EvidenceTrace(storage: .operation(
            kind: kind,
            expression: expression,
            context: context,
            children: children.map(\.storage),
            summary: summary,
            conclusion: conclusion
        ))
    }

    /// Question 的 no-answer 只包裝既有 subject trace，不重投射任何 atom。
    static func negating(
        _ operand: EvidenceTrace,
        as expression: PropositionExpression
    ) -> EvidenceTrace {
        precondition(expression.kind == .not && expression.children == [operand.expression])
        let operandSummary = operand.completionSummary ?? SupervaluationSummary(
            completionCount: 1,
            observedTrue: operand.conclusion == .holds,
            observedFalse: operand.conclusion == .fails
        )
        let summary = SupervaluationSummary(
            completionCount: operandSummary.completionCount,
            observedTrue: operandSummary.observedFalse,
            observedFalse: operandSummary.observedTrue
        )
        return operation(
            kind: .not,
            expression: expression,
            context: operand.context,
            children: [operand],
            summary: summary,
            conclusion: operand.conclusion.negatedForExpression
        )
    }

    public var kind: Kind {
        switch storage {
        case .atom: return .atom
        case .operation(let kind, _, _, _, _, _): return kind
        }
    }

    public var expression: PropositionExpression {
        switch storage {
        case .atom(let expression, _, _),
             .operation(_, let expression, _, _, _, _):
            return expression
        }
    }

    public var context: ValuationContext {
        switch storage {
        case .atom(_, let context, _),
             .operation(_, _, let context, _, _, _):
            return context
        }
    }

    public var children: [EvidenceTrace] {
        guard case .operation(_, _, _, let children, _, _) = storage else { return [] }
        return children.map { EvidenceTrace(storage: $0) }
    }

    public var atomicEvidence: AtomicEvidenceTrace? {
        guard case .atom(_, _, let evidence) = storage else { return nil }
        return evidence
    }

    public var completionSummary: SupervaluationSummary? {
        guard case .operation(_, _, _, _, let summary, _) = storage else { return nil }
        return summary
    }

    @available(*, deprecated, message: "改用 children；operand 只適用 not node")
    public var operand: EvidenceTrace? {
        guard kind == .not else { return nil }
        return children.first
    }

    public var conclusion: TruthValue {
        switch storage {
        case .atom(_, _, let evidence): return evidence.conclusion
        case .operation(_, _, _, _, _, let conclusion): return conclusion
        }
    }

    /// Equality 使用顯式 stack；不依賴 recursive enum 的 synthesized traversal。
    public static func == (lhs: EvidenceTrace, rhs: EvidenceTrace) -> Bool {
        var pending: [(Storage, Storage)] = [(lhs.storage, rhs.storage)]
        while let (left, right) = pending.popLast() {
            switch (left, right) {
            case let (
                .atom(leftExpression, leftContext, leftEvidence),
                .atom(rightExpression, rightContext, rightEvidence)
            ):
                guard leftExpression == rightExpression,
                      leftContext == rightContext,
                      leftEvidence == rightEvidence else { return false }
            case let (
                .operation(
                    leftKind, leftExpression, leftContext, leftChildren,
                    leftSummary, leftConclusion
                ),
                .operation(
                    rightKind, rightExpression, rightContext, rightChildren,
                    rightSummary, rightConclusion
                )
            ):
                guard leftKind == rightKind,
                      leftExpression == rightExpression,
                      leftContext == rightContext,
                      leftSummary == rightSummary,
                      leftConclusion == rightConclusion,
                      leftChildren.count == rightChildren.count else { return false }
                pending.append(contentsOf: zip(leftChildren, rightChildren))
            case (.atom, .operation), (.operation, .atom):
                return false
            }
        }
        return true
    }
}

public struct Valuation: Equatable {
    public let expression: PropositionExpression
    public let truth: TruthValue
    public let context: ValuationContext
    public let trace: EvidenceTrace

    init(
        expression: PropositionExpression,
        truth: TruthValue,
        context: ValuationContext,
        trace: EvidenceTrace
    ) {
        self.expression = expression
        self.truth = truth
        self.context = context
        self.trace = trace
    }

    /// 只供 module 內的 expression／question evaluator 使用：不重投射、不重載 store，
    /// 僅從既有 valuation 導出上一層 negation。
    func negated(as negatedExpression: PropositionExpression) -> Valuation {
        precondition(
            negatedExpression.kind == .not
                && negatedExpression.children == [expression],
            "negation valuation 的 expression 必須恰為 operand expression 的 not"
        )
        let negatedTrace = EvidenceTrace.negating(trace, as: negatedExpression)
        return Valuation(
            expression: negatedExpression,
            truth: negatedTrace.conclusion,
            context: context,
            trace: negatedTrace
        )
    }
}

extension TruthValue {
    /// 不公開 context-free negation；只有完整 expression valuation derivation 可使用。
    fileprivate var negatedForExpression: TruthValue {
        switch self {
        case .holds: return .fails
        case .fails: return .holds
        case .undetermined(let reason): return .undetermined(reason)
        }
    }
}

extension Proposition {
    /// 對 supplied context 保存的不可變 model 解析每一個 role。
    public func project(in context: ValuationContext) throws -> Projection {
        try validate()
        let model = context.model

        func personProjection(_ reference: EntityRef) -> ResultValue<Person> {
            switch reference {
            case .literal(let literal):
                return .failure(.unresolvedSymbol(role: "person", literal: literal))
            case .key(let key):
                if let person = model.peopleByKey[key] { return .success(person) }
                if model.entriesByKey[key] != nil || model.organizationsByKey[key] != nil {
                    return .failure(.wrongEntityKind(
                        role: "person", key: key, expected: "person"
                    ))
                }
                return .failure(.unknownIdentity(role: "person", key: key))
            }
        }

        switch self {
        case let .authored(personReference, workReference):
            let person: Person
            switch personProjection(personReference) {
            case .success(let value): person = value
            case .failure(let reason): return .unprojectable(reason)
            }

            switch workReference {
            case .literal(let literal):
                return .unprojectable(.unresolvedSymbol(role: "work", literal: literal))
            case .key(let key):
                if let work = model.entriesByKey[key] { return .authored(person: person, work: work) }
                if model.peopleByKey[key] != nil || model.organizationsByKey[key] != nil {
                    return .unprojectable(.wrongEntityKind(
                        role: "work", key: key, expected: "work"
                    ))
                }
                return .unprojectable(.unknownIdentity(role: "work", key: key))
            }

        case let .affiliated(personReference, organizationReference):
            let person: Person
            switch personProjection(personReference) {
            case .success(let value): person = value
            case .failure(let reason): return .unprojectable(reason)
            }

            switch organizationReference {
            case .literal(let literal):
                return .unprojectable(.unresolvedSymbol(role: "organization", literal: literal))
            case .key(let key):
                if let organization = model.organizationsByKey[key] {
                    return .affiliated(person: person, organization: organization)
                }
                if model.peopleByKey[key] != nil || model.entriesByKey[key] != nil {
                    return .unprojectable(.wrongEntityKind(
                        role: "organization", key: key, expected: "organization"
                    ))
                }
                return .unprojectable(.unknownIdentity(role: "organization", key: key))
            }
        }
    }

    /// Atomic evaluator；expression 層先驗證整棵 AST，再且僅再呼叫這裡一次。
    fileprivate func evaluateAtom(in context: ValuationContext) throws -> Valuation {
        let projected = try project(in: context)
        if case .unprojectable(let reason) = projected {
            let truth = TruthValue.undetermined(.notProjectable(reason))
            return try valuation(
                truth: truth,
                context: context,
                scope: predicateScope,
                projection: .unprojectable(reason),
                evidence: []
            )
        }

        switch (self, projected) {
        case let (.authored, .authored(person, work)):
            return try evaluateAuthored(person: person, work: work, context: context)
        case let (.affiliated, .affiliated(person, organization)):
            return try evaluateAffiliated(
                person: person,
                organization: organization,
                context: context
            )
        case (.authored, .affiliated), (.affiliated, .authored), (_, .unprojectable):
            preconditionFailure("投射 predicate 必須與來源命題相符")
        }
    }

    private var predicateScope: PredicateScope {
        switch self {
        case .authored: return .snapshotScopedTimeInvariant
        case .affiliated: return .validTimeScoped
        }
    }

    private func evaluateAuthored(
        person: Person,
        work: Entry,
        context: ValuationContext
    ) throws -> Valuation {
        var supportingLiteral: String?
        var unresolvedLiteral: String?
        var holds = false
        var evidence = work.authors.map { slot -> EvidenceItem in
            switch slot {
            case .key(let key) where key == person.key:
                holds = true
                return .authorSlot(slot: slot, assessment: .supports)
            case .key:
                return .authorSlot(slot: slot, assessment: .doesNotSupport)
            case .organization:
                // #323：團體作者槽對「**某人**著有這篇」永遠不支持——它已判定為
                // organization，不是任何 person。**不落 `unresolvedLiteral`**：那一格
                // 的語意是「還沒判定、可能是這個人」，而團體作者已經判定過了。
                return .authorSlot(slot: slot, assessment: .doesNotSupport)
            case .literal(let literal):
                // #227：身分比對看**全部**名字——candidate 資格不因指定與否而異。
                let candidate = person.names.all.contains {
                    NameNormalization.matchingKey($0)
                        == NameNormalization.matchingKey(literal)
                }
                if candidate, supportingLiteral == nil { supportingLiteral = literal }
                if !candidate, unresolvedLiteral == nil { unresolvedLiteral = literal }
                return .authorSlot(
                    slot: slot,
                    assessment: candidate ? .unresolvedCandidate : .identityUnresolved
                )
            }
        }
        let completeness = work.akashic.authorListCompleteness
        if let completeness {
            evidence.append(.authorListCompleteness(witness: completeness))
        }

        let truth: TruthValue
        if holds {
            truth = .holds
        } else if let literal = supportingLiteral {
            truth = .undetermined(.supportingEvidenceUnresolved(literal: literal))
        } else if let literal = unresolvedLiteral {
            truth = .undetermined(.authorIdentityUnresolved(literal: literal))
        } else if completeness != nil {
            truth = .fails
        } else {
            truth = .undetermined(.noSupportingEvidence)
        }
        return try valuation(
            truth: truth,
            context: context,
            scope: .snapshotScopedTimeInvariant,
            projection: .authored(personKey: person.key, workKey: work.citekey),
            evidence: evidence
        )
    }

    private func evaluateAffiliated(
        person: Person,
        organization: Organization,
        context: ValuationContext
    ) throws -> Valuation {
        let candidateNames = Set(
            ([organization.key] + organization.authorized
                + organization.names.entries.map(\.value))
                .map(NameNormalization.matchingKey)
        )

        var hasPositive = false
        var hasInvalid = false
        var hasIndeterminate = false
        var unresolvedLiteral: String?

        let evidence = person.profile.affiliations.entries.map { segment -> EvidenceItem in
            let identity: AffiliationIdentityAssessment
            switch segment.value {
            case .key(let key):
                identity = key == organization.key ? .resolvedMatch : .differentIdentity
            case .literal(let literal):
                if candidateNames.contains(NameNormalization.matchingKey(literal)) {
                    identity = .unresolvedCandidate
                } else {
                    identity = .differentIdentity
                }
            }

            let temporal = segment.range.assess(at: context.validAt)
            if identity == .resolvedMatch {
                switch temporal {
                case .definitelyContains: hasPositive = true
                case .definitelyExcludes: break
                case .indeterminate: hasIndeterminate = true
                case .invalidEvidence: hasInvalid = true
                }
            } else if identity == .unresolvedCandidate {
                switch temporal {
                case .definitelyContains:
                    if unresolvedLiteral == nil,
                       case .literal(let literal) = segment.value {
                        unresolvedLiteral = literal
                    }
                case .definitelyExcludes:
                    break
                case .indeterminate:
                    hasIndeterminate = true
                case .invalidEvidence:
                    hasInvalid = true
                }
            }
            return .affiliationSegment(
                segment: segment,
                identity: identity,
                temporal: temporal
            )
        }

        let truth: TruthValue
        if hasPositive {
            truth = .holds
        } else if hasInvalid {
            truth = .undetermined(.invalidTemporalEvidence)
        } else if hasIndeterminate {
            truth = .undetermined(.temporalEvidenceIndeterminate)
        } else if let unresolvedLiteral {
            truth = .undetermined(.supportingEvidenceUnresolved(literal: unresolvedLiteral))
        } else {
            truth = .undetermined(.noSupportingEvidence)
        }
        return try valuation(
            truth: truth,
            context: context,
            scope: .validTimeScoped,
            projection: .affiliated(
                personKey: person.key,
                organizationKey: organization.key
            ),
            evidence: evidence
        )
    }

    private func valuation(
        truth: TruthValue,
        context: ValuationContext,
        scope: PredicateScope,
        projection: EvidenceProjection,
        evidence: [EvidenceItem]
    ) throws -> Valuation {
        let atomExpression = try asExpression()
        let atomicEvidence = AtomicEvidenceTrace(
            scope: scope,
            projection: projection,
            evidence: evidence,
            snapshotQuarantine: context.model.snapshotQuarantine,
            conclusion: truth
        )
        return Valuation(
            expression: atomExpression,
            truth: truth,
            context: context,
            trace: .atom(
                expression: atomExpression,
                context: context,
                evidence: atomicEvidence
            )
        )
    }
}

private struct SupervaluationNode {
    let expression: PropositionExpression
    var children: [Int]
}

extension PropositionExpression {
    /// 只透過明示的 snapshot／day context 求值。每個 canonical atom 只投射一次；
    /// operator 則在所有相容 completions 上求值，以 supervaluation 聚合結論。
    public func evaluate(in context: ValuationContext) throws -> Valuation {
        try evaluate(
            in: context,
            shift: productionCheckedPowerOfTwoShift,
            workspaceProbe: .noOp,
            atomicObserver: { _ in }
        )
    }

    /// Module-internal、per-call 的觀測縫只供承重測試；public path 固定使用安全 defaults。
    func evaluate(
        in context: ValuationContext,
        shift: (_ exponent: Int) -> Int?,
        workspaceProbe: EnumerationWorkspaceProbe,
        atomicObserver: (Proposition) -> Void
    ) throws -> Valuation {
        let canonicalAtoms = atoms
        var atomicValuations: [(atom: Proposition, valuation: Valuation)] = []
        atomicValuations.reserveCapacity(canonicalAtoms.count)
        for atom in canonicalAtoms {
            atomicObserver(atom)
            atomicValuations.append((atom, try atom.evaluateAtom(in: context)))
        }

        let undeterminedAtoms = atomicValuations.compactMap { item -> Proposition? in
            if case .undetermined = item.valuation.truth { return item.atom }
            return nil
        }
        guard let completionCount = checkedPowerOfTwoCount(
            variableCount: undeterminedAtoms.count,
            maximum: PropositionLogicLimits.maximumSupervaluationCompletions,
            shift: shift
        ) else {
            throw PropositionEvaluationError.supervaluationCompletionLimitExceeded(
                undeterminedAtomCount: undeterminedAtoms.count,
                maximumCompletions: PropositionLogicLimits.maximumSupervaluationCompletions
            )
        }

        var nodes: [SupervaluationNode] = []
        nodes.reserveCapacity(nodeCount)
        var pending: [(expression: PropositionExpression, parent: Int?)] = [(self, nil)]
        while let item = pending.popLast() {
            let nodeIndex = nodes.count
            nodes.append(SupervaluationNode(expression: item.expression, children: []))
            if let parent = item.parent {
                nodes[parent].children.append(nodeIndex)
            }
            for child in item.expression.children.reversed() {
                pending.append((child, nodeIndex))
            }
        }
        precondition(nodes.count == nodeCount, "opaque expression node count 必須精確")

        workspaceProbe.recordAllocation(elementCount: completionCount)
        var observedTrue = [Bool](repeating: false, count: nodes.count)
        var observedFalse = [Bool](repeating: false, count: nodes.count)
        var completionValues = [Bool](repeating: false, count: nodes.count)
        let (outcomeCount, outcomeCountOverflow) = nodes.count
            .multipliedReportingOverflow(by: completionCount)
        precondition(!outcomeCountOverflow, "bounded node／completion product 必須可表示")
        var completionOutcomes = [Bool](repeating: false, count: outcomeCount)

        func atomicValuation(for atom: Proposition) -> Valuation {
            guard let match = atomicValuations.first(where: { $0.atom == atom }) else {
                preconditionFailure("expression atom 必須存在於 canonical valuation cache")
            }
            return match.valuation
        }

        for completionIndex in 0..<completionCount {
            for nodeIndex in nodes.indices.reversed() {
                let node = nodes[nodeIndex]
                let value: Bool
                switch node.expression.kind {
                case .atom:
                    guard let atom = node.expression.proposition else {
                        preconditionFailure("atom node 缺少 proposition")
                    }
                    switch atomicValuation(for: atom).truth {
                    case .holds:
                        value = true
                    case .fails:
                        value = false
                    case .undetermined:
                        guard let unknownIndex = undeterminedAtoms.firstIndex(of: atom) else {
                            preconditionFailure("undetermined atom 必須存在於 completion table")
                        }
                        let bitOffset = undeterminedAtoms.count - unknownIndex - 1
                        value = ((completionIndex >> bitOffset) & 1) == 1
                    }
                case .not:
                    precondition(node.children.count == 1)
                    value = !completionValues[node.children[0]]
                case .and:
                    precondition(node.children.count == 2)
                    value = completionValues[node.children[0]]
                        && completionValues[node.children[1]]
                case .or:
                    precondition(node.children.count == 2)
                    value = completionValues[node.children[0]]
                        || completionValues[node.children[1]]
                case .implies:
                    precondition(node.children.count == 2)
                    value = !completionValues[node.children[0]]
                        || completionValues[node.children[1]]
                case .nor:
                    precondition(node.children.count == 2)
                    value = !(completionValues[node.children[0]]
                        || completionValues[node.children[1]])
                }
                completionValues[nodeIndex] = value
                completionOutcomes[completionIndex * nodes.count + nodeIndex] = value
                observedTrue[nodeIndex] = observedTrue[nodeIndex] || value
                observedFalse[nodeIndex] = observedFalse[nodeIndex] || !value
            }
        }

        var traces = [EvidenceTrace?](repeating: nil, count: nodes.count)
        var conclusions = [TruthValue?](repeating: nil, count: nodes.count)
        var completionDependentAtoms = [[Proposition]](
            repeating: [],
            count: nodes.count
        )
        for nodeIndex in nodes.indices.reversed() {
            let node = nodes[nodeIndex]
            if node.expression.kind == .atom {
                guard let atom = node.expression.proposition else {
                    preconditionFailure("atom node 缺少 proposition")
                }
                let atomic = atomicValuation(for: atom)
                traces[nodeIndex] = atomic.trace
                conclusions[nodeIndex] = atomic.truth
                if case .undetermined = atomic.truth {
                    completionDependentAtoms[nodeIndex] = [atom]
                }
                continue
            }

            let childTraces = node.children.map { childIndex -> EvidenceTrace in
                guard let trace = traces[childIndex] else {
                    preconditionFailure("operator child trace 必須先由內向外建立")
                }
                return trace
            }
            let conclusion: TruthValue
            if observedTrue[nodeIndex] && !observedFalse[nodeIndex] {
                conclusion = .holds
            } else if observedFalse[nodeIndex] && !observedTrue[nodeIndex] {
                conclusion = .fails
            } else if node.expression.kind == .not,
                      let childConclusion = conclusions[node.children[0]],
                      case .undetermined(let reason) = childConclusion {
                completionDependentAtoms[nodeIndex] =
                    completionDependentAtoms[node.children[0]]
                conclusion = .undetermined(reason)
            } else {
                // 對每個 unknown 比較只翻轉該 bit 的成對 completions。只有至少一對
                // 會改變本節點結果時，該 atom 才是 mixed 結論的實際原因；單純出現在
                // syntax／mixed child 裡但被吸收律消去的 atom 不得冒充 inconclusive。
                let relevantUnknowns = node.expression.atoms.filter { candidate in
                    guard let unknownIndex = undeterminedAtoms.firstIndex(of: candidate) else {
                        return false
                    }
                    let bitOffset = undeterminedAtoms.count - unknownIndex - 1
                    guard let bitMask = productionCheckedPowerOfTwoShift(bitOffset) else {
                        preconditionFailure("bounded completion bit 必須可表示")
                    }
                    for completionIndex in 0..<completionCount
                    where completionIndex & bitMask == 0 {
                        let pairedIndex = completionIndex | bitMask
                        let value = completionOutcomes[
                            completionIndex * nodes.count + nodeIndex
                        ]
                        let pairedValue = completionOutcomes[
                            pairedIndex * nodes.count + nodeIndex
                        ]
                        if value != pairedValue { return true }
                    }
                    return false
                }
                completionDependentAtoms[nodeIndex] = relevantUnknowns
                conclusion = .undetermined(.supervaluationInconclusive(
                    atoms: relevantUnknowns
                ))
            }

            let traceKind: EvidenceTrace.Kind
            switch node.expression.kind {
            case .atom:
                preconditionFailure("atom 已在前面分流")
            case .not: traceKind = .not
            case .and: traceKind = .and
            case .or: traceKind = .or
            case .implies: traceKind = .implies
            case .nor: traceKind = .nor
            }
            let trace = EvidenceTrace.operation(
                kind: traceKind,
                expression: node.expression,
                context: context,
                children: childTraces,
                summary: SupervaluationSummary(
                    completionCount: completionCount,
                    observedTrue: observedTrue[nodeIndex],
                    observedFalse: observedFalse[nodeIndex]
                ),
                conclusion: conclusion
            )
            traces[nodeIndex] = trace
            conclusions[nodeIndex] = conclusion
        }

        guard let rootTrace = traces.first ?? nil,
              let rootConclusion = conclusions.first ?? nil else {
            preconditionFailure("非空 expression 必須產生 root valuation")
        }
        return Valuation(
            expression: self,
            truth: rootConclusion,
            context: context,
            trace: rootTrace
        )
    }
}

extension Proposition {
    /// Atomic convenience path；回傳值仍以 `.atom(self)` 作為完整 expression identity。
    public func evaluate(in context: ValuationContext) throws -> Valuation {
        try asExpression().evaluate(in: context)
    }
}

private enum ResultValue<Value> {
    case success(Value)
    case failure(UnprojectableReason)
}
