import 'dart:async';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../core/constants.dart';

import '../services/story_service.dart';

export '../services/storage_service.dart' show FocusRecord;

enum TimerState { initial, running, finished, failed }

class TimerProvider extends ChangeNotifier {
  final StorageService _storageService;
  final StoryService _storyService;

  Timer? _timer;
  int _remainingSeconds = AppConstants.defaultTimerSeconds;
  TimerState _state = TimerState.initial;
  String? _currentRewardStory;
  DateTime? _endsAt;
  bool _isCompleting = false;

  TimerProvider(this._storageService, this._storyService);

  // Getters
  int get remainingSeconds => _remainingSeconds;
  TimerState get state => _state;
  int get focusCount => _storageService.focusCount;

  // 獲取當前的獎勵故事 (非同步加載完成後才有值)
  String? get currentRewardStory => _currentRewardStory;

  // 獲取歷史紀錄（最新的在最前面）
  List<FocusRecord> get focusHistory => _storageService.focusHistory;

  // ==================== 統計相關 Getters ====================

  // 今日專注次數
  int get todayFocusCount =>
      _storageService.getFocusCountForDate(DateTime.now());

  // 今日專注總分鐘數
  int get todayFocusMinutes =>
      _storageService.getFocusMinutesForDate(DateTime.now());

  // 連續專注天數
  int get currentStreak => _storageService.getCurrentStreak();

  // 本週總覽
  ({int count, int minutes}) get thisWeekSummary =>
      _storageService.getThisWeekSummary();

  // 最近七天每日專注次數
  List<int> get last7DaysFocusCounts =>
      _storageService.getLast7DaysFocusCounts();

  // 最近七天星期標籤
  List<String> get last7DaysLabels => _storageService.getLast7DaysLabels();

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
    _endsAt = DateTime.now().add(Duration(seconds: _remainingSeconds));
    notifyListeners();

    _startTicker();
  }

  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      syncWithClock();
    });
  }

  void syncWithClock() {
    if (_state != TimerState.running || _endsAt == null || _isCompleting) {
      return;
    }

    final millisecondsLeft = _endsAt!.difference(DateTime.now()).inMilliseconds;
    final nextRemaining =
        millisecondsLeft <= 0 ? 0 : (millisecondsLeft / 1000).ceil();

    if (_remainingSeconds != nextRemaining) {
      _remainingSeconds = nextRemaining;
      notifyListeners();
    }

    if (millisecondsLeft <= 0) {
      _onTimerFinished();
    }
  }

  // 放棄計時 (進入失敗狀態)
  void giveUp() {
    _timer?.cancel();
    _endsAt = null;
    _state = TimerState.failed;
    notifyListeners();
  }

  // 從失敗狀態重置回初始狀態
  void resetFromFailure() {
    _remainingSeconds = AppConstants.defaultTimerSeconds;
    _endsAt = null;
    _isCompleting = false;
    _state = TimerState.initial;
    notifyListeners();
  }

  // 計時完成
  Future<void> _onTimerFinished() async {
    if (_isCompleting) return;
    _isCompleting = true;
    _timer?.cancel();
    _endsAt = null;
    _remainingSeconds = 0;
    notifyListeners();

    // 非同步獲取故事
    final minutes = (AppConstants.defaultTimerSeconds / 60).floor();
    final rewardStory = await _storyService.getRewardStory(
      focusMinutes: minutes,
    );
    _currentRewardStory = rewardStory.storyText;

    // 增加專注次數並記錄歷史
    await _storageService.incrementFocusCount();
    await _storageService.addFocusRecord(
      rewardStory.storyText,
      petId: rewardStory.petId,
      petName: rewardStory.petName,
      species: rewardStory.species,
    );

    _state = TimerState.finished;
    _isCompleting = false;
    notifyListeners();
  }

  // 領取獎勵後，重置回初始狀態並切換到下一個故事
  void resetAfterReward() {
    _remainingSeconds = AppConstants.defaultTimerSeconds;
    _endsAt = null;
    _isCompleting = false;
    _state = TimerState.initial;
    _currentRewardStory = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
