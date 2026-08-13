# 作者機構隸屬判定報告

**論文 DOI**: `10.1000/demo.2025.1`  
**分析日期**: 2026-08-04

---

## 逐位判定結果

### 1. Wu HJ — ✅ **確認隸屬中研院統計所**

**機構字串**:
```
Institute of Statistical Science, Academia Sinica, Taipei, Taiwan.
```

**判定**:
- 字串直接標示 "Institute of Statistical Science"，隸屬明確
- 無歧義，為統計所成員

---

### 2. Chang ML — ⚠️ **否，主要隸屬非統計所**

**機構字串** (2 條):
```
[1] Institute of Plant and Microbial Biology, Academia Sinica, Taipei, Taiwan. mlchang@gate.sinica.edu.tw.
[2] Bioinformatics Program, Institute of Statistical Science, Taiwan International Graduate Program, Academia Sinica, Taipei, Taiwan.
```

**判定**:
- **主要隸屬**（第 1 機構）: 植物微生物研究所（Institute of Plant and Microbial Biology）
- **第 2 機構的陷阱**: 雖然字面上寫著 "Institute of Statistical Science"，但它修飾的是 "Bioinformatics Program"（生物資訊學程），而非她的僱用機構
  - 生物資訊學程是 **跨院所教學單位**，由統計所主辦但非其獨有
  - Email 域名 `mlchang@gate.sinica.edu.tw` 對應通用名單系統，第 1 機構「植物微生物研究所」是其主要職位
  - 機構順序反映權重：主要隸屬通常列在前

**反例檢核** (SKILL.md 3e 型): 若作者同時擁有多個中研院機構，優先看 email domain 與論文署名的一致性。此處 email 與第 1 機構相符。

**結論**: Chang ML 不計入統計所隸屬。

---

### 3. Fischer K — ⚠️ **副要隸屬統計所（非主要）**

**機構字串** (2 條):
```
[1] Department of Mathematics, ETH Zurich, Switzerland.
[2] Institute of Statistical Science, Academia Sinica, Taipei, Taiwan.
```

**判定**:
- **主要隸屬**: ETH Zurich（蘇黎世理工大學）— 列在第一位
- **副隸屬**: 中研院統計所 — 列在第二位
- 常見模式：國外訪問學者/聯合指導教授，於來源機構（ETH）與合作單位（統計所）同時列名

**結論**: Fischer K 與統計所有關（副要隸屬），但若問「誰是統計所的人」，主僱主是 ETH Zurich。是否計入取決於統計所隸屬的定義範圍（core members 只含 Fischer K；affiliated 可含）。

---

### 4. Lee SY — ✅ **確認隸屬中研院統計所**

**機構字串** (2 條):
```
[1] Institute of Statistical Science, Academia Sinica, Taipei, Taiwan.
[2] Department of Public Health, National Taiwan University, Taipei, Taiwan.
```

**判定**:
- **主要隸屬**（第 1 機構）: 統計所
- **副隸屬**: 台灣大學公共衛生系（可能是兼任或合聘）
- 機構順序清楚反映優先級：統計所為主

**結論**: Lee SY 為統計所成員。

---

## 彙總

### 確認隸屬統計所的作者

| 作者名 | 隸屬類型 | 信心度 | 備註 |
|--------|---------|--------|------|
| Wu HJ | 直接隸屬 | 100% | 單一機構，無歧義 |
| Lee SY | 主要隸屬 | 100% | 列名優先級清楚 |
| Fischer K | 副要隸屬 | 95% | 國外訪問學者，主僱主是 ETH |
| Chang ML | 否 | 100% | 主隸屬為植物微生物所，統計所只是學程主辦單位 |

### 供 person 記錄補充的隸屬

**直接建議納入**:
- **wu-hj**: affiliation = "Institute of Statistical Science, Academia Sinica" (primary)
- **lee-sy**: affiliation = "Institute of Statistical Science, Academia Sinica" (primary)

**可選納入**（取決於隸屬定義廣度）:
- **fischer-k**: affiliation = "Institute of Statistical Science, Academia Sinica" (secondary/visiting)

**不建議納入**:
- **chang-ml**: primary = "Institute of Plant and Microbial Biology"

---

## 關鍵判定邏輯

1. **機構順序**: 同一作者的多機構字串中，第 1 項通常反映主要隸屬
2. **Email domain 對應**: 當 email 明確指向某機構時（如 `mlchang@gate`），與該機構的優先度對應
3. **教學單位 vs 研究單位**: "Program" / "Graduate Program" 常是跨院所教學單位，主辦單位≠必然隸屬
4. **反例檢核**: 字面上含 "Institute of Statistical Science" 不等於隸屬該所；需檢查語法結構（修飾對象是誰）與其他線索

