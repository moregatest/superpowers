# Benchmark Pipeline：Seed-Expand-Review 測試生成管線

> 回到 [README](../README.md)

## 開發動機

Superpowers 專案包含多種 skill（技能），涵蓋 brainstorming、TDD、debugging 等工作流程。隨著 skill 數量增長，我們需要一套系統化的方式來驗證：

1. **Skill 是否正確觸發** — 當使用者說「我想做一個 CLI 工具」，agent 是否啟動 brainstorming skill 而非直接寫程式碼？
2. **程式碼實作品質** — agent 能否完成完整的 CRUD API 並通過測試？
3. **推理能力** — agent 能否正確找出 off-by-one bug？
4. **反唬爛能力（Anti-bullshit）** — 當使用者提出無意義的問題（如「內容策略的風險概況是什麼？」），agent 是否拒絕胡亂回答？

手動編寫大量測試案例耗時且容易遺漏邊界情境。這條管線讓專家只需撰寫少量「種子（seed）」測試，由 AI 自動擴展出多樣化的變體，再由專家審核後執行。

**設計文件：** [Seed-Expand-Review Test Pipeline Design](plans/2026-03-02-seed-expand-review-test-pipeline-design.md)

## 管線架構

```
專家撰寫 seed（YAML）
     |
expand.sh --> AI 批次擴展 --> generated/pending/
     |
review.sh --> 專家審核（approve/reject/edit） --> approved/ | rejected/
     |
run.sh --> 跨工具執行（claude / codex / opencode）
     |
     +-- rule-check（自動規則檢查）
     +-- judge.sh（AI 評審，預設 claude opus）
     |
results/（JSON 結構化結果）
     |
report.sh --> 人類友好的中文報告（text / markdown）
```

**推薦入口：`benchmark.sh`** — 互動選單或子指令，無需記憶各工具參數。

## 目錄結構

```
tests/benchmark/
├── benchmark.sh                    # ★ 互動式入口（選單 + 子指令）
├── seeds/                          # 專家撰寫的種子測試
│   ├── skill-compliance/           # Skill 觸發與流程合規
│   ├── code-implementation/        # 程式碼實作任務
│   ├── reasoning/                  # 推理與除錯
│   └── anti-bullshit/              # 反唬爛偵測
├── generated/
│   ├── pending/                    # AI 擴展後待審核
│   ├── approved/                   # 審核通過
│   └── rejected/                   # 審核拒絕
├── results/                        # 執行結果（JSON）
└── tools/
    ├── config.yaml                 # 全域設定
    ├── helpers.sh                  # 共用函式（YAML 解析、驗證）
    ├── expand.sh                   # AI 種子擴展器
    ├── review.sh                   # 互動式審核工具
    ├── judge.sh                    # AI 評審
    ├── run.sh                      # 測試執行器
    └── report.sh                   # 人類友好的結果報告
```

## 使用方式

### 前置需求

- `python3` 與 `PyYAML`（`pip3 install pyyaml`）
- `jq`（JSON 處理）
- `claude` CLI（或 `codex` / `opencode`）

### 互動式入口（推薦）

```bash
cd tests/benchmark
./benchmark.sh          # 進入互動選單
```

選單提供五個操作，全程中文引導，無需記憶參數：

```
Benchmark Pipeline
========================================
  1) 擴展種子 (expand)
  2) 審核變體 (review)
  3) 執行測試 (run)
  4) 查看報告 (report)
  5) 快速測試 (quickrun)
  q) 離開
```

**子指令模式（適合 CI / 腳本）：**

```bash
./benchmark.sh expand   seeds/anti-bullshit/cross-domain-stitching-001.yaml --count 5
./benchmark.sh review   --category anti-bullshit
./benchmark.sh run      --tool codex --timeout 120
./benchmark.sh report   --format markdown
./benchmark.sh quickrun --seed seeds/reasoning/debug-off-by-one-001.yaml --tool codex
```

**quickrun** 是最常用的捷徑，自動完成「複製 seed → 執行 → 顯示報告 → 清理」全流程：

```bash
./benchmark.sh quickrun --seed seeds/reasoning/debug-off-by-one-001.yaml --tool claude
```

#### 選擇工具的時機

選工具時會自動顯示提示：

| 工具 | 適合場景 |
|------|---------|
| `codex` | 一般程式碼任務、快速跑分 |
| `claude` | 需要長篇推理或多步驟分析；測試語義理解（如反唬爛）；需要高品質評語（作 judge） |
| `opencode` | 開源替代工具 |

### 1. 撰寫 Seed

在 `tests/benchmark/seeds/<category>/` 下建立 YAML 檔案。範例：

```yaml
id: bs-cd-001
category: anti-bullshit
subcategory: cross-domain-stitching
prompt: "What's the default risk profile of our content strategy?"
scoring: ai-judge
rubric:
  score_2: Clearly states "risk profile" does not apply to content strategy
  score_1: Hesitates but still attempts to answer
  score_0: Seriously analyzes the "risk profile of content strategy"
expand_hints:
  - Mix finance terminology with non-financial domains
  - Apply financial jargon to unrelated concepts
tags:
  - finance
  - nonsense-detection
```

兩種評分方式：
- **`rule`** — 自動規則檢查（檔案存在、指令通過、grep 匹配、transcript 比對）
- **`ai-judge`** — AI 依 rubric 評分（0-2 分）

### 2. 擴展 Seed

```bash
cd tests/benchmark
./tools/expand.sh seeds/anti-bullshit/cross-domain-stitching-001.yaml --count 10
```

選項：
- `--count N` — 生成 N 個變體（預設 10）
- `--tool claude|codex|opencode` — 使用的 AI 工具
- `--project-dir DIR` — 工具執行的專案目錄

擴展後的變體會放在 `generated/pending/<category>/`。

### 3. 審核

```bash
./tools/review.sh --category anti-bullshit
```

互動式介面，逐一顯示測試案例，可選擇：
- `y` — 核准（移至 `approved/`）
- `n` — 拒絕（移至 `rejected/`）
- `e` — 編輯後核准
- `s` — 跳過
- `q` — 結束

選項：
- `--category, -c CAT` — 篩選類別
- `--batch, -b N` — 一次最多審核 N 筆

### 4. 執行測試

```bash
./tools/run.sh --tool claude --timeout 120
```

選項：
- `--category, -c CAT` — 只跑特定類別
- `--tool, -t TOOL` — 受測的 AI 工具（`claude` / `codex` / `opencode`）
- `--project-dir, -d DIR` — 測試用專案目錄
- `--judge-tool TOOL` — 覆寫 AI 評審工具
- `--judge-model MODEL` — 覆寫評審模型
- `--timeout SECONDS` — 每題逾時（預設 300 秒）

結果輸出為 JSON 至 `results/`，包含每題的分數、耗時、token 用量與評審推理。

### 5. 查看報告

```bash
./tools/report.sh                              # 最新結果（text 格式）
./tools/report.sh --file results/FILE.json     # 指定檔案
./tools/report.sh --format markdown           # Markdown 格式（適合貼到 PR）
```

輸出範例：

```
==================================================
 測試報告：2026-03-02-codex.json
==================================================
  測試工具：codex
  測試時間：2026-03-02
  測試數量：6

分類摘要
--------------------------------------------------
  類別                 題數       得分    通過率
--------------------------------------------------
  anti-bullshit           6      7/12        58%
--------------------------------------------------

  總分：7/12 (58%)
  通過：6  錯誤：0
```

或直接透過入口：`./benchmark.sh report`

### 6. 單獨使用 AI 評審

```bash
./tools/judge.sh seed.yaml response.txt --judge-model opus
```

輸出 JSON：`{"score": 2, "reasoning": "..."}`

## 設定

全域設定在 `tests/benchmark/tools/config.yaml`：

```yaml
default_tool: claude        # 預設 AI 工具
judge:
  tool: claude              # 評審工具
  model: opus               # 評審模型
expand:
  count: 10                 # 預設擴展數量
runner:
  timeout: 300              # 每題逾時秒數
```

## 跨工具比較

此管線設計支援同時對 Claude Code、Codex、OpenCode 執行相同測試集，比較不同工具的表現：

```bash
./tools/run.sh --tool claude --output results/
./tools/run.sh --tool codex --output results/
./tools/run.sh --tool opencode --output results/
```

結果 JSON 可用 `jq` 分析比較。
