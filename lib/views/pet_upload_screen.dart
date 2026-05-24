import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
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

  @override
  void dispose() {
    _nameController.dispose();
    _featureNoteController.dispose();
    super.dispose();
  }

  /// 選取並壓縮單張照片
  /// - 使用 image_picker 內建的 maxWidth / maxHeight / imageQuality 參數
  ///   在選取時即進行一次壓縮，減少記憶體與網路傳輸量
  /// - 限制只能選一張圖片（pickImage 本身即為單選）
  Future<void> _pickImage(BuildContext context) async {
    final billingService = context.read<BillingService>();
    final petViewModel = context.read<PetViewModel>();

    // 先檢查是否付費解鎖
    final canUnlock = await billingService.canUnlockCustomPet();
    if (!canUnlock) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('需要先解鎖自定義寵物功能唷！')),
      );
      return;
    }

    // 選取單張圖片，同時限制解析度與品質以壓縮檔案
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 768,
      maxHeight: 768,
      imageQuality: 60,
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

  Widget _buildStateUI(BuildContext context, PetViewModel viewModel) {
    switch (viewModel.uploadState) {
      case PetUploadState.idle:
      case PetUploadState.error:
        if (_selectedImageBytes != null) {
          return _buildSelectedImageUI(context, viewModel);
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
              '支援貓、狗、兔子，讓牠化身小助手陪你專注！',
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
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 80, color: Colors.green),
            const SizedBox(height: 24),
            Text(
              '太棒了！',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
            ),
            const SizedBox(height: 12),
            const Text('你的專屬寵物已成功加入陪伴行列。'),
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: () {
                viewModel.resetUploadState();
                _nameController.clear();
                _featureNoteController.clear();
                _selectedImageBytes = null;
                _selectedImageMimeType = null;
                Navigator.of(context).pop();
              },
              child: const Text('開始專注'),
            )
          ],
        );
    }
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
                      errorBuilder: (context, error) {
                        debugPrint(
                          '[PetAvatar] pending normal image load failed '
                          'url=${viewModel.pendingNormalUrl} error=$error',
                        );
                        return Container(
                          height: 200,
                          width: 200,
                          color: Colors.grey[200],
                          child: const Icon(Icons.error),
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
            onPressed: () {
              final name = _nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('請輸入寵物名稱')),
                );
                return;
              }
              viewModel.savePetNameAndFinish(name);
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
            child: const Text('完成設定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('路飛的好朋友',
            style: TextStyle(color: AppConstants.primaryTextColor)),
        backgroundColor: AppConstants.backgroundColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppConstants.primaryTextColor),
      ),
      body: Consumer<PetViewModel>(
        builder: (context, viewModel, child) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: _buildStateUI(context, viewModel),
            ),
          );
        },
      ),
    );
  }
}
