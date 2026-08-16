---
name: akashic-literal-campaign
description: literal 歸零 campaign 的編排層（#303）——以「全 entity 域 literal 歸零」為終局（#304 裁決），驅動分批的「查證 → resolve → apply」循環並量測進度。讀 store 現況（三域 census：author／venue／affiliation）→ 按批 TaskCreate → 逐 distinct literal 走查證管線 → 每輪把計數落一筆 #303 comment。當使用者說「繼續 literal campaign」「這批 literal 收一收」「歸戶進度到哪了」「跑一輪 resolve」「campaign 下一批」時使用。與 akashic-person-verify 的分工：那是單一配對的查證紀律，本 skill 是批次編排與進度追蹤——每個候選的查證仍走 person-verify。
---

# literal 歸零 campaign：從積壓到終局

終局（#304 裁決）：**所有 literal 轉成 key，全 entity 域**。殘留 literal＝查證未完成，不是穩態。本 skill 管「怎麼一批一批走到那裡」與「怎麼知道走到哪了」。

**單位工作不是「跑一次 resolve」**。實測（2026-08-16）exact-alias 收割面歸零後，寬鬆提名 tier（#303）讓 resolver 重新有提名能力，但 tier 越低證據越弱——campaign 的核心是把「查證 → apply」的吞吐組織起來，不是自動收割（絕不自動合併鐵律不動）。

## Workflow

### 0. Census（每輪開場與收尾各跑一次）

```bash
bash plugin/skills/akashic-literal-campaign/scripts/literal-census.sh   # 預設 ~/.akashic
```

三域各報**邊數與 distinct 兩個口徑**（只報比率會藏住 pending）。venue 域在 store format < 11 時報「未部署」——那是缺席不是零，部署鏈走完才進 venue 輪。

### 1. 看提名現況

```
akashic_resolve_people（不帶參數）
```

candidates 依 tier 信心降冪：`exact` → `confirmed-elsewhere` → `reorder` → `initials`。讀法：

| tier | 證據強度 | 處置 |
|---|---|---|
| `exact` | alias 完全命中 | 查證後成批 apply |
| `confirmed-elsewhere` | 同 literal 已於他處人工 confirmed | 近乎機械——確認是同一脈絡即 apply |
| `reorder` | token 重排（`Yung-Fong Hsu`↔`Hsu, Yung-Fong`） | 查證後 apply；同名重排碰撞留意 ambiguities |
| `initials` | 姓＋首字母（`Chen, Y.-H.`） | **apply 前必查證**——93/724 的「姓＋首字母」鍵對到 2+ 人，單命中只是店裡「今天」只有一個同鍵者（store 不完整假象，person-verify 有同款警告） |

ambiguities 帶 tier：`initials` 碰撞 ≠ `exact` 同名——前者先用區辨欄位（ORCID／隸屬）補進正確記錄再重跑，後者走 person-verify 的兩種相反處置判斷。

### 2. 分批（TaskCreate 編排）

批次順序（使用者 2026-08-16 拍板：**混合——高頻先掃、統計所批接續、長尾殿後**）：

1. **R1 高頻批**：candidates 按 literal 頻次降冪，freq ≥ 5 的 distinct 先收（一次查證收割全部同字串邊）
2. **R2 統計所批**：iss view works 的 literal 作者（storyline 查證動線接續）
3. **R3+ 長尾**：freq=1 的 one-off（實測 1,134 個、53.4% 邊）——批次建檔問題，走 akashic-bootstrap／add-person，**key 碰撞防護：寧漏勿誤**
4. **venue 輪**（format 11 部署後）：add-venue 標準刊 → resolve-venues；縮寫刊名走 akashic-venue-verify

每批開工時用 TaskCreate 建 batch 清單（一個 distinct literal 一個 task：「查證＋apply『<literal>』×N 邊」），完成即 TaskUpdate——批內進度可見，中斷可續。

### 3. 逐 distinct 的查證管線

對每個 distinct literal（不是每條邊——同字串查一次、apply 收全部）：

1. **查證**：走 [akashic-person-verify](../akashic-person-verify/SKILL.md) 的證據鏈（Europe PMC／ORCID／OpenAlex／出版商頁）——本 skill 不複製那套紀律，只引用
2. **判定**：
   - 是同一人 → `akashic_resolve_people apply:[該 literal 的全部候選 id]`（同動作寫 resolution-confirmed；此後同字串在新 entry 以 `confirmed-elsewhere` 自動提名——查證知識走 verdict 持久化，不寫 alias）
   - 不是 → `reject`（寫 resolution-rejected；同 literal 他 entry 照提）
   - 查不出來 → `akashic_record_divergence` 落進度（person-verify 的第三個出口）
3. **候選不在列**（無任何 tier 命中）→ 店裡沒這個人：走 bootstrap／add-person 建檔，重跑 resolve 讓配對成為候選

### 4. 每輪收尾：進度落地

收尾 census 一次，把兩次計數（開場／收尾）與本輪 apply/reject/divergence 數落一筆 #303 comment：

```markdown
## Campaign R<N>（YYYY-MM-DD）
| 域 | 邊（開場→收尾） | distinct（開場→收尾） |
|---|---|---|
| author | 2123 → … | 1493 → … |
…
本輪：apply X 筆／reject Y 筆／divergence Z 筆／建檔 W 人
```

趨勢只認 #303 的 comment 串——不散落在對話裡（查一次記一次的 campaign 版）。

## 邊界

- **絕不自動合併**：任何 tier 的 apply 都是人（或人授權的批次）顯式確認後的動作；本 skill 編排吞吐，不代做判定
- **寫入前退路**：每批 apply 前確認 store 的 git 工作樹乾淨（或先 commit）——批次寫入沒有內建復原
- **venue 輪 gate 在部署**：format 11 未 bump 前不做 venue 域——census 的「未部署」就是這個訊號
- **initials 的 store 不完整假象**（再說一次，因為它最會咬人）：單命中不是同一性證據，是店裡目前只有一個同鍵者；R3 長尾建檔會讓 initials 碰撞面隨 person 空間成長——早輪的 initials apply 要比晚輪更保守
