import CryptoKit
import Foundation

private enum GeneratorError: Error, CustomStringConvertible {
    case usage(String)
    case invalidData(String)
    case verification(String)

    var description: String {
        switch self {
        case .usage(let message), .invalidData(let message), .verification(let message):
            return message
        }
    }
}

private struct Options {
    let ucdRoot: URL
    let manifest: URL
    let output: URL
    let verifyV1: Bool

    init(arguments: [String]) throws {
        var ucdRoot: URL?
        var manifest: URL?
        var output: URL?
        var verifyV1 = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--ucd-root":
                index += 1
                guard index < arguments.count else {
                    throw GeneratorError.usage("--ucd-root 缺少路徑")
                }
                ucdRoot = URL(fileURLWithPath: arguments[index], isDirectory: true)
            case "--manifest":
                index += 1
                guard index < arguments.count else {
                    throw GeneratorError.usage("--manifest 缺少路徑")
                }
                manifest = URL(fileURLWithPath: arguments[index])
            case "--output":
                index += 1
                guard index < arguments.count else {
                    throw GeneratorError.usage("--output 缺少路徑")
                }
                output = URL(fileURLWithPath: arguments[index])
            case "--verify-v1":
                verifyV1 = true
            default:
                throw GeneratorError.usage("不認得的參數：\(arguments[index])")
            }
            index += 1
        }
        guard let ucdRoot, let manifest, let output else {
            throw GeneratorError.usage(
                "用法：UnicodeNormalizationGenerator --ucd-root <dir> --manifest <json> "
                + "--output <swift> [--verify-v1]"
            )
        }
        self.ucdRoot = ucdRoot
        self.manifest = manifest
        self.output = output
        self.verifyV1 = verifyV1
    }
}

private struct Manifest: Decodable {
    struct Input: Decodable {
        let file: String
        let url: String
        let sha256: String
    }

    struct Source: Decodable {
        let role: String
        let path: String
        let sha256: String
    }

    let schemaVersion: Int
    let unicodeVersion: String
    let canonicalDomains: [String]
    let inputs: [Input]
    let sources: [Source]
    let regenerationCommand: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case unicodeVersion = "unicode_version"
        case canonicalDomains = "canonical_domains"
        case inputs
        case sources
        case regenerationCommand = "regeneration_command"
    }
}

private struct ScalarRange: Comparable {
    let lower: UInt32
    let upper: UInt32

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.lower == rhs.lower ? lhs.upper < rhs.upper : lhs.lower < rhs.lower
    }
}

private struct CombiningRange: Comparable {
    let lower: UInt32
    let upper: UInt32
    let value: UInt8

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.lower != rhs.lower { return lhs.lower < rhs.lower }
        if lhs.upper != rhs.upper { return lhs.upper < rhs.upper }
        return lhs.value < rhs.value
    }
}

private struct Decomposition: Comparable {
    let scalar: UInt32
    let values: [UInt32]

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.scalar < rhs.scalar }
}

private struct Composition: Comparable {
    let first: UInt32
    let second: UInt32
    let composite: UInt32

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.first != rhs.first { return lhs.first < rhs.first }
        if lhs.second != rhs.second { return lhs.second < rhs.second }
        return lhs.composite < rhs.composite
    }
}

private struct Tables {
    var assigned: [ScalarRange]
    var whiteSpace: [ScalarRange]
    var combining: [CombiningRange]
    var decompositions: [Decomposition]
    var compositions: [Composition]
}

private let officialInputs: [(file: String, digest: String)] = [
    ("UnicodeData.txt", "2fc713e6a31a87c4850a37fe2caffa4218180fadb5de86b43a143ddb4581fb86"),
    ("CompositionExclusions.txt", "59d2d9e3dfdf0a999cf9dae11d594f053631222679a2f5710315ea07f7fe82af"),
    ("DerivedNormalizationProps.txt", "8875dccee2bc1a7c1fe568a3b502a9e78c9e0495afd96b6568b4294d0ed1f7e1"),
    ("PropList.txt", "05672956317b6296bc2ec3d6cef1f6452b57ff4f2efc6dc55b0a19277d5fcfd1"),
    ("NormalizationTest.txt", "871238e37e3be0696ec2bd0891119a041b052da1a84485eda05a5438724b223e"),
]

private let canonicalDomains = [
    "akashic-proposition-atom-v1",
    "akashic-proposition-expression-v1",
    "akashic-classical-truth-table-v1",
    "akashic-boolean-function-table-v1",
]

private let regenerationCommand =
    "swift run UnicodeNormalizationGenerator --ucd-root Vendor/Unicode/15.1.0 "
    + "--manifest unicode-normalization-v1.manifest.json --output "
    + "Sources/AkashicProposition/Generated/UnicodeNormalizationTablesV1.swift --verify-v1"

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func data(at url: URL) throws -> Data {
    do {
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    } catch {
        throw GeneratorError.invalidData("無法讀取 \(url.path)：\(error.localizedDescription)")
    }
}

private func parseHex(_ text: Substring, context: String) throws -> UInt32 {
    guard let value = UInt32(text.trimmingCharacters(in: .whitespaces), radix: 16) else {
        throw GeneratorError.invalidData("\(context) 含無效 scalar：\(text)")
    }
    return value
}

private func parseRange(_ text: Substring, context: String) throws -> ScalarRange {
    let bounds = text.trimmingCharacters(in: .whitespaces).split(separator: ".")
    if bounds.count == 1 {
        let value = try parseHex(bounds[0], context: context)
        return ScalarRange(lower: value, upper: value)
    }
    guard bounds.count == 2 else {
        throw GeneratorError.invalidData("\(context) 含無效 range：\(text)")
    }
    return try ScalarRange(
        lower: parseHex(bounds[0], context: context),
        upper: parseHex(bounds[1], context: context)
    )
}

private func merged(_ ranges: [ScalarRange]) -> [ScalarRange] {
    var result: [ScalarRange] = []
    for range in ranges.sorted() {
        if let last = result.last, range.lower <= last.upper &+ 1 {
            result[result.count - 1] = ScalarRange(
                lower: last.lower,
                upper: max(last.upper, range.upper)
            )
        } else {
            result.append(range)
        }
    }
    return result
}

private func parseUnicodeData(at url: URL) throws
    -> (assigned: [ScalarRange], combining: [CombiningRange], decompositions: [Decomposition])
{
    let text = String(decoding: try data(at: url), as: UTF8.self)
    var assigned: [ScalarRange] = []
    var combining: [CombiningRange] = []
    var decompositions: [Decomposition] = []
    var pendingRange: (start: UInt32, combining: UInt8)?

    for (lineNumber, rawLine) in text.split(whereSeparator: \Character.isNewline).enumerated() {
        let fields = rawLine.split(separator: ";", omittingEmptySubsequences: false)
        guard fields.count >= 15 else {
            throw GeneratorError.invalidData("UnicodeData.txt:\(lineNumber + 1) 欄位不足")
        }
        let scalar = try parseHex(fields[0], context: "UnicodeData.txt:\(lineNumber + 1)")
        guard let ccc = UInt8(fields[3]) else {
            throw GeneratorError.invalidData("UnicodeData.txt:\(lineNumber + 1) CCC 無效")
        }
        let name = fields[1]
        if name.hasSuffix(", First>") {
            guard pendingRange == nil else {
                throw GeneratorError.invalidData("UnicodeData.txt range 重疊")
            }
            pendingRange = (scalar, ccc)
            continue
        }
        if name.hasSuffix(", Last>") {
            guard let pending = pendingRange, pending.start <= scalar, pending.combining == ccc else {
                throw GeneratorError.invalidData("UnicodeData.txt range 未成對")
            }
            assigned.append(ScalarRange(lower: pending.start, upper: scalar))
            if ccc != 0 {
                combining.append(CombiningRange(lower: pending.start, upper: scalar, value: ccc))
            }
            pendingRange = nil
            continue
        }

        assigned.append(ScalarRange(lower: scalar, upper: scalar))
        if ccc != 0 {
            combining.append(CombiningRange(lower: scalar, upper: scalar, value: ccc))
        }
        let decomposition = fields[5].trimmingCharacters(in: .whitespaces)
        if !decomposition.isEmpty, !decomposition.hasPrefix("<") {
            let values = try decomposition.split(separator: " ").map {
                try parseHex($0, context: "UnicodeData.txt:\(lineNumber + 1)")
            }
            decompositions.append(Decomposition(scalar: scalar, values: values))
        }
    }
    guard pendingRange == nil else {
        throw GeneratorError.invalidData("UnicodeData.txt 結尾仍有未關閉 range")
    }
    return (merged(assigned), combining.sorted(), decompositions.sorted())
}

private func parsePropertyRanges(at url: URL, property: String) throws -> [ScalarRange] {
    let text = String(decoding: try data(at: url), as: UTF8.self)
    var ranges: [ScalarRange] = []
    for (lineNumber, rawLine) in text.split(whereSeparator: \Character.isNewline).enumerated() {
        let content = rawLine.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first ?? rawLine
        let fields = content.split(separator: ";", omittingEmptySubsequences: false)
        guard fields.count >= 2 else { continue }
        guard fields[1].trimmingCharacters(in: .whitespaces) == property else { continue }
        ranges.append(try parseRange(fields[0], context: "\(url.lastPathComponent):\(lineNumber + 1)"))
    }
    return merged(ranges)
}

private func parseCompositionExclusions(at url: URL) throws -> [ScalarRange] {
    let text = String(decoding: try data(at: url), as: UTF8.self)
    var ranges: [ScalarRange] = []
    for (lineNumber, rawLine) in text.split(whereSeparator: \Character.isNewline).enumerated() {
        let content = rawLine.split(
            separator: "#",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first ?? rawLine
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        ranges.append(try parseRange(Substring(trimmed), context: "CompositionExclusions.txt:\(lineNumber + 1)"))
    }
    return merged(ranges)
}

private func contains(_ ranges: [ScalarRange], _ value: UInt32) -> Bool {
    var low = 0
    var high = ranges.count
    while low < high {
        let middle = low + (high - low) / 2
        let range = ranges[middle]
        if value < range.lower {
            high = middle
        } else if value > range.upper {
            low = middle + 1
        } else {
            return true
        }
    }
    return false
}

private func buildTables(ucdRoot: URL) throws -> Tables {
    let unicode = try parseUnicodeData(at: ucdRoot.appendingPathComponent("UnicodeData.txt"))
    let whiteSpace = try parsePropertyRanges(
        at: ucdRoot.appendingPathComponent("PropList.txt"),
        property: "White_Space"
    )
    let explicitExclusions = try parseCompositionExclusions(
        at: ucdRoot.appendingPathComponent("CompositionExclusions.txt")
    )
    let fullExclusions = try parsePropertyRanges(
        at: ucdRoot.appendingPathComponent("DerivedNormalizationProps.txt"),
        property: "Full_Composition_Exclusion"
    )
    let exclusions = merged(explicitExclusions + fullExclusions)
    let compositions = unicode.decompositions.compactMap { decomposition -> Composition? in
        guard decomposition.values.count == 2,
              !contains(exclusions, decomposition.scalar) else { return nil }
        return Composition(
            first: decomposition.values[0],
            second: decomposition.values[1],
            composite: decomposition.scalar
        )
    }.sorted()
    return Tables(
        assigned: unicode.assigned,
        whiteSpace: whiteSpace,
        combining: unicode.combining,
        decompositions: unicode.decompositions,
        compositions: compositions
    )
}

private extension Data {
    mutating func appendUInt8(_ value: UInt8) { append(value) }

    mutating func appendUInt16(_ value: UInt16) {
        var encoded = value.bigEndian
        Swift.withUnsafeBytes(of: &encoded) { append(contentsOf: $0) }
    }

    mutating func appendUInt32(_ value: UInt32) {
        var encoded = value.bigEndian
        Swift.withUnsafeBytes(of: &encoded) { append(contentsOf: $0) }
    }
}

private func encodedTables(_ tables: Tables) throws -> Data {
    var output = Data("AKUN1".utf8)
    output.appendUInt32(UInt32(tables.assigned.count))
    for range in tables.assigned {
        output.appendUInt32(range.lower)
        output.appendUInt32(range.upper)
    }
    output.appendUInt32(UInt32(tables.whiteSpace.count))
    for range in tables.whiteSpace {
        output.appendUInt32(range.lower)
        output.appendUInt32(range.upper)
    }
    output.appendUInt32(UInt32(tables.combining.count))
    for range in tables.combining {
        output.appendUInt32(range.lower)
        output.appendUInt32(range.upper)
        output.appendUInt8(range.value)
    }
    output.appendUInt32(UInt32(tables.decompositions.count))
    for decomposition in tables.decompositions {
        guard decomposition.values.count <= Int(UInt16.max) else {
            throw GeneratorError.invalidData("decomposition 過長：U+\(String(decomposition.scalar, radix: 16))")
        }
        output.appendUInt32(decomposition.scalar)
        output.appendUInt16(UInt16(decomposition.values.count))
        for value in decomposition.values { output.appendUInt32(value) }
    }
    output.appendUInt32(UInt32(tables.compositions.count))
    for composition in tables.compositions {
        output.appendUInt32(composition.first)
        output.appendUInt32(composition.second)
        output.appendUInt32(composition.composite)
    }
    return output
}

private func generatedSource(from tables: Tables) throws -> Data {
    let encoded = try encodedTables(tables).base64EncodedString()
    var lines: [String] = []
    lines.reserveCapacity((encoded.count / 96) + 1)
    var index = encoded.startIndex
    while index < encoded.endIndex {
        let end = encoded.index(index, offsetBy: 96, limitedBy: encoded.endIndex)
            ?? encoded.endIndex
        lines.append(String(encoded[index..<end]))
        index = end
    }
    var source = "import Foundation\n\n"
    source += "/// 由 UnicodeNormalizationGenerator 從檢入的 Unicode 15.1.0 UCD 決定性產生。\n"
    source += "/// 請勿手改；`unicode-normalization-v1.manifest.json` 固定本檔完整 SHA-256。\n"
    source += "enum GeneratedUnicodeNormalizationTablesV1 {\n"
    source += "    static let unicodeVersion = \"15.1.0\"\n"
    source += "    static let encodedTablesBase64 = \"\"\"\n"
    source += lines.map { "    " + $0 }.joined(separator: "\n")
    source += "\n    \"\"\"\n"
    source += "}\n"
    return Data(source.utf8)
}

private func verifyManifest(_ manifest: Manifest, options: Options, generated: Data) throws {
    guard manifest.schemaVersion == 1 else {
        throw GeneratorError.verification("manifest schema_version 必須為 1")
    }
    guard manifest.unicodeVersion == "15.1.0" else {
        throw GeneratorError.verification("manifest unicode_version 必須為 15.1.0")
    }
    guard manifest.canonicalDomains == canonicalDomains else {
        throw GeneratorError.verification("manifest canonical domains 與 v1 contract 不符")
    }
    guard manifest.regenerationCommand == regenerationCommand else {
        throw GeneratorError.verification("manifest regeneration command 漂移")
    }
    guard manifest.inputs.count == officialInputs.count else {
        throw GeneratorError.verification("manifest 必須且只能列出五份 UCD inputs")
    }
    for (file, digest) in officialInputs {
        guard let input = manifest.inputs.first(where: { $0.file == file }) else {
            throw GeneratorError.verification("manifest 缺少 \(file)")
        }
        let expectedURL = "https://www.unicode.org/Public/15.1.0/ucd/\(file)"
        guard input.url == expectedURL, input.sha256 == digest else {
            throw GeneratorError.verification("manifest 的 \(file) URL／SHA 漂移")
        }
        let actual = sha256(try data(at: options.ucdRoot.appendingPathComponent(file)))
        guard actual == digest else {
            throw GeneratorError.verification("vendored \(file) SHA 不符：\(actual)")
        }
    }

    let root = options.manifest.deletingLastPathComponent()
    let expectedRoles = ["generator", "runtime_normalizer", "generated_tables"]
    guard manifest.sources.map(\.role).sorted() == expectedRoles.sorted() else {
        throw GeneratorError.verification("manifest source roles 不完整")
    }
    for source in manifest.sources {
        let sourceURL = root.appendingPathComponent(source.path)
        let actual: String
        if source.role == "generated_tables" {
            actual = sha256(generated)
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                let checkedIn = sha256(try data(at: sourceURL))
                guard checkedIn == actual else {
                    throw GeneratorError.verification("checked-in generated tables 與 replay 不同")
                }
            }
        } else {
            actual = sha256(try data(at: sourceURL))
        }
        guard source.sha256 == actual else {
            throw GeneratorError.verification("\(source.role) SHA 不符：\(actual)")
        }
    }
}

do {
    let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
    let tables = try buildTables(ucdRoot: options.ucdRoot)
    let source = try generatedSource(from: tables)
    if options.verifyV1 {
        let manifest = try JSONDecoder().decode(Manifest.self, from: data(at: options.manifest))
        try verifyManifest(manifest, options: options, generated: source)
    }
    try FileManager.default.createDirectory(
        at: options.output.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try source.write(to: options.output, options: .atomic)
} catch {
    FileHandle.standardError.write(Data("UnicodeNormalizationGenerator: \(error)\n".utf8))
    exit(1)
}
