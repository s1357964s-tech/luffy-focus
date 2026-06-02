import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'storage_service.dart';
import 'firebase_service.dart';

class PetAvatarResult {
  final String normalImageUrl;
  final String sleepingImageUrl;
  final String failedImageUrl;
  final String? originalImagePath;

  const PetAvatarResult({
    required this.normalImageUrl,
    required this.sleepingImageUrl,
    required this.failedImageUrl,
    this.originalImagePath,
  });
}

class PetImageAnalysis {
  final bool isPet;
  final String? species;
  final String? breed;
  final double breedConfidence;
  final String breedTraits;
  final List<String> visualTraits;

  const PetImageAnalysis({
    required this.isPet,
    required this.species,
    required this.breed,
    required this.breedConfidence,
    required this.breedTraits,
    required this.visualTraits,
  });
}

class AiPetService {

  final StorageService _storageService;

  /// 僅保留給舊資料/測試資料判斷圖片來源；正式辨識與生成不再自動 Mock。
  bool isMockMode = false;

  AiPetService(this._storageService);

  /// 判斷圖片是否為貓狗
  /// 回傳：是否為支援寵物、物種、品種/類型與可見外觀特徵
  /// 若非寵物，會觸發防刷機制紀錄；若觸發 24 小時鎖定，會拋出例外
  Future<PetImageAnalysis> analyzePetImage(
    String base64Image, {
    required String imageMimeType,
  }) async {
    if (_storageService.isUploadLocked) {
      throw Exception('上傳功能已被暫時鎖定（24小時），請稍後再試。');
    }

    try {
      final data = await _callFunctionWithRetry(
        name: 'analyzePetImage',
        timeout: const Duration(seconds: 150),
        payload: {
          'imageBase64': base64Image,
          'imageMimeType': imageMimeType,
        },
      );

      final bool isPet = data['isPet'] ?? false;
      final String? species = data['species'];
      final String? breed = data['breed'] as String?;
      final breedConfidenceValue = data['breedConfidence'];
      final double breedConfidence = breedConfidenceValue is num
          ? breedConfidenceValue.toDouble()
          : double.tryParse(breedConfidenceValue?.toString() ?? '') ?? 0;
      final String breedTraits = data['breedTraits'] as String? ?? '';
      final List<String> visualTraits = (data['visualTraits'] as List? ?? [])
          .whereType<String>()
          .where((trait) => trait.trim().isNotEmpty)
          .map((trait) => trait.trim())
          .toList();

      if (!isPet) {
        final isLocked = await _storageService.recordUploadFailure();
        if (isLocked) {
          throw Exception('多次上傳無效圖片，上傳功能已被暫停 24 小時。');
        }
      }

      isMockMode = false;
      debugPrint(
        '[PetAnalysis] isPet=$isPet species=$species breed=$breed '
        'confidence=$breedConfidence traits=${visualTraits.join(" | ")}',
      );
      return PetImageAnalysis(
        isPet: isPet,
        species: species,
        breed: breed,
        breedConfidence: breedConfidence,
        breedTraits: breedTraits,
        visualTraits: visualTraits,
      );
    } catch (e) {
      final message = e.toString();
      if (message.contains('上傳功能已被暫時鎖定') || message.contains('多次上傳無效圖片')) {
        rethrow;
      }

      // Check if it's a network, TLS, handshake or timeout error (case-insensitive)
      final normalized = e.toString().toLowerCase();
      
      // 為什麼這樣設計 (Why)：
      // 當大陸用戶在無 VPN 的受限網路下透過「本地降級支付」獲得自定義寵物名額後，後端 Firestore 並無該筆 credit 紀錄。
      // 用戶在此狀態下點擊送出，若此時網絡連通（或配置了閘道），呼叫後端會回傳 "please purchase a custom pet..." 的業務錯誤。
      // 為了避免流程中斷，我們必須在此處攔截該錯誤，並將其視同網路連線異常處理，直接觸發本地 Mock 橘貓生成降級。
      final isNetworkError = e is TimeoutException ||
          normalized.contains('network error') ||
          normalized.contains('timeout') ||
          normalized.contains('tls') ||
          normalized.contains('secure connection') ||
          normalized.contains('handshake') ||
          normalized.contains('connection terminated during handshake') ||
          normalized.contains('unreachable') ||
          normalized.contains('unavailable') ||
          normalized.contains('host') ||
          normalized.contains('please purchase a custom pet') ||
          (e is FirebaseFunctionsException && (
              e.code == 'unavailable' ||
              e.code == 'deadline-exceeded' ||
              e.code == 'failed-precondition' ||
              e.message?.toLowerCase().contains('network error') == true
          ));

      if (isNetworkError) {
        debugPrint('[PetAnalysis] 檢測到網路連線失敗或後端額度未同步，自動啟用本地 Mock 模式。');
        isMockMode = true;
        return const PetImageAnalysis(
          isPet: true,
          species: 'cat',
          breed: 'orange tabby',
          breedConfidence: 0.95,
          breedTraits: '橘貓性格溫順，愛撒嬌，非常親人，且通常體型較為圓潤。',
          visualTraits: ['橘色條紋', '短毛', '圓臉', '黃色眼睛'],
        );
      }

      isMockMode = false;
      throw Exception(_readableFunctionError(e, '寵物圖片辨識失敗，請稍後再試。'));
    }
  }

  /// 呼叫 Gemini 圖片模型產生三種狀態的卡通圖片
  /// 回傳生成後儲存在 Firebase Storage 的圖片 URL
  Future<PetAvatarResult> generatePetAvatar({
    required String base64Image,
    required String imageMimeType,
    required String featureNote,
    required String species,
    required String? breed,
    required String breedTraits,
    required List<String> visualTraits,
    required String petId,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      debugPrint(
        '[PetAvatar] generatePetAvatar start petId=$petId species=$species '
        'mime=$imageMimeType base64Length=${base64Image.length} '
        'hasFeatureNote=${featureNote.trim().isNotEmpty}',
      );
      final data = await _callFunctionWithRetry(
        name: 'generatePetAvatar',
        timeout: const Duration(seconds: 330),
        payload: {
          'petId': petId,
          'imageBase64': base64Image,
          'imageMimeType': imageMimeType,
          'featureNote': featureNote,
          'species': species,
          'breed': breed,
          'breedTraits': breedTraits,
          'visualTraits': visualTraits,
        },
      );

      final normalImageUrl = data['normalImageUrl'] as String;
      final sleepingImageUrl = data['sleepingImageUrl'] as String;
      final failedImageUrl = data['failedImageUrl'] as String;
      debugPrint(
        '[PetAvatar] generatePetAvatar success petId=$petId '
        'elapsedMs=${stopwatch.elapsedMilliseconds} '
        'normalUrl=${_shortUrl(normalImageUrl)}',
      );
      isMockMode = false;
      return PetAvatarResult(
        normalImageUrl: normalImageUrl,
        sleepingImageUrl: sleepingImageUrl,
        failedImageUrl: failedImageUrl,
        originalImagePath: data['originalImagePath'] as String?,
      );
    } catch (e) {
      debugPrint(
        '[PetAvatar] generatePetAvatar failed petId=$petId '
        'elapsedMs=${stopwatch.elapsedMilliseconds} error=$e',
      );

      // Check if it's a network, TLS, handshake or timeout error (case-insensitive)
      final normalized = e.toString().toLowerCase();
      
      // 為什麼這樣設計 (Why)：
      // 當大陸用戶在無 VPN 的受限網路下透過「本地降級支付」獲得自定義寵物名額後，後端 Firestore 並無該筆 credit 紀錄。
      // 用戶在此狀態下進行生圖，若此時網絡連通（或配置了閘道），呼叫後端會回傳 "please purchase a custom pet..." 的業務錯誤。
      // 為了避免流程中斷，我們必須在此處攔截該錯誤，並將其視同網路連線異常處理，直接觸發本地 Mock 圖片路徑降級。
      final isNetworkError = e is TimeoutException ||
          normalized.contains('network error') ||
          normalized.contains('timeout') ||
          normalized.contains('tls') ||
          normalized.contains('secure connection') ||
          normalized.contains('handshake') ||
          normalized.contains('connection terminated during handshake') ||
          normalized.contains('unreachable') ||
          normalized.contains('unavailable') ||
          normalized.contains('host') ||
          normalized.contains('please purchase a custom pet') ||
          (e is FirebaseFunctionsException && (
              e.code == 'unavailable' ||
              e.code == 'deadline-exceeded' ||
              e.code == 'failed-precondition' ||
              e.message?.toLowerCase().contains('network error') == true
          ));

      if (isNetworkError) {
        debugPrint('[PetAvatar] 檢測到網路連線失敗或後端額度未同步，自動啟用本地 Mock 生成。');
        isMockMode = true;
        return const PetAvatarResult(
          normalImageUrl: 'assets/images/mock/mock_cat_normal.png',
          sleepingImageUrl: 'assets/images/mock/mock_cat_sleeping.png',
          failedImageUrl: 'assets/images/mock/mock_cat_failed.png',
          originalImagePath: null,
        );
      }

      isMockMode = false;
      throw Exception(_readableFunctionError(e, '寵物卡通圖生成失敗，請稍後再試。'));
    }
  }

  Future<PetAvatarResult?> generatePetAvatarStates({
    required String base64Image,
    required String imageMimeType,
    required String featureNote,
    required String species,
    required String? breed,
    required String breedTraits,
    required List<String> visualTraits,
    required String petId,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      debugPrint(
        '[PetAvatar] generatePetAvatarStates start petId=$petId species=$species',
      );
      final data = await _callFunctionWithRetry(
        name: 'generatePetAvatarStates',
        timeout: const Duration(seconds: 240),
        payload: {
          'petId': petId,
          'imageBase64': base64Image,
          'imageMimeType': imageMimeType,
          'featureNote': featureNote,
          'species': species,
          'breed': breed,
          'breedTraits': breedTraits,
          'visualTraits': visualTraits,
        },
      );

      final sleepingImageUrl = data['sleepingImageUrl'] as String;
      final failedImageUrl = data['failedImageUrl'] as String;
      debugPrint(
        '[PetAvatar] generatePetAvatarStates success petId=$petId '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      return PetAvatarResult(
        normalImageUrl: '',
        sleepingImageUrl: sleepingImageUrl,
        failedImageUrl: failedImageUrl,
      );
    } catch (e) {
      debugPrint(
        '[PetAvatar] generatePetAvatarStates failed petId=$petId '
        'elapsedMs=${stopwatch.elapsedMilliseconds} error=$e',
      );
      return null;
    }
  }

  Future<PetAvatarResult?> repairPetAvatarStates({
    required String petId,
    bool force = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      debugPrint('[PetAvatar] repairPetAvatarStates start petId=$petId');
      final data = await _callFunctionWithRetry(
        name: 'repairPetAvatarStates',
        timeout: const Duration(seconds: 330),
        payload: {
          'petId': petId,
          'force': force,
        },
      );

      final normalImageUrl = data['normalImageUrl'] as String? ?? '';
      final sleepingImageUrl = data['sleepingImageUrl'] as String;
      final failedImageUrl = data['failedImageUrl'] as String;
      debugPrint(
        '[PetAvatar] repairPetAvatarStates success petId=$petId '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
      );
      return PetAvatarResult(
        normalImageUrl: normalImageUrl,
        sleepingImageUrl: sleepingImageUrl,
        failedImageUrl: failedImageUrl,
      );
    } catch (e) {
      debugPrint(
        '[PetAvatar] repairPetAvatarStates failed petId=$petId '
        'elapsedMs=${stopwatch.elapsedMilliseconds} error=$e',
      );
      return null;
    }
  }

  String _readableFunctionError(Object error, String fallback) {
    if (error is FirebaseFunctionsException) {
      if (_isTransientFunctionError(error)) {
        return '$fallback（網路連線不穩，請稍後再試。）';
      }
      final msg = error.message ?? '';
      if (msg.trim().isNotEmpty) {
        return '$fallback（$msg）';
      }
      return '$fallback（${error.code}）';
    }
    if (error is TimeoutException) {
      return '$fallback（連線逾時，請稍後再試。）';
    }
    return fallback;
  }

  Future<Map<dynamic, dynamic>> _callFunctionWithRetry({
    required String name,
    required Duration timeout,
    required Map<String, dynamic> payload,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final data = await _callFunction(name, payload, timeout);
        if (data is Map) return data;
        throw StateError('$name returned invalid data: $data');
      } catch (error) {
        lastError = error;
        debugPrint('[FirebaseHttp] $name attempt=$attempt failed: $error');
        if (attempt >= 3 || !_isTransientFunctionError(error)) {
          rethrow;
        }
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }

    throw lastError ?? StateError('$name failed');
  }

  Future<dynamic> _callFunction(
    String name,
    Map<String, dynamic> payload,
    Duration timeout,
  ) async {
    return FirebaseService.callFunction(
      name,
      data: payload,
      timeout: timeout,
    );
  }

  bool _isTransientFunctionError(Object error) {
    final message = error.toString().toLowerCase();
    if (error is FirebaseFunctionsException) {
      return error.code == 'unavailable' ||
          error.code == 'deadline-exceeded' ||
          error.code == 'internal' ||
          error.code == 'unknown' ||
          message.contains('tls') ||
          message.contains('secure connection') ||
          message.contains('socket') ||
          message.contains('connection failed') ||
          message.contains('no route to host');
    }
    return message.contains('timeout') ||
        message.contains('tls') ||
        message.contains('secure connection') ||
        message.contains('network error') ||
        message.contains('interrupted connection') ||
        message.contains('unreachable host') ||
        message.contains('socket') ||
        message.contains('connection failed') ||
        message.contains('no route to host');
  }

  String _shortUrl(String value) {
    if (value.length <= 120) return value;
    return '${value.substring(0, 120)}...';
  }
}
