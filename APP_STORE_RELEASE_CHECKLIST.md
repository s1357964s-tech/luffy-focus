# App Store 上架前清單

## 1. Apple 帳號與合約

- [ ] Apple Developer Program 已啟用。
- [ ] App Store Connect → Business 完成 Paid Apps Agreement、Tax、Banking。
- [ ] 帳號角色具備 Account Holder、Admin 或 App Manager 權限。

## 2. App Store Connect App

- [ ] Platform: iOS。
- [ ] App Name: `路飛番茄鐘`。
- [ ] Bundle ID: `com.stevehu.luffyFocus`。
- [ ] SKU: `luffy-focus-ios-001`。
- [ ] Primary Language: Traditional Chinese。

## 3. 內購商品

- [ ] Type: Consumable。
- [ ] Product ID: `luffy.custom_pet.create.v1`。
- [ ] Reference Name: `Custom Pet Creation Credit`。
- [ ] Price: USD 0.99。
- [ ] Display Name: `新增寵物名額`。
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
- [ ] Firebase Functions 驗證 App Store transaction 並去重。
- [ ] Firestore 記錄 unused / reserved / consumed credit。
- [ ] 生成寵物時 reserve credit；保存名稱成功時 consume credit。
- [ ] 付款成功但退出流程時，unused credit 保留到下次新增。
- [ ] `normal/sleeping/failed` 圖片都使用本機快取。
- [ ] 刪除寵物時刪除圖片、夢境故事與圖片快取。
- [ ] 所有錯誤文案已檢查：付款取消、付款 pending、驗證失敗、AI 生成失敗、圖片載入失敗。

## 6. Firebase 生產檢查

- [ ] `GEMINI_API_KEY` 已設定為 Functions secret。
- [ ] App Store IAP 驗證所需資訊已放在 Functions secrets 或安全環境；不可寫死在 app。
- [ ] Firestore rules 僅允許使用者讀寫自己的 `users/{uid}` 資料。
- [ ] Storage rules 僅允許使用者讀寫自己的 `users/{uid}` 圖片。
- [ ] 部署 Functions、Firestore rules、Storage rules。
- [ ] 評估啟用 Firebase App Check，降低 API 被刷風險。

## 7. 版本與建置

- [ ] `pubspec.yaml` version 首次送審可用 `1.0.0+1`；每次重新上傳 build number 需遞增。
- [ ] Xcode signing team 正確。
- [ ] iOS deployment target 與 Firebase SDK 相容。
- [ ] 相簿權限文案與通知權限文案已確認。
- [ ] `flutter analyze` 通過。
- [ ] `flutter test` 通過。
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
