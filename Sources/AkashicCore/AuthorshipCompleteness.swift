import CryptoKit
import Foundation
import Yams

/// Ordered exact author snapshot 的版本化、domain-separated SHA-256 binding。
public struct AuthorListFingerprint: Equatable, Hashable, Sendable {
    public let digest: String

    /// Persisted digest 的 strict parser；不合法的大小寫、長度或 prefix 一律拒絕。
    public init(digest: String) throws {
        guard ProvenanceReference.isValidDigest(digest) else {
            throw AuthorshipCompletenessValidationError(
                reason: .malformedFingerprint,
                detail: digest)
        }
        self.digest = digest
    }

    /// v1 framing：domain bytes、UInt64 BE slot count，接著每個 slot 的 one-byte
    /// case tag、UInt64 BE raw UTF-8 length 與 raw UTF-8 bytes。
    public init(authors: [Author]) {
        var hasher = SHA256()
        hasher.update(data: Data("akashic-author-list-v1".utf8))
        Self.update(UInt64(authors.count), in: &hasher)

        for author in authors {
            let tag: UInt8
            let value: String
            switch author {
            case .key(let key):
                tag = 0
                value = key
            case .organization(let key):
                // **tag 2 是新值，不重用 0/1**（#323）：若團體作者沿用 tag 0，
                // `.key("x")` 與 `.organization("x")` 會雜湊成同一值——見證的用途正是
                // 分辨作者清單有沒有變，把兩種不同的歸戶混為一談會讓變更靜默通過。
                tag = 2
                value = key
            case .literal(let literal):
                tag = 1
                value = literal
            }
            let bytes = Data(value.utf8)
            hasher.update(data: Data([tag]))
            Self.update(UInt64(bytes.count), in: &hasher)
            hasher.update(data: bytes)
        }

        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        digest = "sha256:\(hex)"
    }

    private static func update(_ value: UInt64, in hasher: inout SHA256) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { buffer in
            hasher.update(data: Data(buffer))
        }
    }
}

/// Witness 建構／decode 的穩定、typed validation surface。
public struct AuthorshipCompletenessValidationError:
    Error, Equatable, LocalizedError, CustomStringConvertible, CustomDebugStringConvertible
{
    public enum Reason: Equatable, Hashable, Sendable {
        case malformedFingerprint
        case fingerprintMismatch
        case authorKey(index: Int)
        case authorLiteral(index: Int)
        case referencesRequired
        case referenceField(index: Int)
        case referenceValue(index: Int)
        case retrievalURL(index: Int)
        case retrievalDate(index: Int)
        case retrievalDigest(index: Int)
        case judgementStatement(index: Int)
        case judgementRestsOn(index: Int)
        case judgementDigest(index: Int)
        case retrievalRequired
        case judgementRequired
        case judgementDigestNotRetrieved(index: Int)
    }

    public let reason: Reason
    /// 已消毒且有固定 post-escape 上限；不得再由 reflection 洩漏原始輸入。
    public let detail: String?

    init(reason: Reason, detail: String? = nil) {
        self.reason = reason
        self.detail = detail.map { Self.boundedDisplaySafe($0) }
    }

    public var errorDescription: String? {
        let base: String
        switch reason {
        case .malformedFingerprint:
            base = "author-list fingerprint 必須是 sha256: 加 64 個小寫 hex"
        case .fingerprintMismatch:
            base = "author-list fingerprint 與 attested authors 不符"
        case .authorKey(let index):
            base = "attested-authors[\(index)].key 不符合 StoreKey"
        case .authorLiteral(let index):
            base = "attested-authors[\(index)].literal 不得為空"
        case .referencesRequired:
            base = "author-list completeness references 不得為空"
        case .referenceField(let index):
            base = "references[\(index)].field 必須恰為 authors"
        case .referenceValue(let index):
            base = "references[\(index)].value 必須缺席"
        case .retrievalURL(let index):
            base = "references[\(index)] retrieval URL 不得為空"
        case .retrievalDate(let index):
            base = "references[\(index)] retrieval date 不得為空"
        case .retrievalDigest(let index):
            base = "references[\(index)] retrieval content digest 不合法"
        case .judgementStatement(let index):
            base = "references[\(index)] judgement statement 不得為空"
        case .judgementRestsOn(let index):
            base = "references[\(index)] judgement rests-on 不得為空"
        case .judgementDigest(let index):
            base = "references[\(index)] judgement digest 不合法"
        case .retrievalRequired:
            base = "author-list completeness 至少需要一筆 retrieval"
        case .judgementRequired:
            base = "author-list completeness 至少需要一筆 judgement"
        case .judgementDigestNotRetrieved(let index):
            base = "references[\(index)] judgement 引用 bundle 外部 digest"
        }
        guard let detail else { return base }
        return "\(base)：\(detail)"
    }

    public var description: String { errorDescription ?? "AuthorshipCompletenessValidationError" }
    public var debugDescription: String { description }

    /// 先逐 scalar 做 displaySafe，再以輸出 scalar 數量計預算；永不切斷 escape token。
    private static func boundedDisplaySafe(_ raw: String, maximum: Int = 160) -> String {
        var result = ""
        var used = 0
        var truncated = false
        for scalar in raw.unicodeScalars {
            let escaped = displaySafe(String(scalar), max: 1)
            let cost = escaped.unicodeScalars.count
            if used + cost > maximum - 1 {
                truncated = true
                break
            }
            result += escaped
            used += cost
        }
        if truncated { result += "…" }
        return result
    }
}

public enum AuthorListCompletenessBindingIssue: Equatable, Hashable, Sendable {
    public enum Kind: Int, Equatable, Hashable, Sendable {
        case workID
        case authorSnapshot
    }

    case workID(witness: UUID, current: UUID)
    case authorSnapshot(attested: AuthorListFingerprint, current: AuthorListFingerprint)

    public var kind: Kind {
        switch self {
        case .workID: return .workID
        case .authorSnapshot: return .authorSnapshot
        }
    }

    fileprivate var stableKey: String {
        switch self {
        case let .workID(witness, current):
            return "0\u{0}\(witness.uuidString)\u{0}\(current.uuidString)"   // display-safe-exempt: UUID.uuidString 是固定 ASCII hex+dash；本值只作排序鍵、不進輸出
        case let .authorSnapshot(attested, current):
            return "1\u{0}\(attested.digest)\u{0}\(current.digest)"   // display-safe-exempt: fingerprint 已 strict 限為固定長度 sha256 小寫 hex；本值只作排序鍵、不進輸出
        }
    }
}

/// Programmatic model 與 decode 共用的 deterministic aggregate binding refusal。
public struct AuthorListCompletenessBindingError:
    Error, Equatable, LocalizedError, CustomStringConvertible, CustomDebugStringConvertible
{
    public let issues: [AuthorListCompletenessBindingIssue]

    public init(issues: [AuthorListCompletenessBindingIssue]) {
        self.issues = Array(Set(issues)).sorted { $0.stableKey < $1.stableKey }
    }

    public var errorDescription: String? {
        guard !issues.isEmpty else {
            return "author-list completeness binding error（無 issue）"
        }
        let displayed = issues.prefix(2)
        let parts = displayed.map { issue in
            switch issue {
            case let .workID(witness, current):
                return "work UUID 不符（witness \(witness.uuidString)，current \(current.uuidString)）"   // display-safe-exempt: UUID.uuidString 是固定 ASCII hex+dash
            case let .authorSnapshot(attested, current):
                return "ordered raw author snapshot 不符（attested \(attested.digest)，current \(current.digest)）"   // display-safe-exempt: fingerprint 已 strict 限為固定長度 sha256 小寫 hex
            }
        }
        var message = "author-list completeness binding error：" + parts.joined(separator: "；")
        if issues.count > displayed.count {
            message += "；另有 \(issues.count - displayed.count) 項（完整 machine payload 請讀 issues）"
        }
        return Self.boundedDescription(message)
    }

    public var description: String { errorDescription ?? "AuthorListCompletenessBindingError" }
    public var debugDescription: String { description }

    /// 人類顯示面同時限制筆數與總長；typed `issues` 不截斷。
    private static func boundedDescription(_ text: String, maximum: Int = 480) -> String {
        let scalars = text.unicodeScalars
        guard scalars.count > maximum else { return text }
        return String(String.UnicodeScalarView(scalars.prefix(maximum - 1))) + "…"
    }
}

/// Akashic-owned canonical Entry metadata 所保存的作者清單完備性證言。
public struct AuthorListCompletenessWitness: Equatable {
    public let workID: UUID
    public let fingerprint: AuthorListFingerprint
    public let attestedAuthors: [Author]
    public let references: [ProvenanceReference]

    public init(
        workID: UUID,
        fingerprint: AuthorListFingerprint,
        attestedAuthors: [Author],
        references: [ProvenanceReference]
    ) throws {
        for (index, author) in attestedAuthors.enumerated() {
            switch author {
            case .key(let key), .organization(let key):
                // organization key 與 person key 同樣受 StoreKey 約束（#323）。
                guard StoreKey.isValid(key) else {
                    throw AuthorshipCompletenessValidationError(
                        reason: .authorKey(index: index), detail: key)
                }
            case .literal(let literal):
                guard !literal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw AuthorshipCompletenessValidationError(
                        reason: .authorLiteral(index: index), detail: literal)
                }
            }
        }

        let derived = AuthorListFingerprint(authors: attestedAuthors)
        guard fingerprint == derived else {
            throw AuthorshipCompletenessValidationError(
                reason: .fingerprintMismatch,
                detail: "persisted \(fingerprint.digest) / derived \(derived.digest)")
        }
        guard !references.isEmpty else {
            throw AuthorshipCompletenessValidationError(reason: .referencesRequired)
        }

        var retrievalDigests = Set<String>()
        var judgementDigests: [(index: Int, digest: String)] = []
        var hasRetrieval = false
        var hasJudgement = false
        for (index, reference) in references.enumerated() {
            guard reference.field == "authors" else {
                throw AuthorshipCompletenessValidationError(
                    reason: .referenceField(index: index), detail: reference.field)
            }
            guard reference.value == nil else {
                throw AuthorshipCompletenessValidationError(
                    reason: .referenceValue(index: index), detail: reference.value)
            }
            switch reference.kind {
            case let .retrieval(url, retrieved, _, _, content):
                guard !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw AuthorshipCompletenessValidationError(
                        reason: .retrievalURL(index: index), detail: url)
                }
                guard !retrieved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw AuthorshipCompletenessValidationError(
                        reason: .retrievalDate(index: index), detail: retrieved)
                }
                guard ProvenanceReference.isValidDigest(content) else {
                    throw AuthorshipCompletenessValidationError(
                        reason: .retrievalDigest(index: index), detail: content)
                }
                hasRetrieval = true
                retrievalDigests.insert(content)
            case let .judgement(statement, restsOn):
                guard !statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw AuthorshipCompletenessValidationError(
                        reason: .judgementStatement(index: index), detail: statement)
                }
                guard !restsOn.isEmpty else {
                    throw AuthorshipCompletenessValidationError(
                        reason: .judgementRestsOn(index: index))
                }
                for digest in restsOn {
                    guard ProvenanceReference.isValidDigest(digest) else {
                        throw AuthorshipCompletenessValidationError(
                            reason: .judgementDigest(index: index), detail: digest)
                    }
                    judgementDigests.append((index, digest))
                }
                hasJudgement = true
            }
        }
        guard hasRetrieval else {
            throw AuthorshipCompletenessValidationError(reason: .retrievalRequired)
        }
        guard hasJudgement else {
            throw AuthorshipCompletenessValidationError(reason: .judgementRequired)
        }
        if let external = judgementDigests.first(where: { !retrievalDigests.contains($0.digest) }) {
            throw AuthorshipCompletenessValidationError(
                reason: .judgementDigestNotRetrieved(index: external.index),
                detail: external.digest)
        }

        self.workID = workID
        self.fingerprint = fingerprint
        self.attestedAuthors = attestedAuthors
        self.references = references
    }

    /// Exact Entry binding；citekey 不在 binding 中，work UUID 與 ordered raw authors 才在。
    public func validateBinding(workID currentWorkID: UUID, authors currentAuthors: [Author]) throws {
        var issues: [AuthorListCompletenessBindingIssue] = []
        if workID != currentWorkID {
            issues.append(.workID(witness: workID, current: currentWorkID))
        }
        let currentFingerprint = AuthorListFingerprint(authors: currentAuthors)
        if fingerprint != currentFingerprint
            || !Self.rawAuthorSnapshotsEqual(attestedAuthors, currentAuthors) {
            issues.append(.authorSnapshot(attested: fingerprint, current: currentFingerprint))
        }
        if !issues.isEmpty {
            throw AuthorListCompletenessBindingError(issues: issues)
        }
    }

    /// Fingerprint 之外的 redundant exact guard；不用 Swift String equality，因其會把
    /// canonically-equivalent NFC／NFD 視為相等。
    static func rawAuthorSnapshotsEqual(_ lhs: [Author], _ rhs: [Author]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            switch (left, right) {
            case let (.key(leftValue), .key(rightValue)),
                 let (.organization(leftValue), .organization(rightValue)),
                 let (.literal(leftValue), .literal(rightValue)):
                return leftValue.utf8.elementsEqual(rightValue.utf8)
            // **跨態一律不等**（#323）：同一個字串在不同態下是不同的事實
            // （`.key("x")` ＝已判定為人；`.organization("x")` ＝已判定為團體；
            // `.literal("x")` ＝未判定）。混為相等會讓歸戶動作在見證上看不出來。
            case (.key, _), (.organization, _), (.literal, _):
                return false
            }
        }
    }
}

/// `akashic.author-list-completeness` 的 strict canonical codec。
enum AuthorListCompletenessYAML {
    private static let knownKeys: Set<String> = [
        "work-id", "author-list-fingerprint", "attested-authors", "references",
    ]

    static func node(_ witness: AuthorListCompletenessWitness) throws -> Node {
        let authorNodes = witness.attestedAuthors.map { author -> Node in
            switch author {
            case .key(let key):
                return Node([
                    (Node("key"), ProvenanceYAML.strictStringNode(key)),
                ] as [(Node, Node)])
            case .organization(let key):
                return Node([
                    (Node("organization"), ProvenanceYAML.strictStringNode(key)),
                ] as [(Node, Node)])
            case .literal(let literal):
                return Node([
                    (Node("literal"), ProvenanceYAML.strictStringNode(literal)),
                ] as [(Node, Node)])
            }
        }
        return Node([
            (Node("work-id"), ProvenanceYAML.strictStringNode(witness.workID.uuidString)),
            (Node("author-list-fingerprint"),
             ProvenanceYAML.strictStringNode(witness.fingerprint.digest)),
            (Node("attested-authors"), Node(authorNodes)),
            (Node("references"), try ProvenanceYAML.strictNode(witness.references)),
        ] as [(Node, Node)])
    }

    static func decode(
        _ node: Node,
        entryWorkID: UUID,
        entryAuthors: [Author]
    ) throws -> AuthorListCompletenessWitness {
        guard let map = node.mapping else {
            throw StoreYAMLError.invalidField(
                "akashic.author-list-completeness", "必須是 mapping")
        }
        try EntryYAML.rejectUnknownKeys(
            map, known: knownKeys, context: "akashic.author-list-completeness")
        try rejectDuplicateKeys(map, context: "akashic.author-list-completeness")

        guard let workNode = map["work-id"] else {
            throw StoreYAMLError.missingField("akashic.author-list-completeness.work-id")
        }
        let workString = try strictString(
            workNode, context: "akashic.author-list-completeness.work-id")
        guard let workID = UUID(uuidString: workString) else {
            throw StoreYAMLError.invalidField(
                "akashic.author-list-completeness.work-id", "必須是 UUID")
        }

        guard let fingerprintNode = map["author-list-fingerprint"] else {
            throw StoreYAMLError.missingField(
                "akashic.author-list-completeness.author-list-fingerprint")
        }
        let fingerprintString = try strictString(
            fingerprintNode,
            context: "akashic.author-list-completeness.author-list-fingerprint")
        let fingerprint = try AuthorListFingerprint(digest: fingerprintString)

        guard let authorsNode = map["attested-authors"],
              let authorSequence = authorsNode.sequence else {
            throw StoreYAMLError.invalidField(
                "akashic.author-list-completeness.attested-authors",
                "必須是 sequence（exact 空清單請寫 []）")
        }
        let attestedAuthors: [Author] = try authorSequence.enumerated().map { index, item in
            let context = "akashic.author-list-completeness.attested-authors[\(index)]"
            guard let authorMap = item.mapping else {
                throw StoreYAMLError.invalidField(context, "必須是 mapping")
            }
            try EntryYAML.rejectUnknownKeys(
                authorMap, known: ["key", "literal"], context: context)
            try rejectDuplicateKeys(authorMap, context: context)
            let key = try authorMap["key"].map {
                try strictString($0, context: "\(context).key")
            }
            let literal = try authorMap["literal"].map {
                try strictString($0, context: "\(context).literal")
            }
            switch (key, literal) {
            case (let value?, nil): return .key(value)
            case (nil, let value?): return .literal(value)
            default:
                throw StoreYAMLError.invalidField(
                    context, "必須恰好有 key 或 literal 其一")
            }
        }

        guard let referencesNode = map["references"] else {
            throw StoreYAMLError.missingField(
                "akashic.author-list-completeness.references")
        }
        if let sequence = referencesNode.sequence {
            for (index, item) in sequence.enumerated() {
                guard let referenceMap = item.mapping else { continue }
                let context = "akashic.author-list-completeness.references[\(index)]"
                try rejectDuplicateKeys(
                    referenceMap,
                    context: context)
                try validateReferenceTags(referenceMap, context: context)
            }
        }
        let references = try ProvenanceYAML.decode(
            referencesNode, context: "akashic.author-list-completeness")
        let witness = try AuthorListCompletenessWitness(
            workID: workID,
            fingerprint: fingerprint,
            attestedAuthors: attestedAuthors,
            references: references)
        try witness.validateBinding(workID: entryWorkID, authors: entryAuthors)
        return witness
    }

    private static func strictString(_ node: Node, context: String) throws -> String {
        guard let scalar = node.scalar, node.tag == Tag(.str) else {
            throw StoreYAMLError.invalidField(context, "必須是 string scalar")
        }
        return scalar.string
    }

    private static func validateReferenceTags(
        _ map: Node.Mapping,
        context: String
    ) throws {
        try EntryYAML.rejectUnknownKeys(map, known: ProvenanceYAML.knownKeys, context: context)
        guard map["value"] == nil else {
            throw StoreYAMLError.invalidField("\(context).value", "必須缺席")
        }

        for key in ["field", "url", "retrieved", "media-type", "content", "judgement"] {
            if let node = map[key] {
                _ = try strictString(node, context: "\(context).\(key)")
            }
        }
        if let status = map["status"] {
            guard status.scalar != nil, status.tag == Tag(.int) else {
                throw StoreYAMLError.invalidField("\(context).status", "必須是 int scalar")
            }
        }
        if let restsOn = map["rests-on"] {
            guard let sequence = restsOn.sequence else {
                throw StoreYAMLError.invalidField("\(context).rests-on", "必須是 sequence")
            }
            for (index, node) in sequence.enumerated() {
                _ = try strictString(node, context: "\(context).rests-on[\(index)]")
            }
        }
    }

    private static func rejectDuplicateKeys(
        _ map: Node.Mapping,
        context: String
    ) throws {
        var seen = Set<String>()
        for (key, _) in map {
            guard let scalar = key.scalar else {
                throw StoreYAMLError.invalidField(context, "非 scalar 鍵")
            }
            let value = scalar.string
            guard key.tag == Tag(.str) else {
                throw StoreYAMLError.invalidField(
                    context,
                    "鍵「\(displaySafe(value, max: 120))」帶非字串 tag——strict mapping 不接受")
            }
            guard seen.insert(value).inserted else {
                throw StoreYAMLError.invalidField(
                    context,
                    "鍵「\(displaySafe(value, max: 120))」重複——strict mapping 不採 first/last-wins")
            }
        }
    }
}
