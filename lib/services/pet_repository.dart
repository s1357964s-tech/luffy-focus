import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'firebase_service.dart';
import 'storage_service.dart';

class PetRepository {
  final StorageService _localStorage;
  final FirebaseFirestore? _firestore;
  final FirebaseStorage? _storage;

  PetRepository(
    this._localStorage, {
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = FirebaseService.isAvailable
            ? (firestore ?? FirebaseFirestore.instance)
            : firestore,
        _storage = FirebaseService.isAvailable
            ? (storage ?? FirebaseStorage.instance)
            : storage;

  String get _uid => FirebaseService.currentUser.uid;

  DocumentReference<Map<String, dynamic>> get _userRef =>
      _firestore!.collection('users').doc(_uid);

  CollectionReference<Map<String, dynamic>> get _petsRef =>
      _userRef.collection('pets');

  CollectionReference<Map<String, dynamic>> get _storiesRef =>
      _userRef.collection('stories');

  Future<void> ensureUserDocument() async {
    if (!FirebaseService.isAvailable) return;

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
    if (!FirebaseService.isAvailable) {
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
    if (!FirebaseService.isAvailable) return;

    final localPets = _localStorage.customPets;
    final remotePets = await fetchPets();
    if (remotePets.isNotEmpty || localPets.isEmpty) return;

    final batch = _firestore!.batch();
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
    await batch.commit();
  }

  Future<String?> fetchSelectedPetId() async {
    if (!FirebaseService.isAvailable) {
      return _localStorage.selectedPetId;
    }

    final snapshot = await _userRef.get();
    final id = snapshot.data()?['selectedPetId'];
    return id is String && id.isNotEmpty ? id : null;
  }

  Future<void> setSelectedPetId(String? id) async {
    await _localStorage.setSelectedPetId(id);
    if (!FirebaseService.isAvailable) return;

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
    if (!FirebaseService.isAvailable || _storage == null) {
      throw StateError('Firebase Storage is not available on this platform.');
    }

    final extension = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => 'jpg',
    };
    final path = 'users/$_uid/pets/$petId/original.$extension';
    final ref = _storage!.ref(path);
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

    await _petsRef.doc(petId).set({
      'name': name,
      'status': 'ready',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final snapshot = await _petsRef.doc(petId).get();
    if (snapshot.exists && snapshot.data() != null) {
      return _customPetFromDoc(snapshot);
    }

    final pet = fallbackPet.copyWith(name: name, status: 'ready');
    await _localStorage.addCustomPet(pet);
    return pet;
  }

  Future<void> deletePet(CustomPet pet) async {
    if (FirebaseService.isAvailable && !pet.isLocalAsset) {
      await Future.wait([
        if (pet.originalImagePath != null && pet.originalImagePath!.isNotEmpty)
          _deleteStoragePathIfExists(pet.originalImagePath!),
        _deleteStorageUrlIfExists(pet.normalImageUrl),
        _deleteStorageUrlIfExists(pet.sleepingImageUrl),
        _deleteStorageUrlIfExists(pet.failedImageUrl),
      ]);
    }

    if (FirebaseService.isAvailable) {
      await _petsRef.doc(pet.id).delete();
    }

    if (_localStorage.selectedPetId == pet.id) {
      await setSelectedPetId(null);
    }

    final remainingPets =
        _localStorage.customPets.where((item) => item.id != pet.id).toList();
    await _localStorage.replaceCustomPets(remainingPets);
  }

  Future<void> _deleteStoragePathIfExists(String path) async {
    if (_storage == null) return;

    try {
      await _storage!.ref(path).delete();
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
  }

  Future<void> _deleteStorageUrlIfExists(String url) async {
    if (_storage == null) return;
    if (!url.startsWith('http')) return;
    try {
      await _storage!.refFromURL(url).delete();
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
    return CustomPet(
      id: doc.id,
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
}
