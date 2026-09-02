# verdict holder 遷移網格補齊最後四格（#463）

`VerdictPairingValue` 的遷移是一張 4 退役操作 × 3 記錄形狀的網格。#232（rename×person）、#271
（work-merge×person）、#395（person-rename×person／org）、#460（rename／work-merge×venue）填了八格，
剩四格在本次補齊：

| 退役操作 | organization 記錄 | person 記錄 |
|---|---|---|
| `renameEntry` | ✅ 本次（鏡射 venue 迴圈；寫入前置條件鏡射 `writeOrganization`） | — |
| `resolveWorkDivergence` | ✅ 本次（複用 #461 的 helper） | — |
| `resolvePersonDivergence` | ✅ 本次（`person:` holder） | ✅ 本次（`person:` holder） |

- **helper 泛化**：`migrateHolderVerdicts(_:merged:survivor:holderKind:)`；`migrateWorkHolderVerdicts` 成為
  它的 `.work` 特例（#461 的測試不動）。
- **為什麼漏了三次**：organization 是 #443／OrgResolver 之後才開始持有 `work:` verdict；每次補迴圈時
  它都「還不存在」或「不在列舉裡」。live store 實測 9 條 org 持有的 `work:` verdict，任一 holder 被
  rename 或 merge 就重演 #460（#464 verify 的 DA 在副本上 rename 兩次得 4 條死 verdict）。
- **person-merge 的兩格**：#271 搬的是 doomed 自己的 references，不是**指向** doomed 的 `person:` holder
  （住在 organization 記錄上的 org-resolution 判定）；#395 rename 側已遷，merge 側零遷移——#232→#271
  的不對稱在 person-key 軸重演。
- **測試**：`VerdictHolderGridTests` 每格一支＋helper 的 kind 篩選＋live 形狀（多個 org 指向同一 citekey）。
- **偵測器**：#464 的死 verdict 掃描是這張網格的守衛——四格補齊後它對這些路徑應恆為 0。
