import 'package:flutter_test/flutter_test.dart';
import 'package:luffy_focus/services/storage_service.dart';

void main() {
  test('CustomPet serializes cloud image fields', () {
    final pet = CustomPet(
      id: 'pet-1',
      name: 'Momo',
      species: 'cat',
      originalImagePath: 'users/user-1/pets/pet-1/original.jpg',
      normalImageUrl: 'https://example.com/normal.png',
      sleepingImageUrl: 'https://example.com/sleeping.png',
      failedImageUrl: 'https://example.com/failed.png',
      avatarStatesVersion: 3,
      createdAt: DateTime(2026, 5, 17),
    );

    final decoded = CustomPet.fromJson(pet.toJson());

    expect(decoded.id, pet.id);
    expect(decoded.originalImagePath, pet.originalImagePath);
    expect(decoded.normalImageUrl, pet.normalImageUrl);
    expect(decoded.sleepingImageUrl, pet.sleepingImageUrl);
    expect(decoded.failedImageUrl, pet.failedImageUrl);
    expect(decoded.avatarStatesVersion, pet.avatarStatesVersion);
    expect(decoded.status, 'ready');
  });
}
