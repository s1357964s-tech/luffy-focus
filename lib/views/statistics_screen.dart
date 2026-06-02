import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../viewmodels/timer_provider.dart';
import 'widgets/weekly_bar_chart.dart';

/// 每日/每週專注統計頁面
/// 展示今日摘要、七日趨勢圖、連續天數 Streak、本週總覽
class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TimerProvider>();

    // 從 Provider 取得統計資料
    final todayCount = provider.todayFocusCount;
    final todayMinutes = provider.todayFocusMinutes;
    final streak = provider.currentStreak;
    final weekSummary = provider.thisWeekSummary;
    final last7Days = provider.last7DaysFocusCounts;
    final last7Labels = provider.last7DaysLabels;

    // 計算日均（避免除以零）
    final daysElapsed = DateTime.now().weekday; // 本週已過的天數
    final dailyAvg = weekSummary.count > 0
        ? (weekSummary.count / daysElapsed).toStringAsFixed(1)
        : '0';

    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: AppBar(
        title: const Text('專注統計'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppConstants.primaryTextColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          children: [
            // ===== 今日摘要 + Streak =====
            _buildTodaySummaryCard(context, todayCount, todayMinutes, streak),

            const SizedBox(height: 20),

            // ===== 七日柱狀圖 =====
            _buildWeeklyChartCard(context, last7Days, last7Labels),

            const SizedBox(height: 20),

            // ===== 本週總覽 =====
            _buildWeekOverviewCard(context, weekSummary, dailyAvg),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// 今日摘要卡片（含 Streak）
  Widget _buildTodaySummaryCard(
    BuildContext context,
    int todayCount,
    int todayMinutes,
    int streak,
  ) {
    final now = DateTime.now();
    final dateStr = '${now.month}/${now.day}（${{
      1: '一',
      2: '二',
      3: '三',
      4: '四',
      5: '五',
      6: '六',
      7: '日'
    }[now.weekday]}）';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppConstants.cardBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 頂部標題行
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.pets,
                      size: 22, color: AppConstants.primaryButtonColor),
                  SizedBox(width: 8),
                  Text(
                    '今日專注',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.primaryTextColor,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 16,
                      color:
                          AppConstants.primaryTextColor.withValues(alpha: 0.5)),
                  const SizedBox(width: 4),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 14,
                      color:
                          AppConstants.primaryTextColor.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 今日數據
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem(
                  Icons.local_fire_department_rounded, '$todayCount', '次'),
              Container(
                width: 1,
                height: 40,
                color: AppConstants.primaryTextColor.withValues(alpha: 0.1),
              ),
              _buildStatItem(Icons.timer_outlined, '$todayMinutes', '分鐘'),
            ],
          ),

          // Streak 分隔線
          const SizedBox(height: 16),
          Divider(color: AppConstants.primaryTextColor.withValues(alpha: 0.08)),
          const SizedBox(height: 12),

          // Streak 顯示
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                streak > 0 ? Icons.whatshot_rounded : Icons.bedtime_rounded,
                size: 24,
                color: streak > 0
                    ? AppConstants.streakFireColor
                    : AppConstants.primaryTextColor.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 8),
              Text(
                streak > 0 ? '連續專注 $streak 天！' : '今天還沒開始專注喔～',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: streak > 0
                      ? AppConstants.streakFireColor
                      : AppConstants.primaryTextColor.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 數據項（圖示 + 數字 + 單位）
  Widget _buildStatItem(IconData icon, String value, String unit) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Icon(icon, size: 22, color: AppConstants.primaryButtonColor),
            const SizedBox(width: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppConstants.primaryTextColor,
              ),
            ),
            const SizedBox(width: 4),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                unit,
                style: TextStyle(
                  fontSize: 14,
                  color: AppConstants.primaryTextColor.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 七日柱狀圖卡片
  Widget _buildWeeklyChartCard(
    BuildContext context,
    List<int> counts,
    List<String> labels,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppConstants.cardBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.show_chart_rounded,
                  size: 22, color: AppConstants.primaryButtonColor),
              SizedBox(width: 8),
              Text(
                '本週專注趨勢',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.primaryTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 170,
            child: WeeklyBarChart(
              dailyCounts: counts,
              dayLabels: labels,
            ),
          ),
        ],
      ),
    );
  }

  /// 本週總覽卡片
  Widget _buildWeekOverviewCard(
    BuildContext context,
    ({int count, int minutes}) summary,
    String dailyAvg,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppConstants.cardBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.assessment_outlined,
                  size: 22, color: AppConstants.primaryButtonColor),
              SizedBox(width: 8),
              Text(
                '本週總覽',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppConstants.primaryTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildOverviewRow('總專注次數', '${summary.count} 次'),
          const SizedBox(height: 12),
          _buildOverviewRow('總專注時長', '${summary.minutes} 分鐘'),
          const SizedBox(height: 12),
          _buildOverviewRow('日均專注', '$dailyAvg 次'),
        ],
      ),
    );
  }

  /// 總覽行（標籤 + 數值）
  Widget _buildOverviewRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: AppConstants.primaryTextColor.withValues(alpha: 0.7),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppConstants.primaryTextColor,
          ),
        ),
      ],
    );
  }
}
