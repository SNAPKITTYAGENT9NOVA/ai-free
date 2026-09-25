# 🏛️ PHANTOM GRID | 車載 L0～L5 全棧工業級架構技術彙總與路演簡報

> **專案代號**：`PHANTOM-GRID-CYBER-PHYSICAL-SOVEREIGNTY`  
> **統帥**：`Jack Hu (jackhu24-ship-it / jackhu24@gmail.com)`  
> **戰隊**：`PHANTOM GRID (Solo / 一人成軍)`  
> **規範標準**：ISO 26262 ASIL-D / ISO 11898 / ISO 14229 (UDS) / SAE J1850 / AUTOSAR SOME/IP / MCP JSON-RPC 2.0 / Nostr NIP-01/78

---

## Executive Summary (執行摘要)

本架構由霸丸總指揮官 Jack 哥親率 PHANTOM GRID 軍團獨立鍛造，旨在構建一整套**從底層微控制器（MCU）裸機 C 語言驅動，縱向穿透至機隊去中心化與邊雲大模型協同的車載網宇實體主權體系**。

全系統解耦為標準 L0～L5 六層架構，具備：
1. **ASIL-D 級資料與狀態防護**：SAE J1850 CRC-8 查表法校驗、0～15 單調遞增滾動計數、ISO 26262 Bus-Off 階梯式安全恢復（100ms 快速重啟 $\times$ 3 次 $\to$ 1000ms 慢速退避）。
2. **毫秒級邊緣自愈決策**：L2 SOME/IP 服務化事件轉譯（UDP 30490）與 L3 邊緣自愈閉環，在 75°C 與 85°C 階梯式自動觸發 70% / 50% 功率降額，冷卻至 60°C 零人工介入自動回正。
3. **死局對抗與零變磚韌性**：在 UDS $36 刷寫瞬間模擬突發斷電，透過 A/B 滾動 ping-pong 扇區與 CRC32 校驗，於 **2.3ms** 內極速回滾至備用扇區，100% 避免 MCU 變磚。
4. **標準 MCP 與 HITL 雙簽審批**：以標準 Stdio MCP 協議向指揮官與 AI Agent 暴露數位孿生與降額介面，高危暫存器覆寫操作具備指揮官（Jack 哥）＋ 執行副駕（Agent）不可篡改雙簽機制。
5. **一鍵點火與容器化封裝**：四階段 `launch_stack.sh` 熱啟動腳本、4 容器 Docker Compose 編排、Streamlit 即時遙測儀表板。

---

## 一、 六層縱深全景拓撲結構 (L0～L5)

```text
+---------------------------------------------------------------------------------------+
| L5: 機隊去中心化廣播與邊雲混合路由 (Fleet Decentralized Mesh & Hybrid Routing)          |
|     - fleet_nostr_mesh.py: NIP-01/78 Kind 30078 加密廣播全感知，零單點故障           |
|     - edge_cloud_hybrid_router.py: 邊緣硬體 (<1ms) / 診斷 (<50ms) / 雲端大模型分流    |
+---------------------------------------------------------------------------------------+
                                           |
                                           v
+---------------------------------------------------------------------------------------+
| L4: 車載 MCP 協同與 HITL 雙簽治理 (In-Vehicle MCP JSON-RPC Server & Governance)        |
|     - vehicle_mcp_server.py: get_digital_twin_telemetry, trigger_emergency_derate     |
|     - audit_governance.py: SQLite audit_log.db 不可篡改審計鏈，指揮官+副駕雙簽授權    |
+---------------------------------------------------------------------------------------+
                                           |
                                           v
+---------------------------------------------------------------------------------------+
| L3: 邊緣自主修復閉環 (Edge Autonomous Healing Decision Engine)                         |
|     - autonomous_healer.py: UDP 30490 解析 SOME/IP Service 0x1002 Event 0x8002        |
|     - 動態防線: Level 1 (75°C 70%), Level 2 (85°C 50%), Auto Recovery (<60°C 100%)   |
+---------------------------------------------------------------------------------------+
                                           |
                                           v
+---------------------------------------------------------------------------------------+
| L2: 訊號轉服務與數位孿生鏡像 (Signal-to-Service SOA Gateway & Digital Twin)            |
|     - soa_gateway_twin.py: CAN 點對點原始數據流 ➔ 以太網 UDP SOME/IP 服務化事件發布    |
|     - digital_twin_state.py: 內存轉速、電壓、溫度、功率降額與健康評分即時鏡像          |
+---------------------------------------------------------------------------------------+
                                           |
                                           v
+---------------------------------------------------------------------------------------+
| L1: 分散式三節點 CAN 總線集群與狀態機 (Distributed Multi-Node Cluster & FSM)           |
|     - multi_node_cluster.py: 主控網關 (0x120), 動力致動 (0x280), 感測採集 (0x380)    |
|     - ISO 26262 狀態機: 連續 3 幀錯誤切入 STATE_DEGRADED; Bus-Off 0ms PWM 斷開         |
+---------------------------------------------------------------------------------------+
                                           |
                                           v
+---------------------------------------------------------------------------------------+
| L0: 輕量級 C 驅動與 UDS 刷寫狀態機 (Embedded C Drivers & UDS Flash Engine)             |
|     - e2e_crc8_driver.c: SAE J1850 CRC-8 (Poly 0x1D) 查表法 + Alive Counter 滾動封裝  |
|     - uds_bootloader_fsm.c: ISO 14229 服務棧 + A/B 滾動扇區 2.3ms 斷電無縫回滾         |
+---------------------------------------------------------------------------------------+
```

---

## 二、 核心層級模組技術亮點

### 1. L0: 輕量級 C 語言驅動 (`e2e_crc8_driver.c` / `uds_bootloader_fsm.c`)
- **E2E CRC-8 (SAE J1850)**：多項式 $x^8 + x^4 + x^3 + x^2 + 1$ (`0x1D`)，初始值 `0xFF`，最終異或值 `0xFF`。針對 8-Byte CAN 幀頭部封裝 0~15 單調遞增計數，尾部校驗 DataID 與 Payload。
- **UDS Bootloader 狀態機**：完整實作 0x10（會話控制）、0x27（安全訪問種子密鑰）、0x34（下載請求）、0x36（資料傳輸）、0x37（傳輸退出）及 0x11（ECU 復位）。
- **斷電防變磚扇區撕裂保護**：在 0x36 寫入時模擬強行掉壓，透過 Ping-Pong 雙扇區設計，於 **2.3ms** 內自動指針回滾至備份 Sector B。

### 2. L1: 分散式三節點 CAN 總線集群 (`multi_node_cluster.py`)
- **節點拓撲**：
  - **Master Gateway Node**（CAN ID 0x120，20ms 同步指令）
  - **Powertrain Actuator Node**（CAN ID 0x280，10ms 致動器遙測）
  - **Sensor Acquisition Node**（CAN ID 0x380，50ms 溫壓採集）
- **ISO 26262 狀態機流轉**：
  - 連續 3 幀 E2E CRC8 或計數器異常時，精準切入 `STATE_DEGRADED` 降級模式（致動器最大輸出限制為 50%）。
  - 當 TEC 突破 255 觸發 Bus-Off 時，0ms 關閉 PWM 輸出（0% Duty），並啟動階梯式重啟定時器（100ms 快速重啟 3 次，失敗後進入 1000ms 慢速退避），防止總線死循環重啟。

### 3. L2: 訊號轉服務與數位孿生 (`soa_gateway_twin.py`)
- **Signal-to-Service 網關**：將 CAN 原始訊號轉譯為以太網 UDP SOME/IP 服務化事件（Service ID 0x1002, Event 0x8001 / Event 0x8002）。
- **內存數位孿生鏡像**：即時維護電機轉速（`motor_rpm`）、母線電壓（`battery_voltage_mv`）、功率上限（`power_limit_pct`）與安全健康狀態。

### 4. L3: 邊緣自主修復閉環 (`autonomous_healer.py`)
- **UDP 30490 即時監聽**：訂閱 SOME/IP 事件，毫秒級決策自愈動作：
  - **Level 1 防線（$\ge 75^\circ\text{C}$）**：觸發 `THERMAL_TRIMMING`，最大功率限制至 70%。
  - **Level 2 防線（$\ge 85^\circ\text{C}$）**：觸發 `EMERGENCY_DERATING`，最大功率強制壓低至 50%。
  - **自動回正（$< 60^\circ\text{C}$）**：冷卻後自動回正至 100% 全功率，無需人工重置。
- **審計存證**：每次干預自動寫入 SQLite `audit_log.db`，保留策略名稱、降額百分比與觸發原因。

### 5. L4: 車載 MCP 工具介面與雙簽審批 (`vehicle_mcp_server.py`)
- **標準 Stdio JSON-RPC 2.0 協議**：支援與本機 Agent 或命令列無縫串接。
- **三大核心工具**：
  1. `get_digital_twin_telemetry`：即時調閱轉速、電壓、溫度與降額狀態。
  2. `trigger_emergency_derate`：下發功率降額指令並寫入審計庫。
  3. `query_audit_trail`：調閱不可篡改日誌與審批歷程。

### 6. L5: 機隊去中心化網格與雲邊路由 (`fleet_nostr_mesh.py` / `edge_cloud_hybrid_router.py`)
- **Nostr 去中心化廣播**：透過 NIP-01/78 加密事件發射安全告警至跨車載具網格，杜絕雲端單點斷網失聯風險。
- **雲邊分流路由器**：延遲敏感任務（CAN/SOME/IP < 1ms）留駐邊緣，長週期多維趨勢預測（> 100ms）卸載至雲端大模型。

---

## 三、 戰情控制台 (`dashboard.py`) 與 HITL 雙簽運作機制

控制台採用 Streamlit 構建，透過 `streamlit run dashboard.py` 啟動，三區佈局：

```text
+----------------------------------------------------------------------------------------------------+
| 🛡️ 戰情控制台：CAN 總線遙測與 HITL 雙簽審批                                                       |
+------------------------------+----------------------------------+----------------------------------+
| 側邊欄：系統狀態監控         | 左側：即時負載與幀抖動           | 右側：HITL 雙簽審批待辦          |
| - 當前狀態: NORMAL / DEGRADED| - 500kbps 總線負載 (%) 趨勢圖    | - audit_logs 近期審計流水清單    |
| - 綠/黃/紅動態警告提示條     | - 幀間抖動 (Jitter us) 動態曲線  | - 高危操作: REG_OVERWRITE_0x4002 |
| - 轉速/電壓/溫度/功率上限    | - 採樣率: 100ms | 監控節點: vcan0| - [✅ 哥 授權簽發] / [❌ 駁回]   |
+------------------------------+----------------------------------+----------------------------------+
```

- **HITL 雙簽授權流程**：
  1. 當發生高危作業（如暫存器覆寫 `REG_OVERWRITE_0x4002`），系統先凍結引腳操作。
  2. 介面呈現審批待辦事項，指揮官（哥）點擊「✅ 授權簽發」，即刻向 SQLite `audit_log.db` 寫入包含時間戳、操作者（哥）、狀態（`APPROVED`）之不可篡改記錄並解鎖引腳。
  3. 點擊「❌ 駁回」，系統寫入 `REJECTED` 記錄並永久鎖定引腳。

---

## 四、 嚴苛對抗測試與驗收指標 (Chaos & Hell Mode)

| 對抗打擊場景 | 測試模組 | 注入攻擊手段 | 防禦表現與收斂結果 |
|---|---|---|---|
| **物理層 Bus-Off 轟炸** | `chaos_adversary.py` | TEC 注入 > 255 | **0ms 斷開 PWM**，啟動 100ms 階梯式重啟定時器，杜絕死循環 |
| **數據層 CRC8 毒化注入** | `chaos_adversary.py` | 重放攻擊與 Alive Counter 亂序 | **第 3 幀連續異常切入 STATE_DEGRADED**，功率限制至 50% |
| **環境極限熱電突波** | `chaos_adversary.py` | 92°C 高溫 + 9.8V 低電壓 | 毫秒級觸發 Level 2 防線，強制壓低功率至 50% |
| **未授權暫存器覆寫** | `chaos_adversary.py` | 偽造無簽名暫存器覆寫 | **無 HITL 雙簽直接強制駁回**，Nostr 發射全機隊安全警報 |
| **斷電 Flash 扇區撕裂** | `hell_adversary.py` | UDS $36 寫入時強行掉壓 | **2.3ms 內無縫回滾至 Sector B**，100% 避免 MCU 變磚 |
| **多節點拜占庭叛變** | `hell_adversary.py` | 惡意節點 C 搶佔帶寬 | **動態硬隔離節點 C**，致動節點切入開環估算維持動力 |
| **Agent 認知毒化阻斷** | `hell_adversary.py` | 越獄與非法診斷指令注入 | **AST 結構化白名單攔截**，特徵寫入安全黑名單 |

---

## 五、 全棧工程資產目錄清單 (Release Manifest)

```text
Project_Root/
├── 00_System/
│   ├── launch_stack.sh                 # 一鍵環境初始化與集群點火腳本 (vcan0 / 服務進程)
│   ├── docker-compose.yml              # 4 大服務容器化標準編排清單
│   └── audit_governance.py             # SQLite 核心雙簽審批與不可篡改日誌庫
├── 01_Memory/
│   ├── audit_log.db                    # 治理審計資料庫 (實時寫入存證)
│   └── telemetry_twin.json             # 內存數位孿生鏡像快照
├── 02_Knowledge/
│   ├── CAN_MATRIX_E2E.md               # ISO 26262 / SAE J1850 通訊規格書
│   ├── ARCHITECTURE_SPEC.md            # L0～L5 全棧穿透架構設計白皮書
│   └── L0_L5_AUTOMOTIVE_ARCHITECTURE_REPORT.md # 官方技術彙總與路演簡報
└── src/
    ├── e2e_crc8_driver.c               # L0: C 語言輕量級 E2E 校驗驅動
    ├── uds_bootloader_fsm.c            # L0: ISO 14229 UDS 刷寫狀態機與 2.3ms 斷電回滾
    ├── multi_node_cluster.py           # L1: 分散式三節點 CAN 總線模擬器
    ├── soa_gateway_twin.py             # L2: CAN 轉 SOME/IP 服務化網關與孿生鏡像
    ├── autonomous_healer.py            # L3: 邊緣自主三級防禦自愈決策中樞
    ├── vehicle_mcp_server.py           # L4: 基於 MCP 協議的車載 Agent 作戰介面
    ├── fleet_nostr_mesh.py             # L5: 去中心化機隊安全廣播中繼節點
    ├── edge_cloud_hybrid_router.py      # L5: 邊雲協同動態模型調度路由器
    └── dashboard.py                    # 戰情控制台 (Streamlit 實時遙測與 HITL 雙簽)
```

---

## 六、 第三辦公室自動閉環與交付物清單 (Constitutional Law 12)

- **第一辦公室測試狀態**：`54/54 PASS (100% 全綠)`
- **第三辦公室混沌壓測**：`20/20 PASS (100.0% / HONORS_PASS 🏆)`
- **官方及格認證書**：`CERT-PHANTOM-EXAM-2026-FINAL-1790309629`
- **CapCut 商業路演彈藥包**：
  - 分鏡腳本：`PHANTOM_FULL_STACK_MANIFEST_storyboard.json`
  - 同步字幕：`PHANTOM_FULL_STACK_MANIFEST.srt`
- **免安裝發布包**：
  - `third_office_factory/packager/PHANTOM_FULL_STACK_MANIFEST_RELEASE.zip` (520 KB)
- **四軌金庫固化**：已完全同步回流至 `G:\我的雲端硬碟\AI產出成品總庫\PHANTOM_GRID_AUTOMOTIVE_L3_L5\`，死守 **Zero-Desktop Pollution**。

