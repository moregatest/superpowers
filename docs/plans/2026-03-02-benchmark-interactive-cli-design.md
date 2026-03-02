# Benchmark Interactive CLI 設計

## 動機

防唬爛測試結果顯示 pipeline 功能正常（Codex 得分 7/12, 58%），但使用體驗有四個痛點：

1. **指令太多步驟** — 需手動 copy seed 到 approved、記各種 flag、切目錄
2. **結果不易閱讀** — JSON 輸出需用 jq 手動查詢
3. **缺少一鍵執行** — 沒有 seed→run 的快捷路徑
4. **新手不知從何開始** — 缺少互動式引導

## 方案

建立 `tests/benchmark/benchmark.sh` 作為唯一入口，提供互動選單與指令模式。

## 設計

### 1. 入口與雙模式

**互動模式（無參數）：**
```
$ ./benchmark.sh

Benchmark Pipeline
==================
1) 擴展種子 (expand)
2) 審核變體 (review)
3) 執行測試 (run)
4) 查看報告 (report)
5) 快速測試 (quickrun)
q) 離開

選擇 >
```

**指令模式（帶參數）：**
```
$ ./benchmark.sh expand --seed seeds/anti-bullshit/cross-domain-stitching-001.yaml
$ ./benchmark.sh run --category reasoning --tool codex
$ ./benchmark.sh report
$ ./benchmark.sh quickrun --seed seeds/reasoning/debug-off-by-one-001.yaml --tool codex
```

子指令轉發給對應腳本，加上合理預設值。

### 2. Quickrun — 一鍵測試

一個指令完成整個流程：

1. 複製 seed → `generated/approved/<category>/`
2. 執行 `run.sh`
3. 輸出人類友善摘要
4. 清理暫存檔案

互動模式下引導選擇類別 → seed → 工具，Enter 即可用預設值。

支援 `--judge-tool` 參數指定評審工具（預設跟 `--tool` 相同，避免巢狀 session 問題）。

### 3. Report — 人類友善報告

從 `results/` 讀取 JSON 並生成可讀摘要：

- 分類摘要表（類別、題數、得分、通過率）
- 逐題結果（prompt 摘要、得分、judge 評語）
- 總結與弱點分析

參數：
- `--file FILE` — 指定結果檔案（預設最新）
- `--format markdown` — 輸出 markdown 格式

### 4. 互動式 Expand + Review 銜接

每步完成後自動提示下一步：

- Expand 完成 → 「要審核嗎？(y/n)」
- Review 完成 → 「要執行測試嗎？(y/n)」
- Run 完成 → 「要查看報告嗎？(y/n)」

預設值合理，Enter 即可繼續，步驟無縫銜接。

## 新增檔案

| 檔案 | 用途 |
|------|------|
| `tests/benchmark/benchmark.sh` | 主入口（互動選單 + 子指令路由） |
| `tests/benchmark/tools/report.sh` | 報告生成器 |

## 不變動的檔案

現有的 expand.sh、review.sh、judge.sh、run.sh 保持不變，benchmark.sh 作為上層封裝呼叫它們。
