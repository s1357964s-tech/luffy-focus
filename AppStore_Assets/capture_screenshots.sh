#!/bin/bash

# 這個腳本用來幫助你快速擷取 iOS 模擬器的螢幕截圖
# 這些截圖可以用於 App Store Connect 的上架

# 建立存放截圖的資料夾
OUTPUT_DIR="$(dirname "$0")/Screenshots"
mkdir -p "$OUTPUT_DIR"

# 取得目前已啟動的模擬器 ID
BOOTED_SIMULATOR=$(xcrun simctl list devices | grep "(Booted)" | head -1 | awk -F '[()]' '{print $2}')

if [ -z "$BOOTED_SIMULATOR" ]; then
    echo "❌ 找不到正在運行的 iOS 模擬器！請先啟動模擬器。"
    exit 1
fi

echo "✅ 找到運作中的模擬器: $BOOTED_SIMULATOR"

# 提示輸入截圖名稱
echo ""
echo "👉 請在模擬器中將 App 切換到你要截圖的畫面 (例如: 清醒、睡覺、獎勵彈窗、歷史紀錄)"
echo "請輸入這張截圖的名稱 (例如: 1_home, 2_sleeping, 3_reward)，然後按 Enter:"
read FILENAME

if [ -z "$FILENAME" ]; then
    FILENAME="screenshot_$(date +%s)"
fi

OUTPUT_PATH="$OUTPUT_DIR/$FILENAME.png"

echo "📸 正在擷取螢幕..."
xcrun simctl io "$BOOTED_SIMULATOR" screenshot "$OUTPUT_PATH"

if [ $? -eq 0 ]; then
    echo "✨ 截圖成功！已儲存至: $OUTPUT_PATH"
    open "$OUTPUT_DIR"
else
    echo "❌ 截圖失敗！"
fi
