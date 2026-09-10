# venue／org 的建檔面終於會問「庫裡是不是已經有了」——而缺口早就發生過（#548）

## 立案時的描述要修正一處

#548 說 `bootstrap-venues` 與 `-organizations`「**完全不做**與既有記錄的比對」。
不精確：兩者都有 `NameNormalization.matchingKey` 的**精確**比對（`known` 集合），
缺的是**寬鬆**那一層。

而真正的形狀比 issue 描述的更值得記：**`VenueResolver` 也只有那一層**（131 行、
單一 tier）。所以不是「bootstrap 漏了 resolver 有的檢查」——是**兩邊都沒有**。

## 缺口不是零實例，它已經發生過 5 組／11 筆

`matchingKey` 摺 NFKC、連字號家族、Cf、大小寫、空白——**不摺標點**。於是同一本刊
只差一個符號就成了兩筆記錄。實測 live store 的 406 筆 venue：

```
journal-of-the-royal-statistical-society     …Series B: Statistical Methodology
journal-of-the-royal-statistical-society-2   …Series B (Statistical Methodology)
journal-of-the-royal-statistical-society-3   …SERIES B-STATISTICAL METHODOLOGY

journal-of-the-royal-statistical-society-4   …Series C (Applied Statistics)
journal-of-the-royal-statistical-society-5   …Series C: Applied Statistics
journal-of-the-royal-statistical-society-8   …Series C (Applied Statistics)   ← 帶句點的 Society.

american-statistician        AMERICAN STATISTICIAN
the-american-statistician    The American Statistician          ← ISSN 在這一筆

american-journal-of-psychology      /  the-american-journal-of-psychology
british-journal-of-mathematical-and-statistical  /  …-mathematical-statistical-psychology（`&` vs `and`）
```

`-2`／`-3`／`-8` 這些後綴**是 `bootstrap-venues` 自己撞號時加的**——工具留下了它造成
重複的指紋。

## 判準是新的一套，而那是裁決不是省略

`LooseNameKey` 的兩個 tier 對刊名都不適用，各有理由：

| tier | 對人名 | 對刊名 |
|---|---|---|
| `reorderKey`（token 集合相等） | `Hsu, Yung-Fong` ↔ `Yung-Fong Hsu`——索引系統**真的會**重排人名 | **誤判來源**：刊名不會被重排，而 token 集合相等會把不同的刊當成同一本 |
| `initialsKeys`（姓＋首字母） | `Chen, Y.-H.` ↔ `Chen, Yi-Hau` | 刊名沒有姓 |

所以新增 `LooseTitleKey`（core，venue 與 org 共用）：`matchingKey` 之上再摺 `&`→`and`、
標點→空白，並剝掉**前導**冠詞。

**取窄的那一版。** 量過兩版——本版與「連 of／and／for／in／on 一起丟」的寬版，
**在真實資料上結果完全相同**（同樣 5 組重複、同樣 404 個鍵、候選側同樣命中 1 筆）。
寬版多丟的那些詞今天沒有換到任何東西，只擴大未來的誤判面。

## CLI 的印是被單獨守著的

`VenueBootstrap.Result` 與 `OrgBootstrap.Result` 各加一個 `pendingResolution` 桶，
撞到就不建檔；CLI 在**乾跑與 `--apply` 兩條路**都印。

新增的 `BootstrapVenuesPendingCLITests` 走真 binary。**負控證明它守的是 #547 那個
失效形狀**：只拿掉 CLI 的印（model 端的桶完好）——單元測試**維持 15/15 綠**，
CLI 測試 **3 紅**。那正是 #547 的 BLOCKING（model 端加了桶、單元測試全綠，而
`--apply` 從不呼叫印它的函式，253 組被靜默扣住）。

另一個負控：拿掉分流 → 17 條裡 11 紅。兩個都乾淨（build error 0）。

## 實測效果

`bootstrap-venues` 在 live store：候選 **78 → 77**，`pendingResolution` **1**
（`Guilford Press` ↔ 既有 `the-guilford-press`）。`bootstrap-organizations` 今天
0 候選、0 pending。

## 不加 zero-instance-guards 的列

那張表管的是「還沒發生過的形狀」。這個形狀**已經發生 5 組／11 筆**，所以不屬於它。

## 既有的 5 組重複沒有被這個 change 修掉

工具現在擋得住**新的**，但庫裡那 11 筆仍在。清理要走 `resolve-venues --repoint`
把邊改指到留下的那一筆，再處理空記錄——那是 venue 輪的工作，不是本 change 的。
