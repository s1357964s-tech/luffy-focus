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

  // (可選) 重置次數，開發測試用
  Future<void> resetFocusCount() async {
    await _prefs.remove(_focusCountKey);
    await _prefs.remove(_storyIndexKey);
    await _prefs.remove(_historyKey);
  }

  // ⚠️ 截圖 Demo 用：注入假資料，截完圖後請移除此方法與 main.dart 中的呼叫
  Future<void> seedMockData() async {
    // 如果已有真實資料就不覆蓋
    final existing = _prefs.getStringList(_historyKey) ?? [];
    if (existing.isNotEmpty) return;

    final now = DateTime.now();
    final mockRecords = [
      FocusRecord(
        storyText: '【路飛與奇幻森林的蝴蝶】\n今天下午，陽光透過窗台灑在地板上，路飛正追著一隻閃閃發光的藍色蝴蝶。不知不覺中，客廳的角落竟出現了一扇發著微光的木門。路飛好奇地用鼻子頂開了門，發現門後是一片一望無際的奇幻森林。',
        completedAt: now.subtract(const Duration(days: 4, hours: 2)),
      ),
      FocusRecord(
        storyText: '【勇敢的柴犬騎士】\n在路飛的夢境裡，牠變成了一位披著紅色披風的勇敢騎士。這座名為「肉泥小鎮」的地方，最近受到了一隻巨大橘貓的威脅。路飛騎士挺身而出，牠帶著最喜歡的啾啾玩具骨頭，來到了橘貓的巢穴。',
        completedAt: now.subtract(const Duration(days: 3, hours: 5)),
      ),
      FocusRecord(
        storyText: '【路飛的星空航海記】\n夜幕低垂，路飛戴上了一頂小小的水手帽，搭乘著一艘木製的小船，航行在平靜無波的星空之海。這片海洋的水是溫暖的，水面上倒映著天空中無數閃爍的繁星。',
        completedAt: now.subtract(const Duration(days: 2, hours: 1)),
      ),
      FocusRecord(
        storyText: '【雲端上的棉花糖樂園】\n今天路飛做了一個好甜的夢。牠發現自己輕飄飄地飛上了天空，來到了一個完全由白雲構成的樂園。這裡的雲朵不僅踩起來軟綿綿的，而且竟然是香草棉花糖的口味！',
        completedAt: now.subtract(const Duration(days: 1, hours: 3)),
      ),
      FocusRecord(
        storyText: '【秋日秘境與烤番薯】\n雖然現在不是秋天，但路飛的夢裡卻充滿了金黃色的落葉。在夢中，路飛來到了一片神秘的楓樹林，地上的落葉積得像小山一樣高。路飛毫不猶豫地助跑，然後「撲通」一聲整隻狗鑽進了落葉堆裡。',
        completedAt: now.subtract(const Duration(hours: 4)),
      ),
    ];

    final jsonList = mockRecords
        .map((r) => jsonEncode(r.toJson()))
        .toList();
    await _prefs.setStringList(_historyKey, jsonList);
    await _prefs.setInt(_focusCountKey, mockRecords.length);
  }
}
