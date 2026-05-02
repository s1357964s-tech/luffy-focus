import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 負責本地推播通知的封裝服務
/// 主要用途：當番茄鐘計時中，用戶將 App 切到後台時，發送可愛的提醒通知
/// 採用完全延遲初始化策略，插件實例也延遲建立，避免在不支援的平台上崩潰
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // 延遲建立插件實例，避免在 macOS 等平台上過早初始化導致崩潰
  FlutterLocalNotificationsPlugin? _plugin;
  
  // 是否已完成初始化
  bool _isInitialized = false;

  // 路飛風格的可愛提醒訊息
  static const List<String> _focusReminders = [
    '汪！你去哪裡了？路飛正在乖乖睡覺等你回來呢... 🐶',
    '嗚嗚～路飛發現你不見了，快回來陪牠完成這次專注吧！',
    '路飛睜開了一隻眼睛偷看你...牠說：「主人快回來，我還在努力睡覺呢！」',
    '喂喂喂！路飛聞到你在外面偷吃零食的味道了！快回來專注啦～ 🍪',
    '路飛在夢裡等你呢！如果你不回來，牠的夢境故事就要消失了... ✨',
    '汪汪！路飛說：「我都這麼努力在睡了，你怎麼可以分心呢？」',
    '路飛的小耳朵動了一下，牠感覺到你離開了...快回來讓牠安心睡覺吧 💤',
  ];

  /// 確保通知服務已初始化（完全延遲初始化）
  Future<bool> _ensureInitialized() async {
    if (_isInitialized) return true;

    try {
      _plugin = FlutterLocalNotificationsPlugin();

      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const macOSSettings = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

      const initSettings = InitializationSettings(
        iOS: iosSettings,
        macOS: macOSSettings,
        android: androidSettings,
      );

      await _plugin!.initialize(initSettings);
      _isInitialized = true;
      return true;
    } catch (e) {
      debugPrint('通知服務初始化失敗: $e');
      _plugin = null;
      return false;
    }
  }

  /// 請求通知權限（iOS / macOS 需要明確請求）
  Future<bool> requestPermission() async {
    try {
      final initialized = await _ensureInitialized();
      if (!initialized || _plugin == null) return false;

      // iOS 權限請求
      final iosPlugin = _plugin!.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (iosPlugin != null) {
        final granted = await iosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }

      // macOS 權限請求
      final macOSPlugin = _plugin!.resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      if (macOSPlugin != null) {
        final granted = await macOSPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }

      return true;
    } catch (e) {
      debugPrint('請求通知權限失敗: $e');
      return false;
    }
  }

  /// 發送「專注中離開」的可愛提醒通知
  Future<void> showFocusReminder() async {
    if (!_isInitialized || _plugin == null) return;

    try {
      final random = Random();
      final message = _focusReminders[random.nextInt(_focusReminders.length)];

      const notificationDetails = NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        android: AndroidNotificationDetails(
          'luffy_focus_channel',
          '路飛專注提醒',
          channelDescription: '在專注期間離開 App 時的提醒通知',
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

      await _plugin!.show(
        0,
        '🐶 路飛在找你！',
        message,
        notificationDetails,
      );
    } catch (e) {
      debugPrint('發送通知失敗: $e');
    }
  }

  /// 取消所有通知（用戶返回 App 時清除）
  Future<void> cancelAll() async {
    if (!_isInitialized || _plugin == null) return;
    try {
      await _plugin!.cancelAll();
    } catch (e) {
      debugPrint('清除通知失敗: $e');
    }
  }
}
