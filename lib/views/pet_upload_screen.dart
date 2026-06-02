import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../services/pet_image_cache.dart';
import '../viewmodels/pet_viewmodel.dart';
import '../services/billing_service.dart';
import 'widgets/firebase_storage_image.dart';

class PetUploadScreen extends StatefulWidget {
  const PetUploadScreen({super.key});

  @override
  State<PetUploadScreen> createState() => _PetUploadScreenState();
}

class _PetUploadScreenState extends State<PetUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _featureNoteController = TextEditingController();
  Uint8List? _selectedImageBytes;
  String? _selectedImageMimeType;
  bool _allowPop = false;
  bool _isLeaving = false;
  bool _isSavingName = false;
  /// 是否正在等待後端收據驗證（Apple 已確認付款但後端尚未回應）
  bool _isPurchaseVerifying = false;
  /// 是否正在手動查詢訂單狀態（「我已支付」的載入狀態）
  bool _isManualChecking = false;
  StreamSubscription<CustomPetPurchaseOutcome>? _purchaseOutcomeSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final billingService = context.read<BillingService>();
      unawaited(billingService.initialize());
      // 訂閱 StoreKit 彈窗即時結果，彈窗關閉後立即觸發 _handlePurchaseOutcome
      _purchaseOutcomeSubscription =
          billingService.purchaseOutcomeStream.listen(_handlePurchaseOutcome);
    });
  }

  @override
  void dispose() {
    _purchaseOutcomeSubscription?.cancel();
    _nameController.dispose();
    _featureNoteController.dispose();
    super.dispose();
  }

  /// 發起購買（fire-and-forget），結果統一由 [_handlePurchaseOutcome] 處理
  Future<void> _startPurchaseFlow(BuildContext context) async {
    await context.read<BillingService>().purchaseCustomPetUnlock();
  }

  /// 收到 StoreKit 彈窗即時結果後的處理邏輯
  /// - canceled：停留頁面，不做任何動作
  /// - failed：顯示固定錯誤 Toast，停留頁面
  /// - purchased：進入等待後端驗證的 loading，確認後進入上傳流程
  Future<void> _handlePurchaseOutcome(CustomPetPurchaseOutcome outcome) async {
    if (!mounted) return;
    switch (outcome) {
      case CustomPetPurchaseOutcome.canceled:
        break;

      case CustomPetPurchaseOutcome.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('付款失敗，請稍後再試。'),
            backgroundColor: Colors.redAccent,
          ),
        );
        break;

      case CustomPetPurchaseOutcome.purchased:
        setState(() => _isPurchaseVerifying = true);
        try {
          final billingService = context.read<BillingService>();
          // 等待後端驗證，正常情況下通常很快，但若網路慢可能需要等待
          final confirmed = await billingService.waitForCreditConfirmation(
            timeout: const Duration(seconds: 15),
          );
          if (!mounted) return;
          if (confirmed) {
            setState(() {
              _isPurchaseVerifying = false;
            });
            await _pickImage(context);
          } else {
            // 驗證失敗或超清，不重置 _isPurchaseVerifying，讓使用者留在等待頁面手動重試或放棄
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  billingService.errorMessage ?? '驗證逾時，請點擊「我已支付」手動重新驗證。',
                ),
                backgroundColor: Colors.orangeAccent,
              ),
            );
          }
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('驗證逾時，請點擊「我已支付」手動重新驗證。'),
              backgroundColor: Colors.orangeAccent,
            ),
          );
        }
        break;
    }
  }

  /// 手動點擊「我已支付」時重新請求訂單狀態
  Future<void> _handleManualCheck(BuildContext context) async {
    if (_isManualChecking) return;
    setState(() {
      _isManualChecking = true;
    });

    try {
      final billingService = context.read<BillingService>();
      // 重新向後端請求 credit 狀態
      await billingService.refreshCustomPetCredit(timeout: const Duration(seconds: 15));

      if (!context.mounted) return;

      if (billingService.hasUnusedCredit) {
        setState(() {
          _isManualChecking = false;
          _isPurchaseVerifying = false;
        });
        await _pickImage(context);
      } else {
        setState(() {
          _isManualChecking = false;
        });
        final errorMsg = billingService.errorMessage;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg ?? '付款結果確認中，請稍候再試或繼續等待。'),
            backgroundColor:
                errorMsg != null ? Colors.redAccent : Colors.orangeAccent,
          ),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      setState(() {
        _isManualChecking = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('連線失敗，請稍候再試。'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  /// 選取並壓縮單張照片
  /// - 使用 image_picker 內建的 maxWidth / maxHeight / imageQuality 參數
  ///   在選取時即進行一次壓縮，減少記憶體與網路傳輸量
  /// - 限制只能選一張圖片（pickImage 本身即為單選）
  Future<void> _pickImage(BuildContext context) async {
    final billingService = context.read<BillingService>();
    final petViewModel = context.read<PetViewModel>();

    if (!billingService.hasUnusedCredit) {
      await _startPurchaseFlow(context);
      return;
    }

    if (petViewModel.isAtPetLimit) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已達寵物上限，請先刪除一隻再新增。')),
      );
      return;
    }

    // 選取單張圖片，同時限制解析度與品質以壓縮檔案
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 640,
      maxHeight: 640,
      imageQuality: 52,
      requestFullMetadata: false,
    );

    if (image == null) return;

    final imageMimeType = _normalizedImageMimeType(image);

    // 讀取壓縮後的位元組，先留在預覽畫面，等使用者補充特徵後再送出。
    final Uint8List bytes = await image.readAsBytes();

    // 額外安全檢查：若壓縮後仍超過 5MB，提示使用者換一張
    if (bytes.lengthInBytes > 5 * 1024 * 1024) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('圖片太大了，請選擇一張較小的照片（5MB 以下）'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    if (!mounted) return;
    petViewModel.resetUploadState();
    setState(() {
      _selectedImageBytes = bytes;
      _selectedImageMimeType = imageMimeType;
    });
  }

  Future<void> _submitSelectedImage(BuildContext context) async {
    final bytes = _selectedImageBytes;
    final mimeType = _selectedImageMimeType;
    if (bytes == null || mimeType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇一張寵物照片')),
      );
      return;
    }

    final billingService = context.read<BillingService>();
    if (!billingService.hasUnusedCredit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先購買新增寵物名額')),
      );
      return;
    }

    final viewModel = context.read<PetViewModel>();
    await viewModel.uploadAndAnalyze(
      bytes,
      imageMimeType: mimeType,
      featureNote: _featureNoteController.text.trim(),
    );

    if (!context.mounted) return;
    if (viewModel.uploadState == PetUploadState.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(viewModel.errorMessage ?? '上傳失敗'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  String _normalizedImageMimeType(XFile image) {
    final mimeType = image.mimeType?.toLowerCase();
    if (mimeType == 'image/jpeg' ||
        mimeType == 'image/png' ||
        mimeType == 'image/webp') {
      return mimeType!;
    }

    final path = image.path.toLowerCase();
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  void _clearLocalDraft() {
    _nameController.clear();
    _featureNoteController.clear();
    _selectedImageBytes = null;
    _selectedImageMimeType = null;
  }

  Future<void> _discardDraftAndPop(BuildContext context) async {
    if (_isLeaving) return;
    _isLeaving = true;

    final viewModel = context.read<PetViewModel>();
    await viewModel.discardPendingUpload();
    _clearLocalDraft();

    if (!context.mounted) return;
    _popScreen(context);
  }

  Future<void> _precacheSavedPetImages(PetViewModel viewModel) async {
    final urls = <String>{
      if (viewModel.pendingNormalUrl != null) viewModel.pendingNormalUrl!,
      if (viewModel.pendingSleepingUrl != null) viewModel.pendingSleepingUrl!,
      if (viewModel.pendingFailedUrl != null) viewModel.pendingFailedUrl!,
    }.where((url) => url.isNotEmpty && url.startsWith('http'));

    await PetImageCache.preloadAll(urls);
  }

  void _popScreen(BuildContext context) {
    if (!context.mounted) return;
    setState(() {
      _allowPop = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  Widget _buildStateUI(
    BuildContext context,
    PetViewModel viewModel,
    BillingService billingService,
  ) {
    switch (viewModel.uploadState) {
      case PetUploadState.idle:
      case PetUploadState.error:
        if (_selectedImageBytes != null) {
          return _buildSelectedImageUI(context, viewModel);
        }
        if (_isPurchaseVerifying) {
          return _buildVerifyingUI(context);
        }
        if (!billingService.hasUnusedCredit) {
          return _buildPurchaseUI(context, billingService);
        }

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.pets,
              size: 80,
              color: AppConstants.primaryButtonColor,
            ),
            const SizedBox(height: 24),
            Text(
              '上傳專屬寵物照片',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              '支援貓、狗，讓牠化身小助手陪你專注！',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppConstants.primaryTextColor.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 48),
            ElevatedButton.icon(
              onPressed: () => _pickImage(context),
              icon: const Icon(Icons.photo_library),
              label: const Text('從相簿選擇'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 50),
              ),
            ),
            if (viewModel.uploadState == PetUploadState.error) ...[
              const SizedBox(height: 24),
              Text(
                '錯誤：${viewModel.errorMessage}',
                style: const TextStyle(color: Colors.redAccent),
              ),
            ]
          ],
        );
      case PetUploadState.analyzing:
        return _buildLoading(context, '正在辨識寵物種類...');
      case PetUploadState.generating:
        return _buildLoading(context, '正在為牠繪製專屬卡通形象...');
      case PetUploadState.naming:
        return _buildNamingUI(context, viewModel);
      case PetUploadState.success:
        final petName = viewModel.completedPetName?.trim().isNotEmpty == true
            ? viewModel.completedPetName!.trim()
            : '新夥伴';
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PetReadyIcon(species: viewModel.completedPetSpecies),
            const SizedBox(height: 24),
            Text(
              '太棒了！',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              '$petName已經準備好陪你專注計畫了',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppConstants.primaryTextColor.withValues(alpha: 0.85),
                fontSize: 16,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: () async {
                final completedPetId = viewModel.completedPetId;
                if (completedPetId != null) {
                  await viewModel.selectPet(completedPetId);
                }
                if (!context.mounted) return;
                viewModel.resetUploadState();
                _clearLocalDraft();
                _popScreen(context);
              },
              child: const Text('開始專注'),
            )
          ],
        );
    }
  }

  /// 購買解鎖畫面：只有說明文案 + 單一購買按鈕
  /// 購買結果由 _handlePurchaseOutcome 統一處理，此處不需任何中間狀態按鈕
  Widget _buildPurchaseUI(
    BuildContext context,
    BillingService billingService,
  ) {
    final isBusy =
        billingService.state == CustomPetPurchaseState.purchasing ||
        billingService.state == CustomPetPurchaseState.loading;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.lock_open,
          size: 76,
          color: AppConstants.primaryButtonColor,
        ),
        const SizedBox(height: 24),
        Text(
          '解鎖新增寵物',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
        ),
        const SizedBox(height: 12),
        Text(
          '購買後可上傳真實寵物照片，讓 AI 繪製專屬卡通形象，一起陪你專注！',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppConstants.primaryTextColor.withValues(alpha: 0.7),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: isBusy ? null : () => _startPurchaseFlow(context),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 50),
          ),
          child: isBusy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text('購買解鎖名額 ${billingService.customPetPriceLabel}'),
        ),
      ],
    );
  }

  /// 支付成功後等待後端收據驗證的 loading 畫面
  Widget _buildVerifyingUI(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(AppConstants.primaryButtonColor),
            strokeWidth: 4,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          '支付成功，正在確認訂單...',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            '若確認時間較長，您可點擊下方按鈕手動刷新狀態。點擊「放棄支付」可先返回，確認成功後您將自動獲得解鎖額度。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppConstants.primaryTextColor.withValues(alpha: 0.6),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 40),
        SizedBox(
          height: 50,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isManualChecking
                      ? null
                      : () async {
                          setState(() {
                            _isPurchaseVerifying = false;
                          });
                          await _discardDraftAndPop(context);
                        },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 50),
                    side: const BorderSide(
                      color: AppConstants.primaryButtonColor,
                      width: 1.5,
                    ),
                    foregroundColor: AppConstants.primaryTextColor,
                  ),
                  child: const Text('放棄支付'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isManualChecking
                      ? null
                      : () => _handleManualCheck(context),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 50),
                  ),
                  child: _isManualChecking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Text('我已支付'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }



  Widget _buildSelectedImageUI(
    BuildContext context,
    PetViewModel viewModel,
  ) {
    final bytes = _selectedImageBytes!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final imageSize = constraints.maxHeight < 620 ? 180.0 : 220.0;

        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: imageSize,
                  height: imageSize,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _featureNoteController,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 120,
                  decoration: InputDecoration(
                    labelText: '補充特徵（選填）',
                    hintText: '例如：眼睛下面有一個痣、左耳比較黑、尾巴末端是白色',
                    labelStyle:
                        const TextStyle(color: AppConstants.primaryTextColor),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppConstants.primaryButtonColor,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (viewModel.uploadState == PetUploadState.error) ...[
                  Text(
                    '錯誤：${viewModel.errorMessage}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  height: 50,
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _pickImage(context),
                          child: const Text('換一張'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _submitSelectedImage(context),
                          child: const Text('送出'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoading(BuildContext context, String text) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(
            valueColor:
                AlwaysStoppedAnimation(AppConstants.primaryButtonColor)),
        const SizedBox(height: 24),
        Text(
          text,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }

  Widget _buildNamingUI(BuildContext context, PetViewModel viewModel) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '形象繪製完成！',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
          ),
          const SizedBox(height: 24),
          if (viewModel.pendingNormalUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              // 判斷是本地 asset 路徑還是網路 URL
              child: viewModel.pendingNormalUrl!.startsWith('assets/')
                  ? Image.asset(
                      viewModel.pendingNormalUrl!,
                      height: 200,
                      width: 200,
                      fit: BoxFit.cover,
                    )
                  : FirebaseStorageImage(
                      imageUrl: viewModel.pendingNormalUrl!,
                      height: 200,
                      width: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, retry) {
                        debugPrint(
                          '[PetAvatar] pending normal image load failed '
                          'url=${viewModel.pendingNormalUrl} error=$error',
                        );
                        return Container(
                          height: 200,
                          width: 200,
                          color: Colors.grey[200],
                          child: Center(
                            child: IconButton(
                              tooltip: '重新載入圖片',
                              icon: const Icon(Icons.refresh),
                              onPressed: retry,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          const SizedBox(height: 32),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: '幫牠取個名字吧',
              labelStyle: const TextStyle(color: AppConstants.primaryTextColor),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: AppConstants.primaryButtonColor, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _isSavingName
                ? null
                : () async {
                    final name = _nameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('請輸入寵物名稱')),
                      );
                      return;
                    }
                    setState(() {
                      _isSavingName = true;
                    });
                    try {
                      await viewModel.savePetNameAndFinish(name);
                      if (context.mounted) {
                        final newPet = viewModel.customPets.firstWhere(
                          (p) => p.id == viewModel.completedPetId,
                          orElse: () => viewModel.customPets.firstWhere(
                            (p) => p.id == viewModel.selectedPetId,
                          ),
                        );
                        if (newPet.isLocalAsset) {
                          await context
                              .read<BillingService>()
                              .consumeLocalFallbackCredit();
                        } else {
                          await context
                              .read<BillingService>()
                              .refreshCustomPetCredit();
                        }
                      }
                      if (context.mounted) {
                        await _precacheSavedPetImages(viewModel);
                      }
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            error.toString().contains('付款')
                                ? error.toString().replaceAll('Exception: ', '')
                                : '保存失敗，請稍後再試。',
                          ),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                    } finally {
                      if (mounted &&
                          viewModel.uploadState == PetUploadState.naming) {
                        setState(() {
                          _isSavingName = false;
                        });
                      }
                    }
                  },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
            child: _isSavingName
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('完成設定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _discardDraftAndPop(context);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('路飛的好朋友',
              style: TextStyle(color: AppConstants.primaryTextColor)),
          backgroundColor: AppConstants.backgroundColor,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppConstants.primaryTextColor),
        ),
        body: Consumer2<PetViewModel, BillingService>(
          builder: (context, viewModel, billingService, child) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: _buildStateUI(context, viewModel, billingService),
              ),
            );
          },
        ),
      ),
    );
  }
}

class PetReadyIcon extends StatelessWidget {
  const PetReadyIcon({super.key, required this.species});

  final String? species;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppConstants.primaryButtonColor.withValues(alpha: 0.14),
      ),
      child: CustomPaint(
        painter: _PetReadyIconPainter(species: species),
      ),
    );
  }
}

class _PetReadyIconPainter extends CustomPainter {
  const _PetReadyIconPainter({required this.species});

  final String? species;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppConstants.primaryButtonColor
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (species) {
      case 'cat':
        _paintCatPaw(canvas, size, paint);
        break;
      case 'dog':
      default:
        _paintDogPaw(canvas, size, paint);
        break;
    }
  }

  void _paintDogPaw(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.62),
        width: w * 0.36,
        height: h * 0.3,
      ),
      paint,
    );
    for (final toe in [
      Offset(w * 0.3, h * 0.35),
      Offset(w * 0.43, h * 0.28),
      Offset(w * 0.57, h * 0.28),
      Offset(w * 0.7, h * 0.35),
    ]) {
      canvas.drawOval(
        Rect.fromCenter(center: toe, width: w * 0.18, height: h * 0.2),
        paint,
      );
    }
  }

  void _paintCatPaw(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.62),
        width: w * 0.3,
        height: h * 0.28,
      ),
      paint,
    );
    for (final toe in [
      Offset(w * 0.34, h * 0.38),
      Offset(w * 0.46, h * 0.31),
      Offset(w * 0.58, h * 0.31),
      Offset(w * 0.7, h * 0.38),
    ]) {
      canvas.drawCircle(toe, w * 0.075, paint);
    }

    final clawPaint = Paint()
      ..color = AppConstants.backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    for (final toe in [
      Offset(w * 0.34, h * 0.31),
      Offset(w * 0.46, h * 0.24),
      Offset(w * 0.58, h * 0.24),
      Offset(w * 0.7, h * 0.31),
    ]) {
      canvas.drawLine(toe, toe.translate(0, -h * 0.045), clawPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PetReadyIconPainter oldDelegate) {
    return oldDelegate.species != species;
  }
}
