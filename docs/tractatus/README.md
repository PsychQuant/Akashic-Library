# 《邏輯哲學論》專案對照正典

本目錄以 `sources.yaml` 與 `corpus/*.yaml` 作為機器可驗證的正典資料；`generated/tractatus-project-map.md` 只能由 `tractatus-doc render` 產生，不可直接編輯。

## 正典範圍

- 收錄維根斯坦序言的八個正文段落，以及編號命題 1–7 的全部 526 條命題。
- 固定範圍不是由 manifest 自己說了算：validator 另以 canonical fingerprint 鎖住序言八段、526 條命題與三個固定版本。
- 獻詞與題辭只保存在 `sources.yaml` 的 metadata；序言簽名與日期仍留在未改寫的來源快照，但不是哲學命題記錄。
- Russell 導論與索引明確排除，不得進入逐句解讀語料。
- 德文原文與 1922 Ogden／Ramsey 英譯可離線逐字稽核；Pears／McGuinness 欄只提供固定版本參照與命題編號，不重製受著作權保護的文字。

## 來源與權利

`source-snapshots/` 的兩個 Markdown 檔是 Ludwig Wittgenstein Project 在 commit `1e69298e1e026512da6fdbe203e73fb3ab35d126` 的原樣快照。快照內的 editor's note 記錄底本、數位化來源與公版判斷；`sources.yaml` 為所有版本固定 bibliography、來源 URL、擷取日期、上游 revision 與權利說明，並只為實際重製內容的 inline 版本固定 SHA-256。驗證全程只讀本機檔案，不依賴網路。

inline corpus 文字必須能逐字回組 pinned snapshot；只有 snapshot digest 正確、但 YAML 文字漂移時仍會回報 `source-mismatch`。若未來有版本以 `licensed` inline 收錄，除 `rights_note` 外還必須提供可稽核的絕對 HTTP(S) `license_evidence_url`。

原文引用的公式圖與圖示保存在 `source-assets/images/`，由 `source-assets/SHA256SUMS` 鎖定內容。產生器把原始 `images/...` 參照改寫成並排文件可解析的離線路徑；缺檔或 digest 漂移都會使 strict validate 失敗。

Pears／McGuinness 採 Routledge 2001 第二版（ISBN 9780415254083）作外部版本參照。本專案未記錄可重製全文的授權，所以 `inclusion_mode` 固定為 `external_reference`、不得指定 snapshot，也不得在 corpus 的 `texts` 中放入該譯文。此版本以 bibliography、Routledge URL、ISBN revision 與 rights note 稽核；因為沒有可校驗的本機重製物，`sha256` 必須省略，禁止以全零值或其他假 digest 代替內容雜湊。

## YAML 編輯契約

每卷檔案必須依印刷順序列出命題。每條命題包含：

- `texts`：德文與 Ogden／Ramsey 的有序來源單位。
- `edition_references`：Pears／McGuinness 的命題編號參照。
- `segments`：來源索引的多對多對齊、臺灣正體中文工作譯文、逐句哲學解讀。為避免 mega-segment 只在形式上覆蓋原文，只允許 1↔1，或為容納德英句界差異而使用 2↔1／1↔2；2↔2 與任一版本三個以上來源單位會回報 `alignment-granularity`。
- alignment 索引必須逐版本嚴格依序；若 1↔1 兩側各自把多個明顯完整句子塞進單一 `texts[]`，會回報 `source-unit-granularity`。2↔1／1↔2 的單一側也不得偷藏多個完整句子，多單位側不得以單字中央等任意切點偽造句界差異。縮寫、公式與真實版本句界仍以逐卷人工稽核處理。
- `interpretation_zh_tw` 必須直接說明該句的哲學作用、術語、歧義或界線；只用「建立論證起點／推進到／收束命題」包住譯文的建構樣板會回報 `generic-interpretation`。
- `project_relations`：每條命題都要獨立判斷與專案的關係；`rationale_zh_tw` 必須針對該命題撰寫，不同命題不得共用空白正規化後完全相同的理由，否則回報 `duplicate-rationale`。
- `project_relations`：對 Akashic 現況的明確 `status`／`mode`、主張、理由與必要證據；不適用時應誠實標為 `not_applicable`。
- evidence `kind` 會實際驗證 heading／test／requirement／symbol 的結構；corpus、snapshot 與 generated 文件不得循環證成自身關係。
- `history`：branch、commit、issue 的歷史脈絡；不得替代 `main` 上的現況證據。
- 應用層的對照（store 設計判準等）一律掛在既有命題的 `project_relations`，不新增正典命題——正典僅限《論考》文本本身（#235 確立此通則）。

不得使用空字串、`<unfinished>`、`<unreviewed>`、`TODO：命題號`、`TBD：命題號` 或其他裝飾過的佔位文字。卷內 `volume` 必須與實際檔名一致；evidence 路徑會先正規化再套用禁止循環引用的規則。德文的 `Gegenstand`、`Sachverhalt`、`Bild` 與英文版本的術語差異應在解讀中保留，不可把 Akashic 的 entity 直接宣稱為《邏輯哲學論》的 simple object。

## 驗證與產生

建構期間可執行：

```sh
swift run tractatus-doc validate --root docs/tractatus --allow-incomplete
```

全書完成後的閘門是：

```sh
swift run tractatus-doc validate --root docs/tractatus
swift run tractatus-doc render --root docs/tractatus --output docs/tractatus/generated/tractatus-project-map.md
swift run tractatus-doc render --root docs/tractatus --output docs/tractatus/generated/tractatus-project-map.md --check
```

驗證器的資源界線固定為：每卷 YAML 1 MiB、正典 YAML 8 檔／目錄項目 64、每卷
256 個命題、每命題 8 個 project relations／32 筆 history、每 relation 32 筆 evidence，
全次驗證最多 1,024 筆 evidence／512 筆 history；current-evidence 單檔最多讀 4 MiB。
`sources.yaml` 最多 256 KiB／16 個 editions，inline snapshot 最多 2 MiB 且依
canonical path 一次擷取，同一份 bytes 同時供 digest 與
fidelity 驗證，`SHA256SUMS` 最多 256 KiB，單一 referenced asset 最多 8 MiB，
每次驗證最多掃描 4,096 次 referenced-image occurrence，unique canonical asset
captures 合計最多 64 MiB；每次擷取前先套用剩餘總預算，不讀取越界 sentinel。
`source-assets` 經 symlink 解析後必須留在 corpus root 內，`SHA256SUMS` 本身也
不得以 symlink 越出 asset trust root。
所有 YAML 另先通過共用 alias-event expansion budget。超界一律以 `resource-limit`
fail closed，不進入 path、composition、locator、digest 或 Git history 的無界工作。

若要人工複核來源快照與圖資的 digest：

```sh
shasum -a 256 docs/tractatus/source-snapshots/*.md
(cd docs/tractatus/source-assets && shasum -a 256 -c SHA256SUMS)
```
