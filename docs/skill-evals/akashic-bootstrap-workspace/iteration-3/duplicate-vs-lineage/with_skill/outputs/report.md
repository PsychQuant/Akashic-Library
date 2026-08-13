# store_records.tsv 重複判定報告

範圍：`fixtures/store_records.tsv` 六筆 work 記錄。純分析，未呼叫任何 akashic 指令、未查外部來源、未寫入任何 store。判斷僅基於這份 TSV 本身六個欄位（citekey / type / title / journal / year / doi）之間的合取與反例檢核。

---

## 組一：`liang2019robust` / `liang2019brobust` — 重複，建議合併

| 欄位 | liang2019robust | liang2019brobust |
|---|---|---|
| type | article | article |
| title | Robust estimation under heavy-tailed noise | Robust estimation under heavy-tailed noise |
| journal | Journal of Multivariate Analysis | Journal of Multivariate Analysis |
| year | 2019 | 2019 |
| doi | 10.1016/j.jmva.2019.04.001 | 10.1016/j.jmva.2019.04.001 |

**判斷依據**：四個獨立欄位（標題、期刊、年份、type）逐字全部一致，DOI 也逐字相同——這是欄位合取檢核（skill 3a：標題相似度＋期刊相似度＋年份差＋type 一致）能拿到的最高信心組合，且不是門檻邊緣，是完全命中。

**反例檢核**：同一 DOI 也可能是「更正啟事與原文共用 DOI」（skill「沒有唯一鍵這回事」表列的已知陷阱，實測踩過一個 store 裡 17 組共用 DOI 的案例）。但更正啟事通常標題會帶「Correction to…」「Erratum:」字樣、type 也常另立一類——這裡兩筆的標題逐字相同（沒有更正字樣）、type 同為 `article`，看不出任何區分兩筆為不同物件的訊號。判定為同一物件被建了兩筆記錄，不是原文＋更正的關係。

**額外佐證（非決定性，但方向一致）**：citekey 的 `robust` / `brobust` 是同一詞根加一個 `b` 後綴——這是常見的「citekey 撞名時工具自動加後綴消歧」痕跡，暗示這兩筆很可能是同一份輸入在不同時間點各被寫入一次。此訊號本身不足以判定重複（後綴只是命名巧合的可能性無法排除），但與欄位合取檢核方向一致，互相加強而非單獨依賴。

**建議**：合併，保留其一（例如較早或欄位較完整的 citekey），另一筆的所有 relation／citation 指向改連到保留者。

---

## 組二：`tsai1992measurement` / `tsai1992bmeasurement` — 重複，建議合併

| 欄位 | tsai1992measurement | tsai1992bmeasurement |
|---|---|---|
| type | article | article |
| title | Measurement invariance in cross-cultural research | Measurement invariance in cross-cultural research |
| journal | Psychological Bulletin | Psychological Bulletin |
| year | 1992 | 1992 |
| doi | （空） | （空） |

**判斷依據**：標題、期刊、年份、type 四項逐字一致，與組一同一等級的合取命中。**這裡沒有 DOI 可用**——但 1992 年早於 DOI 系統普及（DOI 約 1990 年代末才出現、多數期刊回溯掛號更晚），兩筆同時缺 DOI 是**符合年代的正常現象，不是矛盾訊號**，不能因為「沒有 DOI 佐證」就降低信心。換句話說：DOI 缺席在這裡是中性的（沒有提供資訊），不是負面證據。

**反例檢核**：會不會是同一期刊同一年剛好有兩篇標題撞名的獨立文章？以這個標題的具體程度（"Measurement invariance in cross-cultural research"，非泛用短語）而言，同刊同年撞題的機率極低，且沒有任何欄位顯示這是兩篇不同文章（無不同作者、不同頁碼等可資區分的欄位）。

**額外佐證**：citekey 同樣是 `measurement` / `bmeasurement` 的詞根＋`b` 後綴模式，與組一相同的撞名消歧痕跡——第二次出現同一 pattern，強化「`b` 後綴＝同一輸入被寫入兩次」這個假說本身的可信度。

**建議**：合併，保留其一，relation 改連到保留者。

---

## 組三：`anon2021sparse` / `kuo2023sparse` — **不是重複，不要合併**

| 欄位 | anon2021sparse | kuo2023sparse |
|---|---|---|
| type | **unpublished** | **article** |
| title | Sparse recovery with correlated designs | Sparse recovery with correlated designs |
| journal | （無） | **Annals of Statistics** |
| year | **2021** | **2023** |
| doi | （無） | **10.1214/23-aos2301** |

**判斷依據**：標題逐字相同，但這是唯一相同的欄位。type、journal、year、doi 四項全部不同，且年份差 = 2，超過 skill 3a 合取檢核裡「年份差 ≤ 1」的門檻。這正是 skill 明講的典型陷阱案例：「一筆 preprint 可以在第一項（標題）拿滿分，但過不了後三項」。

**識別為版本沿革（lineage），不是重複記錄**：`anon2021sparse` 的形狀（type=unpublished、無期刊、無 DOI、作者未定名只留 `anon`）是預印本／工作論文的典型樣子；`kuo2023sparse` 的形狀（type=article、有期刊、有 DOI、作者已定名為 Kuo）是正式發表版。時間順序（2021 → 2023）與「預印本先掛出、兩年後正式發表」完全吻合。這對應 skill「沒有唯一鍵這回事」表裡明列的反例：「DOI（反向）：預印本無 DOI、正式版有——同一個作品，一個有一個沒有」——標題相同不代表是同一筆*記錄*該被合併，而是同一個*作品*的兩個不同階段，本來就該留下兩筆不同的 bibliographic record。

**不該合併的理由**：這兩筆代表的是不同的物件（一筆是預印本這個實際存在過的文件，一筆是期刊正式版），而不是同一個物件被寫了兩次。若當作重複強行合併，等於把預印本這筆記錄直接刪掉——但預印本本身是有獨立史料價值的記錄（早期版本的內容、掛出時間、當時作者具名狀態都可能與正式版不同），一旦刪除不可逆。這正是 skill 紀律「寧可分割，絕不合併」的核心理由：分割（誤判成兩筆但其實可以事後補關聯）可逆，錯誤合併（刪掉其中一筆）不可逆。

**正確處理方向**（僅供參考，非本次任務範圍）：兩筆都保留，改用 `akashic_link` 之類的關係機制標注「同一作品的不同版本」（例如 has-published-version / preprint-of），而不是合併成一筆。

**額外佐證**：citekey 完全沒有組一、組二那種「詞根＋`b` 後綴」撞名痕跡——`anon2021sparse` 與 `kuo2023sparse` 的字首（作者標籤）本身就不同，符合「這是兩個不同時間點各自獨立建立的記錄，不是同一次輸入被寫兩遍」的判斷。citekey 命名模式本身也是一條獨立訊號，且與上面欄位分析的方向一致。

---

## 總結

| 組別 | 判定 | 關鍵依據 |
|---|---|---|
| liang2019robust / liang2019brobust | 重複 → 合併 | 標題/期刊/年份/type/DOI 五項逐字全同；citekey `b` 後綴為撞名痕跡 |
| tsai1992measurement / tsai1992bmeasurement | 重複 → 合併 | 標題/期刊/年份/type 四項逐字全同；缺 DOI 是年代使然、非矛盾；citekey `b` 後綴同一模式 |
| anon2021sparse / kuo2023sparse | **非重複 → 不合併** | 僅標題相同，type/journal/year/doi 全異、年份差 2；形狀符合「預印本→正式發表」版本沿革；合併會刪掉預印本這筆有獨立價值的記錄；citekey 無撞名痕跡 |

本報告未寫入 store、未呼叫 akashic 工具；若要實際合併組一、組二，屬於 skill 定義的「挑出來的」判斷（合併目標、保留哪個 citekey、relation 如何改連都需人工決定），動手前仍需先跑乾跑報告並取得使用者明確同意。
