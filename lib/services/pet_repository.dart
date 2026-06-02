import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'firebase_service.dart';
import 'pet_image_cache.dart';
import 'storage_service.dart';

class PetRepository {
  final StorageService _localStorage;
  final FirebaseFirestore? _firestoreOverride;
  final FirebaseStorage? _storageOverride;

  PetRepository(
    this._localStorage, {
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestoreOverride = firestore,
        _storageOverride = storage;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;

  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  String get _uid => FirebaseService.currentUser.uid;

  DocumentReference<Map<String, dynamic>> get _userRef =>
      _firestore.collection('users').doc(_uid);

  CollectionReference<Map<String, dynamic>> get _petsRef =>
      _userRef.collection('pets');

  CollectionReference<Map<String, dynamic>> get _storiesRef =>
      _userRef.collection('stories');

  Future<void> ensureUserDocument() async {
    if (!await FirebaseService.ensureSignedIn()) return;

    await _userRef.set({
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<List<CustomPet>> watchPets() {
    if (!FirebaseService.isAvailable) {
      return Stream.value(_localStorage.customPets);
    }

    return _petsRef.orderBy('createdAt', descending: false).snapshots().map(
      (snapshot) {
        final pets = snapshot.docs
            .map(_customPetFromDoc)
            .where((pet) => pet.status == 'ready' && pet.name.trim().isNotEmpty)
            .toList();
        unawaited(_localStorage.replaceCustomPets(pets));
        return pets;
      },
    );
  }

  Future<List<CustomPet>> fetchPets() async {
    if (!await FirebaseService.ensureSignedIn()) {
      return _localStorage.customPets;
    }

    final snapshot =
        await _petsRef.orderBy('createdAt', descending: false).get();
    final pets = snapshot.docs
        .map(_customPetFromDoc)
        .where((pet) => pet.status == 'ready' && pet.name.trim().isNotEmpty)
        .toList();
    await _localStorage.replaceCustomPets(pets);
    return pets;
  }

  Future<void> migrateLocalPetsIfNeeded() async {
    if (!await FirebaseService.ensureSignedIn()) return;

    final localPets = _localStorage.customPets;
    final remotePets = await fetchPets();
    if (remotePets.isNotEmpty || localPets.isEmpty) return;

    final batch = _firestore.batch();
    for (final pet in localPets) {
      batch.set(
          _petsRef.doc(pet.id),
          {
            ...pet.toJson(),
            'status': pet.status,
            'createdAt': Timestamp.fromDate(pet.createdAt),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
    }
    try {
      await batch.commit();
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') rethrow;
      if (kDebugMode) {
        debugPrint('本機寵物雲端遷移被安全規則拒絕，已略過並繼續同步: $error');
      }
    }
  }

  Future<String?> fetchSelectedPetId() async {
    if (!await FirebaseService.ensureSignedIn()) {
      return _localStorage.selectedPetId;
    }

    final snapshot = await _userRef.get();
    final id = snapshot.data()?['selectedPetId'];
    return id is String && id.isNotEmpty ? id : null;
  }

  Future<void> setSelectedPetId(String? id) async {
    await _localStorage.setSelectedPetId(id);
    if (!await FirebaseService.ensureSignedIn()) return;

    await _userRef.set({
      'selectedPetId': id,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<String> uploadOriginalPetImage({
    required String petId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (!await FirebaseService.ensureSignedIn()) {
      throw StateError('Firebase Storage is not available on this platform.');
    }

    final extension = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final path = 'users/$_uid/pets/$petId/original.$extension';
    final ref = _storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: contentType));
    return path;
  }

  Future<CustomPet> saveGeneratedPetName({
    required String petId,
    required String name,
    required CustomPet fallbackPet,
  }) async {
    if (!FirebaseService.isAvailable) {
      final pet = fallbackPet.copyWith(name: name, status: 'ready');
      await _localStorage.addCustomPet(pet);
      return pet;
    }

    final callable =
        FirebaseService.functions.httpsCallable('saveGeneratedPetName');
    final response = await callable.call({
      'petId': petId,
      'name': name,
    });
    final data = response.data;
    if (data is Map) {
      return _customPetFromData(
        petId,
        data.map((key, value) => MapEntry(key.toString(), value)),
      );
    }

    final snapshot = await _petsRef.doc(petId).get();
    return snapshot.exists && snapshot.data() != null
        ? _customPetFromDoc(snapshot)
        : fallbackPet.copyWith(name: name, status: 'ready');
  }

  Future<void> deletePet(CustomPet pet) async {
    final wasSelected = _localStorage.selectedPetId == pet.id;
    if (wasSelected) {
      await _localStorage.setSelectedPetId(null);
    }

    await _localStorage.removeFocusRecordsForPet(pet.id, petName: pet.name);

    final remainingPets =
        _localStorage.customPets.where((item) => item.id != pet.id).toList();
    await _localStorage.replaceCustomPets(remainingPets);
    unawaited(PetImageCache.evictAll([
      pet.normalImageUrl,
      pet.sleepingImageUrl,
      pet.failedImageUrl,
    ]));

    if (FirebaseService.isAvailable) {
      if (pet.status == 'discarded' || pet.name.trim().isEmpty) {
        unawaited(_releaseReservedCreditBestEffort(pet.id));
      }
      unawaited(_deleteRemotePetBestEffort(pet, clearSelection: wasSelected));
    }
  }

  Future<void> _releaseReservedCreditBestEffort(String petId) async {
    try {
      final callable = FirebaseService.functions
          .httpsCallable('releaseCustomPetPurchaseCredit');
      await callable.call({'petId': petId});
    } catch (error) {
      if (kDebugMode) {
        debugPrint('退回未完成寵物名額失敗，已略過: $error');
      }
    }
  }

  Future<void> _deleteRemotePetBestEffort(
    CustomPet pet, {
    required bool clearSelection,
  }) async {
    try {
      if (clearSelection) {
        await _userRef.set({
          'selectedPetId': null,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await _petsRef.doc(pet.id).delete();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('刪除遠端寵物資料失敗，已先保留本地刪除結果: $error');
      }
      return;
    }

    if (!pet.isLocalAsset) {
      await _deletePetImagesBestEffort(pet);
    }
    await _deleteStoryRecordsForPetBestEffort(pet.id);
  }

  Future<void> _deleteStoryRecordsForPetBestEffort(String petId) async {
    try {
      while (true) {
        final snapshot =
            await _storiesRef.where('petId', isEqualTo: petId).limit(450).get();
        if (snapshot.docs.isEmpty) return;

        final batch = _firestore.batch();
        for (final doc in snapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('刪除寵物夢境故事失敗，已略過: $error');
      }
    }
  }

  Future<void> _deletePetImagesBestEffort(CustomPet pet) async {
    try {
      await Future.wait([
        if (pet.originalImagePath != null && pet.originalImagePath!.isNotEmpty)
          _deleteStoragePathIfExists(pet.originalImagePath!),
        _deleteStorageUrlIfExists(pet.normalImageUrl),
        _deleteStorageUrlIfExists(pet.sleepingImageUrl),
        _deleteStorageUrlIfExists(pet.failedImageUrl),
      ]);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('刪除寵物圖片失敗，已略過: $error');
      }
    }
  }

  Future<void> _deleteStoragePathIfExists(String path) async {
    try {
      await _storage.ref(path).delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
  }

  Future<void> _deleteStorageUrlIfExists(String url) async {
    if (!url.startsWith('http')) return;
    try {
      await _storage.refFromURL(url).delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
  }

  Future<void> addStoryRecord({
    required String petId,
    required String petName,
    required String species,
    required int focusMinutes,
    required String storyText,
  }) async {
    if (!FirebaseService.isAvailable) return;

    await _storiesRef.add({
      'petId': petId,
      'petName': petName,
      'species': species,
      'focusMinutes': focusMinutes,
      'storyText': storyText,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  CustomPet _customPetFromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return _customPetFromData(doc.id, data);
  }

  CustomPet _customPetFromData(String id, Map<String, dynamic> data) {
    return CustomPet(
      id: id,
      name: data['name'] as String? ?? '',
      species: data['species'] as String? ?? 'cat',
      breed: data['breed'] as String?,
      breedTraits: data['breedTraits'] as String? ?? '',
      visualTraits:
          (data['visualTraits'] as List? ?? []).whereType<String>().toList(),
      originalImagePath: data['originalImagePath'] as String?,
      normalImageUrl: data['normalImageUrl'] as String? ?? '',
      sleepingImageUrl: data['sleepingImageUrl'] as String? ?? '',
      failedImageUrl: data['failedImageUrl'] as String? ?? '',
      avatarStatesVersion: _intFromFirestore(data['avatarStatesVersion']),
      status: data['status'] as String? ?? 'ready',
      createdAt: _dateFromFirestore(data['createdAt']),
      isLocalAsset: data['isLocalAsset'] as bool? ?? false,
    );
  }

  DateTime _dateFromFirestore(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  int _intFromFirestore(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
