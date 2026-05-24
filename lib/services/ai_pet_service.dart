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

  /// 判斷圖片是否為貓狗兔子
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
    required String originalImagePath,
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
          'originalImagePath': originalImagePath,
        },
      );

      final normalImageUrl = data['normalImageUrl'] as String;
      final sleepingImageUrl =
          data['sleepingImageUrl'] as String? ?? normalImageUrl;
      final failedImageUrl =
          data['failedImageUrl'] as String? ?? normalImageUrl;
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

  String _readableFunctionError(Object error, String fallback) {
    if (error is FirebaseFunctionsException) {
      final details = error.details?.toString();
      if (error.message != null && error.message!.trim().isNotEmpty) {
        return '$fallback（${error.message}）';
      }
      if (details != null && details.trim().isNotEmpty) {
        return '$fallback（$details）';
      }
      return '$fallback（${error.code}）';
    }
    return fallback;
  }

  Future<Map<dynamic, dynamic>> _callFunctionWithRetry({
    required String name,
    required Duration timeout,
    required Map<String, dynamic> payload,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final callable = FirebaseService.functions.httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: timeout),
        );
        final response = await callable.call(payload);
        final data = response.data;
        if (data is Map) return data;
        throw StateError('$name returned invalid data: $data');
      } catch (error) {
        lastError = error;
        debugPrint('[FirebaseCallable] $name attempt=$attempt failed: $error');
        if (attempt >= 2 || !_isTransientFunctionError(error)) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }

    throw lastError ?? StateError('$name failed');
  }

  bool _isTransientFunctionError(Object error) {
    final message = error.toString().toLowerCase();
    if (error is FirebaseFunctionsException) {
      return error.code == 'unavailable' ||
          error.code == 'deadline-exceeded' ||
          error.code == 'internal';
    }
    return message.contains('timeout') ||
        message.contains('network error') ||
        message.contains('interrupted connection') ||
        message.contains('unreachable host') ||
        message.contains('socket');
  }

  String _shortUrl(String value) {
    if (value.length <= 120) return value;
    return '${value.substring(0, 120)}...';
  }
}
