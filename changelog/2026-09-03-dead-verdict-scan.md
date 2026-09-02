# 2026-09-03 · 死 verdict 進 `StoreHealth`（#464）

resolution verdict 的 value 指向已不存在的 holder（`work:<citekey>`／`person:<key>`／`org:<key>`）
現在由 `LibraryStore.health(from:)` 掃出，以 warning 級的 `OwnedIssue` 併入 `perRecordIssues`
——CLI `validate`、MCP `akashic_doctor` 與 App 三面自動繼承（#416 的既有形狀）。

- **判準**是 set-difference：holder 不在對應 kind 的 key 集合即死。解析不了的 value 不在此列
  （寫入閘與各族 `validate()` 已管）。
- **warning 不是 error**：過期不是矛盾。升 error 會讓 `hasFindings` 在每次 rename 之後常態為真。
- **實測**（2026-09-03）：live store 2,700 條 verdict（`grep -h 'field: resolution-' ~/.akashic/entities/*.yaml | wc -l`），`akashic validate` 死引用 0。`zero-instance-guards.md` 加一列
  記錄裁決——這是該表第一個「形狀發生過三次、零是清理後的零」的情形。
- 掃描的 owner 三族：person／organization／venue（`Entry.references` 值域只有識別碼，沒有 verdict）。
