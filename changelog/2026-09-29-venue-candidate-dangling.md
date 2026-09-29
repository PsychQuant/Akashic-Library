# 2026-09-29 — 歧異記錄的 venue 候選不再被報成懸空（#699）

## 問題

`crossRecordIssues` 檢查歧異記錄的候選有沒有對應的記錄時，查找表只有 person、work、organization、divergence 四種。#553 起 venue 是合法的候選形狀，所以任何含 venue 候選的歧異記錄，`validate`／`doctor` 都報「沒有對應的記錄」，並說 `resolve-divergence` 會擲找不到對應記錄；同一個 store 上 `resolve-divergence --dry-run` 其實成功。batch14 R1 verify 的 devil's advocate 席在走 #565 合併流程時以真 binary 重現。

## 修正

- 查找表補上 venue。
- 查找表改成對 `EntityKind` 的窮舉 `switch`：原本是字典字面值，漏一格編譯器看不出來；現在新增一種形狀時，這裡編不過。

## 測試

`DivergenceHardeningTests.testVenueCandidatesAreNotReportedAsDangling`：兩筆 venue 都在的歧異記錄不報，指到不存在的 venue 仍報。修正前紅（三則誤報），修正後綠。
