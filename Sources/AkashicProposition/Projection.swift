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
public enum TruthValue: Equatable {
    case holds
    case fails
    case undetermined(UndeterminedReason)
}

public enum UndeterminedReason: Equatable {
    case notProjectable(UnprojectableReason)
    case noSupportingEvidence
    case supportingEvidenceUnresolved(literal: String)
    /// 存在尚未歸戶、但沒有直接名稱匹配的作者槽；仍不得由字面差異推成反證。
    case authorIdentityUnresolved(literal: String)
    case temporalEvidenceIndeterminate
    case invalidTemporalEvidence
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
    Error, Equatable, LocalizedError, CustomStringConvertible, CustomDebugStringConvertible
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

        // `displaySafe(max: 120)` 限制的是輸入 scalar；控制字元跳脫後仍可能膨脹。
        // 再施加一層固定顯示上限，避免大量反斜線把三類聚合診斷放大；不改上方完整的
        // machine-readable payload。
        func boundedKey(_ key: String) -> String {
            let safe = displaySafe(key, max: 120)
            guard safe.count > 120 else { return safe }
            return String(safe.prefix(119)) + "…"
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
        let maximum = 2_000
        guard message.unicodeScalars.count > maximum else { return message }
        return String(String.UnicodeScalarView(message.unicodeScalars.prefix(maximum - 1))) + "…"
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
}

/// Expression 的唯讀遞迴證據樹。外部 caller 可逐層稽核，但不能自行組裝假結論。
public struct EvidenceTrace: Equatable {
    public enum Kind: Equatable {
        case atom
        case negation
    }

    /// Storage 與 constructor 都留在 module 內；public API 只回傳不可變的 value view。
    private indirect enum Storage {
        case atom(AtomicEvidenceTrace)
        case negation(operand: Storage, conclusion: TruthValue)
    }

    private let storage: Storage

    private init(storage: Storage) {
        self.storage = storage
    }

    static func atom(_ trace: AtomicEvidenceTrace) -> EvidenceTrace {
        EvidenceTrace(storage: .atom(trace))
    }

    /// 結論只能由 operand 機械導出；沒有可傳入任意 conclusion 的 constructor。
    static func negating(_ operand: EvidenceTrace) -> EvidenceTrace {
        EvidenceTrace(storage: .negation(
            operand: operand.storage,
            conclusion: operand.conclusion.negatedForExpression
        ))
    }

    public var kind: Kind {
        switch storage {
        case .atom: return .atom
        case .negation: return .negation
        }
    }

    public var operand: EvidenceTrace? {
        guard case .negation(let operand, _) = storage else { return nil }
        return EvidenceTrace(storage: operand)
    }

    /// 最內層 atomic evidence 的完整唯讀 view。
    public var atomic: AtomicEvidenceTrace {
        var current = storage
        while case .negation(let operand, _) = current { current = operand }
        guard case .atom(let trace) = current else {
            preconditionFailure("EvidenceTrace storage 目前只有 atom／negation")
        }
        return trace
    }

    public var scope: PredicateScope { atomic.scope }
    public var projection: EvidenceProjection { atomic.projection }
    public var evidence: [EvidenceItem] { atomic.evidence }
    public var snapshotQuarantine: [QuarantinedFile] { atomic.snapshotQuarantine }

    public var conclusion: TruthValue {
        switch storage {
        case .atom(let trace): return trace.conclusion
        case .negation(_, let conclusion): return conclusion
        }
    }

    /// 深鏈比較只移動 storage cursor，不使用 recursive enum 的 synthesized equality。
    public static func == (lhs: EvidenceTrace, rhs: EvidenceTrace) -> Bool {
        var left = lhs.storage
        var right = rhs.storage
        while true {
            switch (left, right) {
            case let (.atom(leftTrace), .atom(rightTrace)):
                return leftTrace == rightTrace
            case let (
                .negation(leftOperand, leftConclusion),
                .negation(rightOperand, rightConclusion)
            ):
                guard leftConclusion == rightConclusion else { return false }
                left = leftOperand
                right = rightOperand
            case (.atom, .negation), (.negation, .atom):
                return false
            }
        }
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
            negatedExpression == .not(expression),
            "negation valuation 的 expression 必須恰為 operand expression 的 not"
        )
        let negatedTrace = EvidenceTrace.negating(trace)
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
            return valuation(
                truth: truth,
                context: context,
                scope: predicateScope,
                projection: .unprojectable(reason),
                evidence: []
            )
        }

        switch (self, projected) {
        case let (.authored, .authored(person, work)):
            return evaluateAuthored(person: person, work: work, context: context)
        case let (.affiliated, .affiliated(person, organization)):
            return evaluateAffiliated(
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
    ) -> Valuation {
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
            case .literal(let literal):
                let candidate = person.names.contains {
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
        return valuation(
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
    ) -> Valuation {
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
        return valuation(
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
    ) -> Valuation {
        Valuation(
            expression: expression,
            truth: truth,
            context: context,
            trace: .atom(AtomicEvidenceTrace(
                scope: scope,
                projection: projection,
                evidence: evidence,
                snapshotQuarantine: context.model.snapshotQuarantine,
                conclusion: truth
            ))
        )
    }
}

extension PropositionExpression {
    /// 只透過明示的 snapshot／day context 求值。先以迭代 traversal 驗證完整 expression，
    /// atom 僅投射／求值一次，再由內向外建立一層一層的 negation trace。
    public func evaluate(in context: ValuationContext) throws -> Valuation {
        let decomposition = try validatedAtomAndDepth()
        var valuation = try decomposition.atom.evaluateAtom(in: context)
        for _ in 0..<decomposition.depth {
            valuation = valuation.negated(as: .not(valuation.expression))
        }
        return valuation
    }
}

extension Proposition {
    /// Atomic convenience path；回傳值仍以 `.atom(self)` 作為完整 expression identity。
    public func evaluate(in context: ValuationContext) throws -> Valuation {
        try expression.evaluate(in: context)
    }
}

private enum ResultValue<Value> {
    case success(Value)
    case failure(UnprojectableReason)
}
