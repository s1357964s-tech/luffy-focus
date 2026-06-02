import 'dart:collection';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

class PetImageCache {
  static const int _maxMemoryItems = 24;
  static const int _maxImageBytes = 8 * 1024 * 1024;
  static final LinkedHashMap<String, Uint8List> _memoryCache =
      LinkedHashMap<String, Uint8List>();

  static Uint8List? memoryBytes(String imageUrl) {
    final bytes = _memoryCache.remove(imageUrl);
    if (bytes == null) return null;
    _remember(imageUrl, bytes);
    return bytes;
  }

  static Future<Uint8List?> load(String imageUrl) async {
    if (imageUrl.trim().isEmpty) return null;

    final memory = memoryBytes(imageUrl);
    if (memory != null && memory.isNotEmpty) return memory;

    final cached = await _readFile(imageUrl);
    if (cached != null && cached.isNotEmpty) {
      _remember(imageUrl, cached);
      return cached;
    }

    return _downloadAndCache(imageUrl);
  }

  static Future<void> preloadAll(Iterable<String> imageUrls) async {
    await Future.wait(
      imageUrls
          .where((url) => url.trim().isNotEmpty && url.startsWith('http'))
          .toSet()
          .map((url) async {
        try {
          await load(url);
        } catch (_) {
          // Preloading is opportunistic; visible widgets handle errors.
        }
      }),
    );
  }

  static Future<void> evictAll(Iterable<String> imageUrls) async {
    await Future.wait(imageUrls.toSet().map(evict));
  }

  static Future<void> evict(String imageUrl) async {
    _memoryCache.remove(imageUrl);

    try {
      final file = await _fileForUrl(imageUrl);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Cache eviction must never block the primary delete flow.
    }
  }

  static Future<Uint8List?> _readFile(String imageUrl) async {
    try {
      final file = await _fileForUrl(imageUrl);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        await file.delete();
        return null;
      }
      return bytes;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[PetImageCache] read failed url=$imageUrl error=$error');
      }
      return null;
    }
  }

  static Future<Uint8List?> _downloadAndCache(String imageUrl) async {
    const maxAttempts = 3;

    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        final ref = FirebaseStorage.instance.refFromURL(imageUrl);
        final bytes = await ref.getData(_maxImageBytes);
        if (bytes == null || bytes.isEmpty) return null;

        _remember(imageUrl, bytes);
        await _writeFile(imageUrl, bytes);
        return bytes;
      } catch (error) {
        if (kDebugMode) {
          debugPrint(
            '[PetImageCache] download failed '
            'attempt=$attempt url=$imageUrl error=$error',
          );
        }
        if (attempt < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
        }
      }
    }

    return null;
  }

  static Future<void> _writeFile(String imageUrl, Uint8List bytes) async {
    try {
      final file = await _fileForUrl(imageUrl);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    } catch (error) {
      if (kDebugMode) {
        debugPrint('[PetImageCache] write failed url=$imageUrl error=$error');
      }
    }
  }

  static void _remember(String imageUrl, Uint8List bytes) {
    _memoryCache.remove(imageUrl);
    while (_memoryCache.length >= _maxMemoryItems) {
      _memoryCache.remove(_memoryCache.keys.first);
    }
    _memoryCache[imageUrl] = bytes;
  }

  static Future<File> _fileForUrl(String imageUrl) async {
    final directory =
        Directory('${Directory.systemTemp.path}/luffy_pet_image_cache');
    final cacheKey = _stableCacheKey(imageUrl);
    return File('${directory.path}/$cacheKey.img');
  }

  static String _stableCacheKey(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
