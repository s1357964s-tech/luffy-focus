# App Store 上架前清單

## 2026-11-24 本輪內購驗收紀錄

- [x] App Store Connect：正式 iOS `1.1.0`（build `3`）可分發；真機既有安裝版本相同，未覆寫或清除資料。
- [x] 商品 `luffy.custom_pet.create.v1` 為消耗型、已批准、未下架；台灣官方商品頁顯示 NT$30。
- [x] 商務：既有付費 App 協議有效，銀行可用、稅表使用中。另有新版協議待 Account Holder 閱讀，未代為接受。
- [x] 正式 Firestore 付款資料保護：修正未部署的舊萬用寫入規則；臨時 QA 的名額與交易寫入已由 HTTP 200 改為 HTTP 403，探測資料與帳號已清除。
- [x] 11 筆既有訂單已建立全域 owner 索引，沿用原始時間；未改舊帳本、未增加或扣除任何用戶名額。
- [x] 後端 65 項 Node.js 22 測試通過，已加入全域訂單去重、退款收據拒絕、Apple 暫時錯誤重試、生成預留 lease 與唯一圖片路徑。
- [x] 本機 App 修正：驗證成功後才入帳與完成 Apple 交易；斷線重試不重購；pending 獨立鎖；忽略舊名額回應；StoreKit1 初始化失敗或驗證服務離線時禁止新付款。
- [x] Flutter 25 項測試通過；包含真 BillingService、真付款頁 UI 與既有資料測試。外部 StoreKit／Firebase 使用測試替身，這不是 Apple 真實結帳證據。
- [x] 真機獨立 XCUITest 啟動既有正式 App，首頁與寵物管理頁正常。
- [x] 正式環境真實長毛貓照片整輪 18 項檢查通過：辨識、三態 JPEG 生圖約 23.9 秒、HTTP MIME／副檔名／檔頭／磁碟重讀一致，重複命名只 consume 一次，已消耗名額不能被 release 退回。
- [x] 修正辨識 JSON 截斷：原本 500-token 上限被思考耗盡；改為 thinkingBudget=0、輸出上限 1024，截斷回應可重試。修前已以公開素材重現，修後同素材及正式長毛貓照片皆成功。
- [x] 上述正式整輪採全新匿名 QA 帳號與 qaOnly 名額 1、purchasedCount=0，沒有 App Store 結帳；測完 Storage、Firestore、Auth 與私密 token 檔皆清除。
- [x] 真機 App 內新增頁顯示「購買解鎖名額 $30」，未點購買或恢復，未覆寫正式版本。
- [x] 真機 iPhone 17 Pro／iOS 26.6.1：上述三張 JPEG 皆成功解碼、繪製並讀取 1024×1024 像素。此項驗 UIKit 資料相容性，完整 App 實際付款後的流程仍以下項為準。
- [ ] 使用者本人在 Apple 付款 sheet 核對正式交易與金額並確認付款；尚未觸發實際扣款。
- [ ] 使用者親自完成一筆正式付款後，核對 `environment=Production`、訂單只入帳一次、生成與命名只消耗一次。

本輪 App 端修補尚未送審或出現在正式 build 3。既有正式版本可以連接新版 Firebase 後端；Xcode 本機測試、開發安裝與 TestFlight 不得當作正式扣款驗收。退款後主動追回名額尚未接入 App Store Server Notifications。

## 1. Apple 帳號與合約

- [ ] Apple Developer Program 已啟用。
- [x] App Store Connect → Business 完成 Paid Apps Agreement、Tax、Banking（既有協議有效）。
- [ ] 帳號角色具備 Account Holder、Admin 或 App Manager 權限。

## 2. App Store Connect App

- [ ] Platform: iOS。
- [ ] App Name: `路飛番茄鐘`。
- [ ] Bundle ID: `com.stevehu.luffyFocus`。
- [ ] SKU: `luffy-focus-ios-001`。
- [ ] Primary Language: Traditional Chinese。

## 3. 內購商品

- [x] Type: Consumable。
- [x] Product ID: `luffy.custom_pet.create.v1`。
- [x] Reference Name: `Custom Pet Creation Credit`。
- [x] Price: 台灣 NT$30；其他地區以 App Store 動態價格為準。
- [x] Display Name: `新增寵物名額`。
- [ ] Description: `創建 1 隻專屬陪伴寵物`。
- [ ] Review Screenshot 顯示上傳前付款畫面。
- [ ] Review Notes 說明：購買 1 次可建立 1 隻自訂寵物，付款成功後才可選圖與生成。

## 4. 隱私與法務

- [ ] 將 `PRIVACY_POLICY.md` 發布到可公開訪問的 Privacy Policy URL。
- [ ] 將 `TERMS_OF_USE.md` 發布到可公開訪問的 Terms URL。
- [ ] Support URL 可使用同一個網站或 App Store 開發者聯絡頁。
- [ ] App Privacy 標籤盤點：
  - User Content: 寵物照片、寵物名稱、補充特徵、生成圖片、夢境故事。
  - Identifiers: Firebase anonymous user id。
  - Purchases: App Store 交易 ID、商品 ID、購買驗證狀態。
  - Diagnostics: Firebase / 系統錯誤與診斷資料，如有啟用。
- [ ] 不標示收集付款卡號；付款資訊由 Apple 處理。

## 5. 程式收尾

- [ ] 未付款不能選圖、不能呼叫 AI API。
- [x] Firebase Functions 驗證 App Store transaction 並以全域 owner 記錄去重。
- [ ] Firestore 記錄 unused / reserved / consumed credit。
- [ ] 生成寵物時 reserve credit；保存名稱成功時 consume credit。
- [ ] 付款成功但退出流程時，unused credit 保留到下次新增。
- [ ] `normal/sleeping/failed` 圖片都使用本機快取。
- [ ] 刪除寵物時刪除圖片、夢境故事與圖片快取。
- [ ] 所有錯誤文案已檢查：付款取消、付款 pending、驗證失敗、AI 生成失敗、圖片載入失敗。

## 6. Firebase 生產檢查

- [ ] `GEMINI_API_KEY` 已設定為 Functions secret。
- [ ] App Store IAP 驗證所需資訊已放在 Functions secrets 或安全環境；不可寫死在 app。
- [x] Firestore rules 限定本人資料；內購帳本、名額及生成資料僅後端可寫。
- [x] Storage rules 僅允許使用者讀寫自己的 `users/{uid}` 圖片（生成圖下載 token 為既有產品機制）。
- [ ] 部署 Functions、Firestore rules、Storage rules。
- [ ] 評估啟用 Firebase App Check，降低 API 被刷風險。

## 7. 版本與建置

- [ ] `pubspec.yaml` version 首次送審可用 `1.0.0+1`；每次重新上傳 build number 需遞增。
- [ ] Xcode signing team 正確。
- [ ] iOS deployment target 與 Firebase SDK 相容。
- [ ] 相簿權限文案與通知權限文案已確認。
- [x] `flutter analyze` 通過。
- [x] `flutter test` 通過（本輪 25 項）。
- [ ] iPhone simulator 實測通過。
- [ ] 真機 Sandbox IAP 實測通過。

## 8. TestFlight

- [ ] Internal testing：付款、取消、pending、創建寵物、刪除寵物、圖片快取、專注中斷都通過。
- [ ] External testing：至少 2 台真機測試通過。
- [ ] 首次 external beta 已通過 Apple beta review。

## 9. App Store 商品頁

- [ ] App name、subtitle、description、keywords。
- [ ] iPhone screenshots：首頁、專注中、付款/上傳、歷史故事。
- [ ] 年齡分級問卷。
- [ ] Export compliance 依 Apple 問卷如實回答 HTTPS/Firebase 加密使用。
- [ ] Review Notes 清楚說明如何進入內購流程與測試方式。

## 10. 送審

- [ ] 選擇已處理完成的 build。
- [ ] IAP 狀態為 Ready to Submit，並與 app build 一起提交。
- [ ] 選擇手動發布，審核通過後再手動 release。
