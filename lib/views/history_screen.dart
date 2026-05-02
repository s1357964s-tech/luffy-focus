import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../viewmodels/timer_provider.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final timerProvider = context.watch<TimerProvider>();
    final history = timerProvider.focusHistory;

    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: AppBar(
        title: const Text('專注歷史'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppConstants.primaryTextColor,
      ),
      body: history.isEmpty
          ? _buildEmptyState(context)
          : _buildHistoryList(context, history),
    );
  }

  // 尚無紀錄時的空狀態畫面
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: AppConstants.primaryTextColor.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '還沒有專注紀錄喔！\n完成一次番茄鐘就能解鎖路飛的夢境故事 🐶',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: AppConstants.primaryTextColor.withOpacity(0.5),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // 歷史紀錄列表
  Widget _buildHistoryList(BuildContext context, List<FocusRecord> history) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final record = history[index];
        return _buildHistoryCard(context, record, index + 1, history.length);
      },
    );
  }

  // 單張歷史紀錄卡片
  Widget _buildHistoryCard(
    BuildContext context,
    FocusRecord record,
    int displayIndex,
    int total,
  ) {
    // 從故事文字中擷取標題（【...】之間的文字）
    final titleMatch = RegExp(r'【(.+?)】').firstMatch(record.storyText);
    final title = titleMatch != null ? titleMatch.group(1)! : '路飛的夢境';
    
    // 去掉標題後的純故事內容
    final storyBody = record.storyText
        .replaceFirst(RegExp(r'【.+?】\n?'), '')
        .trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showStoryDetail(context, title, storyBody, record),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左側：序號圓圈
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppConstants.primaryButtonColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '#${total - displayIndex + 1}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.primaryButtonColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // 右側：標題與時間
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.primaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatDateTime(record.completedAt),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppConstants.primaryTextColor.withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      storyBody,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: AppConstants.primaryTextColor.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
              // 箭頭
              Icon(
                Icons.chevron_right,
                color: AppConstants.primaryTextColor.withOpacity(0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 點擊卡片後展示故事全文
  void _showStoryDetail(
    BuildContext context,
    String title,
    String storyBody,
    FocusRecord record,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // 頂部拉條
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 標題區
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Column(
                  children: [
                    const Icon(
                      Icons.auto_stories,
                      size: 36,
                      color: AppConstants.primaryButtonColor,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppConstants.primaryTextColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '完成於 ${_formatDateTime(record.completedAt)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppConstants.primaryTextColor.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 24),
              // 故事全文
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppConstants.backgroundColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      storyBody,
                      style: const TextStyle(
                        fontSize: 16,
                        height: 1.8,
                        color: AppConstants.primaryTextColor,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 格式化日期時間
  String _formatDateTime(DateTime dateTime) {
    final year = dateTime.year;
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$year/$month/$day $hour:$minute';
  }
}
