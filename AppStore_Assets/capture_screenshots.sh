#!/bin/bash

# App Store 截圖自動化腳本（互動式）
# 每次截圖前會倒數 10 秒，讓你有時間操作模擬器

DEVICE_ID="4C9F0BAA-4C9E-4440-80AF-63DD946CA3DC"
OUTPUT_DIR="$(dirname "$0")/Screenshots"
mkdir -p "$OUTPUT_DIR"

# 倒數計時函式
countdown() {
  local seconds=$1
  local message=$2
  echo ""
  echo "📱 $message"
  echo "👉 你有 $seconds 秒時間操作模擬器..."
  for i in $(seq $seconds -1 1); do
    printf "\r⏱  倒數 %d 秒後截圖..." "$i"
    sleep 1
  done
  printf "\r📸 截圖中！                  \n"
}

echo "============================================"
echo "  路飛番茄鐘 - App Store 截圖工具"
echo "============================================"
echo ""

# ---- 截圖 1：首頁（清醒路飛）----
echo "【第 1 張 / 共 4 張】首頁 - 清醒的路飛"
echo "  確認模擬器顯示 App 首頁（有「開始專注」按鈕）"
countdown 8 "請確認模擬器顯示首頁畫面"
xcrun simctl io "$DEVICE_ID" screenshot "$OUTPUT_DIR/1_home_awake.png"
echo "  ✅ 已儲存：1_home_awake.png"
echo ""

# ---- 截圖 2：計時中（睡覺路飛）----
echo "【第 2 張 / 共 4 張】計時中 - 睡覺的路飛"
echo "  請點擊「開始專注」按鈕"
echo "  （若有通知權限彈窗，點「好的，讓路飛守護我！」然後允許）"
countdown 15 "請點擊「開始專注」按鈕，等待畫面顯示睡覺的路飛"
xcrun simctl io "$DEVICE_ID" screenshot "$OUTPUT_DIR/2_running_sleeping.png"
echo "  ✅ 已儲存：2_running_sleeping.png"
echo ""

# ---- 截圖 3：歷史紀錄頁面 ----
echo "【第 3 張 / 共 4 張】歷史紀錄頁面"
echo "  請點擊放棄按鈕回到首頁，再點擊右上角的橘色「已專注: X 次」膠囊按鈕"
countdown 12 "請導航到歷史紀錄頁面"
xcrun simctl io "$DEVICE_ID" screenshot "$OUTPUT_DIR/3_history.png"
echo "  ✅ 已儲存：3_history.png"
echo ""

# ---- 截圖 4：返回首頁 ----
echo "【第 4 張 / 共 4 張】返回首頁"
echo "  請點擊左上角的返回箭頭，回到 App 首頁"
countdown 8 "請返回 App 首頁"
xcrun simctl io "$DEVICE_ID" screenshot "$OUTPUT_DIR/4_home_final.png"
echo "  ✅ 已儲存：4_home_final.png"
echo ""

echo "============================================"
echo "  🎉 全部 4 張截圖完成！"
echo "  📁 儲存位置：$OUTPUT_DIR"
echo "============================================"

# 自動開啟截圖資料夾
open "$OUTPUT_DIR"
