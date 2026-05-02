import 'dart:async';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../core/constants.dart';

export '../services/storage_service.dart' show FocusRecord;

enum TimerState { initial, running, finished }

class TimerProvider extends ChangeNotifier {
  final StorageService _storageService;
  
  Timer? _timer;
  int _remainingSeconds = AppConstants.defaultTimerSeconds;
  TimerState _state = TimerState.initial;

  TimerProvider(this._storageService);

  // Getters
  int get remainingSeconds => _remainingSeconds;
  TimerState get state => _state;
  int get focusCount => _storageService.focusCount;
  
  // 獲取當前順序的故事
  String get currentStory => AppConstants.bedtimeStories[_storageService.storyIndex];

  // 獲取歷史紀錄（最新的在最前面）
  List<FocusRecord> get focusHistory => _storageService.focusHistory;

  // 格式化剩餘時間為 MM:SS
  String get timeString {
    final minutes = (_remainingSeconds / 60).floor().toString().padLeft(2, '0');
    final seconds = (_remainingSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // 開始計時
  void startTimer() {
    if (_state == TimerState.running) return;

    _state = TimerState.running;
    notifyListeners();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        _remainingSeconds--;
        notifyListeners();
      } else {
        _onTimerFinished();
      }
    });
  }

  // 放棄計時 (重置)
  void giveUp() {
    _timer?.cancel();
    _remainingSeconds = AppConstants.defaultTimerSeconds;
    _state = TimerState.initial;
    notifyListeners();
  }

  // 計時完成
  void _onTimerFinished() {
    _timer?.cancel();
    _state = TimerState.finished;
    
    // 增加專注次數並記錄歷史
    _storageService.incrementFocusCount();
    _storageService.addFocusRecord(currentStory);
    
    notifyListeners();
  }

  // 領取獎勵後，重置回初始狀態並切換到下一個故事
  void resetAfterReward() {
    _remainingSeconds = AppConstants.defaultTimerSeconds;
    _state = TimerState.initial;
    _storageService.incrementStoryIndex(AppConstants.bedtimeStories.length);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
