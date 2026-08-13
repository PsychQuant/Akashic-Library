# 機構歸戶判定：Institute of Statistical Science, Academia Sinica

輸入：`iteration-3/fixtures/affiliations.json`（單篇論文，DOI `10.1000/demo.2025.1`，4 位作者的機構字串）

依 `akashic-bootstrap` skill 的紀律：本次僅做分析，不查外部來源、不寫入 store、不呼叫任何 `akashic_*` 指令。判定僅基於輸入檔本身逐字比對機構字串。另依 skill 的 organization 紀律（"organization 先停"），此處只做「這位作者是否應歸戶到 ISS」的判定，不建立/正規化機構實體。

## 逐位判定

### 1. Wu HJ — **是**（信心：高）

機構字串（唯一一筆）：
> Institute of Statistical Science, Academia Sinica, Taipei, Taiwan.

單一機構、逐字完整匹配「Institute of Statistical Science, Academia Sinica」，無任何修飾或附加子單位名稱。清楚、無歧義的 ISS 隸屬。

### 2. Chang ML — **待人工判定**（不要直接歸戶為 ISS，也不要直接排除）

兩筆機構字串：
> 1. Institute of Plant and Microbial Biology, Academia Sinica, Taipei, Taiwan. mlchang@gate.sinica.edu.tw.
> 2. Bioinformatics Program, Institute of Statistical Science, Taiwan International Graduate Program, Academia Sinica, Taipei, Taiwan.

這是本批唯一的陷阱案例，判定依據：

- 第一筆機構（含個人聯絡信箱，通常是作者實際掛名/通訊的主要單位）是**植物暨微生物學研究所**（Institute of Plant and Microbial Biology）——與統計所是完全不同領域、不同單位。
- 第二筆字串裡雖然逐字出現「Institute of Statistical Science」，但它不是獨立成句的機構名（對照 Wu HJ／Fischer K／Lee SY 三人的 ISS 字串都是「Institute of Statistical Science, Academia Sinica, Taipei, Taiwan」這種獨立、乾淨的形式）。這裡它被包在「Bioinformatics Program, Institute of Statistical Science, Taiwan International Graduate Program, Academia Sinica」這個複合字串裡——結構上讀起來像是在指**台灣國際研究生學程（TIGP）生物資訊學程**這個聯合學程，而該學程由中研院統計所（與其他所，如資訊所）共同籌組／掛牌，此處的「Institute of Statistical Science」比較像是「這個學程掛在哪個所底下」的行政歸屬標示，不必然代表 Chang ML 本人是統計所的研究人員或直接隸屬統計所的成員。
- 兩筆字串合起來更像是：本人主要研究單位／實際工作地點在植微所，同時是 TIGP 生資學程的學生，而該學程的行政掛牌單位之一是統計所。這與「本人直接隸屬統計所」是不同的事實，僅從字串本身無法分辨究竟是（a）以 ISS 為正式學籍/行政所屬的 TIGP 學生、實際在植微所做論文研究，或（b)「Institute of Statistical Science」單純是學程官方名稱的一部分、與本人隸屬無關。

依 skill 第 3 節的紀律（相似度高不等於是同一件事，需要多個獨立訊號合取；不確定就標為待人工判定，不要猜；且此類「像但不是」的字串陷阱與 work-sources.md 記錄的 Crossref 假命中案例是同一種風險），Chang ML **不應該**被直接當成清楚的 ISS 隸屬案例寫入 person 記錄，也不應該直接排除——建議標記待人工判定，需要人工核對（例如查 TIGP 官網學程學生名冊，或該論文出版商頁面/ORCID）才能確定是否要把 ISS 記進其 person 記錄的隸屬欄位。

### 3. Fischer K — **是**（信心：高，雙隸屬）

兩筆機構字串：
> 1. Department of Mathematics, ETH Zurich, Switzerland.
> 2. Institute of Statistical Science, Academia Sinica, Taipei, Taiwan.

第一筆是瑞士 ETH Zurich 數學系（國外機構），第二筆是獨立、逐字完整匹配的「Institute of Statistical Science, Academia Sinica」——與 Chang ML 的情形不同，這裡的 ISS 字串沒有被包在任何學程／子計畫名稱裡，是乾淨獨立的一筆。判定為 ISS 隸屬（雙隸屬之一，可能是訪問學者或合聘），信心與 Wu HJ 同等級。

### 4. Lee SY — **是**（信心：高，雙隸屬）

兩筆機構字串：
> 1. Institute of Statistical Science, Academia Sinica, Taipei, Taiwan.
> 2. Department of Public Health, National Taiwan University, Taipei, Taiwan.

第一筆逐字完整匹配「Institute of Statistical Science, Academia Sinica」，獨立成句、無修飾。第二筆是台大公衛系。判定為 ISS 隸屬（雙隸屬之一），信心與 Wu HJ 同等級。

## 小結表

| 作者 | 判定 | 信心 | 關鍵理由 |
|---|---|---|---|
| Wu HJ | 是 | 高 | 單一機構字串，逐字獨立完整匹配 ISS |
| Chang ML | 待人工判定 | 低（不確定） | ISS 字樣僅出現在 TIGP 生資學程複合字串內，主要機構為植微所，兩者是否等於本人隸屬 ISS 無法從字串本身判定 |
| Fischer K | 是 | 高 | 雙隸屬之一為獨立、乾淨匹配的 ISS 字串（另一為 ETH Zurich） |
| Lee SY | 是 | 高 | 雙隸屬之一為獨立、乾淨匹配的 ISS 字串（另一為 NTU 公衛系） |

## 備註（依 skill 紀律）

- 本報告未查任何外部來源（Crossref／Europe PMC／ORCID 等），純粹基於輸入 JSON 逐字判定，若要把「是」的三位正式寫入 person 記錄的隸屬欄位，建議依 skill 第 4 節先出乾跑報告供使用者過目再寫（因為判定屬於「挑出來的」，尤其 Chang ML 那種需要人工核對的情況）。
- 依 skill「organization 先停」的紀律，本報告只回答「這位作者是否該歸戶到 ISS」，不建立或正規化 ISS 這個機構實體本身。
