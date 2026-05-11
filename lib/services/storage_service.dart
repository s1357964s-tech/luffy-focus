import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 單筆歷史紀錄的資料模型
class FocusRecord {
  final String storyText;
  final DateTime completedAt;

  FocusRecord({required this.storyText, required this.completedAt});

  // 序列化為 JSON Map
  Map<String, dynamic> toJson() => {
    'storyText': storyText,
    'completedAt': completedAt.toIso8601String(),
  };

  // 從 JSON Map 反序列化
  factory FocusRecord.fromJson(Map<String, dynamic> json) => FocusRecord(
    storyText: json['storyText'] as String,
    completedAt: DateTime.parse(json['completedAt'] as String),
  );
}

class StorageService {
  static const String _focusCountKey = 'luffy_focus_count';
  static const String _storyIndexKey = 'luffy_story_index';
  static const String _historyKey = 'luffy_focus_history';
  
  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  // 獲取當前專注成功次數
  int get focusCount {
    return _prefs.getInt(_focusCountKey) ?? 0;
  }

  // 獲取當前故事索引
  int get storyIndex {
    return _prefs.getInt(_storyIndexKey) ?? 0;
  }

  // 獲取歷史紀錄列表（最新的排在最前面）
  List<FocusRecord> get focusHistory {
    final jsonList = _prefs.getStringList(_historyKey) ?? [];
    return jsonList
        .map((jsonStr) => FocusRecord.fromJson(jsonDecode(jsonStr)))
        .toList()
        .reversed
        .toList();
  }

  // 增加專注次數
  Future<void> incrementFocusCount() async {
    final currentCount = focusCount;
    await _prefs.setInt(_focusCountKey, currentCount + 1);
  }

  // 新增一筆歷史紀錄
  Future<void> addFocusRecord(String storyText) async {
    final record = FocusRecord(
      storyText: storyText,
      completedAt: DateTime.now(),
    );
    final jsonList = _prefs.getStringList(_historyKey) ?? [];
    jsonList.add(jsonEncode(record.toJson()));
    await _prefs.setStringList(_historyKey, jsonList);
  }

  // 前進到下一個故事
  Future<void> incrementStoryIndex(int totalStories) async {
    final currentIndex = storyIndex;
    await _prefs.setInt(_storyIndexKey, (currentIndex + 1) % totalStories);
  }

  // ==================== 統計相關方法 ====================

  /// 判斷兩個 DateTime 是否為同一天
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// 取得指定日期的專注次數
  int getFocusCountForDate(DateTime date) {
    return focusHistory.where((r) => _isSameDay(r.completedAt, date)).length;
  }

  /// 取得指定日期的專注總分鐘數（每次 25 分鐘）
  int getFocusMinutesForDate(DateTime date) {
    return getFocusCountForDate(date) * 25;
  }

  /// 取得最近 7 天的每日專注次數
  /// 回傳一個長度為 7 的 List，索引 0 = 6 天前，索引 6 = 今天
  List<int> getLast7DaysFocusCounts() {
    final today = DateTime.now();
    return List.generate(7, (i) {
      final date = today.subtract(Duration(days: 6 - i));
      return getFocusCountForDate(date);
    });
  }

  /// 取得最近 7 天對應的星期標籤（例如 ["一", "二", ...]）
  List<String> getLast7DaysLabels() {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final today = DateTime.now();
    return List.generate(7, (i) {
      final date = today.subtract(Duration(days: 6 - i));
      return weekdays[date.weekday - 1];
    });
  }

  /// 取得本週（週一至今天）的總專注次數與分鐘數
  ({int count, int minutes}) getThisWeekSummary() {
    final now = DateTime.now();
    // 找到本週一的日期
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final mondayStart = DateTime(monday.year, monday.month, monday.day);

    final weekRecords = focusHistory
        .where((r) => r.completedAt.isAfter(mondayStart) || _isSameDay(r.completedAt, mondayStart))
        .toList();

    final count = weekRecords.length;
    return (count: count, minutes: count * 25);
  }

  /// 計算連續專注天數（Streak）
  /// 從今天（或昨天，若今天尚未完成）往回推，連續有完成紀錄的天數
  int getCurrentStreak() {
    final today = DateTime.now();
    int streak = 0;

    // 先檢查今天是否有紀錄，若有則從今天開始算
    // 若沒有，從昨天開始算（允許當天尚未完成但 streak 不中斷）
    int startOffset = getFocusCountForDate(today) > 0 ? 0 : 1;

    for (int i = startOffset; i < 365; i++) {
      final date = today.subtract(Duration(days: i));
      if (getFocusCountForDate(date) > 0) {
        streak++;
      } else {
        break;
      }
    }

    return streak;
  }

  // (可選) 重置次數，開發測試用
  Future<void> resetFocusCount() async {
    await _prefs.remove(_focusCountKey);
    await _prefs.remove(_storyIndexKey);
    await _prefs.remove(_historyKey);
  }

  // ⚠️ 截圖 Demo 用：注入假資料，截完圖後請移除 main.dart 中的呼叫
  Future<void> seedMockData() async {
    // 強制覆蓋，確保截圖資料是最新的
    final now = DateTime.now();
    final mockRecords = [
      // 6 天前（1 次）
      FocusRecord(
        storyText: '【路飛與奇幻森林的蝴蝶】\n今天下午，陽光透過窗台灑在地板上，路飛正追著一隻閃閃發光的藍色蝴蝶。不知不覺中，客廳的角落竟出現了一扇發著微光的木門。路飛好奇地用鼻子頂開了門，發現門後是一片一望無際的奇幻森林。',
        completedAt: now.subtract(const Duration(days: 6, hours: 10)),
      ),
      // 5 天前（2 次）
      FocusRecord(
        storyText: '【勇敢的柴犬騎士】\n在路飛的夢境裡，牠變成了一位披著紅色披風的勇敢騎士。這座名為「肉泥小鎮」的地方，最近受到了一隻巨大橘貓的威脅。',
        completedAt: now.subtract(const Duration(days: 5, hours: 9)),
      ),
      FocusRecord(
        storyText: '【路飛的星空航海記】\n夜幕低垂，路飛戴上了一頂小小的水手帽，搭乘著一艘木製的小船，航行在平靜無波的星空之海。',
        completedAt: now.subtract(const Duration(days: 5, hours: 3)),
      ),
      // 4 天前（3 次）
      FocusRecord(
        storyText: '【雲端上的棉花糖樂園】\n今天路飛做了一個好甜的夢。牠發現自己輕飄飄地飛上了天空，來到了一個完全由白雲構成的樂園。',
        completedAt: now.subtract(const Duration(days: 4, hours: 11)),
      ),
      FocusRecord(
        storyText: '【秋日秘境與烤番薯】\n雖然現在不是秋天，但路飛的夢裡卻充滿了金黃色的落葉。在夢中，路飛來到了一片神秘的楓樹林。',
        completedAt: now.subtract(const Duration(days: 4, hours: 6)),
      ),
      FocusRecord(
        storyText: '【路飛與奇幻森林的蝴蝶】\n今天下午，陽光透過窗台灑在地板上，路飛正追著一隻閃閃發光的藍色蝴蝶。',
        completedAt: now.subtract(const Duration(days: 4, hours: 1)),
      ),
      // 3 天前（2 次）
      FocusRecord(
        storyText: '【勇敢的柴犬騎士】\n在路飛的夢境裡，牠變成了一位披著紅色披風的勇敢騎士。',
        completedAt: now.subtract(const Duration(days: 3, hours: 8)),
      ),
      FocusRecord(
        storyText: '【路飛的星空航海記】\n夜幕低垂，路飛戴上了一頂小小的水手帽。',
        completedAt: now.subtract(const Duration(days: 3, hours: 2)),
      ),
      // 2 天前（1 次）
      FocusRecord(
        storyText: '【雲端上的棉花糖樂園】\n今天路飛做了一個好甜的夢。',
        completedAt: now.subtract(const Duration(days: 2, hours: 5)),
      ),
      // 1 天前（3 次）
      FocusRecord(
        storyText: '【秋日秘境與烤番薯】\n路飛來到了一片神秘的楓樹林，地上的落葉積得像小山一樣高。',
        completedAt: now.subtract(const Duration(days: 1, hours: 10)),
      ),
      FocusRecord(
        storyText: '【路飛與奇幻森林的蝴蝶】\n路飛在花園中央找到了一塊最柔軟的草地，心滿意足地趴了下來。',
        completedAt: now.subtract(const Duration(days: 1, hours: 5)),
      ),
      FocusRecord(
        storyText: '【勇敢的柴犬騎士】\n小鎮的居民為了感謝路飛，舉辦了一場盛大的派對。',
        completedAt: now.subtract(const Duration(days: 1, hours: 1)),
      ),
      // 今天（2 次）
      FocusRecord(
        storyText: '【路飛的星空航海記】\n路飛對著流星許下了一個願望：「希望能有吃不完的蘋果切片和永遠不會壞掉的網球」。',
        completedAt: now.subtract(const Duration(hours: 3)),
      ),
      FocusRecord(
        storyText: '【雲端上的棉花糖樂園】\n玩累了之後，路飛找到了一朵最厚、最蓬鬆的晚霞雲，橘紅色的光芒照在牠身上，溫暖又舒適。',
        completedAt: now.subtract(const Duration(hours: 1)),
      ),
    ];

    final jsonList = mockRecords
        .map((r) => jsonEncode(r.toJson()))
        .toList();
    await _prefs.setStringList(_historyKey, jsonList);
    await _prefs.setInt(_focusCountKey, mockRecords.length);
    // 設定故事索引為第 4 個（看起來有進度感）
    await _prefs.setInt(_storyIndexKey, 4);
  }
}
