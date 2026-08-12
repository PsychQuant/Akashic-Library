import CryptoKit
import Foundation
@testable import TractatusDocs

enum TractatusDiskFixture {
    static func make() throws -> URL {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("tractatus-doc-\(UUID().uuidString)", isDirectory: true)
        let root = container.appendingPathComponent("docs/tractatus", isDirectory: true)
        let snapshots = root.appendingPathComponent("source-snapshots", isDirectory: true)
        let corpus = root.appendingPathComponent("corpus", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: corpus, withIntermediateDirectories: true)
        let canonicalManifest = try SourceManifestYAMLDecoder.decode(
            contentsOf: repositoryRoot.appendingPathComponent("docs/tractatus/sources.yaml")
        )
        let inventory = canonicalManifest.scope.inventory
        let german = snapshot(edition: .german, inventory: inventory)
        let english = snapshot(edition: .english, inventory: inventory)
        try german.write(
            to: snapshots.appendingPathComponent("de.md"),
            atomically: true,
            encoding: .utf8
        )
        try english.write(
            to: snapshots.appendingPathComponent("en.md"),
            atomically: true,
            encoding: .utf8
        )
        try manifestYAML(
            inlineGermanDigest: sha256(german),
            inlineEnglishDigest: sha256(english)
        ).write(
            to: root.appendingPathComponent("sources.yaml"),
            atomically: true,
            encoding: .utf8
        )
        for volume in ["preface", "1", "2", "3", "4", "5", "6", "7"] {
            let ids = inventory.filter { id in
                volume == "preface"
                    ? id.hasPrefix("preface.")
                    : id == volume || id.hasPrefix("\(volume).")
            }
            try volumeYAML(volume: volume, ids: ids).write(
                to: corpus.appendingPathComponent("\(volume).yaml"),
                atomically: true,
                encoding: .utf8
            )
        }
        return root
    }

    static func remove(_ root: URL) {
        let container = root
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        try? FileManager.default.removeItem(at: container)
    }

    private enum SnapshotEdition {
        case german
        case english
    }

    private static func snapshot(edition: SnapshotEdition, inventory: [String]) -> String {
        let preface = inventory.filter { $0.hasPrefix("preface.") }
        let numbered = inventory.filter { !$0.hasPrefix("preface.") }
        switch edition {
        case .german:
            let paragraphs = preface.map { "Deutscher Text \($0)." }
                .joined(separator: "\n\n")
            let propositions = numbered.map { "**\($0)** Deutscher Text \($0)." }
                .joined(separator: "\n\n")
            return """
            ## Vorwort

            \(paragraphs)

            *L. W.*

            ## Logisch-philosophische Abhandlung

            \(propositions)
            """ + "\n"
        case .english:
            let paragraphs = preface.map { "English text \($0)." }
                .joined(separator: "\n\n")
            let propositions = numbered.map {
                "**[\($0)](https://example.invalid/\($0))** English text \($0)."
            }.joined(separator: "\n\n")
            return """
            ## Preface

            \(paragraphs)

            *L.W.*

            ## Tractatus Logico-Philosophicus

            \(propositions)
            """ + "\n"
        }
    }

    private static func manifestYAML(
        inlineGermanDigest: String,
        inlineEnglishDigest: String
    ) throws -> String {
        let url = repositoryRoot.appendingPathComponent("docs/tractatus/sources.yaml")
        let source = try String(contentsOf: url, encoding: .utf8)
        return source
            .replacingOccurrences(
                of: "8a78131bf93068f259cdb88996a29348a3cc92f01b50c8f4cbd8c03bbb5dc29f",
                with: inlineGermanDigest
            )
            .replacingOccurrences(
                of: "599a943e6c36ebe6be28f8d06bd78f9bd52b2c961ebcfc86254f53175aeea0d4",
                with: inlineEnglishDigest
            )
            .replacingOccurrences(
                of: "source-snapshots/de-wittgenstein-project.md",
                with: "source-snapshots/de.md"
            )
            .replacingOccurrences(
                of: "source-snapshots/en-ogden-ramsey-1922-wittgenstein-project.md",
                with: "source-snapshots/en.md"
            )
    }

    private static func volumeYAML(volume: String, ids: [String]) throws -> String {
        let records = try ids.map(recordYAML).joined(separator: "\n")
        return """
        schema_version: 1
        volume: "\(volume)"
        propositions:
        \(records)
        """ + "\n"
    }

    private static func recordYAML(id: String) throws -> String {
        let propositionID = try PropositionID(validating: id)
        let parentLine = propositionID.inferredParent.map {
            "\n    parent: \"\($0.rawValue)\""
        } ?? ""
        let label: String
        if id == "1" {
            label = "一"
        } else if id.hasPrefix("preface.") {
            label = "序言 \(id)"
        } else {
            label = "命題 \(id)"
        }
        let externalReference = id.hasPrefix("preface.")
            ? "Preface paragraph \(id.dropFirst("preface.".count))"
            : id
        return """
          - id: "\(id)"\(parentLine)
            texts:
              de: ["Deutscher Text \(id)."]
              en_ogden_ramsey_1922: ["English text \(id)."]
            edition_references:
              en_pears_mcguinness: "\(externalReference)"
            segments:
              - id: "\(id).a"
                alignment:
                  de: [0]
                  en_ogden_ramsey_1922: [0]
                translation_zh_tw: "\(label)的工作譯文。"
                interpretation_zh_tw: "\(label)的哲學解讀。"
            project_relations:
              - status: not_applicable
                claim_zh_tw: "fixture 不聲稱命題 \(id) 已有專案對應。"
                rationale_zh_tw: "命題 \(id) 是獨立 fixture；硬套工程類比會誤導。"
            history: []
        """
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

}
