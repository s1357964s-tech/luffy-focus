import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../viewmodels/timer_provider.dart';
import '../viewmodels/pet_viewmodel.dart';
import '../services/notification_service.dart';
import '../services/pet_image_cache.dart';
import '../services/storage_service.dart';
import 'widgets/reward_modal.dart';
import 'history_screen.dart';
import 'statistics_screen.dart';
import 'pet_management_screen.dart';
import 'pet_upload_screen.dart';
import 'widgets/firebase_storage_image.dart';
import '../services/sound_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  TimerState? _previousState;
  final NotificationService _notificationService = NotificationService();

  // 追蹤系統通知是否已授權
  bool _isNotificationGranted = true;
  // 追蹤是否曾發起過通知權限請求
  bool _hasRequestedNotification = false;
  // 追蹤遠端最新版本
  String? _latestVersion;
  List<String> _updateFeatures = [];

  String? _missingPetPromptPetId;
  final Set<String> _verifiedPetImageUrls = {};
  final Set<String> _verifyingPetImageUrls = {};
  final Set<String> _precachePetIds = {};
  bool _isHandlingMissingPet = false;

  @override
  void initState() {
    super.initState();
    // 註冊生命週期觀察者，用於監聽 App 前後台切換
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionStatus();
    _checkLatestVersion();
    _checkAndShowWhatsNewDialog();
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
      _checkPermissionStatus(); // 回到前台時即時重新整理通知權限狀態
      _checkLatestVersion(); // 同步刷新雲端最新版本狀態
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

    // 監聽狀態變化，若從 running 變成 finished，則彈出獎勵並播放慶祝叫聲
    if (_previousState == TimerState.running && state == TimerState.finished) {
      final species = petViewModel.selectedPet?.species ?? 'dog';
      SoundService().playFocusCompleteSound(species);
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
            // 新增：通知權限引導 Banner
            if (_hasRequestedNotification && !_isNotificationGranted && timerProvider.state != TimerState.running)
              _buildNotificationGuideBanner(context, petName),
            // 新增：軟體版本更新 Banner
            if (_hasNewVersion && timerProvider.state != TimerState.running)
              _buildVersionUpgradeBanner(context),
            const Spacer(),
            _buildLuffyImage(state, petViewModel),
            const SizedBox(height: 48),
            Text(
              timerProvider.timeString,
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 48),
            _buildActionButtons(context, timerProvider, petName),
            if (state != TimerState.running) ...[
              const SizedBox(height: 28),
              _buildPetFriendsButton(context),
            ],
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
    if (isNetwork) {
      _verifyPetImageExists(petVM, pet, imagePath);
      _precachePetImages(pet);
      unawaited(petVM.ensureAvatarStatesReady(pet));
    }

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
                    placeholderImageUrl: imagePath == pet.normalImageUrl
                        ? pet.normalImageUrl
                        : null,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, retry) =>
                        _buildMissingPetImageError(context, petVM, pet, error),
                  )
                : Image.asset(
                    imagePath,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildLocalImageError(context),
                  ),
          ),
        ),
      ],
    );
  }

  void _precachePetImages(CustomPet pet) {
    if (_precachePetIds.contains(pet.id)) return;
    _precachePetIds.add(pet.id);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final urls = {
        pet.normalImageUrl,
        pet.sleepingImageUrl,
        pet.failedImageUrl,
      }.where((url) => url.isNotEmpty && url.startsWith('http'));

      unawaited(PetImageCache.preloadAll(urls));
    });
  }

  Widget _buildMissingPetImageError(
    BuildContext context,
    PetViewModel petViewModel,
    CustomPet pet,
    Object error,
  ) {
    if (_missingPetPromptPetId != pet.id) {
      _missingPetPromptPetId = pet.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && petViewModel.selectedPetId == pet.id) {
          _showMissingPetDialog(context, petViewModel, pet);
        }
      });
    }

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
            '夥伴暫時離開了',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: AppConstants.primaryButtonColor,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () =>
                _handleMissingPetUpload(context, petViewModel, pet),
            icon: const Icon(Icons.auto_fix_high, size: 16),
            label: const Text('重新上傳'),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalImageError(BuildContext context) {
    return Center(
      child: Icon(
        Icons.pets,
        size: 48,
        color: AppConstants.primaryButtonColor.withValues(alpha: 0.75),
      ),
    );
  }

  Future<void> _showMissingPetDialog(
    BuildContext context,
    PetViewModel petViewModel,
    CustomPet pet,
  ) async {
    if (_isHandlingMissingPet) return;

    final shouldUpload = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('夥伴暫時離開了'),
        content: Text('無法取得「${pet.name}」的圖片，需要重新上傳圖片。系統會先移除目前這位夥伴。'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('重新上傳'),
          ),
        ],
      ),
    );

    if (shouldUpload == true && context.mounted) {
      await _handleMissingPetUpload(context, petViewModel, pet);
    }
  }

  void _verifyPetImageExists(
    PetViewModel petViewModel,
    CustomPet pet,
    String imageUrl,
  ) {
    if (_verifiedPetImageUrls.contains(imageUrl) ||
        _verifyingPetImageUrls.contains(imageUrl) ||
        _missingPetPromptPetId == pet.id) {
      return;
    }

    _verifyingPetImageUrls.add(imageUrl);
    Future<void>(() async {
      try {
        await FirebaseStorage.instance
            .refFromURL(imageUrl)
            .getMetadata()
            .timeout(const Duration(seconds: 6));
        _verifiedPetImageUrls.add(imageUrl);
      } on FirebaseException catch (error) {
        if (error.code == 'object-not-found' ||
            error.code == 'unauthorized' ||
            error.code == 'invalid-url') {
          _promptMissingPetIfCurrent(petViewModel, pet);
        }
      } catch (_) {
        // Network timeouts can recover; let the image widget keep loading/retrying.
      } finally {
        _verifyingPetImageUrls.remove(imageUrl);
      }
    });
  }

  void _promptMissingPetIfCurrent(PetViewModel petViewModel, CustomPet pet) {
    if (!mounted ||
        _missingPetPromptPetId == pet.id ||
        petViewModel.selectedPetId != pet.id) {
      return;
    }

    _missingPetPromptPetId = pet.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && petViewModel.selectedPetId == pet.id) {
        _showMissingPetDialog(context, petViewModel, pet);
      }
    });
  }

  Future<void> _handleMissingPetUpload(
    BuildContext context,
    PetViewModel petViewModel,
    CustomPet pet,
  ) async {
    if (_isHandlingMissingPet) return;
    _isHandlingMissingPet = true;

    try {
      await petViewModel.deletePet(pet);
      if (!context.mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PetUploadScreen()),
      );
    } finally {
      if (mounted) {
        _isHandlingMissingPet = false;
        _missingPetPromptPetId = null;
      }
    }
  }

  Widget _buildActionButtons(
      BuildContext context, TimerProvider provider, String petName) {
    if (provider.state == TimerState.initial) {
      return ElevatedButton(
        onPressed: () async {
          // 標記已發起過通知權限請求
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('has_requested_notification', true);
          _checkPermissionStatus();

          final isGranted = await Permission.notification.isGranted;
          if (!isGranted) {
            if (!context.mounted) return;
            final userAgreed =
                await _showNotificationExplanationDialog(petName);
            if (userAgreed == true) {
              final status = await Permission.notification.request();
              _checkPermissionStatus();
              if (status.isPermanentlyDenied || status.isDenied) {
                if (context.mounted) {
                  _showJumpToSettingsDialog(context, petName);
                }
              } else {
                provider.startTimer();
              }
            }
          } else {
            provider.startTimer();
          }
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

  // ──────────────────────────────────────────────────────────────────────────
  // 新增助手方法（權限與版本檢查）
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _checkPermissionStatus() async {
    final granted = await Permission.notification.isGranted;
    final prefs = await SharedPreferences.getInstance();
    final hasRequested = prefs.getBool('has_requested_notification') ?? false;
    if (mounted) {
      setState(() {
        _isNotificationGranted = granted;
        _hasRequestedNotification = hasRequested;
      });
    }
  }

  Future<void> _checkLatestVersion() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('version')
          .get()
          .timeout(const Duration(seconds: 5));
      if (snapshot.exists) {
        final data = snapshot.data();
        final remoteVersion = data?['latestVersion'] as String?;
        final remoteFeatures = List<String>.from(data?['features'] ?? []);
        if (remoteVersion != null) {
          if (mounted) {
            setState(() {
              _latestVersion = remoteVersion;
              _updateFeatures = remoteFeatures;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('[VersionCheck] Failed to check remote version: $e');
    }
  }

  bool _compareVersion(String current, String latest) {
    try {
      final currentParts = current.split('.').map(int.parse).toList();
      final latestParts = latest.split('.').map(int.parse).toList();
      for (var i = 0; i < min(currentParts.length, latestParts.length); i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
      return latestParts.length > currentParts.length;
    } catch (_) {
      return current != latest;
    }
  }

  bool get _hasNewVersion {
    if (_latestVersion == null) return false;
    return _compareVersion(AppConstants.appVersion, _latestVersion!);
  }

  Future<void> _checkAndShowWhatsNewDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSeenVersion = prefs.getString('last_seen_version');
    if (lastSeenVersion == null || _compareVersion(lastSeenVersion, AppConstants.appVersion)) {
      if (!mounted) return;
      _showWhatsNewDialog(context);
      await prefs.setString('last_seen_version', AppConstants.appVersion);
    }
  }

  void _showWhatsNewDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: AppConstants.backgroundColor,
        title: const Row(
          children: [
            Icon(Icons.pets_rounded, color: AppConstants.primaryButtonColor, size: 28),
            SizedBox(width: 8),
            Text(
              '版本更新說明 v1.1.0',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppConstants.primaryTextColor,
              ),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.pets_rounded, color: AppConstants.primaryButtonColor, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '自定義寵物生成',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppConstants.primaryTextColor),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 18),
              Row(
                children: [
                  Icon(Icons.pets_rounded, color: AppConstants.primaryButtonColor, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '專注完成歡呼聲',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppConstants.primaryTextColor),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 18),
              Row(
                children: [
                  Icon(Icons.pets_rounded, color: AppConstants.primaryButtonColor, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '專注時跳出應用會有提示音',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppConstants.primaryTextColor),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.primaryButtonColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('我知道了！', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  void _showJumpToSettingsDialog(BuildContext context, String petName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: const Text('開啟通知權限', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          '🐾 由於您先前拒絕過通知權限，系統無法再次發起彈窗。\n\n'
          '請前往手機「設定」->「Luffy Focus」->「通知」開啟權限，這樣$petName才能在您滑走 App 時提醒您！',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('先不用', style: TextStyle(color: Colors.grey.shade500)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryButtonColor,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await openAppSettings();
            },
            child: const Text('去開啟'),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationGuideBanner(BuildContext context, String petName) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppConstants.primaryButtonColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppConstants.primaryButtonColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_active_rounded, color: AppConstants.primaryButtonColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '我想讓 $petName 通知我',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.primaryTextColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '開啟通知以便在專注中退至後台時接收提醒與叫聲',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppConstants.primaryTextColor.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.primaryButtonColor,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _showJumpToSettingsDialog(context, petName),
            child: const Text(
              '去開啟',
              style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionUpgradeBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.upgrade_rounded, color: Colors.blue.shade400),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '發現新版本 v$_latestVersion',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppConstants.primaryTextColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '點擊查看新功能並前往 App Store 升級',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppConstants.primaryTextColor.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade400,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => _showUpgradeDetailsDialog(context),
            child: const Text(
              '查看',
              style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showUpgradeDetailsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: Text('升級至新版本 v$_latestVersion', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '本次更新內容如下：',
                style: TextStyle(fontWeight: FontWeight.bold, height: 1.5),
              ),
              const SizedBox(height: 12),
              ..._updateFeatures.map((f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(child: Text(f, style: const TextStyle(height: 1.4))),
                  ],
                ),
              )),
              const SizedBox(height: 20),
              const Text(
                '請前往 App Store 搜尋「路飛番茄鐘」以更新至最新版本！',
                style: TextStyle(color: AppConstants.primaryButtonColor, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────
// 更新日誌特色項目元件
// ──────────────────────────────────────────────────────────────────────────

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppConstants.primaryTextColor.withOpacity(0.8)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.primaryTextColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppConstants.primaryTextColor.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
