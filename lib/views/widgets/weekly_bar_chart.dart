import 'package:flutter/material.dart';
import '../../core/constants.dart';

/// 七日專注趨勢柱狀圖
/// 使用 Flutter 原生元件手繪，零外部依賴
/// 柱子從底部動畫長高，今天高亮橘色，其他天淡化
class WeeklyBarChart extends StatefulWidget {
  final List<int> dailyCounts;
  final List<String> dayLabels;

  const WeeklyBarChart({
    super.key,
    required this.dailyCounts,
    required this.dayLabels,
  });

  @override
  State<WeeklyBarChart> createState() => _WeeklyBarChartState();
}

class _WeeklyBarChartState extends State<WeeklyBarChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // 柱狀圖入場動畫：0.6 秒從 0 長到滿高
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _animation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 找出最大值，用於計算柱子比例高度
    final maxCount = widget.dailyCounts.reduce((a, b) => a > b ? a : b);
    // 柱狀圖區域的最大高度
    const double maxBarHeight = 120.0;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(7, (index) {
            final count = widget.dailyCounts[index];
            final label = widget.dayLabels[index];
            final isToday = index == 6; // 最後一個索引 = 今天

            // 計算柱子高度（最少 4px 以保持可見性）
            final double barHeight = maxCount > 0
                ? (count / maxCount * maxBarHeight * _animation.value)
                    .clamp(count > 0 ? 4.0 : 0.0, maxBarHeight)
                : 0.0;

            return _buildBar(
              label: label,
              count: count,
              height: barHeight,
              isToday: isToday,
            );
          }),
        );
      },
    );
  }

  /// 單根柱子（包含數字 + 柱體 + 星期標籤）
  Widget _buildBar({
    required String label,
    required int count,
    required double height,
    required bool isToday,
  }) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // 頂部數字
        Text(
          count > 0 ? '$count' : '',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isToday
                ? AppConstants.chartBarColor
                : AppConstants.primaryTextColor.withOpacity(0.5),
          ),
        ),
        const SizedBox(height: 4),
        // 柱體
        Container(
          width: 28,
          height: height,
          decoration: BoxDecoration(
            color: isToday
                ? AppConstants.chartBarColor
                : AppConstants.chartBarInactive,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ),
        const SizedBox(height: 6),
        // 底部星期標籤
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
            color: isToday
                ? AppConstants.primaryTextColor
                : AppConstants.primaryTextColor.withOpacity(0.5),
          ),
        ),
      ],
    );
  }
}
