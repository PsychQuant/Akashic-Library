import Foundation

struct ValidatedCorpus: Sendable {
    let manifest: SourceManifest
    let volumes: [CorpusVolume]
    let summary: ValidationSummary
}

struct ValidationSummary: Sendable {
    let propositions: Int
    let sourceUnits: Int
    let segments: Int
    let projectRelations: Int

    var countsText: String {
        "propositions=\(propositions) source_units=\(sourceUnits) "
            + "segments=\(segments) project_relations=\(projectRelations)"
    }
}

struct ValidationRun: Sendable {
    let corpus: ValidatedCorpus
    let incompleteness: [ConstructionGap]
    let allowIncomplete: Bool

    var output: String {
        var lines = incompleteness.sorted().map(\.formatted)
        let label = allowIncomplete ? "validated (allow-incomplete)" : "validated"
        lines.append("\(label): \(corpus.summary.countsText)")
        return lines.joined(separator: "\n")
    }
}

struct ConstructionGap: Hashable, Comparable, Sendable {
    let kind: String
    let value: String

    static func < (lhs: ConstructionGap, rhs: ConstructionGap) -> Bool {
        if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
        return lhs.value < rhs.value
    }

    var formatted: String {
        "incomplete: \(kind) \(value)"
    }
}

enum CorpusValidationEngine {
    private static let expectedVolumes = [
        "preface.yaml", "1.yaml", "2.yaml", "3.yaml", "4.yaml",
        "5.yaml", "6.yaml", "7.yaml",
    ]

    static func validate(root: URL, allowIncomplete: Bool) throws -> ValidationRun {
        let canonicalRoot = root.standardizedFileURL
        var diagnostics: [CorpusDiagnostic] = []
        var gaps: [ConstructionGap] = []

        let manifest = try loadManifest(root: canonicalRoot)
        if manifest.schemaVersion != 1 {
            diagnostics.append(CorpusDiagnostic(
                path: "sources.yaml",
                recordID: "schema_version",
                code: "schema-error",
                message: "只支援 schema_version 1。"
            ))
        }

        let load = loadVolumes(
            root: canonicalRoot,
            allowIncomplete: allowIncomplete,
            diagnostics: &diagnostics,
            gaps: &gaps
        )
        let volumes = load.volumes.sorted { volumeOrder($0.volume) < volumeOrder($1.volume) }
        let projectRoot = findProjectRoot(from: canonicalRoot)

        diagnostics += SourceManifestValidator.validate(
            manifest,
            root: canonicalRoot,
            volumes: volumes
        )
        diagnostics += CorpusValidator.validateStructure(manifest: manifest, volumes: volumes)
        diagnostics += CorpusValidator.validateAlignment(manifest: manifest, volumes: volumes)
        diagnostics += CorpusValidator.validateRelations(volumes: volumes)
        diagnostics += CorpusValidator.validateEvidence(volumes: volumes, projectRoot: projectRoot)
        diagnostics += CorpusValidator.validateAssets(volumes: volumes, root: canonicalRoot)

        if allowIncomplete {
            var retained: [CorpusDiagnostic] = []
            for diagnostic in diagnostics {
                if diagnostic.code == "missing-proposition"
                    && diagnostic.message.hasPrefix("manifest inventory") {
                    gaps.append(ConstructionGap(
                        kind: "missing-proposition",
                        value: diagnostic.recordID
                    ))
                } else {
                    retained.append(diagnostic)
                }
            }
            diagnostics = retained
        }

        diagnostics = uniqueDiagnostics(diagnostics)
        gaps = Array(Set(gaps)).sorted()
        if !diagnostics.isEmpty {
            throw TractatusValidationFailure(
                diagnostics: diagnostics,
                incompleteness: gaps.map(\.formatted)
            )
        }

        let summary = ValidationSummary(
            propositions: volumes.reduce(0) { $0 + $1.propositions.count },
            sourceUnits: volumes
                .flatMap(\.propositions)
                .reduce(0) { count, proposition in
                    count + proposition.texts.values.reduce(0) { $0 + $1.count }
                },
            segments: volumes.flatMap(\.propositions).reduce(0) { $0 + $1.segments.count },
            projectRelations: volumes
                .flatMap(\.propositions)
                .reduce(0) { $0 + $1.projectRelations.count }
        )
        let corpus = ValidatedCorpus(manifest: manifest, volumes: volumes, summary: summary)
        return ValidationRun(
            corpus: corpus,
            incompleteness: gaps,
            allowIncomplete: allowIncomplete
        )
    }

    private static func loadManifest(root: URL) throws -> SourceManifest {
        let url = root.appendingPathComponent("sources.yaml")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TractatusValidationFailure(diagnostics: [CorpusDiagnostic(
                path: "sources.yaml",
                recordID: "manifest",
                code: "broken-path",
                message: "找不到來源 manifest。"
            )])
        }
        do {
            return try SourceManifestYAMLDecoder.decode(contentsOf: url)
        } catch {
            throw TractatusValidationFailure(diagnostics: [decodeDiagnostic(
                error,
                path: "sources.yaml"
            )])
        }
    }

    private static func loadVolumes(
        root: URL,
        allowIncomplete: Bool,
        diagnostics: inout [CorpusDiagnostic],
        gaps: inout [ConstructionGap]
    ) -> (volumes: [CorpusVolume], filenames: Set<String>) {
        let corpusDirectory = root.appendingPathComponent("corpus", isDirectory: true)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: corpusDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let yamlURLs = urls.filter { $0.pathExtension == "yaml" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let filenames = Set(yamlURLs.map(\.lastPathComponent))

        for expected in expectedVolumes where !filenames.contains(expected) {
            if allowIncomplete {
                gaps.append(ConstructionGap(kind: "missing-volume", value: "corpus/\(expected)"))
            } else {
                diagnostics.append(CorpusDiagnostic(
                    path: "corpus/\(expected)",
                    recordID: expected.replacingOccurrences(of: ".yaml", with: ""),
                    code: "missing-proposition",
                    message: "strict mode 缺少必要 corpus volume。"
                ))
            }
        }

        var volumes: [CorpusVolume] = []
        for url in yamlURLs {
            let relativePath = "corpus/\(url.lastPathComponent)"
            if !expectedVolumes.contains(url.lastPathComponent) {
                diagnostics.append(CorpusDiagnostic(
                    path: relativePath,
                    recordID: url.deletingPathExtension().lastPathComponent,
                    code: "extra-proposition",
                    message: "正典只接受 preface.yaml 與 1.yaml 至 7.yaml。"
                ))
            }
            do {
                let volume = try CorpusYAMLDecoder.decodeVolume(contentsOf: url)
                let expectedVolume = url.deletingPathExtension().lastPathComponent
                if volume.volume != expectedVolume {
                    diagnostics.append(CorpusDiagnostic(
                        path: relativePath,
                        recordID: volume.volume,
                        code: "volume-file-mismatch",
                        message: "YAML volume 必須與檔名 \(expectedVolume).yaml 一致。"
                    ))
                }
                volumes.append(volume)
            } catch {
                diagnostics.append(decodeDiagnostic(error, path: relativePath))
            }
        }
        return (volumes, filenames)
    }

    private static func decodeDiagnostic(_ error: Error, path: String) -> CorpusDiagnostic {
        if let schemaError = error as? CorpusSchemaError {
            return CorpusDiagnostic(
                path: path,
                recordID: schemaError.diagnosticSubject,
                code: schemaError.diagnosticCode,
                message: schemaError.errorDescription ?? "YAML schema 錯誤。"
            )
        }
        return CorpusDiagnostic(
            path: path,
            recordID: "document",
            code: "schema-error",
            message: "YAML 無法依封閉 schema 解碼。"
        )
    }

    private static func findProjectRoot(from root: URL) -> URL {
        var candidate = root.standardizedFileURL
        while candidate.path != "/" {
            let package = candidate.appendingPathComponent("Package.swift")
            let git = candidate.appendingPathComponent(".git")
            if FileManager.default.fileExists(atPath: package.path)
                || FileManager.default.fileExists(atPath: git.path) {
                return candidate
            }
            let parent = candidate.deletingLastPathComponent()
            if parent == candidate { break }
            candidate = parent
        }
        return root.standardizedFileURL
    }

    private static func volumeOrder(_ volume: String) -> Int {
        if volume == "preface" { return 0 }
        return Int(volume).map { $0 + 1 } ?? Int.max
    }

    private static func uniqueDiagnostics(_ diagnostics: [CorpusDiagnostic]) -> [CorpusDiagnostic] {
        var seen: Set<String> = []
        return diagnostics.sorted().filter { diagnostic in
            seen.insert(diagnostic.formatted).inserted
        }
    }
}
