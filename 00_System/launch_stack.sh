#!/usr/bin/env bash
set -euo pipefail

echo "=========================================================="
echo " 🚀 全棧工業級架構實體化：L0～L5 全集群一鍵啟航"
echo " 指揮官: 👑 小幫手 | 執行秘書: 小米 | 審批核心: 哥"
echo "=========================================================="

# 1. 檢查並加載 vcan 內核模組
if ! lsmod | grep -q vcan; then
    echo "[!] 載入 Linux vcan 虛擬 CAN 總線內核驅動..."
    sudo modprobe vcan || true
fi

# 2. 初始化 vcan0 虛擬總線設備
if ! ip link show vcan0 > /dev/null 2>&1; then
    echo "[+] 建立並啟動 vcan0 虛擬總線 (500 kbps)..."
    sudo ip link add dev vcan0 type vcan
    sudo ip link set up vcan0
fi

# 3. 初始化審計數據庫
python3 -c "from audit_governance import GovernanceDB; db = GovernanceDB('audit_log.db'); print('[+] SQLite 審計中樞就緒: audit_log.db')"

# 4. 依序拉起後台服務
echo "[+] 啟動 L1 分散式三節點總線集群..."
python3 multi_node_cluster.py > /dev/null 2>&1 &
PID_CLUSTER=$!

echo "[+] 啟動 L2/L3 服務化網關與自愈中樞..."
python3 autonomous_healer.py > /dev/null 2>&1 &
PID_HEALER=$!

echo "[+] 啟動 L5 機隊去中心化廣播網格..."
python3 fleet_nostr_mesh.py > /dev/null 2>&1 &
PID_FLEET=$!

echo "=========================================================="
echo " ✅ 全系統部署完畢！各層守護進程 PID:"
echo "    - CAN 拓撲集群: ${PID_CLUSTER}"
echo "    - 自愈與網關:   ${PID_HEALER}"
echo "    - 機隊網格節點: ${PID_FLEET}"
echo " 🌐 戰情儀表板請運行: streamlit run dashboard.py"
echo " 🛡️ 車載 MCP 接口可隨時接入大模型終端"
echo "=========================================================="

