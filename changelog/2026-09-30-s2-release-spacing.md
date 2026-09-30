# 2026-09-30 S2 節流在鎖內保證兩次放行的間隔（#701）

`S2CommandTests.testTwoProcessesShareTheOneRequestPerSecondBudget` 偶發失敗：兩個程序共用每秒 1 次的額度，量到兩次請求間隔 0.92 秒（斷言 ≥ 0.95 秒）。

## 根因：限流真的會讓兩次請求靠得太近，不是量錯時刻

先量再改。在節流與 client 加暫時的計時輸出（沒有 commit），跑這支測試 30 次，每個請求記下預約的時段、醒來的時刻、放行的時刻、送出前的時刻，以及 stub 收到的時刻：

- 放行到 stub 收到只差 1–5 ms。測試量的是 stub 收到的時刻，這個時刻與節流放行的時刻幾乎相同，量測本身沒有問題。
- 預約的時段兩兩相差 1.05 秒，沒有例外。
- `Task.sleep` 晚醒的量隨睡眠長度變化：睡約 1.05 秒的晚醒 124–139 ms，睡約 0.5 秒的晚醒約 58 ms。
- 兩次放行的間隔＝1.05 秒＋後一個的晚醒－前一個的晚醒。30 次裡有 2 次前一個晚醒約 130 ms、後一個只晚醒約 58 ms，放行間隔 0.976 秒。全套測試時負載更重，晚醒的差距更大，就量到 0.92 秒。

預約只保證每一次放行不早於自己的時段，從來不保證兩次放行的間隔。spec 的 Scenario「every pair of send times SHALL be at least one second apart, within a 50 ms tolerance」因此在負載下不成立，是限流的問題（issue 列的情形 (b)），不是測試量錯。

## 改了什麼

- `S2FileThrottle.acquire` 醒來之後改呼叫 `release()`，在同一把鎖內決定：仍在 429 封鎖期就重新預約（原本的 `isBlocked()`，併進來後刪掉）；離上一次實際放行不到 1.05 秒就再等；否則放行，記下這一刻（狀態檔新增可省略的 `lastReleasedAt`），並把 `nextAllowedAt` 推到至少這一刻加 1.05。
- 小於 1 ms 的等待不睡（`releaseSlack`）：準時醒來的呼叫者會因浮點誤差差幾個 ulp。所以保證的放行間隔是 1.049 秒。
- `lastReleasedAt` 比現在晚超過 60 秒時視為過期，與 `nextAllowedAt`、`blockedUntil` 同一條規則。
- 測試的斷言不放寬，仍是 ≥ 0.95 秒。
- `openspec/changes/semantic-scholar-interface/design.md` 的〈跨程序節流〉補一條說明這一步。spec 的文字不必改：每一次請求仍不早於自己的時段送出，Scenario 的間隔現在才真的成立。

## 測試與負控

`S2ThrottleReleaseSpacingTests.swift` 加三支（假時鐘，不連網、不讀 keychain）：前一個晚醒 130 ms 時後一個要多等 130 ms、放行把 `nextAllowedAt` 從實際放行算起、過期的 `lastReleasedAt` 不擋人。先寫測試時編譯不過（`release()` 還不存在）。

負控（反向編輯、`cmp` 確認還原）：拿掉間隔比對 → 第一支紅（放行在 1.05 秒、只睡一次）；拿掉 `nextAllowedAt` 的推移 → 第二支紅；拿掉過期判斷 → 第三支紅（多睡 121 秒）；`releaseSlack` 改成 0 → 第一支在假時鐘上無限迴圈（剩下約 1e-7 秒的等待小於 `Date` 在 t0 附近的解析度，時鐘推不動），手動中止。最後這個是假時鐘的現象，真時鐘會前進，只會多睡一次極短的覺；它說明這個門檻不是裝飾。

跨程序測試連跑（`--filter S2CommandTests/testTwoProcessesShareTheOneRequestPerSecondBudget`，機器上同時有其他工作，load average 約 13–17）：

| | 次數 | 失敗 | 最小間隔 |
|---|---|---|---|
| 修之前 | 20 | 2 | 0.935、0.945 秒（失敗的兩次） |
| 修之前，加計時輸出 | 30 | 0 | stub 收到 0.974 秒、放行 0.976 秒 |
| 修之後 | 20 | 0 | 沒有輸出（通過時測試不印時間） |
| 修之後，加計時輸出 | 30 | 0 | stub 收到 1.047 秒、放行 1.050 秒；180 次放行裡 88 次多等了一次 |

## 誠實邊界

- 保證的是放行的間隔。放行到封包送出之間還有 client 的開銷（實測 0–5 ms），那一段不受節流控制，由 1.05 秒與 1 秒之間的 50 ms 餘裕吸收。
- 舊 binary 寫回狀態檔時會丟掉 `lastReleasedAt`（JSON 只寫它認得的欄位），新舊 binary 同時在跑的那段時間，間隔回到只由預約保證。
- 沒有改 `Task.sleep` 的容許誤差。縮小晚醒只能讓間隔少縮一點，負載重時仍然會縮，所以改在鎖內比對。
