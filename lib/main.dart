import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'services/storage_service.dart';
import 'services/firebase_service.dart';
import 'services/billing_service.dart';
import 'services/ai_pet_service.dart';
import 'services/story_service.dart';
import 'services/pet_repository.dart';
import 'viewmodels/timer_provider.dart';
import 'viewmodels/pet_viewmodel.dart';
import 'views/home_screen.dart';

void main() async {
  // 確保在 runApp 之前完成 Flutter 綁定初始化
  WidgetsFlutterBinding.ensureInitialized();

  if (defaultTargetPlatform == TargetPlatform.iOS) {
    try {
      // The current Firebase verifier validates the StoreKit 1 app receipt.
      // ignore: deprecated_member_use
      await InAppPurchaseStoreKitPlatform.enableStoreKit1();
    } catch (error) {
      debugPrint('StoreKit1 初始化失敗，App 會繼續啟動並在內購頁重試: $error');
    }
  }

  // 初始化 Firebase
  try {
    await FirebaseService.init();
  } catch (error) {
    debugPrint('Firebase 初始化失敗，App 會先以本機模式啟動: $error');
  }

  // 初始化本地存儲服務
  final StorageService storageService;
  try {
    storageService = await StorageService.init();
  } catch (error) {
    debugPrint('本地存儲初始化失敗，使用暫時記憶體模式: $error');
    rethrow;
  }

  // 初始化其它服務
  final billingService = BillingService();
  final aiPetService = AiPetService(storageService);
  final petRepository = PetRepository(storageService);
  final storyService = StoryService(storageService, petRepository);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) =>
              PetViewModel(storageService, aiPetService, petRepository),
        ),
        ChangeNotifierProvider(
          create: (_) => TimerProvider(storageService, storyService),
        ),
        ChangeNotifierProvider<BillingService>.value(value: billingService),
      ],
      child: const LuffyFocusApp(),
    ),
  );
}

class LuffyFocusApp extends StatelessWidget {
  const LuffyFocusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '路飛的專注時間',
      theme: AppTheme.lightTheme,
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
