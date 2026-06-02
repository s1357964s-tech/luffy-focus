import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import '../services/storage_service.dart';
import '../services/ai_pet_service.dart';
import '../services/pet_repository.dart';
import '../services/pet_image_cache.dart';
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
  static const int _requiredAvatarStatesVersion = 3;

  final StorageService _storageService;
  final AiPetService _aiPetService;
  final PetRepository _petRepository;
  final _uuid = const Uuid();
  StreamSubscription<List<CustomPet>>? _petsSubscription;

  List<CustomPet> _customPets = [];
  final Map<String, CustomPet> _locallyFinalizedPets = {};
  final Set<String> _locallyDeletedPetIds = {};
  final Set<String> _discardedPendingPetIds = {};
  final Set<String> _repairingPetStateIds = {};
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
  String? _completedPetName;
  String? _completedPetSpecies;
  String? _completedPetId;

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
  String? get pendingSleepingUrl => _pendingSleepingUrl;
  String? get pendingFailedUrl => _pendingFailedUrl;
  String? get completedPetName => _completedPetName;
  String? get completedPetSpecies => _completedPetSpecies;
  String? get completedPetId => _completedPetId;

  Future<void> _initialize() async {
    _customPets = _storageService.customPets;
    _selectedPetId = _storageService.selectedPetId;
    notifyListeners();
    unawaited(_repairPetsWithDuplicateStateImages(_customPets));

    try {
      await _petRepository.ensureUserDocument();
      await _petRepository.migrateLocalPetsIfNeeded();
      final remoteSelectedPetId = await _petRepository.fetchSelectedPetId();
      if (remoteSelectedPetId != _selectedPetId) {
        _selectedPetId = remoteSelectedPetId;
        await _storageService.setSelectedPetId(remoteSelectedPetId);
        notifyListeners();
      }

      final remotePets = await _petRepository.fetchPets();
      if (remotePets.isNotEmpty) {
        _customPets = remotePets
            .where((pet) => !_locallyDeletedPetIds.contains(pet.id))
            .toList();
        unawaited(_repairPetsWithDuplicateStateImages(_customPets));
        notifyListeners();
      }

      _petsSubscription = _petRepository.watchPets().listen((pets) {
        final visiblePets = pets
            .where((pet) => !_locallyDeletedPetIds.contains(pet.id))
            .toList();
        final visiblePetIds = visiblePets.map((pet) => pet.id).toSet();
        _locallyFinalizedPets.removeWhere(
          (petId, _) =>
              visiblePetIds.contains(petId) ||
              _locallyDeletedPetIds.contains(petId),
        );
        _customPets = [
          ...visiblePets,
          ..._locallyFinalizedPets.values,
        ];
        if (_selectedPetId != null &&
            _customPets.every((pet) => pet.id != _selectedPetId)) {
          _selectedPetId = null;
          unawaited(_petRepository.setSelectedPetId(null));
        }
        if (_locallyDeletedPetIds.isNotEmpty) {
          unawaited(_storageService.replaceCustomPets(_customPets));
        }
        unawaited(_repairPetsWithDuplicateStateImages(_customPets));
        notifyListeners();
      });
    } catch (e) {
      if (kDebugMode) {
        print('Firebase 寵物資料初始化失敗，暫時使用本地快取: $e');
      }
    }
  }

  Future<void> selectPet(String? id) async {
    _selectedPetId = id;
    notifyListeners();

    final pet = selectedPet;
    if (pet != null && !pet.isLocalAsset) {
      unawaited(PetImageCache.preloadAll([
        pet.normalImageUrl,
        pet.sleepingImageUrl,
        pet.failedImageUrl,
      ]));
      unawaited(_repairPetsWithDuplicateStateImages([pet]));
    }

    await _storageService.setSelectedPetId(id);
    unawaited(
      _petRepository.setSelectedPetId(id).catchError((error) {
        if (kDebugMode) {
          debugPrint('同步選擇寵物到雲端失敗，已保留本機選擇: $error');
        }
      }),
    );
  }

  Future<void> deletePet(CustomPet pet) async {
    _locallyFinalizedPets.remove(pet.id);
    _locallyDeletedPetIds.add(pet.id);
    _customPets = _customPets.where((item) => item.id != pet.id).toList();
    if (_selectedPetId == pet.id) {
      _selectedPetId = null;
    }
    notifyListeners();

    await _petRepository.deletePet(pet);
  }

  Future<void> ensureAvatarStatesReady(CustomPet pet) async {
    await _repairPetsWithDuplicateStateImages([pet]);
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
        throw Exception('請上傳貓或狗的清晰照片！');
      }

      final petId = _uuid.v4();

      _pendingSpecies = species;
      _pendingBreed = analysis.breed;
      _pendingBreedTraits = analysis.breedTraits;
      _pendingVisualTraits = analysis.visualTraits;
      _pendingPetId = petId;
      _pendingOriginalImagePath = '';
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
      );

      if (_discardedPendingPetIds.contains(petId)) {
        await _deleteGeneratedDraft(
          petId: petId,
          species: species,
          originalImagePath: avatar.originalImagePath ?? '',
          normalImageUrl: avatar.normalImageUrl,
          sleepingImageUrl: avatar.sleepingImageUrl,
          failedImageUrl: avatar.failedImageUrl,
        );
        return;
      }

      _pendingNormalUrl = avatar.normalImageUrl;
      _pendingSleepingUrl = avatar.sleepingImageUrl;
      _pendingFailedUrl = avatar.failedImageUrl;
      _pendingOriginalImagePath = avatar.originalImagePath ?? '';
      unawaited(PetImageCache.preloadAll([
        avatar.normalImageUrl,
        avatar.sleepingImageUrl,
        avatar.failedImageUrl,
      ]));
      _uploadState = PetUploadState.naming;
      notifyListeners();
    } catch (e) {
      if (_pendingPetId != null &&
          _discardedPendingPetIds.contains(_pendingPetId)) {
        resetUploadState();
        return;
      }
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

    var savedPet = newPet.copyWith(status: 'ready');
    if (!_aiPetService.isMockMode) {
      savedPet = await _petRepository.saveGeneratedPetName(
        petId: savedPet.id,
        name: name,
        fallbackPet: savedPet,
      );
    }

    final existingIndex =
        _customPets.indexWhere((pet) => pet.id == savedPet.id);
    if (existingIndex >= 0) {
      _customPets[existingIndex] = savedPet;
    } else {
      _customPets = [..._customPets, savedPet];
    }
    _locallyFinalizedPets[savedPet.id] = savedPet;
    await _storageService.replaceCustomPets(_customPets);
    unawaited(PetImageCache.preloadAll([
      savedPet.normalImageUrl,
      savedPet.sleepingImageUrl,
      savedPet.failedImageUrl,
    ]));

    // 自動選中新寵物
    await _storageService.setSelectedPetId(savedPet.id);
    _selectedPetId = savedPet.id;
    if (!_aiPetService.isMockMode) {
      unawaited(
        _petRepository.setSelectedPetId(savedPet.id).catchError((error) {
          if (kDebugMode) {
            debugPrint('寵物選取狀態遠端同步失敗，已保留本地設定: $error');
          }
        }),
      );
    }

    _completedPetName = savedPet.name;
    _completedPetSpecies = savedPet.species;
    _completedPetId = savedPet.id;
    _uploadState = PetUploadState.success;
    notifyListeners();

    if (!_aiPetService.isMockMode && _hasDuplicateStateImages(savedPet)) {
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
      avatarStatesVersion: _requiredAvatarStatesVersion,
    );
    final existingIndex =
        _customPets.indexWhere((pet) => pet.id == savedPet.id);
    if (existingIndex >= 0) {
      _customPets[existingIndex] = updatedPet;
      if (_locallyFinalizedPets.containsKey(updatedPet.id)) {
        _locallyFinalizedPets[updatedPet.id] = updatedPet;
      }
      await _storageService.replaceCustomPets(_customPets);
      unawaited(PetImageCache.preloadAll([
        updatedPet.normalImageUrl,
        updatedPet.sleepingImageUrl,
        updatedPet.failedImageUrl,
      ]));
      notifyListeners();
    }
  }

  bool _hasDuplicateStateImages(CustomPet pet) {
    final urls = [
      pet.normalImageUrl.trim(),
      pet.sleepingImageUrl.trim(),
      pet.failedImageUrl.trim(),
    ];
    if (urls.any((url) => url.isEmpty)) return true;
    return urls.toSet().length < urls.length;
  }

  bool _needsAvatarStateRepair(CustomPet pet) {
    return _hasDuplicateStateImages(pet) ||
        pet.avatarStatesVersion < _requiredAvatarStatesVersion;
  }

  Future<void> _repairPetsWithDuplicateStateImages(
    List<CustomPet> pets,
  ) async {
    for (final pet in pets) {
      if (pet.isLocalAsset ||
          !_needsAvatarStateRepair(pet) ||
          _repairingPetStateIds.contains(pet.id)) {
        continue;
      }

      _repairingPetStateIds.add(pet.id);
      try {
        final avatar = await _aiPetService.repairPetAvatarStates(
          petId: pet.id,
          force: true,
        );
        if (avatar == null) continue;

        final currentIndex =
            _customPets.indexWhere((item) => item.id == pet.id);
        if (currentIndex < 0) continue;

        final currentPet = _customPets[currentIndex];
        final updatedPet = currentPet.copyWith(
          sleepingImageUrl: avatar.sleepingImageUrl,
          failedImageUrl: avatar.failedImageUrl,
          avatarStatesVersion: _requiredAvatarStatesVersion,
        );
        _customPets[currentIndex] = updatedPet;
        if (_locallyFinalizedPets.containsKey(updatedPet.id)) {
          _locallyFinalizedPets[updatedPet.id] = updatedPet;
        }
        await _storageService.replaceCustomPets(_customPets);
        unawaited(PetImageCache.preloadAll([
          updatedPet.normalImageUrl,
          updatedPet.sleepingImageUrl,
          updatedPet.failedImageUrl,
        ]));
        notifyListeners();
      } finally {
        _repairingPetStateIds.remove(pet.id);
      }
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
    _completedPetName = null;
    _completedPetSpecies = null;
    _completedPetId = null;
    notifyListeners();
  }

  Future<void> discardPendingUpload() async {
    final petId = _pendingPetId;
    if (petId == null) {
      resetUploadState();
      return;
    }

    _discardedPendingPetIds.add(petId);
    final draftPet = _pendingDraftPet();
    resetUploadState();

    if (draftPet != null) {
      await _petRepository.deletePet(draftPet);
    }
  }

  CustomPet? _pendingDraftPet() {
    final petId = _pendingPetId;
    if (petId == null) return null;

    final normalImageUrl = _pendingNormalUrl ?? '';
    return CustomPet(
      id: petId,
      name: '',
      species: _pendingSpecies ?? 'cat',
      breed: _pendingBreed,
      breedTraits: _pendingBreedTraits,
      visualTraits: _pendingVisualTraits,
      originalImagePath: _pendingOriginalImagePath,
      normalImageUrl: normalImageUrl,
      sleepingImageUrl: _pendingSleepingUrl ?? normalImageUrl,
      failedImageUrl: _pendingFailedUrl ?? normalImageUrl,
      status: 'discarded',
      createdAt: DateTime.now(),
      isLocalAsset: _aiPetService.isMockMode,
    );
  }

  Future<void> _deleteGeneratedDraft({
    required String petId,
    required String species,
    required String originalImagePath,
    required String normalImageUrl,
    required String sleepingImageUrl,
    required String failedImageUrl,
  }) async {
    final draftPet = CustomPet(
      id: petId,
      name: '',
      species: species,
      originalImagePath: originalImagePath,
      normalImageUrl: normalImageUrl,
      sleepingImageUrl: sleepingImageUrl,
      failedImageUrl: failedImageUrl,
      status: 'discarded',
      createdAt: DateTime.now(),
      isLocalAsset: _aiPetService.isMockMode,
    );
    await _petRepository.deletePet(draftPet);
    resetUploadState();
  }

  @override
  void dispose() {
    _petsSubscription?.cancel();
    super.dispose();
  }
}
