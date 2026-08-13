# 重複判定報告 — store_records.tsv（六筆 work）

分析方法依 akashic-bootstrap skill 步驟3的驗證紀律：判定兩筆記錄是否為同一實體，要求多個互相獨立的訊號同時成立（標題相似度、期刊名相似度、年份差、type是否相同），而非只看單一訊號。純分析，未呼叫任何 akashic 指令、未寫入 store。

**組一 liang2019robust vs liang2019brobust — 重複，應合併**
標題完全相同、期刊完全相同、年份相同、type皆article、DOI完全相同(10.1016/j.jmva.2019.04.001)。四項獨立訊號全合取，且DOI逐字相同——排除「像但不是」的可能。citekey的robust/brobust模式符合「兩個寫入者對同一份資料產生兩種形狀」。建議合併，但保留哪個citekey屬「挑出來的」判斷，需人工核准。

**組二 anon2021sparse vs kuo2023sparse — 非重複，是lineage，不應合併**
標題完全相同(單一訊號滿分)，但type不同(unpublished vs article)、期刊不同(空白 vs Annals of Statistics)、年份差2年(超過≤1門檻)、DOI一無一有。這正是skill警告的失敗模式：preprint在標題項拿滿分但過不了後三項。更合理解讀是同一研究的兩個出版階段(2021未發表版→2023正式發表版)。合併會抹除先後版本資訊且造成不可逆資料損失；若要表達關聯應用akashic_relations建立preprint-of/published-as關係，而非合併/刪除。

**組三 tsai1992measurement vs tsai1992bmeasurement — 很可能重複，建議合併前先做外部核對**
標題、期刊、年份、type四項可得訊號全部逐字相同，強度超過skill門檻，但兩筆都缺DOI，無法做步驟3要求的反向驗證。citekey的measurement/bmeasurement模式與組一相同(寫入碰撞產生第二形狀)。建議分類為重複，但寫入前先用標題+作者查DOI做一次外部核對，補上缺失的最強獨立訊號後再落地合併。

---
（註：本檔由主控代為存檔——subagent 被系統限制禁止寫 report 檔，內容為其回傳的完整文字。）
