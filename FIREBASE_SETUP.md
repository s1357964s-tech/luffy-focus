# Firebase 设置指引

这份指引用于把「自定义宠物卡通生成」和「专属故事生成」接到 Firebase。

## 目前的正式部署架構

- iOS App 直接呼叫 Firebase 專案 `luffy-focus` 的 Cloud Functions，區域為 `us-central1`；後端不經過 Vercel。
- 圖片辨識與故事模型為 `gemini-2.5-flash`；生圖模型為 [`gemini-3-pro-image`](https://ai.google.dev/gemini-api/docs/models/gemini-3-pro-image)。
- 後端部署使用 Node.js 22。Google 已於 2026-10-30 停止接受 Node.js 20 的部署。
- 生成圖片依模型回傳的 MIME 儲存：JPEG 使用 `.jpg`／`image/jpeg`，PNG 與 WebP 也保留對應格式。
- 照片辨識使用 `thinkingBudget=0`、1024 個輸出 tokens，避免短 JSON 被思考預算截斷；僅記錄 token／完成原因等診斷資訊。
- 已驗證 Apple 訂單會寫入全域 `appStoreTransactions/{environment}_{transactionId}` owner 索引，防止同一訂單跨帳號重複入帳。生成中的預留名額有 330 秒 lease；等待命名的完成草稿不以這個短 lease 退回。
- 公開 `releaseCustomPetPurchaseCredit` 僅回收確實已過期的生成預留；不能用取消退回已生成或仍在生成的名額。實際模型失敗仍由後端內部回滾，已交付圖片草稿保留供命名。
- `generatePetAvatarStates` 與 `repairPetAvatarStates` 共用付費寵物授權及交易鎖，只修復伺服器現有寵物；忽略客戶端替換照片與 `force` 重生要求，完整三態直接回傳既有結果。
- 目前 Firebase 設定僅支援 iOS；GitHub 更新不會自動部署 Functions，也不會建立可使用的 Flutter Web 版本。

## 1. 创建 Firebase 项目

1. 打开 https://console.firebase.google.com/
2. 创建项目，例如 `luffy-focus`
3. 按你要发布的平台添加 App：
   - iOS：使用 Xcode/Firebase Console 中对应的 Bundle ID
   - Android：使用 `android/app/build.gradle.kts` 中的 `applicationId`
   - Web/macOS 如需支持，也一起添加

## 2. 生成 Flutter Firebase 配置

如果本机还没有 `flutterfire` 命令，先安装 FlutterFire CLI：

```bash
dart pub global activate flutterfire_cli
```

如果安装后仍提示 `zsh: command not found: flutterfire`，把 Dart 全局命令目录加入 PATH：

```bash
echo 'export PATH="$PATH:$HOME/.pub-cache/bin"' >> ~/.zshrc
source ~/.zshrc
```

也可以不改 PATH，直接运行：

```bash
dart pub global run flutterfire_cli:flutterfire configure
```

在项目根目录运行：

```bash
flutterfire configure
```

这会替换 `lib/firebase_options.dart`。目前檔案已設定正式 iOS Firebase App；只有新增平台或更換 Firebase App 時才需要重新配置。

## 3. 开启 Authentication

Firebase Console -> Authentication -> Sign-in method -> 开启 `Anonymous`。

App 会在启动时自动匿名登录，并用 `uid` 隔离每个用户的数据。

## 4. 开启 Firestore 和 Storage

Firebase Console 中分别开启：

- Firestore Database
- Storage

本项目已提供规则文件：

- `firestore.rules`
- `storage.rules`

规则含义：用户只能读取和写入自己的 `users/{uid}` 数据与图片。

## 5. 开启 Cloud Functions

Cloud Functions 调用外部 AI 服务通常需要 Firebase Blaze 计费计划。

如果本机还没有 `firebase` 命令，先安装 Firebase CLI：

```bash
npm install -g firebase-tools
```

如果不想全局安装，也可以把后续命令里的 `firebase` 改成 `npx firebase-tools`。

如果需要以與後端一致的 Node.js 22 執行 Firebase CLI，可使用：

```bash
npx -p node@22 -p firebase-tools firebase projects:list
```

后续所有 `firebase ...` 命令都可以替换成：

```bash
npx -p node@22 -p firebase-tools firebase ...
```

安装后，在项目根目录登录并绑定项目：

```bash
firebase login
firebase use --add
```

## 6. 设置 AI 密钥

不要把密钥写入 Flutter 前端，也不要提交到 Git。当前后端的图片识别、宠物卡通图生成、故事生成都使用 Google Gemini，因此只需要 `GEMINI_API_KEY`。

```bash
firebase functions:secrets:set GEMINI_API_KEY
```

如果你使用 Node.js 22 临时写法：

```bash
npx -p node@22 -p firebase-tools firebase functions:secrets:set GEMINI_API_KEY --project luffy-focus
```

## 7. 安装和部署 Functions

2026-11-24 的完整內購／生圖驗收已更新以下八個函式至 Node.js 22（故事函式不在本輪變更內）：

```bash
firebase deploy --only functions:analyzePetImage,functions:generatePetAvatar,functions:generatePetAvatarStates,functions:repairPetAvatarStates,functions:getCustomPetPurchaseCredit,functions:verifyCustomPetPurchase,functions:saveGeneratedPetName,functions:releaseCustomPetPurchaseCredit --project luffy-focus
```

本輪另已部署儲存在 repo 的 `firestore.rules`，禁止客戶端改寫訂單、名額及生成資料；詳見 `APP_STORE_RELEASE_CHECKLIST.md` 的逐項驗收結果。

本次只更新生圖功能時，先驗證，再限定部署三個函式。其餘既有函式不會在這次發布中升級 runtime：

```bash
cd functions
npm ci
npm test
npm run lint
cd ..
firebase deploy --only functions:generatePetAvatar,functions:generatePetAvatarStates,functions:repairPetAvatarStates --project luffy-focus
```

需要發布全部後端或規則時，再依對應變更選擇以下部署指令：

```bash
cd functions
npm install
cd ..
firebase deploy --only functions,firestore:rules,storage
```

建议分开部署，方便定位问题：

```bash
npx -p node@22 -p firebase-tools firebase deploy --only firestore:rules,storage --project luffy-focus
npx -p node@22 -p firebase-tools firebase deploy --only functions --project luffy-focus
```

## 8. 本地 Flutter 依赖

```bash
flutter pub get
```

完成后运行 App。首次启动会匿名登录，上传宠物图后：

1. 原图保存到 Firebase Storage
2. Cloud Function 调 AI 生成三张卡通图
3. 生成图保存到 Firebase Storage
4. 宠物资料写入 Firestore
5. 专注完成后故事写入 `users/{uid}/stories`
