import 'package:flutter/material.dart';
import '../../core/constants.dart';

class RewardModal extends StatelessWidget {
  final int currentFocusCount;
  final String storyText;
  final VoidCallback onClaimReward;

  const RewardModal({
    super.key,
    required this.currentFocusCount,
    required this.storyText,
    required this.onClaimReward,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      title: Column(
        children: [
          const Icon(
            Icons.celebration,
            color: AppConstants.primaryButtonColor,
            size: 48,
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
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              decoration: BoxDecoration(
                color: AppConstants.backgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
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
          ],
        ),
      ),
      actions: [
        Center(
          child: ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onClaimReward();
            },
            child: const Text('摸摸路飛的頭並繼續'),
          ),
        ),
      ],
    );
  }
}
