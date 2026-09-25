# 🏛️ L0～L5 全棧穿透架構設計白皮書 (PHANTOM GRID Sovereign Architecture)

> **架構代號**: `PHANTOM-GRID-CYBER-PHYSICAL-SOVEREIGNTY`  
> **統帥**: `Jack Hu (jackhu24-ship-it)`  
> **戰隊**: `PHANTOM GRID (Solo / 一人成軍)`  

---

## 1. 六層縱深全景拓撲結構 (L0～L5)

```text
+-------------------------------------------------------------------------------+
| L5: 機隊去中心化與雲邊混合路由 (Fleet Decentralized Mesh & Hybrid Routing)    |
|     - fleet_nostr_mesh.py: NIP-01/NIP-78 Kind 30078/30079 加密廣播全感知       |
|     - edge_cloud_hybrid_router.py: 邊緣 ASIL-D (<1ms) / 診斷 (<50ms) / 雲端   |
+-------------------------------------------------------------------------------+
                                      |
                                      v
+-------------------------------------------------------------------------------+
| L4: 車載 MCP 工具介面與 Agent 協同 (In-Vehicle MCP JSON-RPC Server)          |
|     - vehicle_mcp_server.py: get_digital_twin_telemetry, query_audit_trail   |
|     - trigger_emergency_derate: 自然語言交互 + HITL 雙簽 (Commander+Agent)   |
+-------------------------------------------------------------------------------+
                                      |
                                      v
+-------------------------------------------------------------------------------+
| L3: 邊緣自主修復閉環 (Edge Autonomous Healing Engine)                         |
|     - autonomous_healer.py: UDP 30490 監聽 SOME/IP Service 0x1002 Event 0x8002 |
|     - 三階防禦: Level 1 (75°C 70%), Level 2 (85°C 50%), Auto Recovery (<60°C 100%)|
|     - audit_governance.py: audit_log.db / audit_logs 審計資料庫不可篡改存證   |
+-------------------------------------------------------------------------------+
                                      |
                                      v
+-------------------------------------------------------------------------------+
| L2: 訊號轉服務與數位孿生鏡像 (Signal-to-Service SOA Gateway & Digital Twin)   |
|     - soa_gateway_twin.py: CAN 點對點原始數據流 ➔ 以太網 UDP SOME/IP 服務化轉譯|
|     - digital_twin_state.py: 記憶體轉速、電壓、溫度、降額與健康評分即時同步   |
+-------------------------------------------------------------------------------+
                                      |
                                      v
+-------------------------------------------------------------------------------+
| L1: 分散式三節點總線集群與狀態機 (Distributed CAN Multi-Node Cluster)        |
|     - multi_node_cluster.py: 主控網關 (0x080/0x120), 動力致動 (0x280), 感測 (0x380)|
|     - ISO 26262 狀態機: 3 幀錯誤切入 STATE_DEGRADED; Bus-Off 0ms PWM 斷開    |
|     - 階梯恢復: 100ms 快速重啟 (3 次) ➔ 1000ms 慢速重啟退避防 babbling       |
+-------------------------------------------------------------------------------+
                                      |
                                      v
+-------------------------------------------------------------------------------+
| L0: 輕量級 C 驅動與 UDS 刷寫狀態機 (Lightweight Embedded C Engine)            |
|     - e2e_crc8_driver.c: SAE J1850 CRC8 查表法 + Alive Counter 滾動封裝       |
|     - uds_bootloader_fsm.c: ISO 14229 服務棧 + A/B 滾動鏡像 2.3ms 斷電回滾   |
+-------------------------------------------------------------------------------+
```

---

## 2. 三辦公室體系與極速作戰哲學

1. **第一辦公室（戰術研發鍛造廠）**：
   - 核心驅動、狀態機、數學模型與單元測試（pytest）。
   - 100% 全綠 PASS 立即觸發憲法第 12 條自動交棒第三辦公室。
2. **第二辦公室（戰情監控與全景拓撲）**：
   - Streamlit 戰情儀表板（`dashboard.py`）、SSE 毫秒級即時串流、Mermaid 架構圖展台。
3. **第三辦公室（落地模組工廠與考驗驗收）**：
   - 方案 B 影片合成、極限混沌壓測（Chaos Verifier）、官方認證頒發、免安裝發布包與 CapCut Web Studio 彈藥庫。
   - 收工即回流 G 槽真身金庫總庫，嚴格守護 Zero-Desktop Pollution。

