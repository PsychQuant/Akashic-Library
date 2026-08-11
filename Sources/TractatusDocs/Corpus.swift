import AkashicCore
import Foundation
import Yams

public enum CorpusSchemaError: Error, Equatable, LocalizedError {
    case unknownKey(String)
    case invalidID(String)
    case invalidRelation(String)
    case resourceLimit(kind: String, actual: Int, maximum: Int)

    public var errorDescription: String? {
        switch self {
        case let .unknownKey(key):
            return "unknown-key: 不接受欄位 \(displaySafe(key, max: 200))"
        case let .invalidID(id):
            return "invalid-id: 不合法的階層 ID \(displaySafe(id, max: 200))"
        case let .invalidRelation(value):
            return "invalid-relation: 不接受關係值 \(displaySafe(value, max: 200))"
        case let .resourceLimit(kind, actual, maximum):
            return "resource-limit: \(displaySafe(kind, max: 80)) 數量 \(actual) 超過上限 \(maximum)" // display-safe-exempt: actual 與 maximum 是程式產生的 Int 資源計數，不含 store 字串。
        }
    }

    public var diagnosticCode: String {
        switch self {
        case .unknownKey: "unknown-key"
        case .invalidID: "invalid-id"
        case .invalidRelation: "invalid-relation"
        case .resourceLimit: "resource-limit"
        }
    }

    public var diagnosticSubject: String {
        switch self {
        case let .unknownKey(value), let .invalidID(value), let .invalidRelation(value): value
        case let .resourceLimit(kind, _, _): kind
        }
    }
}

enum CorpusResourceLimits {
    static let maximumVolumeUTF8Bytes = 1 * 1024 * 1024
    static let maximumSourceManifestUTF8Bytes = 256 * 1024
    static let maximumInlineSnapshotUTF8Bytes = 2 * 1024 * 1024
    static let maximumAssetManifestUTF8Bytes = 256 * 1024
    static let maximumReferencedAssetBytes = 8 * 1024 * 1024
    static let maximumCorpusDirectoryEntries = 64
    static let maximumCorpusYAMLFiles = 8
    static let maximumPropositionsPerVolume = 256
    static let maximumRelationsPerProposition = 8
    static let maximumEvidencePerRelation = 32
    static let maximumHistoryPerProposition = 32
    static let maximumTotalEvidence = 1_024
    static let maximumTotalHistory = 512
    static let maximumEvidenceFileUTF8Bytes = 4 * 1024 * 1024
}

func enforceCorpusLimit(
    _ actual: Int,
    maximum: Int,
    kind: String
) throws {
    guard actual <= maximum else {
        throw CorpusSchemaError.resourceLimit(
            kind: kind,
            actual: actual,
            maximum: maximum
        )
    }
}

func boundedFileData(
    contentsOf url: URL,
    maximumBytes: Int,
    kind: String
) throws -> Data {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let sentinelCount = maximumBytes + 1
    var data = Data()
    data.reserveCapacity(sentinelCount)
    while data.count < sentinelCount {
        guard let chunk = try handle.read(upToCount: sentinelCount - data.count),
              !chunk.isEmpty else { break }
        data.append(chunk)
    }
    try enforceCorpusLimit(data.count, maximum: maximumBytes, kind: kind)
    return data
}

func boundedUTF8FileContents(
    of url: URL,
    maximumBytes: Int,
    kind: String
) throws -> String {
    let data = try boundedFileData(
        contentsOf: url,
        maximumBytes: maximumBytes,
        kind: kind
    )
    guard let contents = String(data: data, encoding: .utf8) else {
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
    return contents
}

func enforceCorpusAliasBudget(
    _ yaml: String,
    context: String,
    kindPrefix: String
) throws {
    do {
        try AliasEventBudget.check(yaml, context: context)
    } catch let error as AliasBudgetError {
        let resource: CorpusSchemaError?
        switch error {
        case let .expansionTooLarge(actual, maximum):
            resource = .resourceLimit(
                kind: "\(kindPrefix)-alias-expanded-nodes",
                actual: actual,
                maximum: maximum
            )
        case let .expandedBytesTooLarge(actual, maximum):
            resource = .resourceLimit(
                kind: "\(kindPrefix)-alias-expanded-bytes",
                actual: actual,
                maximum: maximum
            )
        case let .tooDeep(actual, maximum):
            resource = .resourceLimit(
                kind: "\(kindPrefix)-alias-expanded-depth",
                actual: actual,
                maximum: maximum
            )
        case let .fileTooLarge(actual, maximum):
            resource = .resourceLimit(
                kind: "\(kindPrefix)-alias-input-bytes",
                actual: actual,
                maximum: maximum
            )
        case let .contextual(_, kind):
            switch kind {
            case let .expansion(actual, maximum):
                resource = .resourceLimit(
                    kind: "\(kindPrefix)-alias-expanded-nodes",
                    actual: actual,
                    maximum: maximum
                )
            case let .bytes(actual, maximum):
                resource = .resourceLimit(
                    kind: "\(kindPrefix)-alias-expanded-bytes",
                    actual: actual,
                    maximum: maximum
                )
            case let .depth(actual, maximum):
                resource = .resourceLimit(
                    kind: "\(kindPrefix)-alias-expanded-depth",
                    actual: actual,
                    maximum: maximum
                )
            case let .size(actual, maximum):
                resource = .resourceLimit(
                    kind: "\(kindPrefix)-alias-input-bytes",
                    actual: actual,
                    maximum: maximum
                )
            case .parser:
                resource = nil
            }
        case .parserUnavailable:
            resource = nil
        }
        if let resource { throw resource }
        throw error
    }
}

/// 保留《邏輯哲學論》印刷編號的字串精度，不把 `2.010` 壓成浮點數 `2.01`。
public struct PropositionID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: String

    public init(validating rawValue: String) throws {
        guard Self.parse(rawValue) != nil else {
            throw CorpusSchemaError.invalidID(rawValue)
        }
        self.rawValue = rawValue
    }

    public init?(rawValue: String) {
        try? self.init(validating: rawValue)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var inferredParent: PropositionID? {
        guard case let .numbered(major, suffix) = Self.parse(rawValue), var suffix else {
            return nil
        }
        suffix.removeLast()
        while suffix.last == "0" {
            suffix.removeLast()
        }
        if suffix.isEmpty {
            return try? PropositionID(validating: String(major))
        }
        return try? PropositionID(validating: "\(major).\(suffix)")
    }

    public static func < (lhs: PropositionID, rhs: PropositionID) -> Bool {
        guard let left = parse(lhs.rawValue), let right = parse(rhs.rawValue) else {
            return lhs.rawValue < rhs.rawValue
        }
        switch (left, right) {
        case let (.preface(a), .preface(b)):
            return a < b
        case (.preface, .numbered):
            return true
        case (.numbered, .preface):
            return false
        case let (.numbered(aMajor, aSuffix), .numbered(bMajor, bSuffix)):
            if aMajor != bMajor { return aMajor < bMajor }
            switch (aSuffix, bSuffix) {
            case (nil, nil):
                return false
            case (nil, .some):
                return true
            case (.some, nil):
                return false
            case let (.some(a), .some(b)):
                let width = max(a.count, b.count)
                let paddedA = a + String(repeating: "0", count: width - a.count)
                let paddedB = b + String(repeating: "0", count: width - b.count)
                if paddedA != paddedB { return paddedA < paddedB }
                if a.count != b.count { return a.count < b.count }
                return a < b
            }
        }
    }

    private enum ParsedID {
        case preface(Int)
        case numbered(Int, String?)
    }

    private static func parse(_ value: String) -> ParsedID? {
        if value.hasPrefix("preface.") {
            let paragraph = value.dropFirst("preface.".count)
            guard !paragraph.isEmpty,
                  paragraph.first != "0",
                  paragraph.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(paragraph) else { return nil }
            return .preface(number)
        }

        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2,
              let major = Int(parts[0]),
              (1...7).contains(major),
              String(major) == parts[0] else { return nil }
        guard parts.count == 2 else { return .numbered(major, nil) }
        let suffix = parts[1]
        guard !suffix.isEmpty,
              suffix.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return .numbered(major, String(suffix))
    }
}

public struct SegmentID: RawRepresentable, Hashable, Comparable, Codable, Sendable {
    public let rawValue: String
    public let owner: PropositionID
    public let suffix: String

    public init(validating rawValue: String) throws {
        guard let separator = rawValue.lastIndex(of: ".") else {
            throw CorpusSchemaError.invalidID(rawValue)
        }
        let ownerText = String(rawValue[..<separator])
        let suffix = String(rawValue[rawValue.index(after: separator)...])
        guard !suffix.isEmpty,
              suffix.allSatisfy({ $0.isASCII && $0.isLowercase && $0.isLetter }),
              let owner = PropositionID(rawValue: ownerText) else {
            throw CorpusSchemaError.invalidID(rawValue)
        }
        self.rawValue = rawValue
        self.owner = owner
        self.suffix = suffix
    }

    public init?(rawValue: String) {
        try? self.init(validating: rawValue)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(validating: container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: SegmentID, rhs: SegmentID) -> Bool {
        if lhs.owner != rhs.owner { return lhs.owner < rhs.owner }
        return lhs.suffix < rhs.suffix
    }
}

public enum RelationStatus: String, Codable, CaseIterable, Sendable {
    case implemented
    case partial
    case aspirational
    case analogyOnly = "analogy_only"
    case rejected
    case notApplicable = "not_applicable"
    case intentionalNonconformance = "intentional_nonconformance"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let status = Self(rawValue: value) else {
            throw CorpusSchemaError.invalidRelation(value)
        }
        self = status
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum RelationMode: String, Codable, CaseIterable, Sendable {
    case instance
    case structuralInvariant = "structural_invariant"
    case semanticOperation = "semantic_operation"
    case formalDerivation = "formal_derivation"
    case refusal
    case shownConstraint = "shown_constraint"
    case metaElucidation = "meta_elucidation"
    case declaredNonconformance = "declared_nonconformance"

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let mode = Self(rawValue: value) else {
            throw CorpusSchemaError.invalidRelation(value)
        }
        self = mode
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum EvidenceLocatorKind: String, Codable, CaseIterable, Sendable {
    case symbol
    case requirement
    case test
    case heading
}

public enum HistoryReferenceKind: String, Codable, CaseIterable, Sendable {
    case branch
    case commit
    case issue
}

public enum HistoryDisposition: String, Codable, CaseIterable, Sendable {
    case retained
    case revised
    case rejected
}

public struct CorpusVolume: Decodable, Equatable, Sendable {
    public let schemaVersion: Int
    public let volume: String
    public let propositions: [PropositionRecord]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case volume
        case propositions
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(from: decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        volume = try container.decode(String.self, forKey: .volume)
        propositions = try container.decode([PropositionRecord].self, forKey: .propositions)
        try enforceCorpusLimit(
            propositions.count,
            maximum: CorpusResourceLimits.maximumPropositionsPerVolume,
            kind: "propositions-per-volume"
        )
    }
}

public struct PropositionRecord: Decodable, Equatable, Sendable {
    public let id: PropositionID
    public let parent: PropositionID?
    public let texts: [String: [String]]
    public let editionReferences: [String: String]
    public let segments: [AlignedSegment]
    public let synthesisZhTW: String?
    public let projectRelations: [ProjectRelation]
    public let history: [HistoryReference]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case parent
        case texts
        case editionReferences = "edition_references"
        case segments
        case synthesisZhTW = "synthesis_zh_tw"
        case projectRelations = "project_relations"
        case history
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(from: decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PropositionID.self, forKey: .id)
        parent = try container.decodeIfPresent(PropositionID.self, forKey: .parent)
        texts = try container.decode([String: [String]].self, forKey: .texts)
        editionReferences = try container.decodeIfPresent(
            [String: String].self,
            forKey: .editionReferences
        ) ?? [:]
        segments = try container.decode([AlignedSegment].self, forKey: .segments)
        synthesisZhTW = try container.decodeIfPresent(String.self, forKey: .synthesisZhTW)
        projectRelations = try container.decodeIfPresent(
            [ProjectRelation].self,
            forKey: .projectRelations
        ) ?? []
        history = try container.decodeIfPresent([HistoryReference].self, forKey: .history) ?? []
        try enforceCorpusLimit(
            projectRelations.count,
            maximum: CorpusResourceLimits.maximumRelationsPerProposition,
            kind: "relations-per-proposition"
        )
        try enforceCorpusLimit(
            history.count,
            maximum: CorpusResourceLimits.maximumHistoryPerProposition,
            kind: "history-per-proposition"
        )
    }
}

public struct AlignedSegment: Decodable, Equatable, Sendable {
    public let id: SegmentID
    public let alignment: [String: [Int]]
    public let translationZhTW: String
    public let interpretationZhTW: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case alignment
        case translationZhTW = "translation_zh_tw"
        case interpretationZhTW = "interpretation_zh_tw"
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(from: decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SegmentID.self, forKey: .id)
        alignment = try container.decode([String: [Int]].self, forKey: .alignment)
        translationZhTW = try container.decode(String.self, forKey: .translationZhTW)
        interpretationZhTW = try container.decode(String.self, forKey: .interpretationZhTW)
    }
}

public struct ProjectRelation: Decodable, Equatable, Sendable {
    public let status: RelationStatus
    public let mode: RelationMode?
    public let claimZhTW: String
    public let rationaleZhTW: String
    public let evidence: [CurrentEvidence]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case status
        case mode
        case claimZhTW = "claim_zh_tw"
        case rationaleZhTW = "rationale_zh_tw"
        case evidence
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(from: decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(RelationStatus.self, forKey: .status)
        mode = try container.decodeIfPresent(RelationMode.self, forKey: .mode)
        claimZhTW = try container.decode(String.self, forKey: .claimZhTW)
        rationaleZhTW = try container.decode(String.self, forKey: .rationaleZhTW)
        evidence = try container.decodeIfPresent([CurrentEvidence].self, forKey: .evidence) ?? []
        try enforceCorpusLimit(
            evidence.count,
            maximum: CorpusResourceLimits.maximumEvidencePerRelation,
            kind: "evidence-per-relation"
        )
    }
}

public struct CurrentEvidence: Decodable, Equatable, Sendable {
    public let path: String
    public let kind: EvidenceLocatorKind
    public let locator: String
    public let noteZhTW: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case path
        case kind
        case locator
        case noteZhTW = "note_zh_tw"
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(from: decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        kind = try container.decode(EvidenceLocatorKind.self, forKey: .kind)
        locator = try container.decode(String.self, forKey: .locator)
        noteZhTW = try container.decodeIfPresent(String.self, forKey: .noteZhTW)
    }
}

public struct HistoryReference: Decodable, Equatable, Sendable {
    public let kind: HistoryReferenceKind
    public let reference: String
    public let disposition: HistoryDisposition
    public let noteZhTW: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case reference
        case disposition
        case noteZhTW = "note_zh_tw"
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(from: decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(HistoryReferenceKind.self, forKey: .kind)
        reference = try container.decode(String.self, forKey: .reference)
        disposition = try container.decode(HistoryDisposition.self, forKey: .disposition)
        noteZhTW = try container.decode(String.self, forKey: .noteZhTW)
    }
}

public enum CorpusYAMLDecoder {
    public static func decodeVolume(_ yaml: String) throws -> CorpusVolume {
        try enforceCorpusLimit(
            yaml.utf8.count,
            maximum: CorpusResourceLimits.maximumVolumeUTF8Bytes,
            kind: "volume-utf8-bytes"
        )
        try enforceCorpusAliasBudget(
            yaml,
            context: "tractatus corpus volume",
            kindPrefix: "volume"
        )
        do {
            return try YAMLDecoder().decode(CorpusVolume.self, from: yaml)
        } catch {
            if let schemaError = schemaError(wrappedBy: error) {
                throw schemaError
            }
            throw error
        }
    }

    public static func decodeVolume(contentsOf url: URL) throws -> CorpusVolume {
        let yaml = try boundedUTF8FileContents(
            of: url,
            maximumBytes: CorpusResourceLimits.maximumVolumeUTF8Bytes,
            kind: "volume-utf8-bytes"
        )
        return try decodeVolume(yaml)
    }

    private static func schemaError(wrappedBy error: Error) -> CorpusSchemaError? {
        if let schemaError = error as? CorpusSchemaError { return schemaError }
        let context: DecodingError.Context
        switch error {
        case let DecodingError.dataCorrupted(value):
            context = value
        case let DecodingError.keyNotFound(_, value):
            context = value
        case let DecodingError.typeMismatch(_, value):
            context = value
        case let DecodingError.valueNotFound(_, value):
            context = value
        default:
            return nil
        }
        guard let underlying = context.underlyingError else { return nil }
        return schemaError(wrappedBy: underlying)
    }
}

struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

func rejectUnknownKeys(from decoder: Decoder, allowed: [String]) throws {
    let container = try decoder.container(keyedBy: AnyCodingKey.self)
    let allowedSet = Set(allowed)
    if let unknown = container.allKeys
        .map(\.stringValue)
        .filter({ !allowedSet.contains($0) })
        .sorted()
        .first {
        throw CorpusSchemaError.unknownKey(unknown)
    }
}

/// 語料載入、驗證與 rendering 的唯一公開邊界。
///
/// executable target 只把命令列參數轉成 URL 與旗標；文件行為一律留在這個
/// library target。後續任務會以 typed corpus 實作這兩個入口。
public enum TractatusDocuments {
    public static func validate(root: URL, allowIncomplete: Bool) throws -> String {
        try CorpusValidationEngine.validate(root: root, allowIncomplete: allowIncomplete).output
    }

    public static func render(root: URL, output: URL, check: Bool) throws -> String {
        try CorpusRenderEngine.render(root: root, output: output, check: check)
    }
}
