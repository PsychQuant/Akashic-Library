# 乾跑先抓到我自己的 bug——`migrate-identifiers`（#394 §8）

2026-08-24 深夜。識別碼自 `Entry.fields` 升格為結構化欄位、work 的 `issn` 移位到它的
venue。形狀比照 `migrate-venues`：預設乾跑、`--apply` 才寫、只改 git 追蹤中的檔、
**不自動 bump format**。

## 這一節最重要的事：乾跑抓到的不是資料的問題，是我的

第一版的 `candidates()` 對**所有種類**一律剝括號。理由看起來很正當——實測 25 筆 ISSN
寫成 `1860-0980 (Electronic) 0033-3123 (Linking)`，那些括號是人給的註記，留著會讓值
解析失敗、整筆被略過。

但 **DOI 的後綴合法含括號**。Elsevier／Wiley 大量使用：

```
10.1016/S0304-4076(98)00255-9
10.1002/1097-0258(20001115)19:21<3020::AID-SIM596>3.0.CO;2-A
```

實測真實 store **52 筆**。第一版把它們切成兩半，於是乾跑報告的「解析不了」清單裡出現

```
chen1999incomplete [doi] 「00255-9」
chengderfuh1992bootstrapping [doi] 「90012-h」
chenhsinchen2000research [doi] 「19:21<3020::aid-sim596>3.0.co;2-a」
```

**而這些看起來像是資料本身有問題。**

沒有先乾跑就 `--apply` 的話，那 52 筆的 DOI 會被留在 `fields` 裡並標記為壞資料，
而且**不會有任何東西報錯**——因為「略過並具名」正是設計好的行為。

> **一個正確的機制忠實地執行了一個錯誤的判準。**

修法：是否剝括號**按種類決定**（ISSN／ISBN 剝，DOI 不剝）。修好前後：

| | work | 識別碼 |
|---|---|---|
| 修好前 | 645 | 771 |
| 修好後 | **692** | **822** |

差 51，與量到的 52 筆差 1——`yeager2020what` 依多值裁決不吸收。數字對得起來。

## 乾跑報告：39 個 venue 落點，與 spec 預期一致

- **21 個 venue 合併為單值**，含異寫法收斂：`0033-295x` → `0033-295X`、
  `00031305` → `0003-1305`（無連字號補回）
- **18 個 venue 保留多值**，全是 print／electronic 兩個真的號。
  `american-psychologist: 0003-066X、1935-990X` 的來源是**兩篇 work 各給一半**，
  合併後正好兩個——這是「先正規化再去重」在跨記錄尺度上的效果
- **provenance 改寫 0 筆**，且報告把「零實例是預期的」的理由印出來，
  而不是靜默地什麼都不說

`journal-of-the-royal-statistical-society-7` 與 `-8` 各拿到自己的 ISSN——它們是 Series B
與 C，是兩個不同的 serial。這說明「ISSN 該住在 venue 而不是 work」在實務上是對的：
掛在 work 上時這個結構完全看不出來。

## 略過清單縮到 7 項，每一項都是真的資料問題

| citekey | 欄位 | 值 | 是什麼 |
|---|---|---|---|
| `bollen1989structural` | isbn | `0271-6356` | **ISSN 躺在 isbn 欄位**（Wiley 叢書號）|
| `genz2009computation` | isbn | `0930-0325`、`;` | 同上 ＋ 一個分號 |
| `dweck1975role` / `hong1999implicit` | doi | `DOI` / `Doi` | 前綴雜訊，**真的 DOI 已救回** |
| `yeager2020what` | doi | `(Supplemental)` ＋ 整欄位 | 附錄 DOI，依裁決不吸收 |

原值**都留在 `fields`**，遷移只是不動它們。

## 三支守衛在全套跑時擋下遺漏

1. **未消毒的輸出路徑 3 條**——`citekey`／`reason` 直接送進使用者可見輸出
2. **破壞性命令封閉列舉**——`migrate-identifiers` 有 `--apply` 卻不在 `destructiveCommands`
3. **parity 表**——新 CLI subcommand 沒有 MCP 面裁決（那本來是 task 9.1，守衛把它提前逼出來）

第 3 支紅了之後另外兩支跟著紅（「有守衛在注入前就已經紅，控制組會平白通過」），
修好源頭三支一起恢復。

## 順帶修一個既有的文件漂移

README 寫「**六個**會改寫或刪除記錄的命令」並列出六個，而原始碼**已經是九個**
（`bootstrap-venues`／`enrich-from-zotero` 加入時沒同步）。

依本 repo 的既有立場（`entity-backlink-completeness` 明寫「刻意不重複條數，因為數字
會與清單分岔」），**拿掉那個數字**而不是把它改成九，並註明唯一來源是
`DestructiveTargetGate.destructiveCommands`。

## 量測

| | |
|---|---|
| `swift test` | **2155 tests, 0 failures** |
| 守衛負控 | 53/53 |
| 乾跑對真實 store | **零寫入** |

## 還沒做

`--apply`（等使用者確認乾跑報告）、§9（兩面對等與收尾）、以及最後的手動
`format: 12 → 13`。
