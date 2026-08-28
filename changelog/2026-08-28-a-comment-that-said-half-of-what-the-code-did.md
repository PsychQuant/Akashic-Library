# 一行註解只說了它那行做的一半，而說對的那半讀起來完全合理

2026-08-28，#424 裁決 A。`IdentifierMigration.take` 的收尾：

```swift
// 全部 token 都解析失敗以外的情形：只要有任何一個 bad，就**不移除殘留**
// ——殘留是那些解不了的值唯一的棲身處。
return bad.isEmpty ? values : nil
```

註解說的是「**不移除殘留**」。實作做的是「**連結構化值都不寫**」。

前者保護解不了的那個 token，後者連可解的那個一起放棄。兩者在報告上長得一樣：那筆會
出現在 `skipped` 裡，理由寫「解析不了」——讀者合理地以為指的是整個值。

實測 4 筆因此卡住：

| citekey | `fields` 殘留 | 卡住的原因 |
|---|---|---|
| `dweck1975role` | `DOI 10.1037/h0077149` | `DOI` 是**標籤**不是值 |
| `hong1999implicit` | `Doi 10.1037//0022-3514.77.3.588` | 同上 |
| `bollen1989structural` | `0271-6356 0-471-01171-1` | 前者不是合法 ISBN |
| `genz2009computation` | `…9783642016899 (electronic) 0930-0325 ;` | `0930-0325` 與 `;` 解不了 |

四筆的可解值都完全合法。修掉之後 store 的 top-level DOI 從 **664 → 666**，ISBN 補兩筆。

## 我先走錯了一條路，而它會通過端到端測試

第一版的診斷是「`DOI ` 是標籤，剝掉它就變單值」。那個方案**會讓端到端測試變綠**——
但它讓 `DOI` 這個 token 從 `skipped` 報告裡消失，而
`testUnparseableTokensAreReportedWhileTheRealOneIsRecovered` 正是釘住它要出現。
`lossless-intake` 執行細節 3：丟棄必須可見。

那條既有測試把我擋了下來。**根因不在 tokenizer，在 `take` 把兩個決定綁在同一個 return。**

方案放棄了，但把它寫進保留下來的那個邊界測試的 doc 裡——免得下次重走。

## 診斷順序的教訓

我讀了三次原始碼推理「為什麼這筆沒被遷移」，三次都推錯：

1. 「需要 work 側的識別碼寫入面」——#394 的缺口是真的，但**不是這裡的原因**
2. 「`splitTokens` 把標籤當值」——現象對，處置錯
3. 「`values.count == 1` 的 guard 擋了」——那個 guard 根本沒觸發

**跑一次 `migrate-identifiers` 乾跑，答案在第一屏**：它逐筆列出略過的 token，
`dweck1975role [doi]「DOI」` 那一行說的是「只有這個 token 略過」，不是「整筆略過」。
先跑工具再讀原始碼，順序反過來會付三倍的時間。

## 邊界：一個都解不開時仍然什麼都不寫

`testWhenNothingParsesNothingIsWritten` 釘住這一半沒有順便被放寬。`yeager2020what`
也仍然 skipped——它的兩個 DOI 是**真的**兩個（母文＋附錄），吸收會是一句假的身分宣稱
（#424 裁決 B／C 未決）。
