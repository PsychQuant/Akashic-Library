import Foundation
import XCTest

final class TractatusInterfaceTests: XCTestCase {
    func testHelpExposesOnlyTheTwoDocumentOperations() throws {
        let result = try runCLI(["--help"])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("validate"), result.output)
        XCTAssertTrue(result.output.contains("render"), result.output)
    }

    func testSubcommandHelpExposesItsFileBoundary() throws {
        let validate = try runCLI(["validate", "--help"])
        let render = try runCLI(["render", "--help"])

        XCTAssertEqual(validate.status, 0, validate.output)
        XCTAssertTrue(validate.output.contains("--root"), validate.output)
        XCTAssertEqual(render.status, 0, render.output)
        XCTAssertTrue(render.output.contains("--root"), render.output)
        XCTAssertTrue(render.output.contains("--output"), render.output)
    }

    func testCIEnforcesStrictCorpusAndGeneratedOutputAfterSwiftTests() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/ci.yml"),
            encoding: .utf8
        )
        let testStep = try XCTUnwrap(workflow.range(of: "      - name: Test\n"))
        let validate = try XCTUnwrap(
            workflow.range(of: "swift run tractatus-doc validate --root docs/tractatus")
        )
        let renderOutput = try XCTUnwrap(
            workflow.range(of: "--output docs/tractatus/generated/tractatus-project-map.md")
        )
        let renderCheck = try XCTUnwrap(
            workflow.range(of: "--check", range: renderOutput.upperBound..<workflow.endIndex)
        )

        XCTAssertLessThan(testStep.lowerBound, validate.lowerBound)
        XCTAssertLessThan(validate.lowerBound, renderCheck.lowerBound)
        let corpusStep = workflow[validate.lowerBound..<renderCheck.upperBound]
        XCTAssertFalse(corpusStep.contains("--allow-incomplete"))
        XCTAssertFalse(corpusStep.contains("curl"))
        XCTAssertFalse(corpusStep.contains("wget"))
    }

    func testCICheckoutFetchesFullHistoryForStrictCorpusEvidence() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/ci.yml"),
            encoding: .utf8
        )
        let checkout = try XCTUnwrap(workflow.range(of: "      - uses: actions/checkout@v4\n"))
        let nextStep = try XCTUnwrap(
            workflow.range(of: "\n      - name:", range: checkout.upperBound..<workflow.endIndex)
        )
        let checkoutStep = workflow[checkout.lowerBound..<nextStep.lowerBound]

        XCTAssertTrue(
            checkoutStep.contains("          fetch-depth: 0"),
            "strict validator 需要完整 Git history 才能解析 corpus evidence 引用的舊 commit"
        )
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
