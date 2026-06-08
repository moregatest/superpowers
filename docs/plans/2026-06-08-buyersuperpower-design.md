# buyersuperpower 設計（首期垂直切片）

> 把 superpowers（給 coding agent 的紀律化技能框架）改造成 **buyersuperpower**：
> 服務各國 B2B 買家本人的 AI 國際採購顧問。

## 1. 目標

保留 superpowers 的「自動觸發技能 ＋ 跨平台散佈 ＋ 可量測 benchmark」架構，
把內容換成「**找供應商 → 防詐 → 整理採購建議 → 協助下單**」，並新增一個用
**Playwright 抓供應商官網**的工具層。首期只做一條走得通、單獨就有價值的垂直切片。

## 2. 鎖定的決策（brainstorming 結論）

| 議題 | 決定 |
|---|---|
| 本質 | **改造技能庫、保留架構**（不是新做 app，也不是嵌入 Ready Market 既有平台） |
| 服務對象 | **B2B 買家本人**（未必懂國際貿易）→ skill 要「一步步引導 ＋ 主動防詐」 |
| 國際化 | 全做：**多語言對話 / 進口國法規認證 / 來源國供應商情報 / 跨境金流物流** |
| 供應商搜尋 | **混合**：真實抓取 ＋ 引導；**可插拔 provider**，預設 Playwright，未來接 Ready Market API |
| 首期範圍 | **垂直切片**：bootstrap ＋ 4 個 skill |
| 核心流程 | **Google 找官網 → Playwright 抽潛力商品 → 整理採購建議文件 → 問是否下單** |

## 3. 架構

### 3.1 保留（機制完全不動）
- `hooks/session-start` 注入機制 → 改注入 `using-buyersuperpower`
- 自動觸發模型（skill 的 `description: Use when…` ＋ `Skill` 工具載入）
- 四平台包裝（`.claude-plugin` / `.cursor-plugin` / `.codex` / `.opencode`）
- `skills/writing-skills`（meta，領域中立）→ 用來生產更多 buyer skill
- `tests/benchmark/` 管線（只換 seed 情境）
- `lib/skills-core.js`

### 3.2 新增（工具／資料層 — 與原版最大不同）
部分 skill 從「純文件」升級成「會呼叫工具抓真實資料」：
- **供應商搜尋 provider（可插拔）**：預設 `playwright`；`mock`（測試）；`readymarket-api`（未來 stub）
- `tools/search-suppliers.sh`：依 config 選 provider，統一輸入／輸出 JSON 契約
- `lib/providers/*.mjs`：各 provider 實作

### 3.3 改寫（內容）
- `skills/` 新增 5 個 buyer skill（bootstrap ＋ 4）
- plugin 身分改名 `buyersuperpower`，版本歸零 `0.1.0`（`plugin.json` / `marketplace.json` / 各平台描述）
- `hooks/session-start` 注入 `using-buyersuperpower`
- `tests/benchmark/seeds/` 改成買家類別

### 3.4 多語言（設計決定）
- skill 文件仍以**英文**撰寫（agent 面向指令＝單一真相來源、好維護）
- 由 bootstrap 下指令：**偵測買家語言 → 全程用買家母語對話；關鍵貿易術語雙語並陳（母語＋英文）；對供應商的產出（詢價信）用英文**
- 與現有 benchmark「skill 英文、卻能跑中文」同一招

### 3.5 分層圖
```
[session-start hook] ──注入──► using-buyersuperpower
                                （顧問人格／偵測買家語言／先釐清再行動／主動防詐／skill 觸發規則）
        │ 自動觸發
        ▼
[Buyer Skills 文件層]  clarifying-sourcing-need · finding-suppliers · vetting-suppliers · placing-order
        │ finding／vetting 會呼叫 ↓
        ▼
[工具／資料層（新增）]
 tools/search-suppliers.sh ──選 provider──► playwright.mjs（預設：開瀏覽器抽官網商品）
                                          ├► mock.mjs（測試：回罐頭候選）
                                          └► readymarket-api.mjs（未來：查 Ready Market DB）
 統一輸入／輸出 JSON 契約；skill 只認契約，換後端不改 skill
```

## 4. 元件：bootstrap ＋ 4 個 skill

每個 skill＝`skills/<name>/SKILL.md`，frontmatter 只有 `name` ＋ `description`（`Use when…` 觸發條件，不寫流程摘要）。

### 4.0 `using-buyersuperpower`（注入用的操作框架）
放 `skills/using-buyersuperpower/SKILL.md`，由 `session-start` 讀取注入（與原版 using-superpowers 同模式）。內容：
- **人格**：你是替買家著想的資深國際採購顧問
- **鐵則**：① 先釐清再行動 ② **主動防詐** ③ 找不到就說找不到（反唬爛、不捏造）④ 聯絡供應商／下單前**一定要買家明確確認** ⑤ **絕不自動付款、不外洩買家敏感資料**
- **多語言**：偵測並用買家母語；關鍵貿易術語雙語
- **可用 buyer skills 觸發表** ＋ 沿用 superpowers 的「1% 機率就載入 skill」規則

### 4.1 `clarifying-sourcing-need`
- **description**：Use when a buyer wants to source / buy / import a product but specs, quantity, destination, certifications, or budget aren't pinned down yet
- **職責**：一次一題逼出採購條件（產品、規格、MOQ／月量、目的國、必備認證、目標價、交期、來源國偏好）
- **國際化掛點**：依目的國主動提示必備認證（墨西哥 NOM、歐盟 CE、美國 FCC/UL、英國 UKCA…）
- **輸出**：`criteria` JSON（餵給 finding-suppliers）

### 4.2 `finding-suppliers`（主角，用工具）
- **description**：Use when a sourcing need is defined and it's time to find real manufacturers / suppliers
- **流程**：
  1. 用 agent 的 **web 搜尋工具**找供應商**官網**（過濾掉 alibaba / made-in-china / globalsources 等平台與目錄；必要時用來源國語言加搜）
  2. 呼叫 `tools/search-suppliers.sh extract --urls <清單> --criteria <json>` → **Playwright** 開官網抽**有潛力商品**
  3. **套用 `vetting-suppliers` 規則**（不寫死成「呼叫另一個 skill」——而是「**推薦任何供應商前，必須載入並套用 vetting-suppliers**」，因各平台 skill 互叫能力不一）
  4. 判斷「有潛力」＝符合規格／MOQ／價格區間
  5. 整理成**採購建議文件**（見 §6）
- **輸出**：採購建議文件（markdown），呈現給買家

### 4.3 `vetting-suppliers`（用工具，防詐核心）
- **description**：Use when recommending or contacting any supplier — verify legitimacy and screen for fraud signals
- **紅旗**：無實體地址、只用免費信箱、網域剛註冊、價格低到不合理、無營業執照／認證、盜圖、要求全額 T/T 匯個人帳戶
- **工具**：Playwright 拉官網 about／contact／cert 頁；網域年齡（whois，可選）
- **輸出**：每家 `{ riskLevel: low|medium|high|unknown, confidence: low|medium|high, signals[], reasons[] }`
  - `confidence` 與 `riskLevel` 分離：官網資訊不足 ≠ 詐騙，但 confidence 低就**不能當 low risk 推薦**
- **推薦決策矩陣**：

  | riskLevel | 進推薦區？ |
  |---|---|
  | low | ✅ 可進推薦 |
  | medium | ✅ 可進推薦，**但必須標示待確認事項** |
  | high | ❌ 只進「⚠️謹慎／已排除」 |
  | unknown | ❌ 不進推薦，**除非買家明確要求人工追查** |

### 4.4 `placing-order`（協助發起下單）
- **description**：Use when the buyer wants to proceed with a shortlisted supplier — initiate contact, send an inquiry / RFQ, or move toward an order
- **流程**：把採購建議文件給買家 → 問選哪幾家 → 擬**英文詢價／採購意向信**（含需求摘要、要求報價條件 FOB/EXW、樣品、MOQ、交期、認證）
- **保護**：明確告知這是**詢價非綁定訂單**；**不自動付款**；聯絡供應商前要買家**明確確認**
- **註**：官網通常不能直接結帳，故「下單」的起點＝送出詢價／採購意向

## 5. 供應商搜尋 provider 契約

### 5.1 介面
`tools/search-suppliers.sh <op> [args]`，`op ∈ { extract, search }`
- `extract`：輸入官網 URL 清單 ＋ criteria → 抽商品（**Playwright provider 主力**）
- `search`：輸入 criteria → 直接回供應商（含商品）（**Ready Market provider 主力**；Playwright 可選做 discover fallback）

### 5.2 輸入
```jsonc
// criteria
{ "product": "...", "keywords": ["..."], "destinationCountry": "MX",
  "sourceCountries": ["CN","VN"], "moq": 500, "certs": ["NOM"],
  "targetPrice": { "min": 0, "max": 0, "currency": "USD" }, "limit": 10 }
// urls（extract 用）
["https://example-factory.com", "..."]
```

### 5.3 輸出（stdout JSON）
```jsonc
{ "provider": "playwright",
  "suppliers": [
    { "name": "...", "officialSite": "https://...", "country": "CN",
      "companyInfo": "...",
      "evidence": [ { "type": "contact_page", "url": "https://...", "text": "..." },
                    { "type": "cert_page",    "url": "https://...", "text": "..." } ],
      "products": [ { "name": "...", "specs": {}, "moq": 500,
                      "priceHint": "...", "url": "https://...", "image": "https://...",
                      "evidence": [ { "type": "product_page", "url": "https://...", "text": "..." } ] } ],
      "extractionNotes": "..." } ],
  "notes": "..." }
```

> **每筆 supplier／product 都帶 `evidence`（來源頁面 ＋ 原文片段）** → 支撐 anti-bullshit／anti-fraud 評分，並讓採購建議文件可查證。抽不到就不要硬填。

### 5.4 providers
- `lib/providers/playwright.mjs`（**預設**，**首期只實作 `extract`**；不做 `search`／`discover`——discovery 由 agent 的 web 搜尋負責，避免把搜尋品質與爬站品質綁在一起、也降低跨平台風險）
- `lib/providers/mock.mjs`（**測試**，回罐頭，實作 `extract` ＋ `search`）
- `lib/providers/readymarket-api.mjs`（**未來 stub**，實作 `search`）

### 5.5 config `tools/providers.config.yaml`
```yaml
default_provider: playwright
playwright:
  headless: true
  perSiteTimeoutMs: 20000
  maxPagesPerSite: 5
  rateLimitMs: 1500
  userAgent: "Mozilla/5.0 ..."
discovery:
  platformBlocklist: [alibaba.com, made-in-china.com, globalsources.com, ...]
```

## 6. 採購建議文件（核心產出）結構

以買家母語呈現（術語雙語）：
```
# 採購建議：<產品> → <目的國>
## 需求摘要        ← criteria 回顯（規格／MOQ／目標價／必備認證，術語雙語）
## ✅ 推薦供應商    ← 每家：官網連結｜公司簡介｜可信度(low risk)｜潛力商品表(型號/規格/MOQ/價格線索/連結)｜為何符合
## ⚠️ 謹慎／已排除  ← 可疑供應商 ＋ 原因（防詐透明化）
## 下一步          ← 要不要幫你對哪幾家發詢價／下單？
```

## 7. 錯誤處理與防詐

| 失效情境 | 處理方式 |
|---|---|
| Playwright 被官網擋／逾時 | 每站 timeout ＋ 重試一次、站間 rate-limit、換 UA；擋掉就記「無法擷取，附 URL 供人工查」，**不讓單站失敗拖垮整批** |
| 搜不到官網（結果全是平台） | 誠實說明 → 提議放寬關鍵字／用來源國語言再搜／問買家能否接受平台賣家；**絕不捏造供應商** |
| 可疑／資訊不足供應商 | 依 §4.3 推薦決策矩陣：**high／unknown 不進推薦**；medium 進推薦但標示待確認；一律附原因與 `evidence` |
| 官網找不到規格／價格／MOQ | 寫「官網未提供」，**不猜不編**（反唬爛） |
| 語言偵測不確定 | 直接問買家用哪個語言；關鍵術語一律雙語 |
| 下單前 | 明示「詢價非綁定」；**不自動付款**、不外洩買家資料；聯絡供應商前要買家明確確認 |

## 8. 測試

照 `writing-skills` 鐵律，**每個 skill 先做 RED 壓力基線 → 寫 skill → GREEN**。benchmark 管線留著，seed 類別改造：

| 原類別 | → buyer 類別 | 測什麼 |
|---|---|---|
| skill-compliance | **sourcing-compliance** | 會不會先 `clarifying-need` 才搜？會不會**先 vetting 才推薦**？ |
| anti-bullshit | **anti-bullshit**（留） | 官網沒寫的 MOQ／價格會不會硬編？ |
| （新增） | **anti-fraud** | 丟「好到不真實＋要求匯個人帳戶」的供應商，會不會擋進「已排除」區？ |
| code-implementation | **sourcing-quality** | 給需求，產出的採購建議文件結構是否完整、官網是否真實？ |
| reasoning | **reasoning**（留） | landed cost／匯率／規格比對算對沒？ |

**測試性關鍵設計：`mock` provider** — 測 `finding/vetting/placing-order` 時用罐頭候選，**不上線爬站**，結果可重現、CI 跑得動。
**Playwright provider 契約測試**：餵**本地 fixture HTML**（不打真站）→ 驗證輸出符合 §5.3 JSON 契約。

## 9. 首期 repo 變更清單（交給 writing-plans）

- **ADD**　`skills/{using-buyersuperpower, clarifying-sourcing-need, finding-suppliers, vetting-suppliers, placing-order}/SKILL.md`
- **ADD**　`lib/providers/{playwright.mjs, mock.mjs, readymarket-api.mjs}`、`tools/search-suppliers.sh`、`tools/providers.config.yaml`、`package.json`（playwright 依賴）
- **RETARGET**　`hooks/session-start`（注入 using-buyersuperpower）、`.claude-plugin/plugin.json`＋`marketplace.json`、`.cursor-plugin/plugin.json`、`.codex/INSTALL.md`、`.opencode/*`（改名 buyersuperpower、版本 0.1.0）
- **RETARGET**　`tests/benchmark/seeds/`（buyer 類別 ＋ mock provider 跑得動的 sourcing 情境）
- **KEEP**　`skills/writing-skills`（authoring）、`tests/benchmark/tools/`、`lib/skills-core.js`
- **DEFER（後續切片）**　刪除／封存其餘 dev skill；`comparing-quotes` 及下游（議價／條件／驗貨／物流／爭議）；`readymarket-api` 實作

> **PR 切分、落地順序、Definition of Done 見 §13。** 首期 = PR1（先交付）。

## 10. 不在首期範圍（YAGNI）
- `comparing-quotes` 及下游 buyer skill（比價要等供應商回詢價才做）
- Ready Market API provider 實作（只留 stub ＋ 契約）
- Playwright 的 `search`／`discover`（首期 Playwright 只 `extract`；discovery 由 agent web 搜尋）
- 刪除其餘 superpowers dev skill（先共存，bootstrap 只導向 buyer skill；風險低，留待清理切片）
- 真的下單付款（首期只到詢價／採購意向）

## 11. 全貌願景圖（脈絡，非首期）

| superpowers（開發） | → buyersuperpower（B2B 買家） |
|---|---|
| using-superpowers | **using-buyersuperpower**（首期） |
| brainstorming | **clarifying-sourcing-need**（首期） |
| —（新增） | **finding-suppliers**（首期） |
| —（新增） | **vetting-suppliers**（首期） |
| writing-plans | **writing-rfq** |
| —（新增） | **comparing-quotes** |
| requesting／receiving-code-review | **negotiating-with-suppliers** |
| —（新增） | **evaluating-samples** |
| —（新增） | **setting-trade-terms**（Incoterms＋付款＋合約） |
| test-driven-development／verification | **arranging-inspection**（驗貨／第三方 QC） |
| —（新增） | **managing-logistics-customs** |
| systematic-debugging | **handling-disputes** |
| writing-skills（meta） | **保留** |
| benchmark 管線 | **保留**（換 seed） |

## 12. 風險與待確認
- Playwright 依賴與瀏覽器安裝（`playwright install`）＝首期 setup 多一步
- 官網結構各異 → 抽取需通用啟發式（標題／規格表／價格樣式）＋ 容錯；首期先求「找到產品頁與連結」，規格盡力而為
- 跨平台 web 搜尋工具不一（Claude Code 有 WebSearch；其他平台需對應）→ 文件化工具映射
- 多語言品質依賴模型本身

## 13. 實作順序 · PR 切分 · Definition of Done

### 13.1 PR 切分（每個都是可交付 PR，依賴遞增）

**PR 1 — buyersuperpower 身份與 skill 骨架（首期先交付這個）**
- ADD `skills/{using-buyersuperpower, clarifying-sourcing-need, finding-suppliers, vetting-suppliers, placing-order}/SKILL.md`
- RETARGET `hooks/session-start`（注入 using-buyersuperpower）
- RETARGET plugin metadata（`.claude-plugin/plugin.json`＋`marketplace.json`、`.cursor-plugin/plugin.json`、`.codex/INSTALL.md`、`.opencode/*`，改名 buyersuperpower、版本 0.1.0）
- **順序**：先 bootstrap（using-buyersuperpower ＋ hooks ＋ metadata）→ 再 4 個 skill，優先序 `clarifying-sourcing-need → vetting-suppliers → finding-suppliers → placing-order`（finding 依賴前兩者、placing 最後才需要）
- **驗收**：session-start 注入成功；買家母語回覆；主動防詐；未確認不聯絡供應商

**PR 2 — provider 契約與 mock**
- ADD `tools/search-suppliers.sh`、`tools/providers.config.yaml`、`lib/providers/mock.mjs`、`lib/providers/readymarket-api.mjs`（stub）、provider 契約測試
- **驗收**：下列兩條穩定輸出 §5.3 JSON（含 `evidence`）：
  - `tools/search-suppliers.sh extract --urls urls.json --criteria criteria.json`
  - `tools/search-suppliers.sh search --criteria criteria.json`

**PR 3 — benchmark seed 改造（全吃 mock）**
- RETARGET `tests/benchmark/seeds/`：ADD `sourcing-compliance`、`anti-fraud`；RETARGET `anti-bullshit`、`sourcing-quality`、`reasoning`
- 每類 2–3 筆；最重要前三類
- benchmark 全跑 **mock** provider → skill 行為可 RED→GREEN，不被真站結構／網路不穩拖住

**PR 4 — Playwright extract provider**
- ADD `lib/providers/playwright.mjs`、`package.json`、本地 fixture HTML 測試、timeout／retry／rate-limit

> 順序理由：skills → mock provider → benchmark(on mock) → Playwright。benchmark 只依賴 mock，故排在 Playwright 前。

### 13.2 Playwright 首期範圍（PR 4，不要做太聰明）
- 輸入官網 URL → 抓首頁 → 找 `product / products / catalog / solutions` 類連結 → **最多走 5 頁**
- 抽 `title / h1 / h2 / table / price-like text / MOQ-like text / image`
- 輸出符合 §5.3 契約的 suppliers JSON
- 首期目標＝「**找到產品頁與連結**」；規格／MOQ／價格**有就抽，沒有就明確 `null` 或「官網未提供」**，不捏造

### 13.3 Definition of Done（首期完成標準）
1. session-start 成功注入 using-buyersuperpower
2. 買家用中文或西文詢問採購需求時，agent 用**買家語言**回覆
3. criteria 不完整時，agent **先問問題**，不直接搜
4. criteria 完整時，agent 找官網並**排除平台型結果**
5. mock provider 可回供應商與商品 JSON（**含 evidence**）
6. `finding-suppliers` 產出完整採購建議文件
7. 推薦前**一定有 vetting 結果**
8. **high／unknown risk** 供應商只出現在謹慎／已排除區
9. 官網沒有 MOQ／price／cert 時**不捏造**
10. `placing-order` 只產生英文 RFQ 草稿，**不自動聯絡、不自動付款**
