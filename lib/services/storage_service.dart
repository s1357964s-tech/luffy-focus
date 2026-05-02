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
}
