import Foundation
import AkashicCore

/// 本模組的具名失敗（#629）。payload 在**擲出端**逃脫一次（`displaySafeInvisible`），本型別只是載體
/// （`SanitizedErrorDescription`：頂層 sink 不再逃一次，`displaySafe` 不冪等）。
public enum SkillToolError: Error, LocalizedError, SanitizedErrorDescription {
    /// 輸入檔、外部工具或使用者參數造成的失敗。
    case failure(String)

    public var errorDescription: String? {
        switch self {
        case .failure(let message): return message   // display-safe-exempt: 擲出端已逃一次，本型別只是載體
        }
    }
}
