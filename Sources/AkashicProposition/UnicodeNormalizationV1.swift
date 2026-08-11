import Foundation
import AkashicCore

enum LogicalReferenceSyntaxV1 {
    case key
    case literal
}

struct ValidatedReferenceV1 {
    let tag: UInt8
    let normalizedUTF8: [UInt8]
}

enum UnicodeNormalizationV1 {
    static let version = GeneratedUnicodeNormalizationTablesV1.unicodeVersion

    static func validatedReference(
        _ source: String,
        syntax: LogicalReferenceSyntaxV1
    ) throws -> ValidatedReferenceV1 {
        let maximum = PropositionLogicLimits.maximumReferenceUTF8ByteCount
        try preflightRawUTF8(source, maximum: maximum)

        switch syntax {
        case .key:
            guard StoreKey.isValid(source) else { throw PropositionError.malformedKey(source) }
        case .literal:
            var hasNonWhiteSpace = false
            for scalar in source.unicodeScalars where !UnicodeNormalizationTablesV1.shared
                .isWhiteSpace(scalar.value)
            {
                hasNonWhiteSpace = true
                break
            }
            guard hasNonWhiteSpace else { throw PropositionError.emptyLiteral }
        }

        // Syntax 有明確優先權；只有可表達的 reference 才進 admitted-scalar gate。
        for scalar in source.unicodeScalars {
            guard UnicodeNormalizationTablesV1.shared.isAssigned(scalar.value) else {
                throw PropositionError.unsupportedUnicodeScalar(
                    value: scalar.value,
                    normalizationVersion: version
                )
            }
        }

        let normalized = try PinnedNFCNormalizerV1(
            tables: .shared,
            maximumUTF8ByteCount: maximum
        ).normalize(source)
        return ValidatedReferenceV1(
            tag: syntax == .key ? 0x00 : 0x01,
            normalizedUTF8: normalized
        )
    }

    private static func preflightRawUTF8(_ source: String, maximum: Int) throws {
        var observed = 0
        for _ in source.utf8 {
            if observed == maximum {
                throw PropositionError.referenceUTF8ByteCountExceeded(
                    stage: .rawUTF8,
                    minimumObserved: maximum + 1,
                    maximum: maximum
                )
            }
            observed += 1
        }
    }
}

private struct PinnedNFCNormalizerV1 {
    let tables: UnicodeNormalizationTablesV1
    let maximumUTF8ByteCount: Int

    func normalize(_ source: String) throws -> [UInt8] {
        var state = State(tables: tables, sink: UTF8Sink(maximum: maximumUTF8ByteCount))
        for sourceScalar in source.unicodeScalars {
            var stack = [sourceScalar.value]
            while let scalar = stack.popLast() {
                if let hangul = Self.hangulDecomposition(scalar) {
                    stack.append(contentsOf: hangul.reversed())
                } else if let decomposition = tables.decomposition(of: scalar) {
                    stack.append(contentsOf: decomposition.reversed())
                } else {
                    try state.acceptDecomposed(scalar)
                }
            }
        }
        try state.finish()
        return state.sink.bytes
    }

    private struct State {
        let tables: UnicodeNormalizationTablesV1
        var sink: UTF8Sink
        var pending: [UInt32] = []

        mutating func acceptDecomposed(_ scalar: UInt32) throws {
            let combiningClass = tables.combiningClass(of: scalar)
            guard combiningClass == 0 else {
                pending.append(scalar)
                return
            }
            guard !pending.isEmpty else {
                pending.append(scalar)
                return
            }

            let normalized = normalizedPending()
            if normalized.count == 1,
               let composite = PinnedNFCNormalizerV1.composite(
                   normalized[0],
                   scalar,
                   tables: tables
               )
            {
                pending = [composite]
            } else {
                try emit(normalized)
                pending = [scalar]
            }
        }

        mutating func finish() throws {
            guard !pending.isEmpty else { return }
            try emit(normalizedPending())
            pending.removeAll(keepingCapacity: false)
        }

        private mutating func emit(_ scalars: [UInt32]) throws {
            for scalar in scalars { try sink.append(scalar) }
        }

        private func normalizedPending() -> [UInt32] {
            var ordered = pending
            let markStart = tables.combiningClass(of: ordered[0]) == 0 ? 1 : 0
            if ordered.count > markStart + 1 {
                // Canonical ordering是 stable insertion：相同 CCC 不互換。
                for index in (markStart + 1)..<ordered.count {
                    var cursor = index
                    let candidateClass = tables.combiningClass(of: ordered[cursor])
                    while cursor > markStart {
                        let previousClass = tables.combiningClass(of: ordered[cursor - 1])
                        guard candidateClass < previousClass else { break }
                        ordered.swapAt(cursor, cursor - 1)
                        cursor -= 1
                    }
                }
            }

            var result: [UInt32] = []
            result.reserveCapacity(ordered.count)
            var starterIndex: Int?
            var lastCombiningClass: UInt8 = 0
            for scalar in ordered {
                let combiningClass = tables.combiningClass(of: scalar)
                if let starterIndex,
                   (lastCombiningClass == 0 || lastCombiningClass < combiningClass),
                   let composite = PinnedNFCNormalizerV1.composite(
                       result[starterIndex],
                       scalar,
                       tables: tables
                   )
                {
                    result[starterIndex] = composite
                    continue
                }
                if combiningClass == 0 { starterIndex = result.count }
                result.append(scalar)
                lastCombiningClass = combiningClass
            }
            return result
        }
    }

    private struct UTF8Sink {
        let maximum: Int
        var bytes: [UInt8] = []

        init(maximum: Int) {
            self.maximum = maximum
            bytes.reserveCapacity(min(maximum, 4_096))
        }

        mutating func append(_ scalar: UInt32) throws {
            if scalar <= 0x7F {
                try appendByte(UInt8(scalar))
            } else if scalar <= 0x7FF {
                try appendByte(UInt8(0xC0 | (scalar >> 6)))
                try appendByte(UInt8(0x80 | (scalar & 0x3F)))
            } else if scalar <= 0xFFFF {
                try appendByte(UInt8(0xE0 | (scalar >> 12)))
                try appendByte(UInt8(0x80 | ((scalar >> 6) & 0x3F)))
                try appendByte(UInt8(0x80 | (scalar & 0x3F)))
            } else {
                try appendByte(UInt8(0xF0 | (scalar >> 18)))
                try appendByte(UInt8(0x80 | ((scalar >> 12) & 0x3F)))
                try appendByte(UInt8(0x80 | ((scalar >> 6) & 0x3F)))
                try appendByte(UInt8(0x80 | (scalar & 0x3F)))
            }
        }

        private mutating func appendByte(_ byte: UInt8) throws {
            guard bytes.count < maximum else {
                throw PropositionError.referenceUTF8ByteCountExceeded(
                    stage: .normalizedUTF8,
                    minimumObserved: maximum + 1,
                    maximum: maximum
                )
            }
            bytes.append(byte)
        }
    }

    private static let hangulSBase: UInt32 = 0xAC00
    private static let hangulLBase: UInt32 = 0x1100
    private static let hangulVBase: UInt32 = 0x1161
    private static let hangulTBase: UInt32 = 0x11A7
    private static let hangulLCount: UInt32 = 19
    private static let hangulVCount: UInt32 = 21
    private static let hangulTCount: UInt32 = 28
    private static let hangulNCount = hangulVCount * hangulTCount
    private static let hangulSCount = hangulLCount * hangulNCount

    private static func hangulDecomposition(_ scalar: UInt32) -> [UInt32]? {
        let index = scalar &- hangulSBase
        guard index < hangulSCount else { return nil }
        let leading = hangulLBase + index / hangulNCount
        let vowel = hangulVBase + (index % hangulNCount) / hangulTCount
        let trailingIndex = index % hangulTCount
        if trailingIndex == 0 { return [leading, vowel] }
        return [leading, vowel, hangulTBase + trailingIndex]
    }

    private static func composite(
        _ first: UInt32,
        _ second: UInt32,
        tables: UnicodeNormalizationTablesV1
    ) -> UInt32? {
        let leadingIndex = first &- hangulLBase
        if leadingIndex < hangulLCount {
            let vowelIndex = second &- hangulVBase
            if vowelIndex < hangulVCount {
                return hangulSBase + (leadingIndex * hangulVCount + vowelIndex) * hangulTCount
            }
        }
        let syllableIndex = first &- hangulSBase
        if syllableIndex < hangulSCount, syllableIndex % hangulTCount == 0 {
            let trailingIndex = second &- hangulTBase
            if trailingIndex > 0, trailingIndex < hangulTCount {
                return first + trailingIndex
            }
        }
        return tables.composition(first: first, second: second)
    }
}

private struct UnicodeNormalizationTablesV1 {
    struct ScalarRange {
        let lower: UInt32
        let upper: UInt32
    }

    struct CombiningRange {
        let lower: UInt32
        let upper: UInt32
        let value: UInt8
    }

    struct Decomposition {
        let scalar: UInt32
        let values: [UInt32]
    }

    struct Composition {
        let first: UInt32
        let second: UInt32
        let composite: UInt32
    }

    let assigned: [ScalarRange]
    let whiteSpace: [ScalarRange]
    let combining: [CombiningRange]
    let decompositions: [Decomposition]
    let compositions: [Composition]

    static let shared: Self = {
        guard let data = Data(
            base64Encoded: GeneratedUnicodeNormalizationTablesV1.encodedTablesBase64,
            options: [.ignoreUnknownCharacters]
        ) else {
            preconditionFailure("Unicode 15.1.0 generated tables base64 不合法")
        }
        do {
            return try decode(data)
        } catch {
            preconditionFailure("Unicode 15.1.0 generated tables不合法：\(error)")
        }
    }()

    func isAssigned(_ scalar: UInt32) -> Bool { contains(scalar, in: assigned) }
    func isWhiteSpace(_ scalar: UInt32) -> Bool { contains(scalar, in: whiteSpace) }

    func combiningClass(of scalar: UInt32) -> UInt8 {
        var low = 0
        var high = combining.count
        while low < high {
            let middle = low + (high - low) / 2
            let range = combining[middle]
            if scalar < range.lower {
                high = middle
            } else if scalar > range.upper {
                low = middle + 1
            } else {
                return range.value
            }
        }
        return 0
    }

    func decomposition(of scalar: UInt32) -> [UInt32]? {
        var low = 0
        var high = decompositions.count
        while low < high {
            let middle = low + (high - low) / 2
            let entry = decompositions[middle]
            if scalar < entry.scalar {
                high = middle
            } else if scalar > entry.scalar {
                low = middle + 1
            } else {
                return entry.values
            }
        }
        return nil
    }

    func composition(first: UInt32, second: UInt32) -> UInt32? {
        var low = 0
        var high = compositions.count
        while low < high {
            let middle = low + (high - low) / 2
            let entry = compositions[middle]
            if first < entry.first || (first == entry.first && second < entry.second) {
                high = middle
            } else if first > entry.first || (first == entry.first && second > entry.second) {
                low = middle + 1
            } else {
                return entry.composite
            }
        }
        return nil
    }

    private func contains(_ scalar: UInt32, in ranges: [ScalarRange]) -> Bool {
        var low = 0
        var high = ranges.count
        while low < high {
            let middle = low + (high - low) / 2
            let range = ranges[middle]
            if scalar < range.lower {
                high = middle
            } else if scalar > range.upper {
                low = middle + 1
            } else {
                return true
            }
        }
        return false
    }

    private enum DecodeError: Error {
        case invalidMagic
        case truncated
        case invalidCount
        case trailingBytes
        case invalidOrdering
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        mutating func readUInt8() throws -> UInt8 {
            guard offset < bytes.count else { throw DecodeError.truncated }
            defer { offset += 1 }
            return bytes[offset]
        }

        mutating func readUInt16() throws -> UInt16 {
            var value: UInt16 = 0
            for _ in 0..<2 { value = (value << 8) | UInt16(try readUInt8()) }
            return value
        }

        mutating func readUInt32() throws -> UInt32 {
            var value: UInt32 = 0
            for _ in 0..<4 { value = (value << 8) | UInt32(try readUInt8()) }
            return value
        }

        mutating func count(maximum: Int) throws -> Int {
            let raw = try readUInt32()
            guard raw <= UInt32(maximum) else { throw DecodeError.invalidCount }
            return Int(raw)
        }
    }

    private static func decode(_ data: Data) throws -> Self {
        var reader = Reader(bytes: Array(data))
        let magic = try (0..<5).map { _ in try reader.readUInt8() }
        guard magic == Array("AKUN1".utf8) else { throw DecodeError.invalidMagic }

        let assigned = try (0..<reader.count(maximum: 10_000)).map { _ in
            ScalarRange(lower: try reader.readUInt32(), upper: try reader.readUInt32())
        }
        let whiteSpace = try (0..<reader.count(maximum: 100)).map { _ in
            ScalarRange(lower: try reader.readUInt32(), upper: try reader.readUInt32())
        }
        let combining = try (0..<reader.count(maximum: 10_000)).map { _ in
            CombiningRange(
                lower: try reader.readUInt32(),
                upper: try reader.readUInt32(),
                value: try reader.readUInt8()
            )
        }
        let decompositions = try (0..<reader.count(maximum: 100_000)).map { _ in
            let scalar = try reader.readUInt32()
            let count = Int(try reader.readUInt16())
            guard count <= 100 else { throw DecodeError.invalidCount }
            let values = try (0..<count).map { _ in try reader.readUInt32() }
            return Decomposition(scalar: scalar, values: values)
        }
        let compositions = try (0..<reader.count(maximum: 100_000)).map { _ in
            Composition(
                first: try reader.readUInt32(),
                second: try reader.readUInt32(),
                composite: try reader.readUInt32()
            )
        }
        guard reader.offset == reader.bytes.count else { throw DecodeError.trailingBytes }
        guard orderedRanges(assigned), orderedRanges(whiteSpace),
              orderedCombining(combining), orderedDecompositions(decompositions),
              orderedCompositions(compositions) else {
            throw DecodeError.invalidOrdering
        }
        return Self(
            assigned: assigned,
            whiteSpace: whiteSpace,
            combining: combining,
            decompositions: decompositions,
            compositions: compositions
        )
    }

    private static func orderedRanges(_ values: [ScalarRange]) -> Bool {
        values.enumerated().allSatisfy { index, value in
            value.lower <= value.upper && (index == 0 || values[index - 1].upper < value.lower)
        }
    }

    private static func orderedCombining(_ values: [CombiningRange]) -> Bool {
        values.enumerated().allSatisfy { index, value in
            value.lower <= value.upper && value.value != 0
                && (index == 0 || values[index - 1].upper < value.lower)
        }
    }

    private static func orderedDecompositions(_ values: [Decomposition]) -> Bool {
        values.enumerated().allSatisfy { index, value in
            !value.values.isEmpty && (index == 0 || values[index - 1].scalar < value.scalar)
        }
    }

    private static func orderedCompositions(_ values: [Composition]) -> Bool {
        values.enumerated().allSatisfy { index, value in
            guard index > 0 else { return true }
            let previous = values[index - 1]
            return previous.first < value.first
                || (previous.first == value.first && previous.second < value.second)
        }
    }
}
