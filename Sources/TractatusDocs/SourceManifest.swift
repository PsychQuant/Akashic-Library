import CryptoKit
import Foundation
import Yams

public enum EditionRole: String, Codable, CaseIterable, Sendable {
    case original
    case translation
}

public enum CopyrightStatus: String, Codable, CaseIterable, Sendable {
    case publicDomain = "public_domain"
    case copyrighted
    case licensed
}

public enum InclusionMode: String, Codable, CaseIterable, Sendable {
    case inline
    case externalReference = "external_reference"
}

public struct SourceManifest: Decodable, Equatable, Sendable {
    public let schemaVersion: Int
    public let scope: CanonicalScope
    public let editions: [SourceEdition]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion = "schema_version"
        case scope
        case editions
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(from: decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        scope = try container.decode(CanonicalScope.self, forKey: .scope)
        editions = try container.decode([SourceEdition].self, forKey: .editions)
        try enforceCorpusLimit(
            editions.count,
            maximum: CorpusResourceLimits.maximumSourceEditions,
            kind: "source-editions"
        )
    }
}

public struct CanonicalScope: Decodable, Equatable, Sendable {
    public let inventory: [String]
    public let dedication: String
    public let motto: SourceMotto
    public let excluded: [String]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case inventory
        case dedication
        case motto
        case excluded
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(from: decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inventory = try container.decode([String].self, forKey: .inventory)
        dedication = try container.decode(String.self, forKey: .dedication)
        motto = try container.decode(SourceMotto.self, forKey: .motto)
        excluded = try container.decode([String].self, forKey: .excluded)
    }
}

public struct SourceMotto: Decodable, Equatable, Sendable {
    public let text: String
    public let attribution: String

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case text
        case attribution
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(from: decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        attribution = try container.decode(String.self, forKey: .attribution)
    }
}

public struct SourceEdition: Decodable, Equatable, Sendable {
    public let id: String
    public let role: EditionRole
    public let language: String
    public let bibliography: String
    public let sourceURL: String
    public let retrievalDate: String
    public let upstreamRevision: String
    public let sha256: String?
    public let copyrightStatus: CopyrightStatus
    public let rightsNote: String
    public let licenseEvidenceURL: String?
    public let inclusionMode: InclusionMode
    public let snapshot: String?

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case role
        case language
        case bibliography
        case sourceURL = "source_url"
        case retrievalDate = "retrieval_date"
        case upstreamRevision = "upstream_revision"
        case sha256
        case copyrightStatus = "copyright_status"
        case rightsNote = "rights_note"
        case licenseEvidenceURL = "license_evidence_url"
        case inclusionMode = "inclusion_mode"
        case snapshot
    }

    public init(from decoder: Decoder) throws {
        try rejectUnknownKeys(from: decoder, allowed: CodingKeys.allCases.map(\.rawValue))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(EditionRole.self, forKey: .role)
        language = try container.decode(String.self, forKey: .language)
        bibliography = try container.decode(String.self, forKey: .bibliography)
        sourceURL = try container.decode(String.self, forKey: .sourceURL)
        retrievalDate = try container.decode(String.self, forKey: .retrievalDate)
        upstreamRevision = try container.decode(String.self, forKey: .upstreamRevision)
        sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
        copyrightStatus = try container.decode(CopyrightStatus.self, forKey: .copyrightStatus)
        rightsNote = try container.decode(String.self, forKey: .rightsNote)
        licenseEvidenceURL = try container.decodeIfPresent(String.self, forKey: .licenseEvidenceURL)
        inclusionMode = try container.decode(InclusionMode.self, forKey: .inclusionMode)
        snapshot = try container.decodeIfPresent(String.self, forKey: .snapshot)
    }
}

public enum SourceManifestYAMLDecoder {
    public static func decode(_ yaml: String) throws -> SourceManifest {
        try enforceCorpusLimit(
            yaml.utf8.count,
            maximum: CorpusResourceLimits.maximumSourceManifestUTF8Bytes,
            kind: "source-manifest-utf8-bytes"
        )
        try enforceCorpusAliasBudget(
            yaml,
            context: "tractatus source manifest",
            kindPrefix: "source-manifest"
        )
        do {
            return try YAMLDecoder().decode(SourceManifest.self, from: yaml)
        } catch {
            if let schemaError = unwrapSchemaError(error) { throw schemaError }
            throw error
        }
    }

    public static func decode(contentsOf url: URL) throws -> SourceManifest {
        try decode(boundedUTF8FileContents(
            of: url,
            maximumBytes: CorpusResourceLimits.maximumSourceManifestUTF8Bytes,
            kind: "source-manifest-utf8-bytes"
        ))
    }

    private static func unwrapSchemaError(_ error: Error) -> CorpusSchemaError? {
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
        return unwrapSchemaError(underlying)
    }
}

public enum SourceManifestValidator {
    private enum SnapshotCapture {
        case data(Data)
        case resourceLimit(String)
        case unreadable
    }

    public static func validate(
        _ manifest: SourceManifest,
        root: URL,
        volumes: [CorpusVolume]
    ) -> [CorpusDiagnostic] {
        validate(
            manifest,
            root: root,
            volumes: volumes,
            snapshotLoader: { url in
                try boundedFileData(
                    contentsOf: url,
                    maximumBytes: CorpusResourceLimits.maximumInlineSnapshotUTF8Bytes,
                    kind: "inline-snapshot-utf8-bytes"
                )
            }
        )
    }

    static func validate(
        _ manifest: SourceManifest,
        root: URL,
        volumes: [CorpusVolume],
        snapshotLoader: (URL) throws -> Data
    ) -> [CorpusDiagnostic] {
        var diagnostics: [CorpusDiagnostic] = []
        var inlineSnapshots: [Int: Data] = [:]
        var snapshotCaptureCache: [String: SnapshotCapture] = [:]
        for (editionIndex, edition) in manifest.editions.enumerated() {
            validateProvenance(edition, diagnostics: &diagnostics)
            switch edition.inclusionMode {
            case .inline:
                if let data = validateInline(
                    edition,
                    root: root,
                    snapshotCaptureCache: &snapshotCaptureCache,
                    snapshotLoader: snapshotLoader,
                    diagnostics: &diagnostics
                ) {
                    inlineSnapshots[editionIndex] = data
                }
            case .externalReference:
                validateExternal(
                    edition,
                    volumes: volumes,
                    diagnostics: &diagnostics
                )
            }
        }
        validateCorpusFidelity(
            manifest,
            volumes: volumes,
            inlineSnapshots: inlineSnapshots,
            diagnostics: &diagnostics
        )
        return diagnostics.sorted()
    }

    private static func validateProvenance(
        _ edition: SourceEdition,
        diagnostics: inout [CorpusDiagnostic]
    ) {
        let required = [
            edition.bibliography,
            edition.upstreamRevision,
            edition.rightsNote,
        ]
        let sourceURL = URL(string: edition.sourceURL)
        let sourceURLIsValid = sourceURL?.host != nil
            && ["http", "https"].contains(sourceURL?.scheme?.lowercased() ?? "")
        let digestContractIsValid: Bool
        switch edition.inclusionMode {
        case .inline:
            digestContractIsValid = edition.sha256.map {
                $0.count == 64
                    && $0.allSatisfy { character in
                        character.isASCII && character.hexDigitValue != nil
                    }
            } ?? false
        case .externalReference:
            digestContractIsValid = edition.sha256 == nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        let retrievalDateIsValid = edition.retrievalDate.count == 10
            && formatter.date(from: edition.retrievalDate) != nil

        guard required.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }), sourceURLIsValid, digestContractIsValid, retrievalDateIsValid else {
            diagnostics.append(issue(
                edition,
                code: "invalid-source",
                message: "edition 必須有非空 bibliography、upstream revision、rights note、HTTP(S) source URL 與 YYYY-MM-DD 擷取日期；inline 必須有 64 位 SHA-256，external_reference 必須省略 sha256。"
            ))
            return
        }
    }

    private static func validateInline(
        _ edition: SourceEdition,
        root: URL,
        snapshotCaptureCache: inout [String: SnapshotCapture],
        snapshotLoader: (URL) throws -> Data,
        diagnostics: inout [CorpusDiagnostic]
    ) -> Data? {
        guard let expectedDigest = edition.sha256,
              expectedDigest.count == 64,
              expectedDigest.allSatisfy({
                  $0.isASCII && $0.hexDigitValue != nil
              }) else {
            return nil
        }
        guard edition.copyrightStatus != .copyrighted else {
            diagnostics.append(issue(
                edition,
                code: "license-violation",
                message: "copyrighted edition 不得以 inline 模式重製。"
            ))
            return nil
        }
        guard !edition.rightsNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            diagnostics.append(issue(
                edition,
                code: "license-violation",
                message: "inline edition 缺少可稽核的 rights_note。"
            ))
            return nil
        }
        if edition.copyrightStatus == .licensed {
            guard let evidence = edition.licenseEvidenceURL,
                  let url = URL(string: evidence),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  url.host != nil else {
                diagnostics.append(issue(
                    edition,
                    code: "license-violation",
                    message: "licensed inline edition 必須提供可稽核的 license_evidence_url。"
                ))
                return nil
            }
        }
        guard let snapshot = edition.snapshot else {
            diagnostics.append(issue(
                edition,
                code: "license-violation",
                message: "inline edition 必須指定本機 snapshot。"
            ))
            return nil
        }
        guard let url = safeSnapshotURL(snapshot, root: root) else {
            diagnostics.append(issue(
                edition,
                code: "broken-path",
                message: "找不到或拒絕讀取 snapshot：\(snapshot)"
            ))
            return nil
        }
        let cacheKey = url.path
        let capture: SnapshotCapture
        if let cached = snapshotCaptureCache[cacheKey] {
            capture = cached
        } else {
            do {
                capture = .data(try snapshotLoader(url))
            } catch let error as CorpusSchemaError {
                capture = .resourceLimit(error.localizedDescription)
            } catch {
                capture = .unreadable
            }
            snapshotCaptureCache[cacheKey] = capture
        }
        let data: Data
        switch capture {
        case let .data(captured):
            data = captured
        case let .resourceLimit(message):
            diagnostics.append(issue(
                edition,
                code: "resource-limit",
                message: message
            ))
            return nil
        case .unreadable:
            diagnostics.append(issue(
                edition,
                code: "broken-path",
                message: "找不到或拒絕讀取 snapshot：\(snapshot)"
            ))
            return nil
        }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if actual != expectedDigest.lowercased() {
            diagnostics.append(issue(
                edition,
                code: "digest-mismatch",
                message: "snapshot SHA-256 與 manifest 不一致。"
            ))
        }
        return data
    }

    private static func validateExternal(
        _ edition: SourceEdition,
        volumes: [CorpusVolume],
        diagnostics: inout [CorpusDiagnostic]
    ) {
        if edition.snapshot != nil {
            diagnostics.append(issue(
                edition,
                code: "license-violation",
                message: "external_reference edition 不得指定全文 snapshot。"
            ))
        }
        for proposition in volumes.flatMap(\.propositions) {
            let path = "corpus/\(volumeName(for: proposition.id)).yaml"
            if let units = proposition.texts[edition.id], !units.isEmpty {
                diagnostics.append(CorpusDiagnostic(
                    path: path,
                    recordID: proposition.id.rawValue,
                    code: "license-violation",
                    message: "external_reference edition \(edition.id) 不得含重製文字。"
                ))
            }
            if let reference = proposition.editionReferences[edition.id],
               reference != canonicalExternalReference(for: proposition.id) {
                diagnostics.append(CorpusDiagnostic(
                    path: path,
                    recordID: proposition.id.rawValue,
                    code: "license-violation",
                    message: "external_reference edition \(edition.id) 只能使用 owner record 的固定版本參照。"
                ))
            }
        }
    }

    private static func canonicalExternalReference(for id: PropositionID) -> String {
        guard id.rawValue.hasPrefix("preface.") else { return id.rawValue }
        return "Preface paragraph \(id.rawValue.dropFirst("preface.".count))"
    }

    private static func validateCorpusFidelity(
        _ manifest: SourceManifest,
        volumes: [CorpusVolume],
        inlineSnapshots: [Int: Data],
        diagnostics: inout [CorpusDiagnostic]
    ) {
        for (editionIndex, edition) in manifest.editions.enumerated()
        where edition.inclusionMode == .inline {
            guard let data = inlineSnapshots[editionIndex] else { continue }
            guard let text = String(data: data, encoding: .utf8),
                  let parsed = sourcePassages(text, editionID: edition.id) else {
                diagnostics.append(issue(
                    edition,
                    code: "source-mismatch",
                    message: "inline snapshot 無法解析固定序言與命題結構，來源比對採 fail-closed。"
                ))
                continue
            }
            guard parsed.orderedIDs == manifest.scope.inventory else {
                diagnostics.append(issue(
                    edition,
                    code: "source-mismatch",
                    message: "inline snapshot 的 passage headings 必須完整、唯一且依 manifest inventory 排序。"
                ))
                continue
            }
            for proposition in volumes.flatMap(\.propositions) {
                let path = "corpus/\(volumeName(for: proposition.id)).yaml"
                guard let source = parsed.passagesByID[proposition.id.rawValue],
                      let units = proposition.texts[edition.id],
                      canonicalSourceText(units.joined()) == canonicalSourceText(source) else {
                    diagnostics.append(CorpusDiagnostic(
                        path: path,
                        recordID: proposition.id.rawValue,
                        code: "source-mismatch",
                        message: "\(edition.id) 的 corpus texts 無法逐字回組固定 source snapshot。"
                    ))
                    continue
                }
            }
        }
    }

    private struct ParsedSourcePassage {
        let id: String
        let text: String
        let position: String.Index
    }

    private struct ParsedSourcePassages {
        let passages: [ParsedSourcePassage]

        var orderedIDs: [String] { passages.map(\.id) }
        var passagesByID: [String: String] {
            Dictionary(
                passages.map { ($0.id, $0.text) },
                uniquingKeysWith: { first, _ in first }
            )
        }

        var isEmpty: Bool { orderedIDs.isEmpty }

        func appending(_ other: ParsedSourcePassages) -> ParsedSourcePassages {
            ParsedSourcePassages(
                passages: (passages + other.passages).sorted {
                    $0.position < $1.position
                }
            )
        }
    }

    private static func sourcePassages(
        _ snapshot: String,
        editionID: String
    ) -> ParsedSourcePassages? {
        switch editionID {
        case "de":
            let passages = prefacePassages(
                in: snapshot,
                heading: "## Vorwort",
                signature: "*L. W.*"
            ).appending(
                numberedPassages(
                    in: snapshot,
                    headingPattern: #"(?m)^\*\*([1-7](?:\.[0-9]+)*)\*\*[ \t]*"#
                )
            )
            return passages.isEmpty ? nil : passages
        case "en_ogden_ramsey_1922":
            let passages = prefacePassages(
                in: snapshot,
                heading: "## Preface",
                signature: "*L.W.*"
            ).appending(
                numberedPassages(
                    in: snapshot,
                    headingPattern: #"(?m)^\*\*\[([1-7](?:\.[0-9]+)*)\]\([^\n]*\)\*\*[ \t]*"#
                )
            )
            return passages.isEmpty ? nil : passages
        default:
            return nil
        }
    }

    private static func prefacePassages(
        in snapshot: String,
        heading: String,
        signature: String
    ) -> ParsedSourcePassages {
        guard let headingRange = snapshot.range(of: heading),
              let signatureRange = snapshot.range(
                of: signature,
                range: headingRange.upperBound..<snapshot.endIndex
              ) else {
            return ParsedSourcePassages(passages: [])
        }
        let body = snapshot[headingRange.upperBound..<signatureRange.lowerBound]
        let paragraphs = body
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var searchStart = body.startIndex
        var passages: [ParsedSourcePassage] = []
        for (index, paragraph) in paragraphs.enumerated() {
            guard let paragraphRange = body.range(
                of: paragraph,
                range: searchStart..<body.endIndex
            ) else {
                continue
            }
            passages.append(ParsedSourcePassage(
                id: "preface.\(index + 1)",
                text: paragraph,
                position: paragraphRange.lowerBound
            ))
            searchStart = paragraphRange.upperBound
        }
        return ParsedSourcePassages(passages: passages)
    }

    private static func numberedPassages(
        in snapshot: String,
        headingPattern: String
    ) -> ParsedSourcePassages {
        guard let expression = try? NSRegularExpression(pattern: headingPattern) else {
            return ParsedSourcePassages(passages: [])
        }
        let fullRange = NSRange(snapshot.startIndex..<snapshot.endIndex, in: snapshot)
        let matches = expression.matches(in: snapshot, range: fullRange)
        var passages: [ParsedSourcePassage] = []
        for (index, match) in matches.enumerated() {
            guard let idRange = Range(match.range(at: 1), in: snapshot),
                  let headingRange = Range(match.range, in: snapshot) else {
                continue
            }
            let end = index + 1 < matches.count
                ? Range(matches[index + 1].range, in: snapshot)!.lowerBound
                : snapshot.endIndex
            let id = String(snapshot[idRange])
            passages.append(ParsedSourcePassage(
                id: id,
                text: String(snapshot[headingRange.upperBound..<end]),
                position: headingRange.lowerBound
            ))
        }
        return ParsedSourcePassages(passages: passages)
    }

    private static func canonicalSourceText(_ text: String) -> String {
        let withoutEditorialFootnotes = text.replacingOccurrences(
            of: #"\[\^[^\]]+\]"#,
            with: "",
            options: .regularExpression
        )
        return String(withoutEditorialFootnotes.filter { !$0.isWhitespace })
    }

    private static func safeSnapshotURL(_ path: String, root: URL) -> URL? {
        guard !path.hasPrefix("/") else { return nil }
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root.appendingPathComponent(path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPrefix = canonicalRoot.path.hasSuffix("/")
            ? canonicalRoot.path
            : canonicalRoot.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else { return nil }
        return candidate
    }

    private static func issue(
        _ edition: SourceEdition,
        code: String,
        message: String
    ) -> CorpusDiagnostic {
        CorpusDiagnostic(path: "sources.yaml", recordID: edition.id, code: code, message: message)
    }

    private static func volumeName(for id: PropositionID) -> String {
        if id.rawValue.hasPrefix("preface.") { return "preface" }
        return String(id.rawValue.prefix { $0 != "." })
    }
}
