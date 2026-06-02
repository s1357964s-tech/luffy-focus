import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:home_widget/home_widget.dart';

/// 單筆歷史紀錄的資料模型
class FocusRecord {
  final String storyText;
  final DateTime completedAt;
  final String? petId;
  final String? petName;
  final String? species;

  FocusRecord({
    required this.storyText,
    required this.completedAt,
    this.petId,
    this.petName,
    this.species,
  });

  // 序列化為 JSON Map
  Map<String, dynamic> toJson() => {
        'storyText': storyText,
        'completedAt': completedAt.toIso8601String(),
        'petId': petId,
        'petName': petName,
        'species': species,
      };

  // 從 JSON Map 反序列化
  factory FocusRecord.fromJson(Map<String, dynamic> json) => FocusRecord(
        storyText: json['storyText'] as String? ?? '',
        completedAt: _parseDateTime(json['completedAt']),
        petId: json['petId'] as String?,
        petName: json['petName'] as String?,
        species: _normalizeSpecies(json['species']),
      );
}

/// 自定義寵物模型
class CustomPet {
  final String id;
  final String name;
  final String species; // cat, dog
  final String? breed;
  final String breedTraits;
  final List<String> visualTraits;
  final String? originalImagePath;
  final String normalImageUrl;
  final String sleepingImageUrl;
  final String failedImageUrl;
  final int avatarStatesVersion;
  final String status;
  final DateTime createdAt;

  /// 標記圖片是否為本地 asset（Mock 模式使用 Image.asset，正式模式使用 Image.network）
  final bool isLocalAsset;

  CustomPet({
    required this.id,
    required this.name,
    required this.species,
    this.breed,
    this.breedTraits = '',
    this.visualTraits = const [],
    this.originalImagePath,
    required this.normalImageUrl,
    required this.sleepingImageUrl,
    required this.failedImageUrl,
    this.avatarStatesVersion = 0,
    this.status = 'ready',
    required this.createdAt,
    this.isLocalAsset = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'species': species,
        'breed': breed,
        'breedTraits': breedTraits,
        'visualTraits': visualTraits,
        'originalImagePath': originalImagePath,
        'normalImageUrl': normalImageUrl,
        'sleepingImageUrl': sleepingImageUrl,
        'failedImageUrl': failedImageUrl,
        'avatarStatesVersion': avatarStatesVersion,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'isLocalAsset': isLocalAsset,
      };

  factory CustomPet.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json['id'], 'id');
    final normalImageUrl =
        _requiredString(json['normalImageUrl'], 'normalImageUrl');

    return CustomPet(
      id: id,
      name: _optionalString(json['name']).isEmpty
          ? '好朋友'
          : _optionalString(json['name']),
      species: _normalizeSpecies(json['species']) ?? 'dog',
      breed: json['breed'] as String?,
      breedTraits: json['breedTraits'] as String? ?? '',
      visualTraits:
          (json['visualTraits'] as List? ?? []).whereType<String>().toList(),
      originalImagePath: json['originalImagePath'] as String?,
      normalImageUrl: normalImageUrl,
      sleepingImageUrl: _optionalString(json['sleepingImageUrl']).isEmpty
          ? normalImageUrl
          : _optionalString(json['sleepingImageUrl']),
      failedImageUrl: _optionalString(json['failedImageUrl']).isEmpty
          ? normalImageUrl
          : _optionalString(json['failedImageUrl']),
      avatarStatesVersion: _optionalInt(json['avatarStatesVersion']),
      status: json['status'] as String? ?? 'ready',
      createdAt: _parseDateTime(json['createdAt']),
      isLocalAsset: json['isLocalAsset'] as bool? ?? false,
    );
  }

  CustomPet copyWith({
    String? id,
    String? name,
    String? species,
    String? breed,
    String? breedTraits,
    List<String>? visualTraits,
    String? originalImagePath,
    String? normalImageUrl,
    String? sleepingImageUrl,
    String? failedImageUrl,
    int? avatarStatesVersion,
    String? status,
    DateTime? createdAt,
    bool? isLocalAsset,
  }) {
    return CustomPet(
      id: id ?? this.id,
      name: name ?? this.name,
      species: species ?? this.species,
      breed: breed ?? this.breed,
      breedTraits: breedTraits ?? this.breedTraits,
      visualTraits: visualTraits ?? this.visualTraits,
      originalImagePath: originalImagePath ?? this.originalImagePath,
      normalImageUrl: normalImageUrl ?? this.normalImageUrl,
      sleepingImageUrl: sleepingImageUrl ?? this.sleepingImageUrl,
      failedImageUrl: failedImageUrl ?? this.failedImageUrl,
      avatarStatesVersion: avatarStatesVersion ?? this.avatarStatesVersion,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      isLocalAsset: isLocalAsset ?? this.isLocalAsset,
    );
  }
}

DateTime _parseDateTime(dynamic value) {
  if (value is DateTime) return value;
  if (value is String) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  return DateTime.now();
}

String _requiredString(dynamic value, String fieldName) {
  if (value is String && value.trim().isNotEmpty) {
    return value.trim();
  }
  throw FormatException('CustomPet missing required field: $fieldName');
}

String _optionalString(dynamic value) {
  return value is String ? value.trim() : '';
}

int _optionalInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String? _normalizeSpecies(dynamic value) {
  if (value == 'cat' || value == 'dog') return value as String;
  return null;
}

class StorageService {
  static const String _focusCountKey = 'luffy_focus_count';
  static const String _storyIndexKey = 'luffy_story_index';
  static const String _historyKey = 'luffy_focus_history';
  static const String _customPetsKey = 'luffy_custom_pets';
  static const String _selectedPetIdKey =
      'luffy_selected_pet_id'; // 空字串或 null 代表預設路飛
  static const String _uploadFailureCountKey = 'luffy_upload_failure_count';
  static const String _firstUploadFailureTimeKey =
      'luffy_first_upload_failure_time';
  static const String _uploadLockUntilKey = 'luffy_upload_lock_until';

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
    final records = <FocusRecord>[];
    for (final jsonStr in jsonList) {
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) {
          records.add(FocusRecord.fromJson(decoded));
        } else if (decoded is Map) {
          records.add(FocusRecord.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (error) {
        debugPrint('略過無法解析的專注歷史紀錄: $error');
      }
    }
    return records.reversed.toList();
  }

  // 增加專注次數
  Future<void> incrementFocusCount() async {
    final currentCount = focusCount;
    await _prefs.setInt(_focusCountKey, currentCount + 1);
  }

  // 新增一筆歷史紀錄
  Future<void> addFocusRecord(
    String storyText, {
    String? petId,
    String? petName,
    String? species,
  }) async {
    final record = FocusRecord(
      storyText: storyText,
      completedAt: DateTime.now(),
      petId: petId,
      petName: petName,
      species: species,
    );
    final jsonList = _prefs.getStringList(_historyKey) ?? [];
    jsonList.add(jsonEncode(record.toJson()));
    await _prefs.setStringList(_historyKey, jsonList);
  }

  /// 移除指定寵物的夢境故事紀錄。
  Future<int> removeFocusRecordsForPet(String petId, {String? petName}) async {
    final jsonList = _prefs.getStringList(_historyKey) ?? [];
    final normalizedPetName = petName?.trim();
    var removedCount = 0;
    final keptRecords = <String>[];

    for (final jsonStr in jsonList) {
      try {
        final record = FocusRecord.fromJson(jsonDecode(jsonStr));
        final isSamePetId = record.petId == petId;
        final isLegacyRecordForPet =
            (record.petId == null || record.petId?.isEmpty == true) &&
                normalizedPetName != null &&
                normalizedPetName.isNotEmpty &&
                record.petName?.trim() == normalizedPetName;

        if (isSamePetId || isLegacyRecordForPet) {
          removedCount += 1;
          continue;
        }
      } catch (_) {
        // 舊資料若解析失敗則保留，避免刪除無法識別的使用者紀錄。
      }

      keptRecords.add(jsonStr);
    }

    if (removedCount > 0) {
      await _prefs.setStringList(_historyKey, keptRecords);
    }
    return removedCount;
  }

  // 前進到下一個故事
  Future<void> incrementStoryIndex([int? totalStories]) async {
    final currentIndex = storyIndex;
    await _prefs.setInt(_storyIndexKey, currentIndex + 1);
  }

  // ==================== 自定義寵物相關 ====================

  /// 獲取所有自定義寵物
  List<CustomPet> get customPets {
    final jsonList = _prefs.getStringList(_customPetsKey) ?? [];
    final pets = <CustomPet>[];
    for (final jsonStr in jsonList) {
      try {
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) {
          pets.add(CustomPet.fromJson(decoded));
        } else if (decoded is Map) {
          pets.add(CustomPet.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (error) {
        debugPrint('略過無法解析的寵物資料: $error');
      }
    }
    return pets;
  }

  /// 獲取當前選定的寵物 ID
  String? get selectedPetId {
    final id = _prefs.getString(_selectedPetIdKey);
    if (id == null || id.isEmpty) return null;
    return id;
  }

  /// 獲取當前選定的寵物（若回傳 null 則代表使用預設路飛）
  CustomPet? get selectedPet {
    final id = selectedPetId;
    if (id == null) return null;
    try {
      return customPets.firstWhere((pet) => pet.id == id);
    } catch (e) {
      return null; // 找不到則回傳 null
    }
  }

  /// 儲存選定的寵物 ID (傳入 null 代表切換回路飛)
  Future<void> setSelectedPetId(String? id) async {
    if (id == null) {
      await _prefs.remove(_selectedPetIdKey);
    } else {
      await _prefs.setString(_selectedPetIdKey, id);
    }
    await _updateWidgetData();
  }

  /// 同步資料給 iOS/Android Widget
  /// 在 macOS 桌面等不支援 home_widget 的平台上會靜默跳過
  Future<void> _updateWidgetData() async {
    try {
      final pet = selectedPet;
      final String widgetImageUrl =
          pet != null ? pet.normalImageUrl : 'luffy_awake';

      await HomeWidget.setAppGroupId('group.com.s1357964stech.luffyfocus');
      await HomeWidget.saveWidgetData<String>('pet_image_url', widgetImageUrl);
      await HomeWidget.saveWidgetData<bool>(
          'is_network_image', pet != null && !pet.isLocalAsset);
      await HomeWidget.updateWidget(
        iOSName: 'LuffyWidget',
        androidName: 'LuffyWidgetProvider',
      );
    } catch (e) {
      // macOS 桌面端不支援 home_widget，靜默忽略
      debugPrint('Widget 更新跳過（平台不支援或尚未設定）: $e');
    }
  }

  /// 新增一隻自定義寵物
  Future<void> addCustomPet(CustomPet pet) async {
    final pets = customPets;
    pets.add(pet);
    final jsonList = pets.map((p) => jsonEncode(p.toJson())).toList();
    await _prefs.setStringList(_customPetsKey, jsonList);
  }

  /// 用雲端寵物列表同步本地快取，讓 Widget、故事服務和離線 UI 可共用同一份模型。
  Future<void> replaceCustomPets(List<CustomPet> pets) async {
    final jsonList = pets.map((p) => jsonEncode(p.toJson())).toList();
    await _prefs.setStringList(_customPetsKey, jsonList);
    await _updateWidgetData();
  }

  // ==================== 防刷機制相關 ====================

  /// 檢查是否被鎖定上傳
  bool get isUploadLocked {
    final lockUntilStr = _prefs.getString(_uploadLockUntilKey);
    if (lockUntilStr == null) return false;
    final lockUntil = DateTime.parse(lockUntilStr);
    return DateTime.now().isBefore(lockUntil);
  }

  /// 記錄一次失敗上傳
  /// 回傳是否因此被鎖定 (true 表示觸發了 24 小時鎖定)
  Future<bool> recordUploadFailure() async {
    if (isUploadLocked) return true;

    final now = DateTime.now();
    final firstFailureTimeStr = _prefs.getString(_firstUploadFailureTimeKey);
    int count = _prefs.getInt(_uploadFailureCountKey) ?? 0;

    if (firstFailureTimeStr != null) {
      final firstFailureTime = DateTime.parse(firstFailureTimeStr);
      if (now.difference(firstFailureTime).inMinutes >= 1) {
        // 超過 1 分鐘，重置計數
        count = 0;
        await _prefs.setString(
            _firstUploadFailureTimeKey, now.toIso8601String());
      }
    } else {
      await _prefs.setString(_firstUploadFailureTimeKey, now.toIso8601String());
    }

    count += 1;
    await _prefs.setInt(_uploadFailureCountKey, count);

    if (count >= 3) {
      // 觸發鎖定 24 小時
      final lockUntil = now.add(const Duration(hours: 24));
      await _prefs.setString(_uploadLockUntilKey, lockUntil.toIso8601String());
      // 鎖定後清除計數
      await _prefs.remove(_firstUploadFailureTimeKey);
      await _prefs.remove(_uploadFailureCountKey);
      return true;
    }

    return false;
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
        .where((r) =>
            r.completedAt.isAfter(mondayStart) ||
            _isSameDay(r.completedAt, mondayStart))
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
        storyText:
            '【路飛與奇幻森林的蝴蝶】\n今天下午，陽光透過窗台灑在地板上，路飛正追著一隻閃閃發光的藍色蝴蝶。不知不覺中，客廳的角落竟出現了一扇發著微光的木門。路飛好奇地用鼻子頂開了門，發現門後是一片一望無際的奇幻森林。',
        completedAt: now.subtract(const Duration(days: 6, hours: 10)),
      ),
      // 5 天前（2 次）
      FocusRecord(
        storyText:
            '【勇敢的柴犬騎士】\n在路飛的夢境裡，牠變成了一位披著紅色披風的勇敢騎士。這座名為「肉泥小鎮」的地方，最近受到了一隻巨大橘貓的威脅。',
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

    final jsonList = mockRecords.map((r) => jsonEncode(r.toJson())).toList();
    await _prefs.setStringList(_historyKey, jsonList);
    await _prefs.setInt(_focusCountKey, mockRecords.length);
    // 設定故事索引為第 4 個（看起來有進度感）
    await _prefs.setInt(_storyIndexKey, 4);
  }
}
