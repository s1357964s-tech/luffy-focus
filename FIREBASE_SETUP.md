# Firebase 设置指引

这份指引用于把「自定义宠物卡通生成」和「专属故事生成」接到 Firebase。

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

这会替换 `lib/firebase_options.dart`。当前仓库里的该文件只是占位文件，不能连接真实 Firebase。

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

如果本机 Node 是 24，Firebase CLI 请求 Google API 可能会出现 TLS 连接中断。这个项目已验证可用的临时写法是：

```bash
npx -p node@20 -p firebase-tools firebase projects:list
```

后续所有 `firebase ...` 命令都可以替换成：

```bash
npx -p node@20 -p firebase-tools firebase ...
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

如果你使用 Node 20 临时写法：

```bash
npx -p node@20 -p firebase-tools firebase functions:secrets:set GEMINI_API_KEY --project luffy-focus
```

## 7. 安装和部署 Functions

```bash
cd functions
npm install
cd ..
firebase deploy --only functions,firestore:rules,storage
```

建议分开部署，方便定位问题：

```bash
npx -p node@20 -p firebase-tools firebase deploy --only firestore:rules,storage --project luffy-focus
npx -p node@20 -p firebase-tools firebase deploy --only functions --project luffy-focus
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
