import Foundation
import XCTest

final class TractatusValidationCLITests: XCTestCase {
    func testStrictValidationPrintsDeterministicCorpusCounts() throws {
        let root = try TractatusDiskFixture.make()
        defer { TractatusDiskFixture.remove(root) }

        let result = try runCLI(["validate", "--root", root.path])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("propositions=534"), result.output)
        XCTAssertTrue(result.output.contains("source_units=1068"), result.output)
        XCTAssertTrue(result.output.contains("segments=534"), result.output)
        XCTAssertTrue(result.output.contains("project_relations=534"), result.output)
    }

    func testValidationErrorsAreSortedStableAndDoNotLeakAbsoluteRoot() throws {
        let root = try TractatusDiskFixture.make()
        defer { TractatusDiskFixture.remove(root) }
        let volumeURL = root.appendingPathComponent("corpus/1.yaml")
        var yaml = try String(contentsOf: volumeURL, encoding: .utf8)
        yaml = yaml
            .replacingOccurrences(of: "translation_zh_tw: \"一的工作譯文。\"", with: "translation_zh_tw: \"<unfinished>\"")
            .replacingOccurrences(of: "interpretation_zh_tw: \"一的哲學解讀。\"", with: "interpretation_zh_tw: \"\"")
        try yaml.write(to: volumeURL, atomically: true, encoding: .utf8)

        let first = try runCLI(["validate", "--root", root.path])
        let second = try runCLI(["validate", "--root", root.path])

        XCTAssertNotEqual(first.status, 0)
        XCTAssertEqual(first.status, second.status)
        XCTAssertEqual(first.output, second.output)
        XCTAssertFalse(first.output.contains(root.path), first.output)
        XCTAssertFalse(first.output.contains("incomplete:"), first.output)
        let interpretation = try XCTUnwrap(first.output.range(of: "missing-interpretation"))
        let translation = try XCTUnwrap(first.output.range(of: "missing-translation"))
        XCTAssertLessThan(interpretation.lowerBound, translation.lowerBound)
        XCTAssertTrue(first.output.contains("corpus/1.yaml:1.a:missing-interpretation:"), first.output)
    }

    func testAllowIncompleteListsMissingVolumeAndPropositionWithoutHidingOtherErrors() throws {
        let root = try TractatusDiskFixture.make()
        defer { TractatusDiskFixture.remove(root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("corpus/7.yaml"))

        let result = try runCLI(["validate", "--root", root.path, "--allow-incomplete"])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("missing-volume corpus/7.yaml"), result.output)
        XCTAssertTrue(result.output.contains("missing-proposition 7"), result.output)

        let volumeURL = root.appendingPathComponent("corpus/1.yaml")
        var yaml = try String(contentsOf: volumeURL, encoding: .utf8)
        yaml = yaml.replacingOccurrences(
            of: "translation_zh_tw: \"一的工作譯文。\"",
            with: "translation_zh_tw: \"<unfinished>\""
        )
        try yaml.write(to: volumeURL, atomically: true, encoding: .utf8)
        let invalid = try runCLI(["validate", "--root", root.path, "--allow-incomplete"])
        XCTAssertNotEqual(invalid.status, 0)
        let missingProposition = try XCTUnwrap(
            invalid.output.range(of: "incomplete: missing-proposition 7")
        )
        let missingVolume = try XCTUnwrap(
            invalid.output.range(of: "incomplete: missing-volume corpus/7.yaml")
        )
        let translation = try XCTUnwrap(invalid.output.range(of: "missing-translation"))
        XCTAssertLessThan(missingProposition.lowerBound, missingVolume.lowerBound)
        XCTAssertLessThan(missingVolume.lowerBound, translation.lowerBound)
    }

    func testRenderCommandWritesAndChecksTheGeneratedDocument() throws {
        let root = try TractatusDiskFixture.make()
        defer { TractatusDiskFixture.remove(root) }
        let output = root.appendingPathComponent("generated/map.md")

        let render = try runCLI([
            "render", "--root", root.path, "--output", output.path,
        ])
        let check = try runCLI([
            "render", "--root", root.path, "--output", output.path, "--check",
        ])

        XCTAssertEqual(render.status, 0, render.output)
        XCTAssertEqual(check.status, 0, check.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }

    func testValidationRejectsVolumesWhoseFileNamesWereSwapped() throws {
        let root = try TractatusDiskFixture.make()
        defer { TractatusDiskFixture.remove(root) }
        let oneURL = root.appendingPathComponent("corpus/1.yaml")
        let twoURL = root.appendingPathComponent("corpus/2.yaml")
        let one = try Data(contentsOf: oneURL)
        let two = try Data(contentsOf: twoURL)
        try two.write(to: oneURL, options: .atomic)
        try one.write(to: twoURL, options: .atomic)

        let result = try runCLI(["validate", "--root", root.path])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains(
            "corpus/1.yaml:2:volume-file-mismatch: YAML volume 必須與檔名 1.yaml 一致。"
        ), result.output)
        XCTAssertTrue(result.output.contains(
            "corpus/2.yaml:1:volume-file-mismatch: YAML volume 必須與檔名 2.yaml 一致。"
        ), result.output)
    }

    private func runCLI(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = productsDirectory.appendingPathComponent("tractatus-doc")
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("找不到 products directory")
    }

}
