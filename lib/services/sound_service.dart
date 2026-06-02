import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 負責 App 前台音效播放的服務
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();

  /// 播放專注完成的寵物叫聲
  /// [species] 貓為 'cat'，其他（如狗）播放狗狗叫聲
  Future<void> playFocusCompleteSound(String species) async {
    try {
      final soundPath = species == 'cat'
          ? 'audio/luffy_cat_complete.wav'
          : 'audio/luffy_dog_complete.wav';

      // 為什麼這樣設計 (Why)：
      // 1. 為了與退到後台時發出的警告叫聲做區隔，我們在前台完成專注時播放 complete 音檔。
      // 2. 在播放時，我們將 PlaybackRate 微調至 1.25 倍，使叫聲音調更歡快、有慶祝感。
      // 3. 用戶未來可以直接用不同的音檔替換 assets/audio/ 下的完整音效，實現完全獨立的音軌。
      await _audioPlayer.setPlaybackRate(1.25);
      await _audioPlayer.play(AssetSource(soundPath));
      debugPrint('[SoundService] Played focus complete sound: $soundPath with speed 1.25');
    } catch (e) {
      debugPrint('[SoundService] Failed to play focus complete sound: $e');
    }
  }
}
