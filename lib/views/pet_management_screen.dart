import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../services/storage_service.dart';
import '../viewmodels/pet_viewmodel.dart';
import 'pet_upload_screen.dart';
import 'widgets/firebase_storage_image.dart';

class PetManagementScreen extends StatelessWidget {
  const PetManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('選擇一起專注的夥伴',
            style: TextStyle(color: AppConstants.primaryTextColor)),
        backgroundColor: AppConstants.backgroundColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppConstants.primaryTextColor),
      ),
      body: Consumer<PetViewModel>(
        builder: (context, viewModel, child) {
          final customPets = viewModel.customPets;
          final selectedId = viewModel.selectedPetId;

          return ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              // 預設路飛
              _buildPetCard(
                context: context,
                name: '路飛',
                subtitle: '柴犬 (預設)',
                imageUrl: AppConstants.luffyAwake,
                isSelected: selectedId == null,
                isNetworkImage: false,
                onTap: () => viewModel.selectPet(null),
              ),
              const SizedBox(height: 16),
              const Divider(color: AppConstants.cancelButtonColor),
              const SizedBox(height: 16),

              // 自定義寵物列表
              if (customPets.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40.0),
                    child: Text(
                      '還沒有專屬寵物，快去新增一隻吧！',
                      style: TextStyle(
                        color: AppConstants.primaryTextColor
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                )
              else
                ...customPets.map((pet) => Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: _buildPetCard(
                        context: context,
                        name: pet.name,
                        subtitle: pet.species == 'cat'
                            ? '貓咪'
                            : (pet.species == 'dog' ? '狗狗' : '兔子'),
                        imageUrl: pet.normalImageUrl,
                        isSelected: selectedId == pet.id,
                        isNetworkImage: !pet.isLocalAsset,
                        onTap: () => viewModel.selectPet(pet.id),
                        onDelete: () =>
                            _confirmDeletePet(context, viewModel, pet),
                      ),
                    )),

              const SizedBox(height: 32),
              if (viewModel.isAtPetLimit)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Text(
                    '已達上限（含路飛最多 3 隻寵物）',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color:
                          AppConstants.primaryTextColor.withValues(alpha: 0.5),
                      fontSize: 14,
                    ),
                  ),
                ),
              ElevatedButton.icon(
                onPressed: viewModel.isAtPetLimit
                    ? null // 禁用按鈕
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const PetUploadScreen()),
                        );
                      },
                icon: const Icon(Icons.add),
                label: const Text('路飛的好朋友'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  disabledBackgroundColor:
                      AppConstants.cancelButtonColor.withValues(alpha: 0.5),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPetCard({
    required BuildContext context,
    required String name,
    required String subtitle,
    required String imageUrl,
    required bool isSelected,
    required bool isNetworkImage,
    required VoidCallback onTap,
    Future<void> Function()? onDelete,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? AppConstants.primaryButtonColor.withValues(alpha: 0.2)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppConstants.primaryButtonColor
                : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: isNetworkImage
                  ? FirebaseStorageImage(
                      imageUrl: imageUrl,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __) => Container(
                          width: 60,
                          height: 60,
                          color: Colors.grey[200],
                          child: const Icon(Icons.error)),
                    )
                  : Image.asset(
                      imageUrl,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color:
                          AppConstants.primaryTextColor.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: AppConstants.primaryButtonColor,
                size: 28,
              ),
            if (onDelete != null)
              PopupMenuButton<String>(
                tooltip: '更多',
                icon: const Icon(
                  Icons.more_horiz,
                  color: AppConstants.primaryTextColor,
                ),
                color: Colors.white,
                onSelected: (_) => onDelete(),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: Colors.redAccent),
                        SizedBox(width: 8),
                        Text(
                          '刪除',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeletePet(
    BuildContext context,
    PetViewModel viewModel,
    CustomPet pet,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('刪除寵物'),
        content: Text('確定要刪除「${pet.name}」嗎？這會移除牠的照片與生成圖。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              '刪除',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (shouldDelete != true || !context.mounted) return;

    try {
      await viewModel.deletePet(pet);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已刪除「${pet.name}」')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('刪除失敗，請稍後再試。'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}
