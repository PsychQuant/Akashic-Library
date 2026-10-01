import SwiftUI

/// 側欄的「已寫入，legacy 拷貝要清」Section（#708）：App 的寫入寫進 `entities/`、而搬移後的 legacy 拷貝沒刪掉時出現。
///
/// **非阻斷**：它不是 alert——動作本身已經算成功，使用者照常操作；列表一直留在側欄，直到他按「知道了」或刪掉那些 legacy 檔
/// （下一次 load 自己消失，`LegacyCopyNotice.stillPresent(under:)`）。放在側欄，與「外部變更已同步」同一個位置：App 既有的狀態提示
/// 都是 `AppState` 的一個屬性、由側欄的一個 Section 呈現，這裡沿用那個形狀，不另開一套橫幅機制。
///
/// 窄輸入：只收 `LegacyCopyNotice`（值型別），`AppState` 的其他變化不會讓本 view 失效（`swiftui-specialist`）。
/// 「知道了」經環境裡的 `AppState` 呼叫——只在按鈕動作裡用，body 不讀它的任何屬性，不建立依賴。
struct LegacyCopyNoticeSection: View {
    @Environment(AppState.self) private var state
    let notice: LegacyCopyNotice

    var body: some View {
        Section {
            // 這件事是什麼的一句說明與 CLI／MCP 同一份（`LegacyCopyLeft.explanation`），但標題是一般說明文字、不帶 JSON 鍵名（#708 R1 verify）
            Text(notice.headline)   // display-safe-exempt: notice.headline 是常量字面加筆數（Int）
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(notice.rows) { row in
                LegacyCopyNoticeRow(row: row)
            }
            Button("知道了") { state.dismissLegacyCopyNotice() }
                .font(.caption)
                .buttonStyle(.borderless)
        } header: {
            Label("已寫入，legacy 拷貝要清（\(notice.rows.count)）", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}

/// 一列：哪一筆記錄、要刪的 legacy 檔的**完整路徑**（可選取複製）。完整說明（與 CLI／MCP 同一句）放在 `.help`。
struct LegacyCopyNoticeRow: View {
    let row: LegacyCopyNotice.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.displayRecord)
                .font(.caption.weight(.medium))
            Text(row.displayLegacyPath)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
        .help(row.displayDetail)
    }
}
