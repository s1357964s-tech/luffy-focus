import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme.dart';
import 'services/storage_service.dart';
import 'viewmodels/timer_provider.dart';
import 'views/home_screen.dart';

void main() async {
  // 確保在 runApp 之前完成 Flutter 綁定初始化
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化本地存儲服務
  final storageService = await StorageService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => TimerProvider(storageService),
        ),
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
