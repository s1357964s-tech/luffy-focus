import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../viewmodels/timer_provider.dart';
import '../viewmodels/pet_viewmodel.dart';
import '../services/notification_service.dart';
import 'widgets/reward_modal.dart';
import 'history_screen.dart';
import 'statistics_screen.dart';
import 'pet_management_screen.dart';
import 'widgets/firebase_storage_image.dart';

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
    final petViewModel = context.read<PetViewModel>();

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // App 進入後台且計時器正在運行 → 發送可愛提醒通知
      if (timerProvider.state == TimerState.running) {
        final pet = petViewModel.selectedPet;
        _notificationService.showFocusReminder(
          petName: pet?.name ?? '路飛',
          species: pet?.species ?? 'dog',
        );
      }
    } else if (state == AppLifecycleState.resumed) {
      timerProvider.syncWithClock();
      // 用戶回到前台 → 清除通知
      _notificationService.cancelAll();
    }
  }

  /// 展示通知權限的說明彈窗
  Future<bool?> _showNotificationExplanationDialog(String petName) {
    return showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.notifications_active,
                  color: AppConstants.primaryButtonColor,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$petName想守護你的專注！',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '🐾 哈囉！我是$petName～\n\n'
              '如果你在專注的時候偷偷跑去滑手機，我會發一條通知提醒你回來喔！\n\n'
              '畢竟...我都這麼努力在幫你守護專注時間了，你可不能辜負我的一片苦心呀！',
              style: const TextStyle(
                fontSize: 15,
                height: 1.6,
                color: AppConstants.primaryTextColor,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(
                      '先不用了',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text('好的，讓$petName守護我！'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timerProvider = context.watch<TimerProvider>();
    final petViewModel = context.watch<PetViewModel>();
    final state = timerProvider.state;
    final petName = petViewModel.selectedPet?.name ?? '路飛';

    // 監聽狀態變化，若從 running 變成 finished，則彈出獎勵
    if (_previousState == TimerState.running && state == TimerState.finished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showRewardModal(context, timerProvider, petName, petViewModel);
      });
    }

    // 監聽狀態變化，若變成 failed，則彈出失敗提醒
    if (_previousState == TimerState.running && state == TimerState.failed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showFailureDialog(context, timerProvider, petName);
      });
    }
    _previousState = state;

    return Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 左側：統計入口
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const StatisticsScreen()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppConstants.primaryButtonColor
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.bar_chart_rounded,
                            size: 16,
                            color: AppConstants.primaryButtonColor,
                          ),
                          SizedBox(width: 4),
                          Text(
                            '統計',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppConstants.primaryButtonColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 右側：歷史紀錄入口
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const HistoryScreen()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppConstants.primaryButtonColor
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.auto_stories,
                            size: 16,
                            color: AppConstants.primaryButtonColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '已專注: ${timerProvider.focusCount}',
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppConstants.primaryButtonColor,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            _buildLuffyImage(state, petViewModel),
            const SizedBox(height: 48),
            Text(
              timerProvider.timeString,
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 48),
            _buildActionButtons(context, timerProvider, petName),
            const SizedBox(height: 28),
            _buildPetFriendsButton(context),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildPetFriendsButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PetManagementScreen()),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: AppConstants.primaryButtonColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(22),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.pets,
              size: 18,
              color: AppConstants.primaryButtonColor,
            ),
            SizedBox(width: 6),
            Text(
              '路飛的好朋友',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppConstants.primaryButtonColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRewardModal(BuildContext context, TimerProvider provider,
      String petName, PetViewModel petVM) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (ctx) => RewardModal(
        currentFocusCount: provider.focusCount,
        storyText: provider.currentRewardStory ?? '加載故事中...',
        petName: petName,
        petImageUrl: _getImagePathForState(TimerState.finished, petVM),
        isNetworkImage:
            petVM.selectedPet != null && !petVM.selectedPet!.isLocalAsset,
        onClaimReward: () {
          provider.resetAfterReward();
        },
      ),
    );
  }

  String _getImagePathForState(TimerState state, PetViewModel petVM) {
    final pet = petVM.selectedPet;
    if (pet != null) {
      switch (state) {
        case TimerState.initial:
          return pet.normalImageUrl;
        case TimerState.running:
          return pet.sleepingImageUrl;
        case TimerState.finished:
          return pet.normalImageUrl;
        case TimerState.failed:
          return pet.failedImageUrl;
      }
    } else {
      switch (state) {
        case TimerState.initial:
          return AppConstants.luffyAwake;
        case TimerState.running:
          return AppConstants.luffySleeping;
        case TimerState.finished:
          return AppConstants.luffyHappy;
        case TimerState.failed:
          return AppConstants.luffyInterrupted;
      }
    }
  }

  Widget _buildLuffyImage(TimerState state, PetViewModel petVM) {
    final pet = petVM.selectedPet;
    final imagePath = _getImagePathForState(state, petVM);
    // 只有選了自定義寵物且不是本地 asset 的情況才用 Image.network
    final isNetwork = pet != null && !pet.isLocalAsset;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pet != null) ...[
          Container(
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              pet.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppConstants.primaryTextColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Container(
          width: 250,
          height: 250,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.5),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: ClipOval(
            child: isNetwork
                ? FirebaseStorageImage(
                    imageUrl: imagePath,
                    fit: BoxFit.cover,
                    errorBuilder: _buildImageError,
                  )
                : Image.asset(
                    imagePath,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildImageError(context, error),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageError(BuildContext context, Object error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.pets,
            size: 48,
            color: AppConstants.primaryButtonColor,
          ),
          const SizedBox(height: 8),
          Text(
            '圖片載入中\n(或載入失敗)',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
      BuildContext context, TimerProvider provider, String petName) {
    if (provider.state == TimerState.initial) {
      return ElevatedButton(
        // 第一次開始專注會呼叫提醒，這裡需要修改_handleStartFocus
        onPressed: () async {
          if (!_hasRequestedPermission) {
            _hasRequestedPermission = true;
            final userAgreed =
                await _showNotificationExplanationDialog(petName);
            if (userAgreed == true) {
              await _notificationService.requestPermission();
            }
          }
          provider.startTimer();
        },
        child: const Text('開始專注', style: TextStyle(fontSize: 18)),
      );
    } else if (provider.state == TimerState.running) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppConstants.cancelButtonColor,
        ),
        onPressed: () => _showGiveUpDialog(context, provider, petName),
        child: const Text('放棄',
            style:
                TextStyle(fontSize: 18, color: AppConstants.primaryTextColor)),
      );
    } else if (provider.state == TimerState.failed) {
      return ElevatedButton(
        onPressed: () => provider.resetFromFailure(),
        child: const Text('沒關係，下次再加油！', style: TextStyle(fontSize: 18)),
      );
    } else {
      return ElevatedButton(
        onPressed: () => provider.resetAfterReward(),
        child: const Text('再專注一次', style: TextStyle(fontSize: 18)),
      );
    }
  }

  void _showGiveUpDialog(
      BuildContext context, TimerProvider provider, String petName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.help_outline,
                color: AppConstants.primaryButtonColor, size: 48),
            const SizedBox(height: 16),
            Text(
              '確定要放棄嗎？',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppConstants.primaryTextColor,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              '$petName正在安靜地睡覺，現在放棄會把$petName吵醒喔！',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
                color: AppConstants.primaryTextColor,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('繼續專注',
                        style: TextStyle(color: AppConstants.primaryTextColor)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.cancelButtonColor,
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      provider.giveUp();
                    },
                    child: const Text('放棄',
                        style: TextStyle(color: AppConstants.primaryTextColor)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showFailureDialog(
      BuildContext context, TimerProvider provider, String petName) {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sentiment_very_dissatisfied,
                color: Colors.orange, size: 48),
            const SizedBox(height: 16),
            Text(
              '專注中斷了...',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppConstants.primaryTextColor,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              '嗚嗚，$petName被吵醒了！\n這次的專注時間沒能完成，$petName看起來有點失落。',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
                color: AppConstants.primaryTextColor,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  provider.resetFromFailure();
                },
                child: Text('對不起，$petName'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
