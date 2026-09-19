# -*- coding: utf-8 -*-
"""
plot_ablation_metrics.py - 消融指標可視化與查修分析腳本
自動抓取最新一次或指定 Session 的探索紀錄，產出「殘差收斂曲線」與「動作效率診斷圖」
"""

import os
import sys
import glob
import json
from typing import List, Dict, Any, Tuple
import matplotlib.pyplot as plt

# 確保在 Windows 終端機環境下繁體中文與 UTF-8 輸出不崩潰
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

def ensure_sample_log_if_empty(log_dir: str = "logs/ablation"):
    """如果日誌目錄為空，自動建立一組標準 ARC-3 探索示範資料供可視化驗證"""
    os.makedirs(log_dir, exist_ok=True)
    jsonl_files = glob.glob(os.path.join(log_dir, "session_*.jsonl"))
    if not jsonl_files:
        demo_session_id = "arc3_demo_run"
        demo_jsonl = os.path.join(log_dir, f"session_{demo_session_id}.jsonl")
        demo_summary = os.path.join(log_dir, f"summary_{demo_session_id}.json")
        
        sample_records = [
            {"step": 1, "action": "FILL_COLOR(4)", "state_changed": True, "mismatch_pixels": 42, "mismatch_ratio": 0.42},
            {"step": 2, "action": "CONNECT_PATH(3,7)", "state_changed": True, "mismatch_pixels": 28, "mismatch_ratio": 0.28},
            {"step": 3, "action": "ROTATE_GRID(90)", "state_changed": False, "mismatch_pixels": 28, "mismatch_ratio": 0.28},
            {"step": 4, "action": "ALIGN_SYMMETRY(H)", "state_changed": True, "mismatch_pixels": 14, "mismatch_ratio": 0.14},
            {"step": 5, "action": "FILL_REGION(2)", "state_changed": True, "mismatch_pixels": 6, "mismatch_ratio": 0.06},
            {"step": 6, "action": "INVERT_BINARY", "state_changed": False, "mismatch_pixels": 6, "mismatch_ratio": 0.06},
            {"step": 7, "action": "REFINE_BORDER(1)", "state_changed": True, "mismatch_pixels": 0, "mismatch_ratio": 0.00},
        ]
        
        with open(demo_jsonl, "w", encoding="utf-8") as f:
            for r in sample_records:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
                
        summary_data = {
            "task_id": "ARC3_POLICY_VALUE_NET_01",
            "success": True,
            "action_efficiency": 5 / 7,
            "final_mismatch": 0
        }
        with open(demo_summary, "w", encoding="utf-8") as f:
            json.dump(summary_data, f, ensure_ascii=False, indent=2)
            
        print(f"[*] 已自動建立示範探索日誌供圖表初始化: {demo_jsonl}")

def load_latest_session_log(log_dir: str = "logs/ablation") -> Tuple[str, List[Dict[str, Any]], Dict[str, Any]]:
    """載入最新一次的消融 JSONL 日誌與 Summary 摘要檔案"""
    ensure_sample_log_if_empty(log_dir)
    jsonl_files = sorted(glob.glob(os.path.join(log_dir, "session_*.jsonl")))
    if not jsonl_files:
        raise FileNotFoundError(f"[!] 在目錄 {log_dir} 中未找到任何消融日誌 session_*.jsonl！")
    
    latest_jsonl = jsonl_files[-1]
    session_id = os.path.basename(latest_jsonl).replace("session_", "").replace(".jsonl", "")
    summary_file = os.path.join(log_dir, f"summary_{session_id}.json")
    
    records = []
    with open(latest_jsonl, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))
                
    summary = {}
    if os.path.exists(summary_file):
        with open(summary_file, "r", encoding="utf-8") as f:
            summary = json.load(f)
            
    return session_id, records, summary

def plot_ablation_metrics(output_dir: str = "reports/figures"):
    """繪製 MCTS 殘差收斂與動作有效性分析圖表"""
    os.makedirs(output_dir, exist_ok=True)
    session_id, records, summary = load_latest_session_log()
    
    steps = [r["step"] for r in records]
    mismatch_pixels = [r["mismatch_pixels"] for r in records]
    mismatch_ratios = [r["mismatch_ratio"] * 100 for r in records]
    actions = [f"S{r['step']}:{r['action']}" for r in records]
    state_changes = [1 if r["state_changed"] else 0 for r in records]

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 8), sharex=True)

    # 1. 像素殘差與誤差比例下降曲線 (Mismatch Reduction Curve)
    ax1.plot(steps, mismatch_pixels, marker="o", color="#1f77b4", linewidth=2, label="Mismatch Pixels (Residual)")
    ax1.set_ylabel("Pixel Residual Count", color="#1f77b4", fontsize=11)
    ax1.tick_params(axis="y", labelcolor="#1f77b4")
    ax1.grid(True, linestyle="--", alpha=0.5)

    # 雙 Y 軸繪製殘差百分比
    ax1_twin = ax1.twinx()
    ax1_twin.plot(steps, mismatch_ratios, marker="s", color="#ff7f0e", linestyle=":", linewidth=2, label="Error Ratio (%)")
    ax1_twin.set_ylabel("Error Ratio (%)", color="#ff7f0e", fontsize=11)
    ax1_twin.tick_params(axis="y", labelcolor="#ff7f0e")

    title_text = f"ARC-3 Active Exploration Ablation [Session: {session_id}]"
    if summary:
        title_text += f"\nTask: {summary.get('task_id', 'N/A')} | Success: {summary.get('success')} | Efficiency: {summary.get('action_efficiency')}"
    ax1.set_title(title_text, fontsize=12, fontweight="bold")

    # 2. 動作有效率分佈條形圖 (State Transition Diagnostic)
    bar_colors = ["#2ca02c" if c else "#d62728" for c in state_changes]
    ax2.bar(steps, state_changes, color=bar_colors, alpha=0.7, width=0.6)
    ax2.set_ylabel("State Changed (1/0)", fontsize=11)
    ax2.set_xlabel("Exploration Steps", fontsize=11)
    ax2.set_yticks([0, 1])
    ax2.set_yticklabels(["No Change", "State Shift"])
    ax2.set_xticks(steps)
    ax2.set_xticklabels(actions, rotation=35, ha="right", fontsize=9)
    ax2.grid(True, axis="y", linestyle="--", alpha=0.5)

    plt.tight_layout()
    chart_path = os.path.join(output_dir, f"ablation_curve_{session_id}.png")
    plt.savefig(chart_path, dpi=300)
    plt.close()

    print(f"[OK] 消融分析曲線圖已成功產出: {chart_path}")
    if summary:
        eff = summary.get("action_efficiency", 0)
        eff_pct = eff * 100 if eff is not None else 0
        print(f"[*] 關鍵消融摘要 - 動作有效率: {eff_pct:.2f}%, 最終殘差: {summary.get('final_mismatch')} 像素")

if __name__ == "__main__":
    plot_ablation_metrics()
