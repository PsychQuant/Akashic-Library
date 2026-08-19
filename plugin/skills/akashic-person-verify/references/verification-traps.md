# 查證的已知陷阱

四類實測踩過的失效模式。每一類都曾造成真實的誤判或漏判——不是理論風險。
（ORCID 自身的兩個陷阱——employment 不回填歷史、given-names 存暱稱——在
akashic-bootstrap 的 [person-sources.md](../../akashic-bootstrap/references/person-sources.md)，此處不複製。）

## 1. 名冊是快照，出版品是歷史

機構名冊（人員介紹頁）只反映**現在**：離職博後不入退休頁、約聘頁只列現職。
拿快照去歸戶歷史出版品，**結構上必漏**——爬得再勤也沒用。

實測：某作者 3 篇論文機構欄白紙黑字寫統計所，但名冊四頁（現職／約聘／助理／退休）
都沒有他——博後 2021-07 → 2024-12，離所後名冊上就不存在了。反向也有：某單一作者
論文全篇沒有機構字樣，卻因作者 2009–2014 曾任職而入清單（因人而入）。

**處置**：名冊只當「現況」證據；歷史問題交給著作軌跡（Europe PMC）與隸屬史（OpenAlex）。

## 2. 機構名的誤植真實存在於文獻——不可精確字串比對

正式名稱是 Institute of Statistical Science（單數），但出版商頁面實測印過
「Institute of Statistical Science**s**」（複數）——兩種寫法都真實存在於已發表文獻。
沒有一個「正確字串」可以比。

**處置**：機構欄比對用容錯（正規化＋編輯距離量級），命中後**回原文查證**；
不要因為字串不匹配就判「不是這個機構」。

## 3. Crossref 的機構欄是扁平陣列，順序不保證對齊作者

Crossref 的作者機構是出版社繳交的 metadata，扁平陣列、順序可能錯位。實測：統計所
隸屬被掛到第 4 作者（中央大學）名下，實際屬於第 3 作者——照單全收會**認錯人**
（把非所內當所內、把真所內漏掉）。

**處置**：機構歸屬有疑義時，開**出版商頁**（DOI 落地頁）看逐作者綁定；同團隊
姊妹作的出版商頁也可佐證。Crossref 只當線索，不當判準。

另一族 Crossref 陷阱（「像但不是」的記錄：preprint 相似度可比期刊版還高、期刊＋
年份＋type 合取才擋得住）在 akashic-bootstrap 的
[work-sources.md](../../akashic-bootstrap/references/work-sources.md)。

## 4. OpenAlex：機構過濾用 institution ID，不用名稱字串

名稱字串過濾會被改名歷史打敗。實測：統計所的 OpenAlex institution 實體是
`I4210141710`，而 1993 年前的舊所名是 **Institute of Statistics**（不是
Institute of Statistical Science）——只比新名會漏掉整個 1980s 的著作。

**處置**：先 `https://api.openalex.org/institutions?search=<名稱>` 解析出 institution
ID，再用 ID 過濾作者／著作；隸屬史看 `authors` 端點的 affiliations 時間軸。

## 兩個「看起來像互相印證、其實同源」的陷阱（2026-08-20 實測）

這兩個是同一個病的兩種形狀：**拿一份按名字做的消歧結果，去驗另一份按名字做的消歧結果。**
兩邊會一起錯，而輸出看起來像交叉驗證通過。

### ORCID 的著作清單多半是機器灌的

`works` 的每一筆有 `work-summary[].source.source-name.value`。實測兩位當事人：

```
陳君厚 0000-0003-0899-7477 → Scopus 64、Crossref 10、本人 0
程毅豪 0000-0003-4038-9439 → Scopus 71、本人 20、Crossref 14、MDPI 1
```

Scopus／Crossref 那些是廠商按名字聚合出來的。**只有 `source` 是本人姓名的條目算自報。**

**處置**：把 ORCID works 當證據前先看 `source`；要當**決定性**證據，只採本人那一批。
（`employment` 是另一回事——那個確實是自報，但只列現職、不回填歷史。）

### OpenAlex 的作者實體會把 CJK 縮寫名過度合併

實測：17 筆「C-H Chen」的作者位**全部**被 OpenAlex 掛上同一個 ORCID
（陳君厚）。改看**該作者位登記的機構**後，只有 2 筆真的在中研院，其餘 15 筆分屬慈濟、
長庚、馬偕、UC Davis、國衛院、UCSD、陸軍軍醫大學、北榮、北醫、高醫。

**分界很乾淨**：

| 欄位 | 來源 | 可信？ |
|---|---|---|
| `authorships[i].institutions`／`.raw_affiliation_strings` | **論文自己**登記的 affiliation | ✅ |
| `authorships[i].author.orcid`／`.id` | OpenAlex **自己的**作者消歧 | ❌ 對 CJK 縮寫名不可單獨採信 |

**處置**：有 DOI 時走
`https://api.openalex.org/works/doi:<DOI>` 取該作者位的機構。用索引取之前先驗位置沒錯位
——該位置的作者名，其「姓＋首字母」必須與 literal 相同。

## 通用紀律

- **每一源記 URL＋取得日期**——查證結論落 verdict 時，這些是 provenance 的素材
- **ORCID 覆蓋率實測約三分之一**（某批 42 位已知作者只有 15 位查得到）——
  「ORCID 查無此人」不是「此人不存在」的證據
- **Europe PMC 覆蓋偏生醫**（統計／數學／CS／環境期刊實測 0/4 收錄，見
  [work-sources.md](../../akashic-bootstrap/references/work-sources.md)）——
  第 1 源空手不是「此人無著作」的證據，直接推進 OpenAlex
- **請求節流**：對同一網域連發數十請求會觸發 403，且被擋看起來像「頁面不存在」
  （細節見 [person-sources.md](../../akashic-bootstrap/references/person-sources.md)
  的抓取禮儀段）
