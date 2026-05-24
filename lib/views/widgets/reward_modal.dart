import 'package:flutter/material.dart';
import '../../core/constants.dart';
import 'firebase_storage_image.dart';

class RewardModal extends StatelessWidget {
  final int currentFocusCount;
  final String storyText;
  final String petName;
  final String petImageUrl;
  final bool isNetworkImage;
  final VoidCallback onClaimReward;

  const RewardModal({
    super.key,
    required this.currentFocusCount,
    required this.storyText,
    required this.petName,
    required this.petImageUrl,
    required this.isNetworkImage,
    required this.onClaimReward,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: isNetworkImage
                  ? FirebaseStorageImage(
                      imageUrl: petImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __) => const Icon(Icons.pets,
                          size: 40, color: AppConstants.primaryButtonColor),
                    )
                  : Image.asset(
                      petImageUrl,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '專注完成！',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.primaryButtonColor,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            '這是你累積完成的第 $currentFocusCount 個番茄鐘。',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppConstants.primaryTextColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.4,
            ),
            decoration: BoxDecoration(
              color: AppConstants.backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              child: Text(
                storyText,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: AppConstants.primaryTextColor,
                ),
                textAlign: TextAlign.justify,
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                onClaimReward();
              },
              child: Text('摸摸$petName的頭並繼續'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
