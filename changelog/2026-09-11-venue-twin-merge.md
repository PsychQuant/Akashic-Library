# venue 終於有攣生合併的路，而擋住它的不是我第一次說的那個東西（#553）

## 三次憑讀碼下斷言，三次被實測推翻

這一輪最值得留下的不是程式，是**同一個錯誤犯了三次**的紀錄：

| # | 我說的 | 實測 |
|---|---|---|
| 1 | #548 issue body：「`Divergence.candidates` 的 `shape` 值域也不含 venue」 | **值域早就含**。`EntityKind` 從第一天就有 `.venue` |
| 2 | 「`EntityKind` 已經有 `.venue` 了，沒有值域擴充」 | 結論對、理由錯。真正擋住的是 `recordDivergence` 的 **`byShape` 輸入白名單**——跑一次 `record-divergence --candidate "american-statistician:venue"` 就知道 |
| 3 | 裁決留言列「`migrateHolderVerdicts` 加 `venue:` holder」為工作項 | **不存在這件事**。`VerdictHolderKind` 是 work／person／org，而實測 live store 8,670 條 verdict 全部是 `work:` 前綴 |

三次的共同形狀：**讀了碼、沒有跑**。`assertions-must-be-measured` 的第一個問題我沒問。

## 拒絕條件裡有一格是假的

`fieldsLostByMerging` 的錯誤訊息說「合併會讓它隨檔案消失」。對 `issn`／`type`／
`paginated`／`note` 為真，對 `authorized` **為假**——被併者的全部名字都進倖存者的
`names` 與 `variant`，字串不會消失，改變的是**分類**。

而那一格是照 person 側抄的。person 的論證（#81：「哪個名字對外」是判定，聯集會違反
「每書寫系統至多一個」）依賴一個 venue 不具備的前提：

```
venue 494 筆｜有 authorized 479｜多於一個 0
authorized == [names[0]]：479／479，零例外
```

全庫唯一的 `venue.authorized` 寫入者是 `VenueBootstrap` 的 `authorized: [c.names[0]]`
——建檔時取第一個名字。`updateVenue` 收 add_names／add_variant／add_issn／paginated，
**沒有 authorized**；`authorize-names` 只管 person。

所以那一格是拿 bootstrap 副產品當承重判定。它的代價是可量的：**7 組重複裡有 7 組被它
擋下**，工具對它的立案理由全面無用。這與 #471 記過的是同一個形狀（「一個不做判定的
操作成了唯一的判定寫入者」），只是這次由合併端重演。

**裁決：拿掉那一格，但降級要逐筆說。** 降級是單向的——venue 沒有改回 authorized 的
面，所以那句提醒要出現在 **dry-run**，而不只是實跑之後。

## 提醒與拒絕是同一條紀律

warnings 從 `validateVenuePreconditions` 產生，preview 與實跑共用同一個計算點。
這個檔案為相反的做法付過兩次代價（#139 F1：拒絕條件只在實跑算，dry-run 對最高頻的
`wouldLoseFields` 完全沉默）。負控釘住它：拿掉 preview 那一行 → 2 紅。

## 負控抓到測試套件的一個洞

四個 mutation 全部乾淨地紅（每個都有 `Executed` 摘要，不是建置失敗）。其中第三個
一開始**沒有紅**——`byShape` 改成 `.venue: []`，九條測試全綠。

原因是其餘測試用 `writeDivergence` 直接落檔，繞過了 `recordDivergence`。而 `byShape`
正是 #553 的另一半：記不下來的話，合併管線再完整也沒有記錄可餵。補了兩條（收得下
venue 候選、仍拒絕不存在的 key）之後它才紅。

**綠的測試在證明之前什麼都不是**——這一次它證明的是我漏測了一半。

## 落地

live store：venue **494 → 485**（7 組 16 筆合成 7 筆），寬鬆共鍵的重複群 **7 → 0**，
9 筆 verdict 隨合併遷移，11 筆 work 的 venue 邊改指倖存者，`validate` 全綠。

倖存者的選法逐組寫在 store 的 commit message 裡（`aa109e03`），判準是**名字以外的
證據**：ISSN 在哪一筆、type 是否一致、哪個 key 不會冒充母刊
（`journal-of-the-royal-statistical-society` 這個裸 key 不得被 Series B 佔用）。

## 還沒做的

- **JRSS-B 沒有 ISSN**（三筆都沒有）。那是查證工作，不在本 change。
- **`.organization` 仍是半吊子**：`byShape` 收得下、`resolveDivergence` 解不掉。
  本輪刻意不順手做——org 的合併要面對 `parents` 時間軸，那是另一組前置條件。
  錯誤訊息現在會說出真正的理由（「管線尚未實作」），不再假借「歧異記錄沒有 key」。
- **venue 沒有 authorize 寫入面**。本輪把它從「隱形」變成「每次降級都會說一句」，
  但沒有補那個面。
