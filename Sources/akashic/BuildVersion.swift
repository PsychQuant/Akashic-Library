/// 這個 binary 是從哪一個 commit 建置的（#775）。`akashic --version` 印它。
///
/// 這個受追蹤的檔只放佔位值 `unknown`。`scripts/stamp-version.sh` 在建置期間把它改寫成 `git describe` 的結果
/// （裸的 `<12 位 hash>[-dirty]`），建完一定還原，所以一般的 `swift build`、`swift test` 讀到的都是 `unknown`，
/// 不會失敗。這一行不得手改成其他值，也不得 commit 戳記過的版本——值只能由那支腳本在建置期間寫入。
///
/// 讀它的是 akashic-mcp plugin 的 SessionStart hook（`plugin/hooks/check-cli.sh`）：拿這個 commit 跟原始碼 checkout
/// 比，說出 CLI 落後幾個動到 package 原始碼的 commit；是 `unknown` 時改比檔案時間。
enum BuildVersion { static let value = "unknown" }
