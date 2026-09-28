# 2026-09-28 un-split 刪拆分記錄之前，確認 git 裡真的有副本（#659）

`resolve-people --un-split` 還原之後會刪掉那筆拆分記錄（原 literal、拆法、理由），理由寫的是「歷史留在 git」。但這條路徑沒有任何 git 前置：store 不在 git 工作樹、或那個 work 檔還沒 commit 時，被刪的記錄沒有任何副本。#573 對 `repoint`／`demote` 修過同一個形狀。

## 改了什麼

刪記錄之前走 `assertRecordsRecoverable`（tracked、clean、HEAD 可解析、無 index 位元）：不過就整批拒絕、零寫入，訊息指向 #659。兩面同一條 service 路徑；CLI help 與 MCP 描述同步說明。

## 裁決

issue 列了兩個選項：比照 #573 要求已 commit，或改成留一筆「已還原」記錄（要動第 15 條邊的值域）。使用者 2026-09-27 對移除面一族的裁決是「要求已 commit、不改 store format」，套在這裡就是第一個選項。使用者可翻。

## 測試

`UnSplitAuthorTests` 新增 1 支（不在 git、未提交兩種都拒絕且零寫入）；三支成功路徑的測試改成先 commit store——它們在加上這道閘之後轉紅，這本身就是負控。
