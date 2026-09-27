# 2026-09-27 resolve-organizations 的逐篇判定（#647）

#643 讓 CLI 的篩選式 `--apply` 排除查過未決的候選。這個排除本身是對的：有人查過而判不出來的配對，不該被批次帶走。問題是 CLI 沒有逐 id 的歸戶，所以這些候選在 CLI 上**歸戶不了**，只能改走 MCP。

## 裁決（使用者 2026-09-27）

比照 resolve-people 的 `--judge`：理由必填，寫成逐篇判定。

## 改了什麼

兩面同時新增 judge 腿，走同一個函式 `judgeOrganizations`：CLI 是 `--judge`，MCP 是 `akashic_resolve_organizations` 的 `judge` 參數。

- **格式**：`<列表的 id>@<orgKey>=理由`。id 的解析與 #643 的未決腿共用（`parseOrgIDSpecs`，訊息的名詞參數化，未決腿的訊息逐字不變）。歧義條目也收：歧義的意思是提名器分不出來，不是人分不出來。
- **寫入**：把那一列歸戶到 orgKey，並寫一筆 confirmed verdict，rule 是 `org-judged`，理由進 statement。
- **判定層級**：`org-judged` 是 judged 層級封閉列舉的第三列，是顯式加入的。沒有沿用 `author-organization-judged`，因為這條腿的 holder 還有 person 的隸屬與 organization 的上級機構，不只作者位。
- **兩類失敗分開**（同 people 的 judge）：
  - 輸入錯整批拒絕、零寫入：格式、id 不在這次列表上、orgKey 不是那一列提名的、理由空白或超過 4,096 位元組、同一列判給兩個 org、person 與 organization 同 key 而兩列都在列表上。
  - store 狀態不符該筆略過並具名：work 的 citekey 重複或共用 id、上級機構判給自己或會成環、套用時那個位置已不是那個 literal。
- **成環檢查**：`OrgResolver.resolve` 對候選有 #166 的成環守衛，但歧義報告刻意不過濾會成環的候選，所以這條腿在寫入端檢查：既有的 `.key` parents 加上本次已接受的判定。
- **單獨呼叫**，不與 apply、reject、undecided 組合。CLI 也拒絕 `--holder`／`--org`，因為 id 已經點名了列與 org。CLI 另過 #298 的目標確認閘。
- 篩選式 `--apply` 的排除訊息改成指路 `--judge`。`mcp-cli-parity` 的 resolve_organizations 列、`docs/store-format.md` 的判定層級、`judgedRules` 的 doc 都已同步。

## 測試

`OrgJudgeLegTests` 五支：

- 候選列：歸戶、judged 層級、理由與 rule 尾註；
- 歧義條目；
- 查過未決的候選可以判；
- 上級機構成環略過、另一個照常落地；
- 輸入錯整批拒絕。

另有 `OrgUndecidedCLITests` 的真 binary 測試：排除訊息指路、`--judge` 歸戶、組合拒絕。`VerdictRecordKeyTests` 的封閉列舉計數從 2 改成 3。

負控四組，都紅：

1. 拿掉成環檢查；
2. rule 改回 nominated；
3. 空白理由的檢查只看空字串；
4. 同一列判兩次的檢查改用 id。
