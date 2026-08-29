# 收分隔符，不收拆好的名字

2026-08-29，#443。一個 literal 裝了兩個人時，在此之前**沒有任何面拆得開**。

## 4 筆，同一個形狀

```
鄭澈與雷庚玲 ／ 張泰銓與雷庚玲 ／ 蔡宜妙與雷庚玲 ／ 吳季珊與雷庚玲
```

同一個指導教授的四篇合著，匯入時整個作者欄被當成一個 literal。`resolve-people --apply`
只能把它整個升格成**一個** person——那會建出一個不存在的人。

## 介面的關鍵選擇

收「拆成哪兩個名字」的自由文字，等於讓呼叫端**編造**：打錯一個字就寫進 store，而沒有
任何東西擋得住。

收**分隔符**則讓拆出的每一段必然是**原文的子字串**：

```
citekey:authorIndex:分隔符=理由
```

零編造，且錯了看得出來——切出空段就拒絕（`「與雷庚玲」` 用 `與` 切會得到空的前段；
換行等空白段同拒）。段數有上界（32）：literal 是未信任輸入，高頻分隔符不得把一個作者位
炸成無界多個。同一個作者位一次只能拆一次（去重以解析後的 (citekey, index) 為鍵）。
分隔符不得含 `=`——第一個 `=` 之後一律是理由。

**三樣東西被丟棄，報告全部揭露**（R1 verify 修正——初版只揭露了分隔符）：分隔符、
**原始 literal**、**理由**。報告逐筆印出「原文、用什麼切、切成什麼、為什麼」
（`lossless-intake` 的丟棄必須可見）。**原文與理由不進 store**——拆分沒有「被判定的
另一方」可落 verdict，work 側 references 值域目前只收識別碼；un-split 所需資訊在
store 內不可回復（只在 store repo 的 git 歷史）。持久化需要值域的顯式裁決（follow-up）。

## 拆出來的仍是 `.literal`

拆是**形狀**修正，不是身分判定。拆完之後每一段各自走既有的消歧路徑——依
`literal-first-then-key`，進庫不猜、升格留 verdict。

**而那立刻兌現了**：拆開後 `鄭澈` 被 `resolve-people` 提名到 `che-cheng`（alias 完全
命中），套用後著作數 **55 → 56**。那正是 #303 記的「che-cheng 的著作不含掛在 literal
下的作品」。

其餘三筆的第一作者與雷庚玲都還沒有 person 記錄，維持 `.literal`——那是誠實狀態。

## index 位移由實作處理

同一筆 work 的多個位置一起拆時，**拆開會改變後續 index**。實作由**大到小**處理，於是
先做的那個不影響還沒做的那些；呼叫端給的是**原始**索引，不必自己算位移。

`testSplittingTwoSlotsOnTheSameWorkAccountsForIndexShift` 釘住這一點——它是
`attributeToOrganizations` 踩過的形狀（同一 citekey 多筆 plan）的更尖版本：那次是 crash，
這次會**靜默拆錯位置**。

## 十個測試，七個是負向的

> 初版此節標題寫「五個測試，四個是負向的」——**兩個數字都錯**（實測 3 個
> `XCTAssertThrowsError`，R1 verify DA 抓到）。R1 後補五個測試，現數如題。

| 測試 | 釘住什麼 |
|---|---|
| `BySeparator` | 那條路存在，且拆出的名字是原文的子字串 |
| `RejectsEmptySegment` | 切出空段 → 整批拒絕、零寫入 |
| `RejectsAbsentSeparator` | 分隔符不在該 literal 裡 → 拒絕，而不是靜默不拆 |
| `RefusesAResolvedSlot` | 只作用於 `.literal` |
| `AccountsForIndexShift` | 同一筆 work 多個位置 |
| `RejectsTheSameSlotGivenTwice` | 同 slot 配兩個分隔符 → 拒絕（R1 HIGH：字面去重繞過→陣列毀損）|
| `RejectsTheSameSlotSpelledDifferently` | `0` vs `+0` 同 slot → 拒絕（去重用解析後的值）|
| `RejectsNewlineOnlySegment` | 換行段不是名字 |
| `RejectsPathologicalOversplit` | 段數 > 32 → 拒絕 |
| `ReportCarriesOriginalAndJudgement` | 原文與理由進報告（store 不留的唯一揭露面）|
