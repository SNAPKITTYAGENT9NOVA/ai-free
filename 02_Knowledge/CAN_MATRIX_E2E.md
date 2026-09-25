# 🚗 ISO 26262 / SAE J1850 CAN 通訊矩陣與 E2E 校驗規格書

> **文件編號**: `PHANTOM-SPEC-CAN-E2E-2026`  
> **安全等級**: `ISO 26262 ASIL-D`  
> **總線速率**: `500 kbps (Classic CAN) / 5 Mbps (CAN-FD BRS)`  
> **校驗標準**: `SAE J1850 CRC-8 (Poly: 0x1D, Init: 0xFF, Final XOR: 0xFF)`  

---

## 1. E2E (End-to-End) 數據幀校驗規格 (AUTOSAR Profile 1 變形)

所有關鍵控制與遙測 CAN 數據幀長度固定為 8 位元組（64 位元）：

| 位元組偏移 (Byte) | 欄位名稱 (Field) | 位元寬度 (Bits) | 數值範圍 / 格式 | 說明 |
| :--- | :--- | :--- | :--- | :--- |
| **Byte 0** | **Alive Counter** | 4 bits (低 4 位元) | `0x0 ~ 0xF` (0~15) | 滾動計數器，單調遞增，防重放與丟幀檢測 |
| **Byte 0** | **Reserved** | 4 bits (高 4 位元) | `0x0` | 保留擴展位元 |
| **Byte 1 ~ 6** | **Payload Data** | 48 bits (6 Bytes) | Big-Endian (大端序) | 節點功能數據載荷（如轉速、扭矩、電壓、溫度） |
| **Byte 7** | **CRC-8 Checksum** | 8 bits (1 Byte) | `0x00 ~ 0xFF` | 覆蓋 Data ID + Byte 0..6 計算所得之 SAE J1850 校驗碼 |

### CRC-8 SAE J1850 計算演算法參數：
- **多項式 (Polynomial)**: $P(x) = x^8 + x^4 + x^3 + x^2 + 1$ (`0x1D`)
- **初始值 (Initial Value)**: `0xFF`
- **輸入反轉 (Reflect Input)**: False
- **輸出反轉 (Reflect Output)**: False
- **異或輸出 (Final XOR)**: `0xFF`

---

## 2. CAN 總線節點拓撲與識別碼分配矩陣 (CAN Matrix)

| CAN ID (Hex) | 優先級 | 發送節點 | 週期 (ms) | Data ID | 核心載荷定義 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`0x080`** | 1 (最高) | 主控緊急狀態機 | 突發 (Event) | `0x08` | `[0]` Alive, `[1]` E-Stop 觸發原因, `[2]` 隔離遮罩, `[7]` CRC8 |
| **`0x120`** | 2 | 主控網關 (Master GW) | 10 ms | `0x12` | `[0]` Alive, `[1..2]` 全局同步心跳, `[3]` 系統安全模式, `[7]` CRC8 |
| **`0x280`** | 3 | 動力致動 (Powertrain) | 20 ms | `0x28` | `[0]` Alive, `[1..2]` 輸出轉矩 (Nm), `[3..4]` 電機轉速 (RPM), `[7]` CRC8 |
| **`0x380`** | 4 | 感測採集 (Sensor Acq) | 50 ms | `0x38` | `[0]` Alive, `[1..2]` 電池電壓 (mV), `[3]` 電機溫度 (°C), `[7]` CRC8 |
| **`0x7E0`** | 5 | 診斷儀 (Tester) | 請求 (Req) | N/A | ISO 14229 UDS 診斷服務請求 ($10, $27, $34, $36, $11) |
| **`0x7E8`** | 6 | ECU 診斷伺服端 | 響應 (Resp) | N/A | ISO 14229 UDS 診斷肯定/否定響應 (Positive / Negative Response) |

---

## 3. 安全防禦狀態機流轉規範 (ISO 26262 ASIL-D)

```text
       [ Nominal Operation (100% Torque) ]
                       |
        Consecutive 3x CRC/Alive Errors
                       v
          [ STATE_DEGRADED (50% Torque) ]
                       |
               Bus-Off Detected (TEC > 255)
                       v
         [ BUS_OFF_FAILSAFE (0ms PWM Cut, 0% Torque) ]
                       |
             100ms Fast Recovery Ladder (Up to 3x)
                       |
            Failure    v    Success
          +------------+------------+
          |                         |
   > 3 Fast Retries           Bus Acked OK
          v                         v
[ 1000ms Slow Backoff ]     [ Nominal Restored ]
```

---

## 4. ISO 14229 UDS 服務清單

| SID | 服務名稱 | 支援子功能 | 安全防禦與行為 |
| :--- | :--- | :--- | :--- |
| **`0x10`** | DiagnosticSessionControl | `0x01` Default, `0x02` Programming, `0x03` Extended | 會話切換，啟動 P2/P2* 計時器 |
| **`0x27`** | SecurityAccess | `0x01` RequestSeed, `0x02` SendKey | 動態種子認證（Key = Seed XOR 0xFF），防暴力破解退避 |
| **`0x34`** | RequestDownload | 內存地址與大小封裝 | 檢查物理扇區邊界與權限 |
| **`0x36`** | TransferData | 區塊序列計數 (Block Sequence Counter) | A/B 滾動 ping-pong 鏡像寫入，若掉電 2.3ms 無縫回滾 |
| **`0x37`** | RequestTransferExit | 傳輸校驗摘要 | 驗證整塊韌體之 IEEE 802.3 CRC32 |
| **`0x11`** | ECUReset | `0x01` HardReset, `0x03` SoftReset | 重啟並復位安全狀態與 Flash 指針 |

