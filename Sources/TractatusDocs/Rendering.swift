import Foundation

public enum TractatusMarkdownRenderer {
    private static let germanID = "de"
    private static let ogdenID = "en_ogden_ramsey_1922"
    private static let pearsID = "en_pears_mcguinness"

    public static func render(
        manifest: SourceManifest,
        volumes: [CorpusVolume]
    ) -> String {
        var lines: [String] = [
            "<!-- GENERATED FILE — 請編輯 docs/tractatus/corpus/*.yaml，不要直接修改本檔。 -->",
            "# 《邏輯哲學論》× Akashic-Library 逐條對照",
            "",
            "> 欄位順序固定為：德文原文、Ogden／Ramsey 1922、Pears／McGuinness 版本參照、臺灣正體中文工作譯文。",
            "",
            "## 正典 metadata",
            "",
            "- 獻詞：\(escape(manifest.scope.dedication))",
            "- 題辭：\(escape(manifest.scope.motto.text))（\(escape(manifest.scope.motto.attribution))）",
            "",
            "## 來源版本",
            "",
        ]

        let editions = Dictionary(
            manifest.editions.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for editionID in [germanID, ogdenID, pearsID] {
            guard let edition = editions[editionID] else { continue }
            lines.append(
                "- <code>\(escape(edition.id))</code>（\(escape(edition.role.rawValue))／"
                    + "\(escape(edition.inclusionMode.rawValue))）：\(escape(edition.bibliography)) — "
                    + "<a href=\"\(escape(edition.sourceURL))\">來源</a>"
            )
        }

        let orderedVolumes = volumes.sorted { volumeOrder($0.volume) < volumeOrder($1.volume) }
        for volume in orderedVolumes {
            lines += ["", volumeHeading(volume.volume), "", "<table>"]
            appendTableHeader(to: &lines)
            lines.append("<tbody>")
            for proposition in volume.propositions {
                appendProposition(
                    proposition,
                    externalEdition: editions[pearsID],
                    to: &lines
                )
            }
            lines += ["</tbody>", "</table>"]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func appendTableHeader(to lines: inout [String]) {
        lines += [
            "<thead>",
            "<tr>",
            "<th scope=\"col\">德文原文</th>",
            "<th scope=\"col\">Ogden／Ramsey 1922</th>",
            "<th scope=\"col\">Pears／McGuinness</th>",
            "<th scope=\"col\">臺灣正體中文</th>",
            "</tr>",
            "</thead>",
        ]
    }

    private static func appendProposition(
        _ proposition: PropositionRecord,
        externalEdition: SourceEdition?,
        to lines: inout [String]
    ) {
        let propositionAnchor = anchor(proposition.id.rawValue)
        let synthesis = proposition.synthesisZhTW.map {
            " — \(escape($0))"
        } ?? ""
        lines += [
            "<tr id=\"proposition-\(propositionAnchor)\">",
            "<td colspan=\"4\"><strong>\(escape(proposition.id.rawValue))</strong>\(synthesis)</td>",
            "</tr>",
        ]

        for segment in proposition.segments {
            let german = alignedText(
                proposition: proposition,
                segment: segment,
                editionID: germanID
            )
            let ogden = alignedText(
                proposition: proposition,
                segment: segment,
                editionID: ogdenID
            )
            lines += [
                "<tr id=\"segment-\(anchor(segment.id.rawValue))\">",
                "<td lang=\"de\">\(german)</td>",
                "<td lang=\"en\">\(ogden)</td>",
                "<td lang=\"en\">\(externalReferenceCell(proposition, edition: externalEdition))</td>",
                "<td lang=\"zh-Hant\">\(multilineEscape(segment.translationZhTW))"
                    + "<br><small><strong>哲學解讀：</strong> "
                    + "\(multilineEscape(segment.interpretationZhTW))</small></td>",
                "</tr>",
            ]
        }
        appendProjectRelations(proposition, to: &lines)
    }

    private static func appendProjectRelations(
        _ proposition: PropositionRecord,
        to lines: inout [String]
    ) {
        lines += [
            "<tr class=\"project-relations\">",
            "<td colspan=\"4\">",
            "<strong>Akashic 專案關係</strong>",
            "<ul>",
        ]
        for relation in proposition.projectRelations {
            let mode = relation.mode.map { " / <code>\(escape($0.rawValue))</code>" } ?? ""
            lines.append(
                "<li><code>\(escape(relation.status.rawValue))</code>\(mode) — "
                    + "\(multilineEscape(relation.claimZhTW))<br><small>理由："
                    + "\(multilineEscape(relation.rationaleZhTW))</small>"
            )
            if !relation.evidence.isEmpty {
                lines.append("<ul>")
                for evidence in relation.evidence {
                    let note = evidence.noteZhTW.map { "— \(multilineEscape($0))" } ?? ""
                    lines.append(
                        "<li><code>\(escape(evidence.path))</code>（\(escape(evidence.kind.rawValue))："
                            + "<code>\(escape(evidence.locator))</code>）\(note)</li>"
                    )
                }
                lines.append("</ul>")
            }
            lines.append("</li>")
        }
        lines.append("</ul>")

        if !proposition.history.isEmpty {
            lines += ["<strong>歷史脈絡</strong>", "<ul>"]
            for history in proposition.history {
                lines.append(
                    "<li><code>\(escape(history.kind.rawValue))</code> "
                        + "<code>\(escape(history.reference))</code> — "
                        + "<code>\(escape(history.disposition.rawValue))</code>："
                        + "\(multilineEscape(history.noteZhTW))</li>"
                )
            }
            lines.append("</ul>")
        }
        lines += ["</td>", "</tr>"]
    }

    private static func alignedText(
        proposition: PropositionRecord,
        segment: AlignedSegment,
        editionID: String
    ) -> String {
        guard let units = proposition.texts[editionID],
              let indexes = segment.alignment[editionID] else { return "" }
        return indexes.compactMap { index in
            units.indices.contains(index) ? multilineEscape(units[index]) : nil
        }.joined(separator: "<br>")
    }

    private static func externalReferenceCell(
        _ proposition: PropositionRecord,
        edition: SourceEdition?
    ) -> String {
        guard let edition else { return "<em>外部版本參照未設定。</em>" }
        let reference = proposition.editionReferences[edition.id] ?? proposition.id.rawValue
        return "<em>外部版本參照：</em> \(escape(edition.bibliography))；命題 "
            + "<code>\(escape(reference))</code>；"
            + "<a href=\"\(escape(edition.sourceURL))\">來源</a>"
    }

    private static func volumeHeading(_ volume: String) -> String {
        volume == "preface" ? "## 序言" : "## 命題 \(escape(volume))"
    }

    private static func volumeOrder(_ volume: String) -> Int {
        if volume == "preface" { return 0 }
        return Int(volume).map { $0 + 1 } ?? Int.max
    }

    private static func anchor(_ value: String) -> String {
        value.map { character in
            character.isASCII && (character.isLetter || character.isNumber)
                ? String(character)
                : "-"
        }.joined()
    }

    private static func multilineEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map(renderRichLine)
            .joined(separator: "<br>")
    }

    private static func renderRichLine(_ value: String) -> String {
        let references = MarkdownImageReferenceParser.references(in: value)
        guard !references.isEmpty else { return escape(value) }
        var rendered = ""
        var cursor = value.startIndex
        for reference in references {
            rendered += escape(String(value[cursor..<reference.range.lowerBound]))
            rendered += "<img src=\"../source-assets/\(escape(reference.path))\" "
                + "alt=\"\(escape(reference.alt))\">"
            cursor = reference.range.upperBound
        }
        rendered += escape(String(value[cursor...]))
        return rendered
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

enum CorpusRenderEngine {
    static func render(root: URL, output: URL, check: Bool) throws -> String {
        let validation = try CorpusValidationEngine.validate(root: root, allowIncomplete: false)
        let content = TractatusMarkdownRenderer.render(
            manifest: validation.corpus.manifest,
            volumes: validation.corpus.volumes
        )
        let expected = Data(content.utf8)
        let displayPath = relativeDisplayPath(output: output, root: root)

        if check {
            guard let actual = try? Data(contentsOf: output), actual == expected else {
                throw TractatusValidationFailure(diagnostics: [CorpusDiagnostic(
                    path: displayPath,
                    recordID: "generated",
                    code: "generated-drift",
                    message: "產生內容與版控檔不同；check 模式未寫入任何檔案。"
                )])
            }
            return "render-check: clean \(displayPath) \(validation.corpus.summary.countsText)"
        }

        do {
            try FileManager.default.createDirectory(
                at: output.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try expected.write(to: output, options: .atomic)
        } catch {
            throw TractatusValidationFailure(diagnostics: [CorpusDiagnostic(
                path: displayPath,
                recordID: "generated",
                code: "write-failed",
                message: "無法原子寫入產生文件。"
            )])
        }
        return "rendered: \(displayPath) \(validation.corpus.summary.countsText)"
    }

    private static func relativeDisplayPath(output: URL, root: URL) -> String {
        let canonicalRoot = root.standardizedFileURL.path
        let canonicalOutput = output.standardizedFileURL.path
        let prefix = canonicalRoot.hasSuffix("/") ? canonicalRoot : canonicalRoot + "/"
        if canonicalOutput.hasPrefix(prefix) {
            return String(canonicalOutput.dropFirst(prefix.count))
        }
        let components = output.standardizedFileURL.pathComponents
        if let docsIndex = components.indices.first(where: { index in
            index + 1 < components.count
                && components[index] == "docs"
                && components[index + 1] == "tractatus"
        }) {
            return components[docsIndex...].joined(separator: "/")
        }
        return output.lastPathComponent
    }
}
