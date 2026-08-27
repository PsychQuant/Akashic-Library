# 只推 tag 時跳過驗證——省的不是時間，是 `--no-verify` 的養成

2026-08-28，#434。推一個 tag 要跑完整 pre-push（實測 46 分鐘），而 **tag 不改變任何檔案、
不移動任何 branch**——它給一個已經在遠端的 commit 一個名字。對那樣的 push 跑驗證，驗的是
一個遠端早就有的樹。

## 為什麼這不是效能優化

CLAUDE.md 已記過：

> 四分鐘的 pre-push 在頻繁 push 時會被 `--no-verify` 繞過，那時**所有**守衛等於不存在。

一個**明顯無意義**的 46 分鐘等待，是讓人開始習慣性繞過的最有效訓練。而繞過一旦成為
肌肉記憶，它不會只用在 tag 上。所以這一格的價值不在省下的 46 分鐘，在**沒有製造一個
繞過的正當理由**。

## 判準有兩半，第二半不是裝飾

```
所有 remote ref 都是 refs/tags/*   ∧   每個 local sha 已被某個 remote-tracking branch 含著
```

第二半是必要的：`git push origin v1.0` 可以推一個指向**本地獨有** commit 的 tag，那次
push 會把那個 commit 一起帶上去。那時樹是新的，驗證不能跳。

全零 sha（刪除 ref）視同不引入樹，可跳。

## 負向 case 才是這支測試的重點

新增的 `testTagOnlyPushSkipsVerificationButOnlyWhenTheCommitIsAlreadyRemote` 有三個 case，
**兩個是負向的**：

| # | stdin | 期望 |
|---|---|---|
| ① | tag → `origin/main` 的 sha | 早退，**一次 swift 都不呼叫** |
| ② | branch ref | 照常驗證 |
| ③ | tag → 40 個 `f`（遠端沒有的 sha） | 照常驗證 |

正向那個只證明早退存在；負向那兩個才證明它**沒有跳太多**——而跳太多的失敗是安靜的：
push 成功、驗證沒跑、沒有任何訊息說它沒跑。

## 負控：確認它會紅

把 `if [ -n "$push_refs" ]` 改成 `if false`（反向編輯，**不是** `git checkout`——那會
回滾真修改），測試如期紅在 case ①：

```
XCTAssertFalse failed - 早退之後不該呼叫 swift——跑了就表示沒有真的跳過
```

還原後 0.271 秒通過。早退在最前面，所以這支測試不碰 build／test 階段——它不會踩到 #431
記錄的那個 43 分鐘熱路徑。

## 同輪確認 #432 已修

`AKASHIC_PRE_PUSH_STAGES`（候選 1）與 `run-guards.sh` 抽出（候選 2）**兩個都已落地**，
且 `PrePushHookTests` 在用前者、CI 與 hook 共用後者（`census-parity.yml:149` 與
`pre-push:41` 是同一個命令）。#432 的兩個候選不是二選一，是都做了。
