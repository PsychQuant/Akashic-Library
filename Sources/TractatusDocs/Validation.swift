import AkashicCore
import CryptoKit
import Foundation

/// **不**宣告 `SanitizedErrorDescription`（R31；R30 verify 第 8／18／34 列）：它沒有 `errorDescription`／`description`，Error → 文字會走
/// `String(describing:)` 反射出四個原始欄位——R30 因為 body 裡有 `displaySafe` 而被守衛逼著 conform，那正是「型別在某條路徑上消毒」被當成
/// 「型別在 Error → 文字那條路徑上消毒」。消毒住在 `formatted`，而讀它的是 `TractatusValidationFailure.errorDescription`（那個型別才 conform）。
/// 今天沒有任何地方單獨 `throw CorpusDiagnostic`（三個構造點都包進 `TractatusValidationFailure`）。
public struct CorpusDiagnostic: Error, Equatable, Comparable, Sendable {
    public let path: String
    public let recordID: String
    public let code: String
    public let message: String

    public init(path: String, recordID: String, code: String, message: String) {
        self.path = path
        self.recordID = recordID
        self.code = code
        self.message = message
    }

    public static func < (lhs: CorpusDiagnostic, rhs: CorpusDiagnostic) -> Bool {
        if lhs.path != rhs.path { return lhs.path < rhs.path }
        if lhs.recordID != rhs.recordID { return lhs.recordID < rhs.recordID }
        if lhs.code != rhs.code { return lhs.code < rhs.code }
        return lhs.message < rhs.message
    }

    public var formatted: String {
        "\(singleLine(path)):\(singleLine(recordID)):\(singleLine(code)): \(singleLine(message))"
    }

    private func singleLine(_ value: String) -> String {
        displaySafeInvisible(value, max: 800)   // 性質式（R30；型別自帶消毒——sink 只截）
            .replacingOccurrences(of: ":", with: "\\:")
    }
}

/// 自帶消毒（R31）：`errorDescription` 由 `CorpusDiagnostic.formatted`（逐欄位 `displaySafeInvisible`）與 `incompleteness`（`ConstructionGap.formatted`，
/// 程式組的 gap 描述）組成——若它哪天落進 `displaySafeErrorText`，內容不會被逃第二次（R30 verify 第 34 列：R30 這一格沒 conform，
/// 而它實質上是自帶消毒的，唯一 sink 是 `tractatus-doc` 的顯式 catch 才沒觸發）。守衛的 `descriptionHelpers` 表記著 `formatted` 這條路。
public struct TractatusValidationFailure: Error, LocalizedError, Sendable, SanitizedErrorDescription {
    public let diagnostics: [CorpusDiagnostic]
    let incompleteness: [String]

    public init(diagnostics: [CorpusDiagnostic]) {
        self.init(diagnostics: diagnostics, incompleteness: [])
    }

    init(diagnostics: [CorpusDiagnostic], incompleteness: [String]) {
        self.diagnostics = diagnostics.sorted()
        self.incompleteness = Array(Set(incompleteness)).sorted()
    }

    public var errorDescription: String? {
        (incompleteness + diagnostics.map(\.formatted)).joined(separator: "\n")
    }
}

public enum CorpusValidator {
    private enum AssetCapture {
        case digest(String)
        case resourceLimit(String)
        case unreadable
    }

    public static func validateStructure(
        manifest: SourceManifest,
        volumes: [CorpusVolume]
    ) -> [CorpusDiagnostic] {
        var diagnostics: [CorpusDiagnostic] = []
        let inventory = validatedInventory(manifest, diagnostics: &diagnostics)
        validateFixedScope(manifest, inventory: inventory, diagnostics: &diagnostics)

        var propositionsByID: [PropositionID: [(path: String, record: PropositionRecord)]] = [:]
        var allRecordIDs: [String: [String]] = [:]
        for volume in volumes {
            let path = "corpus/\(volume.volume).yaml"
            if volume.schemaVersion != 1 {
                diagnostics.append(CorpusDiagnostic(
                    path: path,
                    recordID: volume.volume,
                    code: "invalid-id",
                    message: "只支援 schema_version 1。"
                ))
            }
            validateVolumeOrder(volume, path: path, diagnostics: &diagnostics)
            for proposition in volume.propositions {
                validateVolumeMembership(
                    proposition.id,
                    volume: volume.volume,
                    path: path,
                    diagnostics: &diagnostics
                )
                propositionsByID[proposition.id, default: []].append((path, proposition))
                allRecordIDs[proposition.id.rawValue, default: []].append(path)
                for segment in proposition.segments {
                    allRecordIDs[segment.id.rawValue, default: []].append(path)
                    if segment.id.owner != proposition.id {
                        diagnostics.append(CorpusDiagnostic(
                            path: path,
                            recordID: segment.id.rawValue,
                            code: "missing-parent",
                            message: "句段 ID 的 owner 必須是命題 \(proposition.id.rawValue)。"
                        ))
                    }
                }
            }
        }

        for (id, occurrences) in allRecordIDs where occurrences.count > 1 {
            diagnostics.append(CorpusDiagnostic(
                path: occurrences.sorted().dropFirst().first ?? occurrences[0],
                recordID: id,
                code: "duplicate-id",
                message: "ID 在 corpus 中出現 \(occurrences.count) 次。"
            ))
        }

        let corpusIDs = Set(propositionsByID.keys)
        for id in inventory.subtracting(corpusIDs).sorted() {
            diagnostics.append(CorpusDiagnostic(
                path: "sources.yaml",
                recordID: id.rawValue,
                code: "missing-proposition",
                message: "manifest inventory 的命題未出現在任何 corpus volume。"
            ))
        }
        for id in corpusIDs.subtracting(inventory).sorted() {
            let path = propositionsByID[id]?.first?.path ?? "corpus"
            diagnostics.append(CorpusDiagnostic(
                path: path,
                recordID: id.rawValue,
                code: "extra-proposition",
                message: "corpus 命題不在 manifest inventory 內。"
            ))
        }

        for (_, occurrences) in propositionsByID {
            for (path, proposition) in occurrences {
                validateParent(
                    of: proposition,
                    corpusIDs: corpusIDs,
                    path: path,
                    diagnostics: &diagnostics
                )
            }
        }
        return diagnostics.sorted()
    }

    public static func validateAlignment(
        manifest: SourceManifest,
        volumes: [CorpusVolume]
    ) -> [CorpusDiagnostic] {
        let inlineEditionIDs = Set(
            manifest.editions
                .filter { $0.inclusionMode == .inline }
                .map(\.id)
        )
        let externalEditionIDs = Set(
            manifest.editions
                .filter { $0.inclusionMode == .externalReference }
                .map(\.id)
        )
        let knownEditionIDs = inlineEditionIDs.union(externalEditionIDs)
        var diagnostics: [CorpusDiagnostic] = []
        for volume in volumes {
            let path = "corpus/\(volume.volume).yaml"
            for proposition in volume.propositions {
                for editionID in proposition.texts.keys where !knownEditionIDs.contains(editionID) {
                    diagnostics.append(CorpusDiagnostic(
                        path: path,
                        recordID: proposition.id.rawValue,
                        code: "alignment-gap",
                        message: "texts 引用了 manifest 未宣告的 edition：\(editionID)"
                    ))
                }
                for editionID in proposition.editionReferences.keys
                where !externalEditionIDs.contains(editionID) {
                    diagnostics.append(CorpusDiagnostic(
                        path: path,
                        recordID: proposition.id.rawValue,
                        code: "alignment-gap",
                        message: "edition_references 只能引用 external_reference edition：\(editionID)"
                    ))
                }
                for editionID in externalEditionIDs.sorted()
                where proposition.editionReferences[editionID].map(isPlaceholder) != false {
                    diagnostics.append(CorpusDiagnostic(
                        path: path,
                        recordID: proposition.id.rawValue,
                        code: "alignment-gap",
                        message: "external_reference edition \(editionID) 缺少版本參照。"
                    ))
                }
                validateChineseContent(
                    proposition,
                    path: path,
                    diagnostics: &diagnostics
                )
                for segment in proposition.segments {
                    for editionID in inlineEditionIDs.sorted()
                    where segment.alignment[editionID]?.isEmpty != false {
                        diagnostics.append(CorpusDiagnostic(
                            path: path,
                            recordID: segment.id.rawValue,
                            code: "alignment-gap",
                            message: "每個句段都必須對齊 inline edition \(editionID) 的來源單位。"
                        ))
                    }
                    for (editionID, indexes) in segment.alignment {
                        if !inlineEditionIDs.contains(editionID) {
                            diagnostics.append(CorpusDiagnostic(
                                path: path,
                                recordID: segment.id.rawValue,
                                code: "alignment-gap",
                                message: "alignment 只能引用 inline edition；\(editionID) 並非 inline。"
                            ))
                        }
                        if indexes.count > 2 {
                            diagnostics.append(CorpusDiagnostic(
                                path: path,
                                recordID: segment.id.rawValue,
                                code: "alignment-granularity",
                                message: "單一句段在 \(editionID) 吞入 \(indexes.count) 個來源單位；請拆成逐句工作譯文與哲學解讀。"
                            ))
                        }
                    }
                    let inlineCounts = inlineEditionIDs.compactMap {
                        segment.alignment[$0]?.count
                    }
                    if inlineCounts.filter({ $0 == 2 }).count > 1 {
                        diagnostics.append(CorpusDiagnostic(
                            path: path,
                            recordID: segment.id.rawValue,
                            code: "alignment-granularity",
                            message: "逐句句段只允許 1↔1 或版本句界不同時的 2↔1；2↔2 來源單位必須拆段。"
                        ))
                    }
                    validateEditionBoundaryDifference(
                        segment,
                        proposition: proposition,
                        inlineEditionIDs: inlineEditionIDs,
                        path: path,
                        diagnostics: &diagnostics
                    )
                    validateSourceUnitGranularity(
                        segment,
                        proposition: proposition,
                        inlineEditionIDs: inlineEditionIDs,
                        path: path,
                        diagnostics: &diagnostics
                    )
                }
                validateAlignmentOrder(
                    proposition,
                    inlineEditionIDs: inlineEditionIDs,
                    path: path,
                    diagnostics: &diagnostics
                )
                for editionID in inlineEditionIDs.sorted() {
                    validateCoverage(
                        proposition,
                        editionID: editionID,
                        path: path,
                        diagnostics: &diagnostics
                    )
                }
            }
        }
        return diagnostics.sorted()
    }

    private static func validateEditionBoundaryDifference(
        _ segment: AlignedSegment,
        proposition: PropositionRecord,
        inlineEditionIDs: Set<String>,
        path: String,
        diagnostics: inout [CorpusDiagnostic]
    ) {
        let counts = inlineEditionIDs.compactMap { segment.alignment[$0]?.count }
        guard counts.sorted() == [1, 2] else { return }

        var invalid = false
        for editionID in inlineEditionIDs {
            guard let indexes = segment.alignment[editionID],
                  let units = proposition.texts[editionID] else {
                continue
            }
            let aligned = indexes.compactMap { units.indices.contains($0) ? units[$0] : nil }
            if indexes.count == 1, let unit = aligned.first,
               containsObviousInternalSentenceBoundary(unit) {
                invalid = true
            }
            if indexes.count == 2,
               (aligned.count != 2 || !hasPlausibleSourceUnitEnding(aligned[0])) {
                invalid = true
            }
        }
        guard invalid else { return }
        diagnostics.append(CorpusDiagnostic(
            path: path,
            recordID: segment.id.rawValue,
            code: "alignment-granularity",
            message: "2↔1／1↔2 只能表達真實版本句界差異；不得任意切字或在單一來源單位中藏入多個完整句子。"
        ))
    }

    private static func hasPlausibleSourceUnitEnding(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(
            of: #"(?:[.!?:;](?:[\)\]\"'”’»*_]*)|[–—])\\?$"#,
            options: .regularExpression
        ) != nil
    }

    private static func validateSourceUnitGranularity(
        _ segment: AlignedSegment,
        proposition: PropositionRecord,
        inlineEditionIDs: Set<String>,
        path: String,
        diagnostics: inout [CorpusDiagnostic]
    ) {
        let alignedUnits = inlineEditionIDs.sorted().compactMap { editionID -> String? in
            guard let indexes = segment.alignment[editionID], indexes.count == 1,
                  let units = proposition.texts[editionID],
                  units.indices.contains(indexes[0]) else {
                return nil
            }
            return units[indexes[0]]
        }
        guard alignedUnits.count == inlineEditionIDs.count,
              alignedUnits.allSatisfy(containsObviousInternalSentenceBoundary) else {
            return
        }
        diagnostics.append(CorpusDiagnostic(
            path: path,
            recordID: segment.id.rawValue,
            code: "source-unit-granularity",
            message: "1↔1 對齊的各版本來源單位都含多個完整句子；請重切 texts 並為每句提供譯文與解讀。"
        ))
    }

    private static func containsObviousInternalSentenceBoundary(_ text: String) -> Bool {
        let pattern = #"[.!?](?:[\)\]\"'”’»*_]*)\s+(?=[\(\[\"'“„*_]*[A-ZÄÖÜ])"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in expression.matches(in: text, range: range) {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let matched = text[matchRange]
            guard let punctuation = matched.first(where: { ".!?".contains($0) }) else {
                continue
            }
            if punctuation == "." {
                if matchRange.lowerBound > text.startIndex {
                    let previous = text[text.index(before: matchRange.lowerBound)]
                    if previous.isWhitespace { continue }
                }
                let prefix = String(text[..<matchRange.lowerBound]) + "."
                if isSentenceBoundaryAbbreviation(prefix) { continue }
            }
            return true
        }
        return false
    }

    private static func isSentenceBoundaryAbbreviation(_ prefix: String) -> Bool {
        let normalized = prefix
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
            .lowercased()
        let abbreviations = [
            "d. h.", "z. b.", "i. e.", "i.e.", "e. g.", "e.g.",
            "u. s. f.", "u.s.f.", "etc.", "resp.", "viz.", "cf.",
            "dr.", "mr.", "mrs.", "st.",
        ]
        if abbreviations.contains(where: { normalized.hasSuffix($0) }) { return true }
        return normalized.range(of: #"(?:^|\s)[a-zäöü]\.$"#, options: .regularExpression) != nil
    }

    private static func validateAlignmentOrder(
        _ proposition: PropositionRecord,
        inlineEditionIDs: Set<String>,
        path: String,
        diagnostics: inout [CorpusDiagnostic]
    ) {
        for editionID in inlineEditionIDs.sorted() {
            guard let units = proposition.texts[editionID] else { continue }
            let flattened = proposition.segments.flatMap { $0.alignment[editionID] ?? [] }
            guard flattened != Array(units.indices) else { continue }
            diagnostics.append(CorpusDiagnostic(
                path: path,
                recordID: proposition.id.rawValue,
                code: "alignment-order",
                message: "\(editionID) 的來源索引必須依句段順序嚴格遞增，避免跨版本錯欄。"
            ))
        }
    }

    public static func validateRelations(volumes: [CorpusVolume]) -> [CorpusDiagnostic] {
        var diagnostics: [CorpusDiagnostic] = []
        var rationaleOwners: [String: PropositionID] = [:]
        for volume in volumes {
            let path = "corpus/\(volume.volume).yaml"
            for proposition in volume.propositions {
                guard !proposition.projectRelations.isEmpty else {
                    diagnostics.append(CorpusDiagnostic(
                        path: path,
                        recordID: proposition.id.rawValue,
                        code: "invalid-relation",
                        message: "每個命題至少要有一筆明確的 project relation。"
                    ))
                    continue
                }
                // #253：spec.md 的「Current evidence and historical context SHALL remain
                // separate」要求 issue references 住 `history`，**與 status 無關**。本守衛
                // 原本的前件只有 `status == .aspirational`，於是 rationale 引 issue 的
                // not_applicable relation 完全不被檢查（4.0621／4.064／4.0641 三筆即此形）。
                //
                // 修法是**擴及**、不是取代——兩個前件是不同的規則，必須 OR：
                //   (a) aspirational relation → 該命題要有 issue history（既有規則；「還沒
                //       做完的事」本來就該被 issue 追蹤，與 rationale 寫了什麼無關）
                //   (b) 任一 relation 的 rationale 引用了 issue → 同樣要有（本次新增）
                // 第一版實作誤把 (a) 換成 (b)，被既有回歸測試
                // `testAspirationalRelationRejectsMissingOrIncompleteGitHubIssueHistory`
                // 當場擋下——它的 fixture 是 aspirational 但 rationale 不引 issue。
                //
                // (b) 的前件刻意是「rationale 引用了 issue」而非「任一 relation」：後者會
                // flag 上百條（絕大多數 relation 根本不提 issue），那是把條文讀成它沒說的
                // 意思。實測 (b) 恰好命中上述三筆，零附帶損害。
                let hasAspirational = proposition.projectRelations
                    .contains { $0.status == .aspirational }
                let citesIssueInRationale = proposition.projectRelations
                    .contains { citesIssue($0.rationaleZhTW) }
                if (hasAspirational || citesIssueInRationale)
                    && !proposition.history.contains(where: {
                        $0.kind == .issue && isGitHubIssueURL($0.reference)
                    }) {
                    let subject = hasAspirational
                        ? "aspirational relation"
                        : "rationale 引用了 issue 的 relation"
                    diagnostics.append(CorpusDiagnostic(
                        path: path,
                        recordID: proposition.id.rawValue,
                        code: "invalid-relation",
                        message: "\(subject) 必須由完整 GitHub issue URL 的 issue history 追蹤。"
                    ))
                }
                for relation in proposition.projectRelations {
                    let normalizedRationale = relation.rationaleZhTW
                        .split(whereSeparator: \Character.isWhitespace)
                        .joined(separator: " ")
                    // #254：前件原為 `firstOwner != proposition.id`，於是**同命題內**兩條
                    // relation 共用 rationale 不觸發。spec 要求每條 relation「依自身哲學內容
                    // 說明專案關係」——同命題的兩條 relation 論證不同層次（如 not_applicable
                    // 否定 entity 層、analogy_only 肯定儲存層的有限類比），共用等於其中一條
                    // 沒有自己的論證。
                    if let firstOwner = rationaleOwners[normalizedRationale] {
                        // 訊息必須分支：同命題時 firstOwner 就是自己，沿用跨命題措辭會讀成
                        // 「與自己重複」。
                        let message = firstOwner == proposition.id
                            ? "同一命題內有兩條 relation 共用 rationale；每條 relation 必須依自身論證說明專案關係。"
                            : "relation rationale 與命題 \(firstOwner.rawValue) 重複；每條命題必須依自身哲學內容說明專案關係。"
                        diagnostics.append(CorpusDiagnostic(
                            path: path,
                            recordID: proposition.id.rawValue,
                            code: "duplicate-rationale",
                            message: message
                        ))
                    } else if !normalizedRationale.isEmpty {
                        rationaleOwners[normalizedRationale] = proposition.id
                    }
                    if isPlaceholder(relation.claimZhTW)
                        || isPlaceholder(relation.rationaleZhTW)
                        || (relation.status != .notApplicable && relation.mode == nil) {
                        diagnostics.append(CorpusDiagnostic(
                            path: path,
                            recordID: proposition.id.rawValue,
                            code: "invalid-relation",
                            message: "relation 必須有非占位的 claim、rationale 與適用的 mode。"
                        ))
                    }
                    if relation.status != .notApplicable && relation.evidence.isEmpty {
                        diagnostics.append(CorpusDiagnostic(
                            path: path,
                            recordID: proposition.id.rawValue,
                            code: "missing-evidence",
                            message: "除 not_applicable 外，project relation 必須附 current evidence。"
                        ))
                    }
                    if relation.status == .notApplicable
                        && (relation.mode != nil || !relation.evidence.isEmpty) {
                        diagnostics.append(CorpusDiagnostic(
                            path: path,
                            recordID: proposition.id.rawValue,
                            code: "invalid-relation",
                            message: "not_applicable 不得同時宣告實現 mode 或 current evidence。"
                        ))
                    }
                }
            }
        }
        return diagnostics.sorted()
    }

    public static func validateEvidence(
        volumes: [CorpusVolume],
        projectRoot: URL
    ) -> [CorpusDiagnostic] {
        var diagnostics: [CorpusDiagnostic] = []
        var fileCache: [String: String] = [:]
        var swiftCodeCache: [String: String] = [:]
        var fileReadFailures: [String: (code: String, message: String)] = [:]
        var commitCache: [String: Bool] = [:]
        var branchCache: [String: Bool] = [:]

        let evidenceCount = volumes.flatMap(\.propositions).reduce(0) { total, record in
            total + record.projectRelations.reduce(0) { $0 + $1.evidence.count }
        }
        let historyCount = volumes.flatMap(\.propositions).reduce(0) {
            $0 + $1.history.count
        }
        if evidenceCount > CorpusResourceLimits.maximumTotalEvidence {
            diagnostics.append(CorpusDiagnostic(
                path: "corpus",
                recordID: "evidence",
                code: "resource-limit",
                message: "current evidence 總數 \(evidenceCount) 超過上限 "
                    + "\(CorpusResourceLimits.maximumTotalEvidence)。"
            ))
            return diagnostics
        }
        if historyCount > CorpusResourceLimits.maximumTotalHistory {
            diagnostics.append(CorpusDiagnostic(
                path: "corpus",
                recordID: "history",
                code: "resource-limit",
                message: "history 總數 \(historyCount) 超過上限 "
                    + "\(CorpusResourceLimits.maximumTotalHistory)。"
            ))
            return diagnostics
        }

        for volume in volumes {
            let corpusPath = "corpus/\(volume.volume).yaml"
            for proposition in volume.propositions {
                for relation in proposition.projectRelations {
                    for evidence in relation.evidence {
                        validateCurrentEvidence(
                            evidence,
                            propositionID: proposition.id,
                            corpusPath: corpusPath,
                            projectRoot: projectRoot,
                            fileCache: &fileCache,
                            swiftCodeCache: &swiftCodeCache,
                            fileReadFailures: &fileReadFailures,
                            diagnostics: &diagnostics
                        )
                    }
                }
                for history in proposition.history {
                    validateHistory(
                        history,
                        propositionID: proposition.id,
                        corpusPath: corpusPath,
                        projectRoot: projectRoot,
                        commitCache: &commitCache,
                        branchCache: &branchCache,
                        diagnostics: &diagnostics
                    )
                }
            }
        }
        return diagnostics.sorted()
    }

    public static func validateAssets(
        volumes: [CorpusVolume],
        root: URL
    ) -> [CorpusDiagnostic] {
        validateAssets(
            volumes: volumes,
            root: root,
            maximumTotalBytes: CorpusResourceLimits.maximumTotalReferencedAssetBytes,
            maximumReferenceCount: CorpusResourceLimits.maximumReferencedAssetReferences,
            assetLoader: { candidate, maximumBytes in
                try exactlyBoundedFileData(
                    contentsOf: candidate,
                    maximumBytes: maximumBytes,
                    kind: "referenced-asset-bytes"
                )
            }
        )
    }

    static func validateAssets(
        volumes: [CorpusVolume],
        root: URL,
        maximumTotalBytes: Int,
        maximumReferenceCount: Int,
        assetLoader: (URL, Int) throws -> Data
    ) -> [CorpusDiagnostic] {
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let rootPrefix = canonicalRoot.path.hasSuffix("/")
            ? canonicalRoot.path
            : canonicalRoot.path + "/"
        let assetsRoot = root.appendingPathComponent("source-assets", isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard assetsRoot.path.hasPrefix(rootPrefix) else {
            return [CorpusDiagnostic(
                path: "source-assets",
                recordID: "manifest",
                code: "broken-path",
                message: "source-assets 越出 corpus root。"
            )]
        }
        let assetsPrefix = assetsRoot.path.hasSuffix("/")
            ? assetsRoot.path
            : assetsRoot.path + "/"
        let checksumURL = assetsRoot.appendingPathComponent("SHA256SUMS")
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard checksumURL.path.hasPrefix(assetsPrefix) else {
            return [CorpusDiagnostic(
                path: "source-assets/SHA256SUMS",
                recordID: "manifest",
                code: "broken-path",
                message: "SHA256SUMS 越出 source-assets trust root。"
            )]
        }
        let checksums: [String: String]
        do {
            checksums = try loadAssetChecksums(at: checksumURL)
        } catch let error as CorpusSchemaError {
            return [CorpusDiagnostic(
                path: "source-assets/SHA256SUMS",
                recordID: "manifest",
                code: "resource-limit",
                message: error.localizedDescription
            )]
        } catch {
            checksums = [:]
        }
        var diagnostics: [CorpusDiagnostic] = []
        var captureCache: [String: AssetCapture] = [:]
        var totalCapturedBytes = 0
        var totalLimitMessage: String?
        var totalReferenceCount = 0

        func projectedTotalMessage(adding count: Int) -> String? {
            let (sum, overflow) = totalCapturedBytes.addingReportingOverflow(count)
            let actual = overflow ? Int.max : sum
            guard actual > maximumTotalBytes else { return nil }
            return CorpusSchemaError.resourceLimit(
                kind: "referenced-assets-total-bytes",
                actual: actual,
                maximum: maximumTotalBytes
            ).localizedDescription
        }

        for volume in volumes {
            let corpusPath = "corpus/\(volume.volume).yaml"
            for proposition in volume.propositions {
                var references: Set<String> = []
                for value in rendererRichTextValues(in: proposition) {
                    let remainingReferences = maximumReferenceCount - totalReferenceCount
                    do {
                        let parsed = try MarkdownImageReferenceParser.references(
                            in: value,
                            maximumCount: max(0, remainingReferences)
                        )
                        totalReferenceCount += parsed.count
                        for reference in parsed {
                            references.insert(reference.path)
                        }
                    } catch {
                        diagnostics.append(CorpusDiagnostic(
                            path: corpusPath,
                            recordID: proposition.id.rawValue,
                            code: "resource-limit",
                            message: CorpusSchemaError.resourceLimit(
                                kind: "referenced-asset-references",
                                actual: maximumReferenceCount + 1,
                                maximum: maximumReferenceCount
                            ).localizedDescription
                        ))
                        return diagnostics.sorted()
                    }
                }
                for reference in references.sorted() {
                    let candidate = assetsRoot.appendingPathComponent(reference)
                        .standardizedFileURL
                        .resolvingSymlinksInPath()
                    guard candidate.path.hasPrefix(assetsPrefix),
                          FileManager.default.isReadableFile(atPath: candidate.path) else {
                        diagnostics.append(CorpusDiagnostic(
                            path: corpusPath,
                            recordID: proposition.id.rawValue,
                            code: "broken-path",
                            message: "來源圖資缺漏或越出 source-assets：\(reference)"
                        ))
                        continue
                    }
                    guard let expectedDigest = checksums[reference] else {
                        diagnostics.append(CorpusDiagnostic(
                            path: corpusPath,
                            recordID: proposition.id.rawValue,
                            code: "digest-mismatch",
                            message: "來源圖資未列入 source-assets/SHA256SUMS：\(reference)"
                        ))
                        continue
                    }
                    let capture: AssetCapture
                    if let cached = captureCache[candidate.path] {
                        capture = cached
                    } else if let message = totalLimitMessage {
                        capture = .resourceLimit(message)
                        captureCache[candidate.path] = capture
                    } else {
                        let remainingBytes = max(0, maximumTotalBytes - totalCapturedBytes)
                        let captureLimit = min(
                            CorpusResourceLimits.maximumReferencedAssetBytes,
                            remainingBytes
                        )
                        do {
                            let data = try assetLoader(candidate, captureLimit)
                            if let message = projectedTotalMessage(adding: data.count) {
                                totalLimitMessage = message
                                capture = .resourceLimit(message)
                            } else {
                                totalCapturedBytes += data.count
                                let digest = SHA256.hash(data: data)
                                    .map { String(format: "%02x", $0) }
                                    .joined()
                                capture = .digest(digest)
                            }
                        } catch let error as CorpusSchemaError {
                            if case let .resourceLimit(_, actual, _) = error,
                               let message = projectedTotalMessage(adding: actual) {
                                totalLimitMessage = message
                                capture = .resourceLimit(message)
                            } else {
                                capture = .resourceLimit(error.localizedDescription)
                            }
                        } catch {
                            capture = .unreadable
                        }
                        captureCache[candidate.path] = capture
                    }
                    switch capture {
                    case let .resourceLimit(message):
                        diagnostics.append(CorpusDiagnostic(
                            path: corpusPath,
                            recordID: proposition.id.rawValue,
                            code: "resource-limit",
                            message: message
                        ))
                        continue
                    case .unreadable:
                        diagnostics.append(CorpusDiagnostic(
                            path: corpusPath,
                            recordID: proposition.id.rawValue,
                            code: "digest-mismatch",
                            message: "來源圖資無法讀取：\(reference)"
                        ))
                        continue
                    case let .digest(actualDigest):
                        if actualDigest != expectedDigest {
                            diagnostics.append(CorpusDiagnostic(
                                path: corpusPath,
                                recordID: proposition.id.rawValue,
                                code: "digest-mismatch",
                                message: "來源圖資 SHA-256 與離線清單不符：\(reference)"
                            ))
                        }
                    }
                }
            }
        }
        return diagnostics.sorted()
    }

    private static func rendererRichTextValues(in proposition: PropositionRecord) -> [String] {
        var values = proposition.texts.values.flatMap { $0 }
        for segment in proposition.segments {
            values.append(segment.translationZhTW)
            values.append(segment.interpretationZhTW)
        }
        for relation in proposition.projectRelations {
            values.append(relation.claimZhTW)
            values.append(relation.rationaleZhTW)
            values += relation.evidence.compactMap(\.noteZhTW)
        }
        values += proposition.history.map(\.noteZhTW)
        return values
    }

    private static func loadAssetChecksums(at url: URL) throws -> [String: String] {
        let contents = try boundedUTF8FileContents(
            of: url,
            maximumBytes: CorpusResourceLimits.maximumAssetManifestUTF8Bytes,
            kind: "asset-manifest-utf8-bytes"
        )
        var checksums: [String: String] = [:]
        for line in contents.split(separator: "\n") {
            let fields = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
            guard fields.count == 2 else { continue }
            let digest = String(fields[0]).lowercased()
            let path = String(fields[1]).trimmingCharacters(in: .whitespaces)
            guard digest.count == 64,
                  digest.allSatisfy({ $0.isASCII && $0.hexDigitValue != nil }),
                  path.hasPrefix("images/") else {
                continue
            }
            checksums[path] = digest
        }
        return checksums
    }

    private static func validatedInventory(
        _ manifest: SourceManifest,
        diagnostics: inout [CorpusDiagnostic]
    ) -> Set<PropositionID> {
        var ids: Set<PropositionID> = []
        for rawID in manifest.scope.inventory {
            do {
                let id = try PropositionID(validating: rawID)
                if !ids.insert(id).inserted {
                    diagnostics.append(CorpusDiagnostic(
                        path: "sources.yaml",
                        recordID: rawID,
                        code: "duplicate-id",
                        message: "manifest inventory 重複列出同一命題。"
                    ))
                }
            } catch {
                diagnostics.append(CorpusDiagnostic(
                    path: "sources.yaml",
                    recordID: rawID,
                    code: "invalid-id",
                    message: "manifest inventory 含不合法的作者命題 ID。"
                ))
            }
        }
        return ids
    }

    private static func validateFixedScope(
        _ manifest: SourceManifest,
        inventory: Set<PropositionID>,
        diagnostics: inout [CorpusDiagnostic]
    ) {
        let scope = manifest.scope
        let serializedInventory = scope.inventory.joined(separator: "\n") + "\n"
        let inventoryDigest = SHA256.hash(data: Data(serializedInventory.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let canonicalInventoryDigest =
            "aeb7c112311663da7cb58c1ab65e0f2315e899010e83cc2a5a55720ffd3bb305"
        if inventoryDigest != canonicalInventoryDigest {
            diagnostics.append(CorpusDiagnostic(
                path: "sources.yaml",
                recordID: "inventory",
                code: "invalid-scope",
                message: "固定作者範圍必須恰為序言八段與《邏輯哲學論》526 條編號命題。"
            ))
        }

        let expectedEditions: [(id: String, role: EditionRole, language: String, mode: InclusionMode)] = [
            ("de", .original, "de", .inline),
            ("en_ogden_ramsey_1922", .translation, "en", .inline),
            ("en_pears_mcguinness", .translation, "en", .externalReference),
        ]
        let editionShapeMatches = manifest.editions.count == expectedEditions.count
            && zip(manifest.editions, expectedEditions).allSatisfy { edition, expected in
                edition.id == expected.id
                    && edition.role == expected.role
                    && edition.language == expected.language
                    && edition.inclusionMode == expected.mode
            }
        if !editionShapeMatches {
            diagnostics.append(CorpusDiagnostic(
                path: "sources.yaml",
                recordID: "editions",
                code: "invalid-scope",
                message: "固定版本必須依序為德文原典、Ogden／Ramsey 1922 inline 與 Pears／McGuinness external reference。"
            ))
        }

        for rawID in (1...7).map(String.init) {
            guard let id = PropositionID(rawValue: rawID), !inventory.contains(id) else { continue }
            diagnostics.append(CorpusDiagnostic(
                path: "sources.yaml",
                recordID: rawID,
                code: "missing-proposition",
                message: "固定作者範圍必須包含主命題 \(rawID)。"
            ))
        }
        if !inventory.contains(where: { $0.rawValue.hasPrefix("preface.") }) {
            diagnostics.append(CorpusDiagnostic(
                path: "sources.yaml",
                recordID: "preface.*",
                code: "missing-proposition",
                message: "固定作者範圍必須包含維根斯坦序言。"
            ))
        }
        let requiredExclusions = Set(["russell_introduction", "index"])
        let actualExclusions = Set(scope.excluded)
        if !requiredExclusions.isSubset(of: actualExclusions) {
            diagnostics.append(CorpusDiagnostic(
                path: "sources.yaml",
                recordID: "scope",
                code: "invalid-scope",
                message: "Russell 導論與索引必須明載為排除項目。"
            ))
        }
        let canonicalDedication =
            "Dem Andenken meines Freundes DAVID H. PINSENT gewidmet"
        let canonicalMottoPrefix = ". . . und alles, was man weiss, "
        let canonicalMottoMiddle = "nicht bloss rauschen und brausen gehört hat, "
        let canonicalMotto = canonicalMottoPrefix + canonicalMottoMiddle
            + "lässt sich in drei Worten sagen."
        if scope.dedication != canonicalDedication
            || scope.motto.text != canonicalMotto
            || scope.motto.attribution != "Kürnberger" {
            diagnostics.append(CorpusDiagnostic(
                path: "sources.yaml",
                recordID: "scope-metadata",
                code: "invalid-scope",
                message: "獻詞與題辭必須逐字符合固定作者 metadata。"
            ))
        }
    }

    private static func validateVolumeOrder(
        _ volume: CorpusVolume,
        path: String,
        diagnostics: inout [CorpusDiagnostic]
    ) {
        let actual = volume.propositions.map(\.id)
        let expected = actual.sorted()
        guard actual != expected else { return }
        let firstMismatch = zip(actual, expected).first { $0.0 != $0.1 }?.0
        diagnostics.append(CorpusDiagnostic(
            path: path,
            recordID: firstMismatch?.rawValue ?? volume.volume,
            code: "invalid-id",
            message: "命題必須依印刷十進位語意排列，不得用任意或浮點順序。"
        ))
    }

    private static func validateVolumeMembership(
        _ id: PropositionID,
        volume: String,
        path: String,
        diagnostics: inout [CorpusDiagnostic]
    ) {
        let expectedVolume: String
        if id.rawValue.hasPrefix("preface.") {
            expectedVolume = "preface"
        } else {
            expectedVolume = String(id.rawValue.prefix { $0 != "." })
        }
        guard expectedVolume == volume else {
            diagnostics.append(CorpusDiagnostic(
                path: path,
                recordID: id.rawValue,
                code: "invalid-id",
                message: "命題應位於 corpus/\(expectedVolume).yaml。"
            ))
            return
        }
    }

    private static func validateParent(
        of proposition: PropositionRecord,
        corpusIDs: Set<PropositionID>,
        path: String,
        diagnostics: inout [CorpusDiagnostic]
    ) {
        guard let expected = proposition.id.inferredParent else {
            if proposition.parent != nil {
                diagnostics.append(CorpusDiagnostic(
                    path: path,
                    recordID: proposition.id.rawValue,
                    code: "missing-parent",
                    message: "根命題與序言段落不得宣告 parent。"
                ))
            }
            return
        }
        guard proposition.parent == expected, corpusIDs.contains(expected) else {
            diagnostics.append(CorpusDiagnostic(
                path: path,
                recordID: proposition.id.rawValue,
                code: "missing-parent",
                message: "必須宣告並包含印刷階層 parent \(expected.rawValue)。"
            ))
            return
        }
    }

    private static func validateCoverage(
        _ proposition: PropositionRecord,
        editionID: String,
        path: String,
        diagnostics: inout [CorpusDiagnostic]
    ) {
        guard let units = proposition.texts[editionID], !units.isEmpty else {
            diagnostics.append(CorpusDiagnostic(
                path: path,
                recordID: proposition.id.rawValue,
                code: "alignment-gap",
                message: "inline edition \(editionID) 缺少有序來源單位。"
            ))
            return
        }
        var counts = Array(repeating: 0, count: units.count)
        for segment in proposition.segments {
            guard let indexes = segment.alignment[editionID], !indexes.isEmpty else {
                continue
            }
            for index in indexes {
                guard counts.indices.contains(index) else {
                    diagnostics.append(CorpusDiagnostic(
                        path: path,
                        recordID: segment.id.rawValue,
                        code: "alignment-gap",
                        message: "\(editionID) 索引 \(index) 超出 0..<\(units.count) 範圍。"
                    ))
                    continue
                }
                counts[index] += 1
            }
        }
        for index in counts.indices {
            if units[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                diagnostics.append(CorpusDiagnostic(
                    path: path,
                    recordID: proposition.id.rawValue,
                    code: "alignment-gap",
                    message: "\(editionID) 來源單位 \(index) 不得為空。"
                ))
            }
            if counts[index] == 0 {
                diagnostics.append(CorpusDiagnostic(
                    path: path,
                    recordID: proposition.id.rawValue,
                    code: "alignment-gap",
                    message: "\(editionID) 來源單位 \(index) 未被任何句段涵蓋。"
                ))
            } else if counts[index] > 1 {
                diagnostics.append(CorpusDiagnostic(
                    path: path,
                    recordID: proposition.id.rawValue,
                    code: "alignment-duplicate",
                    message: "\(editionID) 來源單位 \(index) 被涵蓋 \(counts[index]) 次。"
                ))
            }
        }
    }

    private static func validateChineseContent(
        _ proposition: PropositionRecord,
        path: String,
        diagnostics: inout [CorpusDiagnostic]
    ) {
        for segment in proposition.segments {
            let translationMissing = isPlaceholder(segment.translationZhTW)
                || !containsHanScalar(segment.translationZhTW)
            let interpretationMissing = isPlaceholder(segment.interpretationZhTW)
                || !containsHanScalar(segment.interpretationZhTW)
            if translationMissing {
                diagnostics.append(CorpusDiagnostic(
                    path: path,
                    recordID: segment.id.rawValue,
                    code: "missing-translation",
                    message: "translation_zh_tw 必須是非占位的臺灣正體中文工作譯文。"
                ))
            }
            if interpretationMissing
                || (!translationMissing
                    && segment.translationZhTW.trimmingCharacters(in: .whitespacesAndNewlines)
                        == segment.interpretationZhTW.trimmingCharacters(in: .whitespacesAndNewlines)) {
                diagnostics.append(CorpusDiagnostic(
                    path: path,
                    recordID: segment.id.rawValue,
                    code: "missing-interpretation",
                    message: "interpretation_zh_tw 必須另行解釋哲學意義，不能以譯文代替。"
                ))
            }
            if containsInterpretationBoilerplate(segment.interpretationZhTW) {
                diagnostics.append(CorpusDiagnostic(
                    path: path,
                    recordID: segment.id.rawValue,
                    code: "generic-interpretation",
                    message: "interpretation_zh_tw 不得以語料建構樣板代替該句的哲學解讀。"
                ))
            }
        }
    }

    private static func containsHanScalar(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            if scalar.properties.isUnifiedIdeograph
                || scalar.value == 0x3007
                || (0x323B0...0x33479).contains(scalar.value) {
                return true
            }

            let isCompatibilityIdeographBlock =
                (0xF900...0xFAFF).contains(scalar.value)
                || (0x2F800...0x2FA1F).contains(scalar.value)
            return isCompatibilityIdeographBlock && scalar.properties.isIdeographic
        }
    }

    private static func containsInterpretationBoilerplate(_ value: String) -> Bool {
        [
            "建立本命題的論證起點",
            "把前述論證推進到",
            "收束本命題",
        ].contains { value.contains($0) }
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lowercased = trimmed.lowercased()
        if lowercased.range(
            of: #"^(?:todo|tbd|待補|待翻譯|待解讀|placeholder)(?:$|[\s:：#()（）\-—－])"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        return ["<unfinished>", "<unreviewed>", "<todo>", "<placeholder>"].contains {
            lowercased.contains($0)
        }
    }

    private static func validateCurrentEvidence(
        _ evidence: CurrentEvidence,
        propositionID: PropositionID,
        corpusPath: String,
        projectRoot: URL,
        fileCache: inout [String: String],
        swiftCodeCache: inout [String: String],
        fileReadFailures: inout [String: (code: String, message: String)],
        diagnostics: inout [CorpusDiagnostic]
    ) {
        guard let fileURL = safeProjectURL(evidence.path, root: projectRoot) else {
            diagnostics.append(CorpusDiagnostic(
                path: corpusPath,
                recordID: propositionID.rawValue,
                code: "broken-path",
                message: "evidence path 必須是專案根目錄內的相對路徑：\(evidence.path)"
            ))
            return
        }
        let canonicalRoot = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        let rootPrefix = canonicalRoot.path.hasSuffix("/")
            ? canonicalRoot.path
            : canonicalRoot.path + "/"
        let normalizedPath = String(fileURL.path.dropFirst(rootPrefix.count))
            .replacingOccurrences(of: "\\", with: "/")
        if normalizedPath == "docs/tractatus/generated"
            || normalizedPath.hasPrefix("docs/tractatus/generated/") {
            diagnostics.append(CorpusDiagnostic(
                path: corpusPath,
                recordID: propositionID.rawValue,
                code: "broken-path",
                message: "generated 文件不得作為 current evidence。"
            ))
            return
        }
        if normalizedPath == "docs/tractatus/corpus"
            || normalizedPath.hasPrefix("docs/tractatus/corpus/")
            || normalizedPath == "docs/tractatus/source-snapshots"
            || normalizedPath.hasPrefix("docs/tractatus/source-snapshots/") {
            diagnostics.append(CorpusDiagnostic(
                path: corpusPath,
                recordID: propositionID.rawValue,
                code: "invalid-evidence",
                message: "canonical corpus 與 source snapshot 不得循環作為自身 project relation 的現況證據。"
            ))
            return
        }

        let cacheKey = fileURL.path
        let contents: String
        if let cached = fileCache[cacheKey] {
            contents = cached
        } else if let failure = fileReadFailures[cacheKey] {
            diagnostics.append(CorpusDiagnostic(
                path: corpusPath,
                recordID: propositionID.rawValue,
                code: failure.code,
                message: failure.message
            ))
            return
        } else {
            do {
                let loaded = try boundedUTF8FileContents(
                    of: fileURL,
                    maximumBytes: CorpusResourceLimits.maximumEvidenceFileUTF8Bytes,
                    kind: "evidence-file-utf8-bytes"
                )
                fileCache[cacheKey] = loaded
                contents = loaded
            } catch let error as CorpusSchemaError {
                fileReadFailures[cacheKey] = (
                    code: "resource-limit",
                    message: error.localizedDescription
                )
                diagnostics.append(CorpusDiagnostic(
                    path: corpusPath,
                    recordID: propositionID.rawValue,
                    code: "resource-limit",
                    message: error.localizedDescription
                ))
                return
            } catch {
                let message = "evidence path 不存在或不是可讀文字檔：\(evidence.path)"
                fileReadFailures[cacheKey] = (code: "broken-path", message: message)
                diagnostics.append(CorpusDiagnostic(
                    path: corpusPath,
                    recordID: propositionID.rawValue,
                    code: "broken-path",
                    message: message
                ))
                return
            }
        }

        let locator = evidence.locator.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !locator.isEmpty, contents.contains(locator) else {
            diagnostics.append(CorpusDiagnostic(
                path: corpusPath,
                recordID: propositionID.rawValue,
                code: "missing-symbol",
                message: "在 \(evidence.path) 找不到 \(evidence.kind.rawValue) 定位點：\(evidence.locator)"
            ))
            return
        }
        let swiftContents: String?
        if normalizedPath.hasSuffix(".swift") {
            if let cached = swiftCodeCache[cacheKey] {
                swiftContents = cached
            } else {
                let lexical = swiftCodeView(contents)
                swiftCodeCache[cacheKey] = lexical
                swiftContents = lexical
            }
        } else {
            swiftContents = nil
        }
        guard locatorMatchesDeclaredKind(
            locator,
            kind: evidence.kind,
            path: normalizedPath,
            contents: contents,
            swiftContents: swiftContents
        ) else {
            diagnostics.append(CorpusDiagnostic(
                path: corpusPath,
                recordID: propositionID.rawValue,
                code: "invalid-evidence",
                message: "定位點存在，但不符合宣告的 \(evidence.kind.rawValue) 結構：\(evidence.locator)"
            ))
            return
        }
    }

    private static func locatorMatchesDeclaredKind(
        _ locator: String,
        kind: EvidenceLocatorKind,
        path: String,
        contents: String,
        swiftContents: String?
    ) -> Bool {
        switch kind {
        case .heading:
            guard locator.range(
                of: #"^#{1,6}\s+\S"#,
                options: .regularExpression
            ) != nil else {
                return false
            }
            return contents.split(separator: "\n", omittingEmptySubsequences: false)
                .contains { $0.trimmingCharacters(in: .whitespaces) == locator }
        case .symbol:
            guard path.hasSuffix(".swift"),
                  locator.range(
                    of: #"^[A-Za-z_][A-Za-z0-9_]*$"#,
                    options: .regularExpression
                  ) != nil else {
                return false
            }
            let escaped = NSRegularExpression.escapedPattern(for: locator)
            return (swiftContents ?? "").range(
                of: #"\b(?:actor|associatedtype|class|enum|func|let|macro|protocol|struct|typealias|var)\s+`?"#
                    + escaped
                    + #"`?(?![A-Za-z0-9_])"#,
                options: .regularExpression
            ) != nil
        case .requirement:
            guard path.hasPrefix("openspec/") else { return false }
            return contents.split(separator: "\n", omittingEmptySubsequences: false)
                .contains { line in
                    let value = line.trimmingCharacters(in: .whitespaces)
                    let prefix = "### Requirement:"
                    guard value.hasPrefix(prefix) else { return false }
                    return value.dropFirst(prefix.count)
                        .trimmingCharacters(in: .whitespaces) == locator
                }
        case .test:
            guard path.hasPrefix("Tests/"),
                  path.hasSuffix(".swift"),
                  locator.range(
                    of: #"^test[A-Za-z0-9_]*$"#,
                    options: .regularExpression
                  ) != nil else {
                return false
            }
            let escaped = NSRegularExpression.escapedPattern(for: locator)
            return (swiftContents ?? "").range(
                of: "\\bfunc\\s+`?\(escaped)`?\\s*\\(",
                options: .regularExpression
            ) != nil
        }
    }

    private enum SwiftLexicalMode {
        case code
        case lineComment
        case blockComment(depth: Int)
        case string(hashCount: Int, quoteCount: Int)
    }

    /// 建立只保留 Swift code token 與換行的窄詞法視圖，避免註解或字串冒充 declaration。
    private static func swiftCodeView(_ source: String) -> String {
        let characters = Array(source)
        var result: [Character] = []
        result.reserveCapacity(characters.count)
        var index = 0
        var mode = SwiftLexicalMode.code

        func has(_ token: [Character], at start: Int) -> Bool {
            guard start >= 0, start + token.count <= characters.count else { return false }
            return characters[start..<(start + token.count)].elementsEqual(token)
        }

        func appendMasked(_ count: Int) {
            for offset in 0..<count {
                let character = characters[index + offset]
                result.append(character == "\n" || character == "\r" ? character : " ")
            }
            index += count
        }

        while index < characters.count {
            switch mode {
            case .code:
                if has(["/", "/"], at: index) {
                    appendMasked(2)
                    mode = .lineComment
                } else if has(["/", "*"], at: index) {
                    appendMasked(2)
                    mode = .blockComment(depth: 1)
                } else {
                    var quoteIndex = index
                    while quoteIndex < characters.count, characters[quoteIndex] == "#" {
                        quoteIndex += 1
                    }
                    guard quoteIndex < characters.count, characters[quoteIndex] == "\"" else {
                        result.append(characters[index])
                        index += 1
                        continue
                    }
                    let quoteCount = hasSwiftStringDelimiter(
                        in: characters,
                        at: quoteIndex,
                        quoteCount: 3,
                        hashCount: 0
                    ) ? 3 : 1
                    let hashCount = quoteIndex - index
                    appendMasked(hashCount + quoteCount)
                    mode = .string(hashCount: hashCount, quoteCount: quoteCount)
                }

            case .lineComment:
                let character = characters[index]
                if character == "\n" || character == "\r" {
                    result.append(character)
                    index += 1
                    mode = .code
                } else {
                    appendMasked(1)
                }

            case let .blockComment(depth):
                if has(["/", "*"], at: index) {
                    appendMasked(2)
                    mode = .blockComment(depth: depth + 1)
                } else if has(["*", "/"], at: index) {
                    appendMasked(2)
                    mode = depth == 1 ? .code : .blockComment(depth: depth - 1)
                } else {
                    appendMasked(1)
                }

            case let .string(hashCount, quoteCount):
                if let end = swiftInterpolationEnd(
                    in: characters,
                    from: index,
                    hashCount: hashCount
                ) {
                    appendMasked(end - index)
                    continue
                }
                if hasSwiftStringDelimiter(
                    in: characters,
                    at: index,
                    quoteCount: quoteCount,
                    hashCount: hashCount
                ) {
                    appendMasked(quoteCount + hashCount)
                    mode = .code
                    continue
                }
                if characters[index] == "\\" {
                    let hashes = Array(repeating: Character("#"), count: hashCount)
                    if has(hashes, at: index + 1),
                       index + 1 + hashCount < characters.count {
                        appendMasked(1 + hashCount)
                        appendMasked(1)
                        continue
                    }
                }
                appendMasked(1)
            }
        }
        return String(result)
    }

    private static func swiftInterpolationEnd(
        in characters: [Character],
        from start: Int,
        hashCount: Int
    ) -> Int? {
        guard start < characters.count, characters[start] == "\\" else { return nil }
        let hashesEnd = start + 1 + hashCount
        guard hashesEnd < characters.count else { return nil }
        for offset in 0..<hashCount where characters[start + 1 + offset] != "#" {
            return nil
        }
        guard characters[hashesEnd] == "(" else { return nil }

        var index = hashesEnd + 1
        var parenthesisDepth = 1
        while index < characters.count {
            if hasCharacters(["/", "/"], in: characters, at: index) {
                index += 2
                while index < characters.count,
                      characters[index] != "\n",
                      characters[index] != "\r" {
                    index += 1
                }
                continue
            }
            if hasCharacters(["/", "*"], in: characters, at: index) {
                index = swiftBlockCommentEnd(in: characters, from: index)
                continue
            }
            if swiftStringOpener(in: characters, at: index) != nil {
                index = swiftStringLiteralEnd(in: characters, from: index)
                continue
            }
            if characters[index] == "(" {
                parenthesisDepth += 1
            } else if characters[index] == ")" {
                parenthesisDepth -= 1
                if parenthesisDepth == 0 { return index + 1 }
            }
            index += 1
        }
        return characters.count
    }

    private static func swiftStringLiteralEnd(
        in characters: [Character],
        from start: Int
    ) -> Int {
        guard let opener = swiftStringOpener(in: characters, at: start) else {
            return start + 1
        }
        var index = opener.contentStart
        while index < characters.count {
            if let end = swiftInterpolationEnd(
                in: characters,
                from: index,
                hashCount: opener.hashCount
            ) {
                index = end
                continue
            }
            if hasSwiftStringDelimiter(
                in: characters,
                at: index,
                quoteCount: opener.quoteCount,
                hashCount: opener.hashCount
            ) {
                return index + opener.quoteCount + opener.hashCount
            }
            if characters[index] == "\\" {
                let escapedScalar = index + 1 + opener.hashCount
                var matchingEscape = escapedScalar < characters.count
                for offset in 0..<opener.hashCount
                where characters[index + 1 + offset] != "#" {
                    matchingEscape = false
                }
                if matchingEscape {
                    index = escapedScalar + 1
                    continue
                }
            }
            index += 1
        }
        return characters.count
    }

    private static func swiftStringOpener(
        in characters: [Character],
        at start: Int
    ) -> (hashCount: Int, quoteCount: Int, contentStart: Int)? {
        guard start < characters.count else { return nil }
        var quoteIndex = start
        while quoteIndex < characters.count, characters[quoteIndex] == "#" {
            quoteIndex += 1
        }
        guard quoteIndex < characters.count, characters[quoteIndex] == "\"" else {
            return nil
        }
        let quoteCount = hasSwiftStringDelimiter(
            in: characters,
            at: quoteIndex,
            quoteCount: 3,
            hashCount: 0
        ) ? 3 : 1
        return (quoteIndex - start, quoteCount, quoteIndex + quoteCount)
    }

    private static func hasSwiftStringDelimiter(
        in characters: [Character],
        at start: Int,
        quoteCount: Int,
        hashCount: Int
    ) -> Bool {
        guard start >= 0,
              start + quoteCount + hashCount <= characters.count else {
            return false
        }
        for offset in 0..<quoteCount where characters[start + offset] != "\"" {
            return false
        }
        for offset in 0..<hashCount
        where characters[start + quoteCount + offset] != "#" {
            return false
        }
        return true
    }

    private static func swiftBlockCommentEnd(
        in characters: [Character],
        from start: Int
    ) -> Int {
        var index = start + 2
        var depth = 1
        while index < characters.count {
            if hasCharacters(["/", "*"], in: characters, at: index) {
                depth += 1
                index += 2
            } else if hasCharacters(["*", "/"], in: characters, at: index) {
                depth -= 1
                index += 2
                if depth == 0 { return index }
            } else {
                index += 1
            }
        }
        return characters.count
    }

    private static func hasCharacters(
        _ token: [Character],
        in characters: [Character],
        at start: Int
    ) -> Bool {
        guard start >= 0, start + token.count <= characters.count else { return false }
        return characters[start..<(start + token.count)].elementsEqual(token)
    }

    private static func validateHistory(
        _ history: HistoryReference,
        propositionID: PropositionID,
        corpusPath: String,
        projectRoot: URL,
        commitCache: inout [String: Bool],
        branchCache: inout [String: Bool],
        diagnostics: inout [CorpusDiagnostic]
    ) {
        if isPlaceholder(history.noteZhTW) {
            diagnostics.append(CorpusDiagnostic(
                path: corpusPath,
                recordID: propositionID.rawValue,
                code: "invalid-history",
                message: "history 必須說明 retained、revised 或 rejected 的理由。"
            ))
        }
        switch history.kind {
        case .commit:
            let exists: Bool
            if let cached = commitCache[history.reference] {
                exists = cached
            } else {
                exists = gitCommitExists(history.reference, projectRoot: projectRoot)
                commitCache[history.reference] = exists
            }
            if !exists {
                diagnostics.append(CorpusDiagnostic(
                    path: corpusPath,
                    recordID: propositionID.rawValue,
                    code: "unknown-commit",
                    message: "本機 Git object database 無法解析 commit：\(history.reference)"
                ))
            }
        case .branch:
            let validFormat = !history.reference.isEmpty
                && history.reference.allSatisfy({
                    $0.isASCII && ($0.isLetter || $0.isNumber || "._/-".contains($0))
                })
            if !validFormat {
                diagnostics.append(CorpusDiagnostic(
                    path: corpusPath,
                    recordID: propositionID.rawValue,
                    code: "invalid-history",
                    message: "branch reference 格式不合法。"
                ))
            } else {
                let exists: Bool
                if let cached = branchCache[history.reference] {
                    exists = cached
                } else {
                    exists = gitBranchExists(history.reference, projectRoot: projectRoot)
                    branchCache[history.reference] = exists
                }
                if !exists {
                    diagnostics.append(CorpusDiagnostic(
                        path: corpusPath,
                        recordID: propositionID.rawValue,
                        code: "unknown-branch",
                        message: "本機 Git object database 無法解析 branch：\(history.reference)"
                    ))
                }
            }
        case .issue:
            if !isGitHubIssueURL(history.reference) {
                diagnostics.append(CorpusDiagnostic(
                    path: corpusPath,
                    recordID: propositionID.rawValue,
                    code: "invalid-history",
                    message: "issue history 必須使用完整 GitHub issue URL。"
                ))
            }
        }
    }

    private static func safeProjectURL(_ relativePath: String, root: URL) -> URL? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return nil }
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root.appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPrefix = canonicalRoot.path.hasSuffix("/")
            ? canonicalRoot.path
            : canonicalRoot.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else { return nil }
        return candidate
    }

    /// 子程序環境：剝除全部 `GIT_*`（#239）。`-C` 擋不住 `GIT_DIR`，而本型別問的
    /// 都是「專案自己的歷史」，答案不該被呼叫者的環境改變。
    private static var scrubbedGitEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    }

    private static func gitCommitExists(_ reference: String, projectRoot: URL) -> Bool {
        guard (7...40).contains(reference.count),
              reference.allSatisfy({ $0.isASCII && $0.hexDigitValue != nil }) else {
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "git", "-C", projectRoot.path, "cat-file", "-e", "\(reference)^{commit}",
        ]
        // #239：`-C` 擋不住 `GIT_DIR`——問的必須是 projectRoot 自己的 repo
        process.environment = Self.scrubbedGitEnvironment
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func gitBranchExists(_ reference: String, projectRoot: URL) -> Bool {
        let candidates: [String]
        if reference.hasPrefix("refs/heads/") || reference.hasPrefix("refs/remotes/") {
            candidates = [reference]
        } else if reference.hasPrefix("refs/") {
            return false
        } else {
            candidates = ["refs/heads/\(reference)", "refs/remotes/\(reference)"]
        }

        for candidate in candidates {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "git", "-C", projectRoot.path,
                "rev-parse", "--verify", "--quiet", "--end-of-options", "\(candidate)^{commit}",
            ]
            // #239：同上
            process.environment = Self.scrubbedGitEnvironment
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    return true
                }
            } catch {
                return false
            }
        }
        return false
    }

    /// 散文裡是否引用了 issue（`#` 後接 1–5 位 ASCII 數字，且數字串未被更長的數字截斷）。
    ///
    /// 這是**啟發式**——它讀的是自由文字，不是結構化欄位。界定位數是為了不把版本號、
    /// 章節號、內部序號誤判成 issue 引用；`#` 後不接數字（如 `C#`）同樣不算。
    /// 實測全 corpus 的 rationale 只出現 `#223` 與 `#214`，皆為真實 issue 號。
    private static func citesIssue(_ text: String) -> Bool {
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            guard chars[i] == "#" else { i += 1; continue }
            var j = i + 1
            while j < chars.count, chars[j].isASCII, chars[j].isNumber { j += 1 }
            let digits = j - (i + 1)
            // 1–5 位才算；`j` 已停在第一個非數字（或字串結尾），故無需再檢查後綴。
            if digits >= 1 && digits <= 5 { return true }
            i = j > i ? j : i + 1
        }
        return false
    }

    private static func isGitHubIssueURL(_ reference: String) -> Bool {
        guard let url = URL(string: reference),
              url.scheme == "https",
              url.host == "github.com" else { return false }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 4,
              components[2] == "issues",
              components[3].allSatisfy({ $0.isASCII && $0.isNumber }),
              let issueNumber = Int(components[3]),
              issueNumber > 0 else { return false }
        return true
    }
}
