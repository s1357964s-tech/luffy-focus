import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../viewmodels/timer_provider.dart';
import '../services/notification_service.dart';
import 'widgets/reward_modal.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  TimerState? _previousState;
  final NotificationService _notificationService = NotificationService();
  
  // 追蹤是否已經請求過通知權限（僅在本次 App 生命週期內）
  bool _hasRequestedPermission = false;

  @override
  void initState() {
    super.initState();
    // 註冊生命週期觀察者，用於監聽 App 前後台切換
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // 移除觀察者，避免記憶體洩漏
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 監聽 App 生命週期狀態變化
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final timerProvider = context.read<TimerProvider>();
    
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // App 進入後台且計時器正在運行 → 發送可愛提醒通知
      if (timerProvider.state == TimerState.running) {
        _notificationService.showFocusReminder();
      }
    } else if (state == AppLifecycleState.resumed) {
      // 用戶回到前台 → 清除通知
      _notificationService.cancelAll();
    }
  }

  /// 處理「開始專注」按鈕的點擊邏輯
  /// 第一次點擊時：先展示通知說明彈窗 → 請求權限 → 然後開始計時
  /// 之後：直接開始計時
  Future<void> _handleStartFocus(TimerProvider provider) async {
    if (!_hasRequestedPermission) {
      _hasRequestedPermission = true;
      
      // 展示可愛的通知權限說明彈窗
      final userAgreed = await _showNotificationExplanationDialog();
      
      if (userAgreed == true) {
        // 用戶同意後，觸發系統權限請求
        await _notificationService.requestPermission();
      }
    }
    
    // 無論用戶是否同意通知，都開始計時（核心功能不受影響）
    provider.startTimer();
  }

  /// 展示通知權限的說明彈窗
  /// 用可愛的路飛口吻解釋為什麼需要通知權限
  Future<bool?> _showNotificationExplanationDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(
              Icons.notifications_active,
              color: AppConstants.primaryButtonColor,
              size: 28,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                '路飛想守護你的專注！',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🐶 汪！我是路飛～\n\n'
              '如果你在專注的時候偷偷跑去滑手機，我會發一條通知提醒你回來喔！\n\n'
              '畢竟...我都這麼努力在幫你守護專注時間了，你可不能辜負我的一片苦心呀！',
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: AppConstants.primaryTextColor,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              '先不用了',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('好的，讓路飛守護我！'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timerProvider = context.watch<TimerProvider>();
    final state = timerProvider.state;

    // 監聽狀態變化，若從 running 變成 finished，則彈出獎勵
    if (_previousState == TimerState.running && state == TimerState.finished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showRewardModal(context, timerProvider);
      });
    }
    _previousState = state;

    return Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Align(
                alignment: Alignment.topRight,
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HistoryScreen()),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppConstants.primaryButtonColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_stories,
                          size: 18,
                          color: AppConstants.primaryButtonColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '已專注: ${timerProvider.focusCount} 次',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppConstants.primaryButtonColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: AppConstants.primaryButtonColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            const Spacer(),

            _buildLuffyImage(state),

            const SizedBox(height: 48),

            Text(
              timerProvider.timeString,
              style: Theme.of(context).textTheme.displayLarge,
            ),

            const SizedBox(height: 48),

            _buildActionButtons(context, timerProvider),

            const Spacer(),
          ],
        ),
      ),
    );
  }

  void _showRewardModal(BuildContext context, TimerProvider provider) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => RewardModal(
        currentFocusCount: provider.focusCount,
        storyText: provider.currentStory,
        onClaimReward: () {
          provider.resetAfterReward();
        },
      ),
    );
  }

  String _getImagePathForState(TimerState state) {
    switch (state) {
      case TimerState.initial:
        return AppConstants.luffyAwake;
      case TimerState.running:
        return AppConstants.luffySleeping;
      case TimerState.finished:
        return AppConstants.luffyHappy;
    }
  }

  Widget _buildLuffyImage(TimerState state) {
    final imagePath = _getImagePathForState(state);
    
    return Container(
      width: 250,
      height: 250,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          imagePath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    state == TimerState.running 
                      ? Icons.nights_stay 
                      : (state == TimerState.finished ? Icons.celebration : Icons.pets),
                    size: 48,
                    color: AppConstants.primaryButtonColor,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '圖片載入中\n(佔位符)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, TimerProvider provider) {
    if (provider.state == TimerState.initial) {
      return ElevatedButton(
        // 改為呼叫帶有通知權限檢查的 _handleStartFocus
        onPressed: () => _handleStartFocus(provider),
        child: const Text('開始專注', style: TextStyle(fontSize: 18)),
      );
    } else if (provider.state == TimerState.running) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppConstants.cancelButtonColor,
        ),
        onPressed: () => _showGiveUpDialog(context, provider),
        child: const Text('放棄', style: TextStyle(fontSize: 18, color: AppConstants.primaryTextColor)),
      );
    } else {
      return ElevatedButton(
        onPressed: () => provider.resetAfterReward(),
        child: const Text('再專注一次', style: TextStyle(fontSize: 18)),
      );
    }
  }

  void _showGiveUpDialog(BuildContext context, TimerProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確定要放棄嗎？'),
        content: const Text('路飛正在安靜地睡覺，現在放棄會把路飛吵醒喔！'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('繼續專注', style: TextStyle(color: AppConstants.primaryTextColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.cancelButtonColor,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              provider.giveUp();
              
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🐶 汪！路飛被吵醒了...'),
                  duration: Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('放棄', style: TextStyle(color: AppConstants.primaryTextColor)),
          ),
        ],
      ),
    );
  }
}
