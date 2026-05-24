import 'package:flutter/material.dart';
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
  // 初始化 Firebase
  await FirebaseService.init();

  // 初始化本地存儲服務
  final storageService = await StorageService.init();

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
        // 也可以將 BillingService 放進 Provider，如果 UI 需要用的話
        Provider<BillingService>.value(value: billingService),
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
