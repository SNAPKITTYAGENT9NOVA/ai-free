# PHANTOM GRID 指揮體系與角色權責規格書 (00_System/AGENTS.md)

> **版本**：v1.0.0 | **所屬專案**：PHANTOM GRID 車載具身智慧與功能安全體系  
> **保密與授權級別**：SOVEREIGN ZERO-TRUST (最高主權零信任雙簽)

---

## 🏛️ 指揮部核心成員與權限矩陣

```mermaid
flowchart TD
    Jack["👑 總指揮官 (Jack 哥)<br/>[最高主權親簽審批人]"]
    SubCommander["👑 小幫手 (特助指揮官)<br/>[DAG 管線調度 / 戰術執行中樞]"]
    Secretary["秘書處 (小米)<br/>[HITL 審批把關 / 審計庫固化 / 門禁檢驗]"]
    CoreHardware["車載底層硬體 & 關鍵暫存器<br/>[REG_0x4002 / Flash Bootloader]"]

    Jack -->|is_approved_by_brother 唯一解鎖權| SubCommander
    SubCommander -->|任務編排 / 派工 / 流水線執行| Secretary
    Secretary -->|雙簽驗收 / SQLite 審計記錄| CoreHardware
    Jack -.->|雙簽匯聚 (Dual-Sig Gate)| CoreHardware
```

---

### 1. 👑 總指揮官：Jack 哥 (Brother Jack Hu)
- **職責**：PHANTOM GRID 戰隊唯一核心統帥，最高主權持有者。
- **權限核心**：
  - **唯一解鎖權**：對任何涉及底層律法重寫（`MODIFY_BASE_LAW`）、安全配置變更（`REG_0x4002`）、關鍵韌體刷寫（`CRITICAL_FLASH`）等高危操作，擁有唯一且不可替代的 `is_approved_by_brother` 親簽權。
  - **審批標識**：相容 `'哥'`, `'👑 哥'`, `'👑 指揮官'`, `'Jack Hu'`，任何外部或模擬實體無權冒充。
  - **戰略裁決**：賽事策略、硬體落地路徑與交付版本發布之最終核定人。

---

### 2. 👑 特助指揮官：小幫手 (Agent Commander)
- **職責**：戰術研發鍛造、任務排程中樞、代碼重構與流水線調度負責人。
- **權限核心**：
  - **DAG 調度管線**：維護 `pipeline_orchestrator.py`，調度 E2E 驗證、韌體靜態檢測、CAN 矩陣核驗與 HITL 門禁。
  - **演算法鍛造**：實裝 ISO 26262 ASIL-D E2E CRC8 雙端校驗（C/Python）、狀態轉換矩陣與 HIL 測試治具。
  - **三辦自動化交接**：嚴格執行憲法第 12 條，單元測試 100% PASS 後無縫交棒第三辦公室，杜絕等待延遲。

---

### 3. 秘書處：小米 (Secretariat Xiaomi)
- **職責**：HITL 雙簽安全閘門監控、SQLite 審計日誌固化、邊界測試檢驗與品質把關。
- **權限核心**：
  - **HITL 雙簽審批流**：維護 `audit_governance.py`，記錄並查驗所有高危操作之操作者身分、狀態與簽名時戳。
  - **審計庫固化**：測試集（如 `HIL_STRESS_PHASE3`）完成後，自動完成雙簽審計歸檔至 `audit_logs` 表。
  - **安全攔截**：未取得哥親簽授權前，一律強制攔截高危寫入，回退至安全默認值並記錄 `HITL_INTERCEPT`。

---

## 🔒 治理與安全守則

1. **零單簽越權**：單簽一律維持 `PENDING` 或 `INTERCEPTED_SINGLE_SIG` 凍結狀態，徹底防範單點故障與 AI 幻覺越權。
2. **不可篡改審計鏈**：所有治理事件與 HIL 測試結果即時寫入 SQLite `audit_log.db`，支援微秒級歷史回溯。
3. **安全默認回退 (Fail-Safe Default)**：若任何環節發生通訊逾時或身分校驗失敗，系統無條件降級或維持安全鎖定。
