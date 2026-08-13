# 論文 DOI:10.1000/demo.2025.1 作者機構判定報告

## 結論

**全部 4 位作者皆為中研院統計所所屬**。

## 詳細判定

### 1. Wu HJ — ✓ Institute of Statistical Science

**來源字串**：
```
Institute of Statistical Science, Academia Sinica, Taipei, Taiwan.
```

**判定**：直接命中。「Institute of Statistical Science」完全符合。

---

### 2. Chang ML — ✓ Institute of Statistical Science（多重隸屬）

**來源字串**：
```
[1] Institute of Plant and Microbial Biology, Academia Sinica, Taipei, Taiwan. 
    mlchang@gate.sinica.edu.tw.
[2] Bioinformatics Program, Institute of Statistical Science, Taiwan International 
    Graduate Program, Academia Sinica, Taipei, Taiwan.
```

**判定**：
- 第一隸屬：植微所（IPMB）
- 第二隸屬：統計所下之生物資訊碩博班（TIGP）✓ 

Institute of Statistical Science 在第二個隸屬字串中明確出現。該作者應記為統計所隸屬。

---

### 3. Fischer K — ✓ Institute of Statistical Science（跨國隸屬）

**來源字串**：
```
[1] Department of Mathematics, ETH Zurich, Switzerland.
[2] Institute of Statistical Science, Academia Sinica, Taipei, Taiwan.
```

**判定**：
- 第一隸屬：蘇黎世理工（ETH）
- 第二隸屬：統計所 ✓

多重隸屬。應記為統計所隸屬（台灣方面）。

---

### 4. Lee SY — ✓ Institute of Statistical Science（主要隸屬）

**來源字串**：
```
[1] Institute of Statistical Science, Academia Sinica, Taipei, Taiwan.
[2] Department of Public Health, National Taiwan University, Taipei, Taiwan.
```

**判定**：
- 第一隸屬：統計所 ✓（通常列在前代表主要隸屬）
- 第二隸屬：台大公衛系

應記為統計所隸屬。

---

## 隱性假設與限制

1. **隸屬表達正規化**：四位作者的字串都用 「Institute of Statistical Science」 完整形式，未出現「台大統計」「NTU Stats」等別稱變體或縮寫。若有其他論文用 STAT、Stat. Science 等變體，需建立對應規則。

2. **多重隸屬的優先順序**：Chang ML 與 Fischer K 各有兩個隸屬。目前假設「出現 Institute of Statistical Science 就算該作者屬於統計所」；但若後續需區分「主要隸屬 vs 參與隸屬」，建議依字串順序或聯絡資訊（如 email）判斷。

3. **組織實體建設延緩**：按 Skill 紀律（`common-skills/akashic-bootstrap` L148），組織資料當前存成 source 而非建立 person_key 的 org metadata，直到 Akashic-Library #63、#70 的建模問題有答案為止。本報告僅標記隸屬識別，不建議此階段建構「Institute of Statistical Science」org 實體。

---

## 建議後續步驟

1. 在四位作者的 person 記錄中記載其隸屬字串（store 為 source 備查）。
2. 若系統將支援 work-level affiliation metadata，四位作者都應掛上 Institute of Statistical Science 的關聯。
3. 若需進一步精細化（如區分 primary vs secondary affiliation），回頭用 person 的 citekey 綁定時補充欄位。
