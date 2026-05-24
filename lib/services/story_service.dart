import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import 'storage_service.dart';
import 'firebase_service.dart';
import 'pet_repository.dart';

class RewardStoryResult {
  final String storyText;
  final String petId;
  final String petName;
  final String species;

  const RewardStoryResult({
    required this.storyText,
    required this.petId,
    required this.petName,
    required this.species,
  });
}

class StoryService {
  final StorageService _storageService;
  final PetRepository _petRepository;

  StoryService(this._storageService, this._petRepository);

  /// 取得專注完成後的夢境故事。
  /// 路飛前 5 篇使用本地固定故事，第 6 篇起與自定義寵物一樣交給模型生成。
  Future<RewardStoryResult> getRewardStory({
    required int focusMinutes,
  }) async {
    final customPet = _storageService.selectedPet;

    if (customPet == null) {
      return _getLuffyStory(focusMinutes: focusMinutes);
    }

    final storyNumber = _storyCountForPet(customPet.id, customPet.name) + 1;
    final previousTitles = _recentStoryTitles(
      petId: customPet.id,
      petName: customPet.name,
    );

    final storyText = await _generateCloudStoryWithFallback(
      petId: customPet.id,
      petName: customPet.name,
      species: customPet.species,
      focusMinutes: focusMinutes,
      storyNumber: storyNumber,
      previousTitles: previousTitles,
    );

    return RewardStoryResult(
      storyText: storyText,
      petId: customPet.id,
      petName: customPet.name,
      species: customPet.species,
    );
  }

  Future<RewardStoryResult> _getLuffyStory({
    required int focusMinutes,
  }) async {
    const petId = 'luffy';
    const petName = '路飛';
    const species = 'dog';
    const stories = AppConstants.bedtimeStories;
    final currentIndex = _storageService.storyIndex;

    if (currentIndex < stories.length) {
      await _storageService.incrementStoryIndex();
      return RewardStoryResult(
        storyText: stories[currentIndex],
        petId: petId,
        petName: petName,
        species: species,
      );
    }

    final storyNumber = currentIndex + 1;
    final previousTitles = {
      ...AppConstants.bedtimeStories.map(_extractTitle).whereType<String>(),
      ..._recentStoryTitles(
        petId: petId,
        petName: petName,
      ),
    }.take(12).toList();
    final storyText = await _generateCloudStoryWithFallback(
      petId: petId,
      petName: petName,
      species: species,
      focusMinutes: focusMinutes,
      storyNumber: storyNumber,
      previousTitles: previousTitles,
    );

    await _storageService.incrementStoryIndex();
    return RewardStoryResult(
      storyText: storyText,
      petId: petId,
      petName: petName,
      species: species,
    );
  }

  Future<String> _generateCloudStoryWithFallback({
    required String petId,
    required String petName,
    required String species,
    required int focusMinutes,
    required int storyNumber,
    required List<String> previousTitles,
  }) async {
    try {
      final callable =
          FirebaseService.functions.httpsCallable('generateRewardStory');
      final response = await callable.call({
        'petId': petId,
        'petName': petName,
        'species': species,
        'focusMinutes': focusMinutes,
        'storyNumber': storyNumber,
        'previousStoryTitles': previousTitles,
      });

      final data = response.data;
      final story = data is Map ? data['story'] : null;
      if (story is String && story.trim().isNotEmpty) {
        return story.trim();
      }

      throw StateError('模型沒有回傳故事內容');
    } catch (e) {
      debugPrint('AI 故事生成失敗，使用不重複本地兜底。錯誤: $e');
      final story = _buildEmergencyStory(
        petName: petName,
        species: species,
        focusMinutes: focusMinutes,
        storyNumber: storyNumber,
        previousTitles: previousTitles,
      );

      if (petId != 'luffy' && FirebaseService.isAvailable) {
        try {
          await _petRepository.addStoryRecord(
            petId: petId,
            petName: petName,
            species: species,
            focusMinutes: focusMinutes,
            storyText: story,
          );
        } catch (_) {
          // 雲端紀錄失敗不阻斷使用者領取故事。
        }
      }

      return story;
    }
  }

  List<String> _recentStoryTitles({
    required String petId,
    required String petName,
  }) {
    return _recordsForPet(petId, petName)
        .map((record) => _extractTitle(record.storyText))
        .whereType<String>()
        .toSet()
        .take(12)
        .toList();
  }

  int _storyCountForPet(String petId, String petName) {
    return _recordsForPet(petId, petName).length;
  }

  Iterable<FocusRecord> _recordsForPet(String petId, String petName) {
    final normalizedPetName = petName.trim();
    return _storageService.focusHistory.where((record) {
      if (record.petId == petId) return true;

      // 舊版歷史沒有 petId，透過故事文字中的名字做一次向後相容判斷。
      if (record.petId == null &&
          normalizedPetName.isNotEmpty &&
          record.storyText.contains(normalizedPetName)) {
        return true;
      }

      return false;
    });
  }

  String? _extractTitle(String storyText) {
    final titleMatch = RegExp(r'【(.+?)】').firstMatch(storyText);
    return titleMatch?.group(1)?.trim();
  }

  String _buildEmergencyStory({
    required String petName,
    required String species,
    required int focusMinutes,
    required int storyNumber,
    required List<String> previousTitles,
  }) {
    const scenes = [
      ('星光郵局', '把你的專注裝進一封發亮的信，寄給正在打瞌睡的月亮。'),
      ('柔軟雲毯', '在雲朵邊緣替你守著時間，讓每一分鐘都安安穩穩落地。'),
      ('晚風花園', '沿著花香巡邏，把分心的小念頭輕輕趕到籬笆外面。'),
      ('奶油月台', '坐在夢境列車旁等你抵達，尾巴或耳朵隨著鐘聲輕輕晃動。'),
      ('糖霜燈塔', '點亮一盞小燈，替剛完成任務的你照出回家的路。'),
    ];
    final scene = scenes[(storyNumber - 1) % scenes.length];
    var title = '$petName的${scene.$1}';
    if (previousTitles.contains(title)) {
      title = '$petName的第$storyNumber個夢境';
    }

    final speciesText = switch (species) {
      'cat' => '貓咪',
      'rabbit' => '兔子',
      _ => '狗狗',
    };

    return '【$title】\n'
        '今天你完成了 $focusMinutes 分鐘的專注，$speciesText$petName也悄悄走進一場新的夢。'
        '夢裡，牠來到「${scene.$1}」，${scene.$2}'
        '牠一邊守護你留下的努力，一邊把那些亮晶晶的時間收好。'
        '等你睜開眼時，$petName已經把這份安定帶回身邊，像是在說：辛苦了，這一次也做得很好。';
  }
}
