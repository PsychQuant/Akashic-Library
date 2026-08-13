# 作者機構判定：哪幾位是中研院統計所（Institute of Statistical Science, ISS）

**輸入**：`iteration-3/fixtures/affiliations.json` — DOI `10.1000/demo.2025.1`，4 位作者的機構字串
**本次做了什麼**：純判讀。**未寫入 store、未呼叫任何 akashic 指令、未連外查證。**
**因此缺的那一步**：skill 的步驟 1（先看 store 已經有什麼）與步驟 5（寫入）都沒做。以下只到「這串字說了什麼、能不能據此下判定」為止，**人物歸戶（把名字對到 person_key）完全沒做**。

---

## 結論表

| # | 作者 | ISS？ | 一句話理由 |
|---|---|---|---|
| 1 | Wu HJ | **是** | 唯一機構就是 ISS，逐字為正式名稱 |
| 2 | Chang ML | **否 → 待人工判定** | ISS 只以「TIGP 學程的掛靠所」身分出現；本人研究單位是植微所（IPMB） |
| 3 | Fischer K | **是**（第二機構） | ISS 以完整 head unit 出現；排在 ETH 之後不構成排除理由 |
| 4 | Lee SY | **是**（第一機構） | ISS 為第一機構，與台大公衛雙隸屬 |

**3 位是、1 位需要人來裁。**

---

## 為什麼不能用字串比對

`grep "Institute of Statistical Science"` 在這四位身上**命中 4/4**，而正解是 3。
precision 0.75、recall 1.00 —— 這正是 skill 步驟 3 警告的失敗形狀：**單一訊號（子字串出現）強度很高，卻不是判定**。

差別不在字串**有沒有出現**，在它在句子裡的**語法角色**：

- Wu / Fischer / Lee：`Institute of Statistical Science, Academia Sinica, Taipei, Taiwan.` —— ISS 是這串地址的 head unit（此人所屬單位）。
- Chang：`Bioinformatics Program, Institute of Statistical Science, Taiwan International Graduate Program, Academia Sinica, Taipei, Taiwan.` —— head 是 **Bioinformatics Program**，ISS 是**那個學程的掛靠單位**。

字串比對看不到這個差別；解析語法角色才看得到。

---

## 逐位判定

### 1. Wu HJ — **是 ISS**

```
Institute of Statistical Science, Academia Sinica, Taipei, Taiwan.
```

- 唯一機構，無其他單位競爭。
- 名稱是單數 `Science`，即 ISS 的正式寫法（`work-sources.md` 記錄過出版商會誤植成複數 `Sciences`；這裡沒有）。
- 語法角色明確：所 → 院 → 城市 → 國家，標準的機構地址階層，ISS 就是此人的所屬單位。

**這四位裡機構軸上最乾淨的一筆。** 若要挑一筆直接記錄，是這筆。

**但**：`Wu HJ` 是縮寫名。機構判定成立不代表**人**判定成立——要記進哪一筆 person 記錄，得先跑 `akashic_person(name: "wu")` 看候選，且候選要交給你挑（skill：候選永遠不自動選第一個）。這是本次沒做的部分。

---

### 2. Chang ML — **否；標為待人工判定（本題的主要陷阱）**

```
aff[0]: Institute of Plant and Microbial Biology, Academia Sinica, Taipei, Taiwan. mlchang@gate.sinica.edu.tw.
aff[1]: Bioinformatics Program, Institute of Statistical Science, Taiwan International Graduate Program, Academia Sinica, Taipei, Taiwan.
```

三個各自獨立的理由指向「ISS 不是他的隸屬」：

**(a) ISS 在這裡是學程的掛靠所，不是任職單位。**
拆解 aff[1] 的階層：`Bioinformatics Program`（學程）→ `Institute of Statistical Science`（主辦／掛靠所）→ `Taiwan International Graduate Program`（TIGP 學程體系）→ `Academia Sinica`（母機構）。TIGP 的每個學程都由院內某所主辦，學生在合作大學註冊學籍、在某位老師的實驗室做研究。這串話說的是「此人隸屬於一個由 ISS 主辦的學程」，**不是「此人是 ISS 的研究人員」**。學程註冊 ≠ 機構任職。

**(b) 他實際做研究的單位是 IPMB。** aff[0] 是植微所，且**通訊 email 掛在 aff[0] 上**。TIGP 學生的典型寫法正是「實驗室所屬所 + TIGP 學程」——aff[0] 是人所在的地方，aff[1] 是學籍/學程。

**(c) email 在此完全沒有鑑別力（不要拿它當第二訊號）。**
`mlchang@gate.sinica.edu.tw` 的 `gate.sinica.edu.tw` 是**中研院院級的 gateway 網域**，證明「中研院」，但**不區分哪一個所**。它對 ISS vs IPMB 的判別是零訊息。（若是 `@stat.sinica.edu.tw` 才會是指向 ISS 的獨立訊號。）

**為什麼是「待人工判定」而不是乾脆的「否」**：他跟 ISS 確實有制度上的連結，只是那個連結的**種類**不是隸屬。而 store 目前沒有辦法表達「關係種類」與「時間起訖」（Akashic-Library#63、#70，也正是 skill「organization 先停」擋住的那批未決問題）。硬把 `ISS` 填進他的 affiliation 欄，會產生一筆**事後看不出錯的錯誤**——skill 的說法是「一筆錯的比一個缺的糟得多：缺的看得見，錯的看不見」。

**要記的話該記成**：`TIGP Bioinformatics Program（掛靠所：ISS）`，關係種類＝學程，而非 `ISS`；且與 `IPMB` 並存。這個形狀現在存不進去 → 停。

**還有一個沒法在本機解決的殘餘不確定**：這串話宣稱該學程掛在 ISS 底下，但我**不能連外核對 TIGP 各學程實際的主辦所**。如果那個掛靠本身是出版商排版誤植，結論方向不變（仍然不是 ISS 隸屬），但理由要換。

---

### 3. Fischer K — **是 ISS**（第二機構）

```
aff[0]: Department of Mathematics, ETH Zurich, Switzerland.
aff[1]: Institute of Statistical Science, Academia Sinica, Taipei, Taiwan.
```

- aff[1] 與 Wu HJ 的唯一機構**逐字相同**，語法角色也相同（ISS 是 head unit）。在「這串話宣稱什麼」的層次，Fischer 的 ISS 主張與 Wu 一樣強。
- 這裡的陷阱是**反向**的：容易套用「第一機構＝真正的機構，其餘是附掛」這個啟發式而排除他。**雙隸屬本來就雙邊都成立**，掛名順序常由期刊格式或作者自己決定，不是證據。

**必須帶的但書**：字串證明「發表當下與 ISS 有隸屬關係」，但分不出那是**合聘、訪問學者、sabbatical、還是短期 visiting 期間掛名**，也沒有起訖時間。記錄時要綁時間界定（＝該文發表年）並標「性質未知」，不要記成無時間限定的現況隸屬。

**額外的來源疑慮（誠實記一筆）**：這篇有 ETH 數學系作者，屬非生醫。`work-sources.md` 實測 Europe PMC（機構資料的主力）**只涵蓋生醫**，統計／數學期刊全查不到機構。這份 fixture 沒有記 provenance——不知道這些 aff 字串是從哪個管道來的。來源不明本身就是一個缺口（skill：取得的原始資料存成 source 並附 provenance）。

---

### 4. Lee SY — **是 ISS**（第一機構）

```
aff[0]: Institute of Statistical Science, Academia Sinica, Taipei, Taiwan.
aff[1]: Department of Public Health, National Taiwan University, Taipei, Taiwan.
```

- aff[0] 逐字為 ISS 正式名稱、head unit 位置 → 成立。
- 與台大公衛的雙隸屬（中研院研究人員在大學合聘／兼任教職是常態），兩者不互斥。
- 「排第一所以是主要機構」只當**提示**、不當證據，理由同 Fischer 那條。

**風險不在機構、在人**：`Lee SY` 的縮寫在台灣姓名裡碰撞率極高（Shu-Yu / Ssu-Yuan / Sheng-Yu / Shih-Yuan…）。四位裡人物消歧風險最高的是這筆。skill 的紀律在此適用：**寧可分割，絕不合併**——不確定是不是同一個 Lee 就先開兩筆，事後補 alias 是可逆的，錯誤合併不可逆。

---

## 這份輸入的三個共同限制

1. **無法做反向驗證。** `10.1000/…` 是 DOI 基金會的示範前綴，這不是一筆可解析的真 DOI。skill 步驟 3 要求「拿到值之後用相反方向回查一次」——這裡做不到，所以**四筆判定全部單一來源**，沒有交叉佐證。所有結論該降一級信心。
2. **機構欄是「發表當下」的快照，不是現況。** 這是它相對於名冊的**唯一優勢**（名冊只有現況），但也是它的限制：不能拿它回答「這個人現在在哪」。
3. **姓名全是縮寫。** 機構判定與人物判定是兩件事；本報告只解決前者。

---

## 建議怎麼記進 person 記錄

- **不要建 ISS 的 organization 實體。** skill 明令「organization 先停」——同一機構多種寫法要不要正規化、時間怎麼表達都還沒有答案（#63、#70）。
- **把這份 aff 原始字串存成 source**，附 provenance（來源管道、查詢方式、取得日期）。「這個欄位憑什麼是這個值」之後查得到，才有救回來的餘地。注意 `sources/` 常被 gitignore 擋住，存之前確認。
- **每筆隸屬綁時間界定**（此文發表年），不要寫成無限期的現況。
- **Chang ML 那筆不要寫。** 等關係種類（學程 vs 任職）能被表達之後再處理。

## 要把這四筆定到可寫入，最省力的下一步

依 `work-sources.md` 的明示順序：

1. **先查 ISS 自己的名冊**——「若目的只是判定某作者是否屬於某機構，該機構自己的名冊或 ORCID employment 往往更快更準」。這一步能同時解決機構與人物兩軸（名冊有全名）。
2. 名冊只有**現況**，所以對 Fischer（訪問可能已結束）與 Chang（可能已畢業）要另外走 `person-sources.md` 的歷任頁／舊版微站路線。
3. ORCID `employment` 可用但有已知陷阱：**只列現職、永不回填歷史**，用它判斷「是否曾屬於某機構」會系統性漏掉離職者。
