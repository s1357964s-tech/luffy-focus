import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import '../services/storage_service.dart';
import '../services/ai_pet_service.dart';
import '../services/pet_repository.dart';
import 'package:uuid/uuid.dart';

enum PetUploadState {
  idle,
  analyzing, // 判斷是否為寵物
  generating, // 生成卡通圖片中
  naming, // 成功生成，等待用戶輸入名稱
  success,
  error
}

class PetViewModel extends ChangeNotifier {
  final StorageService _storageService;
  final AiPetService _aiPetService;
  final PetRepository _petRepository;
  final _uuid = const Uuid();
  StreamSubscription<List<CustomPet>>? _petsSubscription;

  List<CustomPet> _customPets = [];
  String? _selectedPetId;

  // 上傳狀態機
  PetUploadState _uploadState = PetUploadState.idle;
  String? _errorMessage;
  String? _pendingSpecies;
  String? _pendingPetId;
  String? _pendingOriginalImagePath;
  String? _pendingNormalUrl;
  String? _pendingSleepingUrl;
  String? _pendingFailedUrl;
  String? _pendingBreed;
  String _pendingBreedTraits = '';
  List<String> _pendingVisualTraits = [];
  String? _pendingBase64Image;
  String? _pendingImageMimeType;
  String? _pendingFeatureNote;

  PetViewModel(this._storageService, this._aiPetService, this._petRepository) {
    _initialize();
  }

  List<CustomPet> get customPets => _customPets;
  String? get selectedPetId => _selectedPetId;
  CustomPet? get selectedPet {
    if (_selectedPetId == null) return null;
    try {
      return _customPets.firstWhere((pet) => pet.id == _selectedPetId);
    } catch (_) {
      return _storageService.selectedPet;
    }
  }

  PetUploadState get uploadState => _uploadState;
  String? get errorMessage => _errorMessage;

  String? get pendingNormalUrl => _pendingNormalUrl;

  Future<void> _initialize() async {
    _customPets = _storageService.customPets;
    _selectedPetId = _storageService.selectedPetId;
    notifyListeners();

    try {
      await _petRepository.ensureUserDocument();
      await _petRepository.migrateLocalPetsIfNeeded();
      final remoteSelectedPetId = await _petRepository.fetchSelectedPetId();
      if (remoteSelectedPetId != null) {
        _selectedPetId = remoteSelectedPetId;
        await _storageService.setSelectedPetId(remoteSelectedPetId);
      }

      _petsSubscription = _petRepository.watchPets().listen((pets) {
        _customPets = pets;
        if (_selectedPetId != null &&
            pets.every((pet) => pet.id != _selectedPetId)) {
          _selectedPetId = null;
          unawaited(_petRepository.setSelectedPetId(null));
        }
        notifyListeners();
      });
    } catch (e) {
      if (kDebugMode) {
        print('Firebase 寵物資料初始化失敗，暫時使用本地快取: $e');
      }
    }
  }

  Future<void> selectPet(String? id) async {
    await _petRepository.setSelectedPetId(id);
    _selectedPetId = id;
    notifyListeners();
  }

  Future<void> deletePet(CustomPet pet) async {
    await _petRepository.deletePet(pet);

    _customPets = _customPets.where((item) => item.id != pet.id).toList();
    if (_selectedPetId == pet.id) {
      _selectedPetId = null;
    }
    notifyListeners();
  }

  /// 檢查是否已達自定義寵物上限
  bool get isAtPetLimit => _customPets.length >= AppConstants.maxCustomPets;

  /// 開始上傳與分析圖片
  Future<void> uploadAndAnalyze(
    Uint8List imageBytes, {
    required String imageMimeType,
    required String featureNote,
  }) async {
    // 檢查是否超過上限（含路飛共 3 個，自定義最多 2 個）
    if (isAtPetLimit) {
      _uploadState = PetUploadState.error;
      _errorMessage =
          '已達上限！最多只能擁有 ${AppConstants.maxCustomPets} 隻自定義寵物（加上路飛共 3 隻）';
      notifyListeners();
      return;
    }

    _uploadState = PetUploadState.analyzing;
    _errorMessage = null;
    notifyListeners();

    try {
      final base64Image = base64Encode(imageBytes);
      final analysis = await _aiPetService.analyzePetImage(
        base64Image,
        imageMimeType: imageMimeType,
      );
      final species = analysis.species;

      if (!analysis.isPet || species == null) {
        throw Exception('請上傳貓、狗或兔子的清晰照片！');
      }

      final petId = _uuid.v4();
      String originalImagePath = '';
      if (!_aiPetService.isMockMode) {
        originalImagePath = await _petRepository.uploadOriginalPetImage(
          petId: petId,
          bytes: imageBytes,
          contentType: imageMimeType,
        );
      }

      _pendingSpecies = species;
      _pendingBreed = analysis.breed;
      _pendingBreedTraits = analysis.breedTraits;
      _pendingVisualTraits = analysis.visualTraits;
      _pendingPetId = petId;
      _pendingOriginalImagePath = originalImagePath;
      _pendingBase64Image = base64Image;
      _pendingImageMimeType = imageMimeType;
      _pendingFeatureNote = featureNote;
      _uploadState = PetUploadState.generating;
      notifyListeners();

      // 呼叫生成 API
      final avatar = await _aiPetService.generatePetAvatar(
        base64Image: base64Image,
        imageMimeType: imageMimeType,
        featureNote: featureNote,
        species: species,
        breed: analysis.breed,
        breedTraits: analysis.breedTraits,
        visualTraits: analysis.visualTraits,
        petId: petId,
        originalImagePath: originalImagePath,
      );

      _pendingNormalUrl = avatar.normalImageUrl;
      _pendingSleepingUrl = avatar.sleepingImageUrl;
      _pendingFailedUrl = avatar.failedImageUrl;
      _pendingOriginalImagePath = avatar.originalImagePath ?? originalImagePath;
      _uploadState = PetUploadState.naming;
      notifyListeners();
    } catch (e) {
      _uploadState = PetUploadState.error;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
    }
  }

  /// 儲存寵物名稱並完成流程
  Future<void> savePetNameAndFinish(String name) async {
    if (_pendingPetId == null ||
        _pendingSpecies == null ||
        _pendingNormalUrl == null ||
        _pendingSleepingUrl == null ||
        _pendingFailedUrl == null) {
      return;
    }

    final newPet = CustomPet(
      id: _pendingPetId!,
      name: name,
      species: _pendingSpecies!,
      breed: _pendingBreed,
      breedTraits: _pendingBreedTraits,
      visualTraits: _pendingVisualTraits,
      originalImagePath: _pendingOriginalImagePath,
      normalImageUrl: _pendingNormalUrl!,
      sleepingImageUrl: _pendingSleepingUrl!,
      failedImageUrl: _pendingFailedUrl!,
      createdAt: DateTime.now(),
      isLocalAsset: _aiPetService.isMockMode,
    );

    CustomPet savedPet;
    if (_aiPetService.isMockMode) {
      await _storageService.addCustomPet(newPet);
      savedPet = newPet;
    } else {
      savedPet = await _petRepository.saveGeneratedPetName(
        petId: newPet.id,
        name: name,
        fallbackPet: newPet,
      );
    }

    final existingIndex =
        _customPets.indexWhere((pet) => pet.id == savedPet.id);
    if (existingIndex >= 0) {
      _customPets[existingIndex] = savedPet;
    } else {
      _customPets = [..._customPets, savedPet];
    }
    await _storageService.replaceCustomPets(_customPets);

    // 自動選中新寵物
    await selectPet(savedPet.id);

    _uploadState = PetUploadState.success;
    notifyListeners();

    if (!_aiPetService.isMockMode) {
      unawaited(_generateRemainingAvatarStates(savedPet));
    }
  }

  Future<void> _generateRemainingAvatarStates(CustomPet savedPet) async {
    final base64Image = _pendingBase64Image;
    final imageMimeType = _pendingImageMimeType;
    final featureNote = _pendingFeatureNote;
    if (base64Image == null || imageMimeType == null || featureNote == null) {
      return;
    }

    final avatar = await _aiPetService.generatePetAvatarStates(
      base64Image: base64Image,
      imageMimeType: imageMimeType,
      featureNote: featureNote,
      species: savedPet.species,
      breed: _pendingBreed,
      breedTraits: _pendingBreedTraits,
      visualTraits: _pendingVisualTraits,
      petId: savedPet.id,
    );
    if (avatar == null) return;

    final updatedPet = savedPet.copyWith(
      sleepingImageUrl: avatar.sleepingImageUrl,
      failedImageUrl: avatar.failedImageUrl,
    );
    final existingIndex =
        _customPets.indexWhere((pet) => pet.id == savedPet.id);
    if (existingIndex >= 0) {
      _customPets[existingIndex] = updatedPet;
      await _storageService.replaceCustomPets(_customPets);
      notifyListeners();
    }
  }

  void resetUploadState() {
    _uploadState = PetUploadState.idle;
    _errorMessage = null;
    _pendingSpecies = null;
    _pendingPetId = null;
    _pendingOriginalImagePath = null;
    _pendingNormalUrl = null;
    _pendingSleepingUrl = null;
    _pendingFailedUrl = null;
    _pendingBreed = null;
    _pendingBreedTraits = '';
    _pendingVisualTraits = [];
    _pendingBase64Image = null;
    _pendingImageMimeType = null;
    _pendingFeatureNote = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _petsSubscription?.cancel();
    super.dispose();
  }
}
