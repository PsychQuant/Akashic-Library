# divergence 的 rests-on 必須是 digest——decode 與寫入閘補上 `isValidDigest`（#507）

`Judgement.restsOn`（第 12 條邊：divergence 判定的依據）先前**收得下不是 digest 的值**。指向同一個內容儲存區的
三條路徑裡，`Entry.akashic.sources` 在 decode 驗、`ProvenanceReference.restsOn` 在 init 驗，只有 divergence 這條
兩頭都沒閘——`assertDivergenceWritable` 只查 layout／format ≥ 5／候選鍵，`DivergenceYAML.decode` 只查非空、
與 judgement 成對、prefers 在候選內。#453 的掃描第一次在 live store 跑就抓到：divergence `B354B9E9…` 的
`rests-on` 是 `https://doi.org/10.1038/s41586-025-09680-x`。spec（`divergence-record`）寫的是「the digests of
the evidence it rests on」；`Judgement.restsOn` 的 doc 也寫「`sha256:` 前綴的摘要」——是實作漏了，不是契約模糊。

- **decode**：`rests-on` 每個元素過 `ProvenanceReference.isValidDigest`（單一定義，不另寫第二份）；不合法 →
  `invalidField("divergence.rests-on", …)`，整檔 quarantine——與 `akashic.sources` 同語意。訊息說出處置：先
  `store-source` 把依據存進 sources/，再填它的 digest。
- **寫入閘**：`assertDivergenceWritable` 對 `judgement.restsOn` 同一檢查，拒寫零寫入——否則本 binary 寫得出
  一筆下一次載入就 quarantine 的記錄。
- **測試 fixture 一次改完**：`DivergenceDecodeTests` 的 `sha256:9a23d701e4fe4888`（16 hex）、
  `DivergenceSerializationTests` 的 `sha256:0001`／`sha256:ffff`、`DivergenceRecordTests`／`RenamePersonTests`／
  `ServiceTests`／`StdioE2ETests` 的 URL——它們本來就是不合法的形，只是沒人擋。序列化那組保留排序語意
  （`00…01` < `ff…ff`）。
- **#453 的 `wellFormed == false` 分支自此對已載入記錄不可達**：`DanglingSourceScanTests.testMalformedDigestIsUnreachableForLoadedRecords`
  釘住（寫入閘擋、繞過閘直接落 YAML 則 decode 期 quarantine、掃描看不到）。分支留著是防禦；`zero-instance-guards`
  第 8 列的形：零的來源在別處，那段程式改了要有人知道。
- **既有 store 的影響**：live store 唯一那筆 URL restsOn 在本 binary 下會被 quarantine（fail-closed、可見）。
  修法是資料修復：把依據 `store-source` 進 sources/、`rests-on` 改成 digest、local commit——不在本 repo 內。
