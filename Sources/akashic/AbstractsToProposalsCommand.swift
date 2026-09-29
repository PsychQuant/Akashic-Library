import ArgumentParser
import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicSkillTools

/// 階段 B 的摘要存檔（NDJSON）→ `akashic enrich --from` 的 `[Proposal]`（#516；#629 由
/// `akashic-venue-works/scripts/ndjson-abstracts-to-proposals.py` 移植）。
///
/// 只是一個 adapter：輸入是 `akashic-venue-works` 階段 B 的私有產物，輸出是 core 的公開格式；**不寫 store、不連網**。
/// 接著：`akashic enrich --library <root> --from proposals.json --json`（乾跑，先看 counts），數字對了才加 `--apply`。
/// 轉換的三條紀律與 `--out` 的寫入語意見 `AbstractProposals`。
struct AbstractsToProposalsCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "abstracts-to-proposals",
        abstract: "階段 B 的摘要存檔（NDJSON）轉成 enrich 的提案 JSON（adapter，不寫 store）；逐列具名回報略過的列")

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, help: "sha256:<hex>（在 <store>/sources/ 解析並驗雜湊）或 NDJSON 檔路徑")
    var source: String

    @Option(name: .long, help: "寫入的 JSON 檔（省略則印到 stdout）；拒絕寫到非普通檔，原子替換，並把解析後的絕對路徑印到 stderr")
    var out: String?

    func run() throws {
        let resolved: (data: Data, digest: String)
        do {
            resolved = try AbstractProposals.resolveSource(source) { digest in
                // 路徑形不需要 store；只有 digest 形才解析 store（--library → $AKASHIC_LIBRARY → registry，與其他命令同一條）
                guard let root = try? options.resolved().root else { return nil }
                return LibraryStore(root: root).sourceBlobURL(digest: digest)
            }
        } catch {
            throw RuntimeFailure.state(displaySafeErrorText(error))
        }
        let conversion: AbstractProposals.Conversion
        do { conversion = try AbstractProposals.convert(resolved.data, digest: resolved.digest) } catch {
            throw RuntimeFailure.state(displaySafeErrorText(error))
        }
        let stderr = FileHandle.standardError
        for line in AbstractProposals.reportLines(conversion) { stderr.write(Data((line + "\n").utf8)) }   // display-safe-exempt: line：skip 行的每個欄位已過 displaySafeInvisible，總結行是計數與已消毒的理由標籤
        let text = AbstractProposals.render(conversion.proposals)
        if let out {
            do {
                try AbstractProposals.writeOut(path: out, text: text) { stderr.write(Data(($0 + "\n").utf8)) }
            } catch {
                throw RuntimeFailure.state(displaySafeErrorText(error))
            }
        } else {
            FileHandle.standardOutput.write(Data(text.utf8))   // display-safe-exempt: text：提案 JSON 是給 enrich 讀的機器格式，摘要是要原樣進 store 的第三方內容（lossless-intake）——消毒會改寫它
        }
    }
}
