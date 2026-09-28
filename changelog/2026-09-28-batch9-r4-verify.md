# 2026-09-28 #647／#569 的 R4 verify 修正（本批最後一輪）

R4 只審 R3 的修正 commit（`2c1fa576`），六席回報 27 條：1 HIGH、2 MEDIUM，其餘 LOW／INFO。這是先前預告的停損輪：修掉這一輪的 HIGH 與 MEDIUM 之後停止，不再跑 R5，交給使用者決定。

## #647 反方向的矛盾對（HIGH，DA 真 binary）

R3 封住了「先否決、後確認」這個方向。反方向還開著：先 `--judge` 確認 `{Sinica}`，再 `--reject` 同一 work 的 `{SINICA}`，全程只用工具，也會寫出 confirmed＋rejected 的矛盾對，而且處置沒有工具面（#486）。reject 腿從來不檢查被判的 org 是否已確認同一配對。這是既有缺陷，不是 R3 引入的；DA 另外指出，同一個 literal 出現在兩個作者位時，連原始相等的拼法都能走到這一步。

現在兩條 reject 路徑都檢查，以正規化鍵比對（`OrgResolver.confirmedPairingsNormalized`）；那個 org 已確認過同一配對時，該筆略過並具名：
- MCP 的逐 id reject，略過的列在 `skippedConfirmed`；
- CLI 的篩選式 `--reject`，略過的逐筆印出，成功筆數扣掉它們（先前會報「否決 2 筆」而實際只寫一筆）。

這與 judge 腿「略過已否決的配對」對稱。**列表不做抑制**：抑制已確認配對的其他拼法，會讓那些作者位永遠歸戶不了。

## #569 變體選擇子退回逃脫（MEDIUM，logic、security 兩席真 binary）

R3 讓 CLI 檔案出口無條件保留變體選擇子。一串 VS17–256 接在 ASCII 後面時，每個字元可以夾帶一個位元組，這是已知的隱藏文字通道，容量遠大於 SHY。本 repo 的 skill 又會經 Bash 把 CLI stdout 讀進 LLM context，所以「CLI stdout 的下游是 TeX 或終端」這個前提不完全成立。

只放行「接在對應基底後面的單一選擇子」需要判斷脈絡，而 live store 零實例，所以先退回逃脫。代價是 IVS 在檔案出口有損，這是記錄下來的取捨，等第一個實例出現再重開；CGJ、WJ、ZWSP 與 `rendersBlank` 同屬這個取捨。扣掉的四類（Zs、SHY、私用區、ZWJ／ZWNJ）都是低容量或具正字法意義的字元；高容量的通道（TAG、VS、ZWSP）照逃。

## 範圍內的 LOW

- `OrgResolver.normalizedRejection` 與既有的 `ResolutionLedger.statePairing` 是同一個函式，改成呼叫後者，定義只留一份。
- R3 把新函式插進 `resolve` 的 doc comment 中間，`resolve` 因此失去 doc；已移回原位。
- `documentSafe` 的 `forLLM` 改成必填。預設 false 會讓日後回到 LLM 的呼叫端默默拿到較寬的集合；兩個 CLI 出口改為顯式傳 false。
- 三份描述（CLI `--judge` help、MCP `judge`、parity 列）寫明：「已否決而略過」只發生在歧義條目；候選列上已否決配對的其他拼法不再列出，拿它的 id 是輸入錯。
- MCP `reject` 的描述與 CLI `--reject` 的 help 補上 `skippedConfirmed` 與略過。
- 測試改名為 `testLLMDocumentExitsEscapeTypographyAndGraphMLStaysValidXML`：它現在斷言的是 MCP 出口會逃脫。
- DocumentSafe.swift 的 header 補上「變體選擇子不在扣除之列」。

## 測試

新增：
- `OrgJudgeLegTests.testRejectingAVariantOfAConfirmedPairingIsSkipped`
- `OrgJudgeLegTests.testJudgeSkipsARejectedPairingThroughACaseVariant`：走歧義條目，覆蓋 R3 新加、卻沒有任何測試走到的正規化略過分支（Codex）。

CLI 出口測試加上一串 VS17–256 必須逃脫的斷言。負控三組全紅：拿掉 reject 腿的略過、恢復 VS 豁免、judge 略過改回原始比對。

## 記錄、不改（交給使用者）

- **否決正規化有三個站點，負控只測到 work 作者位那一個**；person 隸屬與上級機構兩站點改回原始比對時，測試照樣全綠（DA、Codex）。三處呼叫同一個 helper。
- `testDestinationChecksRunBeforeAnyWrite` 的釘住條件帶一個 `|| contains("ck2020.yaml")` 的析取，比應有的寬。
- MCP 的 bib 改用 LLM 集合之後，如果 LLM 替人把 bib 寫成檔，會帶著有損的 `U+XXXX` 標記。要保真的 .bib，請走 CLI `export-bib --output`。
- 檔案出口保留 Zs、SHY、私用區，是從「文件的正當內容」推出來的裁決，不是使用者裁決；它與 ZWJ／ZWNJ 的類推同樣待使用者確認。
- 補充私用區（U+F0000–10FFFD）在檔案出口保留，容量論證與 VS 相同（security）；live store 零實例。
