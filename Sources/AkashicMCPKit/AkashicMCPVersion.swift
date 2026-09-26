/// `akashic-mcp` 的版號——握手時的 `serverInfo.version`（#632）。
///
/// 發布的版號以 `mcpb/manifest.json` 為準：`scripts/release-signed.sh` 要求 `VERSION` 與它相等，並在發布前核對本常數。
/// 改版時三者一起改；`MCPServerVersionTests` 比對本常數與 manifest，任一邊沒跟上就紅。先前寫死 `0.2.0`，#630 排查時
/// 新舊兩個 binary 握手都回報同一個值，分不出連上的是哪一版。
public enum AkashicMCPVersion {
    public static let current = "0.12.1"
}
