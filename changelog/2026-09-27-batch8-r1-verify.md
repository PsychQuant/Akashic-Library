# 2026-09-27 #660／#661／#582 R1 驗證的處置

ensemble 六席全到（requirements、logic、security、regression、devil's advocate、Codex），共 32 則：0 HIGH、5 MEDIUM，其餘 LOW／INFO。

## MEDIUM

| 項 | 處置 |
|---|---|
| #661 改了 status 推導，`docs/store-format.md` §3 attested 第 2 條沒改（三席同指） | 第 2 條改寫：attested-only 段不算進行中，也不算已結束，status 是 `undetermined`；`died` 與 `status` 那一節補值域。DA 另指出舊條文本來就有兩種讀法——那是這次改寫的理由，不是反證 |
| #582 訊息說「位元組完全相同的工具面寫不出」 | 為假：`dropAuthors`／`splitAuthors` 直接 append，同一個移除做兩次就寫得出。措辭改成「同一個動作做了兩次，或手改、舊 binary」，App 說明與第 35 列同步 |
| #661 `attested: [""]` 讓兩張表又矛盾 | `valid_attested` 改成 JSON 陣列：`[""]` 是非空的一格，含 `;` 的觀測點也不再與兩個觀測點混在一起 |

## LOW

- #661 測試裡 `end + attested` 的 fixture 是 store 拒收的形狀（兩席同指）：換成可達的已結束段（有 end、ended-unknown）。
- #661 同檔兩處註解還寫舊判準 `end IS NULL`：改成三欄皆 NULL。
- #582 混合組只說「只差位元組」：一組裡兩種都有時兩件事都說；value 缺席時標點不再黏在一起。
- #582 計數單位（組，不是記錄）與 doctor 描述不一致（兩席）：描述改成「各族是該族的訊息則數」，並補一支測試（entry 上兩組 → 2）。
- #582 只差 Cf 字元、只差 rests-on 順序的兩筆不報：寫成誠實邊界（程式 doc、第 35 列、changelog）。
- #582 `mcp-cli-parity` 的 `validate` 列沒有上限的家族名單漏了本族（兩席）：補上，連同先前就漏的三族。
- #582 byteExactKey 站點列舉的「十處」找不到一種計法對得上：拿掉數字，改指 `ByteExactKeySiteInventoryTests`。
- #660 第 34 列說指向 organization 的邊有三條：實為五條，另兩條（divergence 候選、verdict value）早有檢查；照改。
- #660 程式註解與第 34 列說 researcher 表分得出懸空：對上級機構那一半為假；照改。

## 另開 follow-up

- #662：CSV 匯出不中和試算表公式與 bidi 字元（既有問題類別；`valid_attested` 改成 JSON 之後本欄不受影響）。
- #663：CLI／MCP／App 把只被觀測到的隸屬說成「曾隸屬」，與匯出的 `undetermined` 對不上。

## 不處置（INFO）

- #661 混合情形一律 `undetermined`，即使同機構的已結束段涵蓋所有觀測點：刻意的保守裁決，changelog 已寫明。
- #660 被 quarantine 的 organization 檔也會被報成「沒有對應的 organization 檔」：與 work 側（#579／#652）同形，不是回歸。
