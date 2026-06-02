import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/pet_image_cache.dart';

typedef FirebaseStorageImageErrorBuilder = Widget Function(
  BuildContext context,
  Object error,
  VoidCallback retry,
);

class FirebaseStorageImage extends StatefulWidget {
  final String imageUrl;
  final String? placeholderImageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final FirebaseStorageImageErrorBuilder? errorBuilder;

  const FirebaseStorageImage({
    super.key,
    required this.imageUrl,
    this.placeholderImageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorBuilder,
  });

  @override
  State<FirebaseStorageImage> createState() => _FirebaseStorageImageState();
}

class _FirebaseStorageImageState extends State<FirebaseStorageImage> {
  Future<Uint8List?>? _imageBytesFuture;
  int _reloadVersion = 0;

  @override
  void didUpdateWidget(covariant FirebaseStorageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _imageBytesFuture = null;
      _reloadVersion = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final memoryBytes = PetImageCache.memoryBytes(widget.imageUrl);
    if (memoryBytes != null && memoryBytes.isNotEmpty) {
      return _buildMemoryImage(memoryBytes);
    }

    _imageBytesFuture ??= PetImageCache.load(widget.imageUrl);

    return FutureBuilder<Uint8List?>(
      key: ValueKey('${widget.imageUrl}:$_reloadVersion'),
      future: _imageBytesFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return _buildMemoryImage(bytes);
        }

        if (snapshot.connectionState != ConnectionState.done) {
          return SizedBox(
            width: widget.width,
            height: widget.height,
            child: _buildPlaceholderOrSpinner(),
          );
        }

        if (snapshot.hasError) {
          return _buildError(context, snapshot.error!);
        }

        return _buildError(context, '圖片載入失敗');
      },
    );
  }

  Widget _buildMemoryImage(Uint8List bytes) {
    return Image.memory(
      bytes,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        debugPrint(
          '[FirebaseStorageImage] Image.memory failed '
          'url=${widget.imageUrl} error=$error',
        );
        unawaited(PetImageCache.evict(widget.imageUrl));
        return _buildError(context, error);
      },
    );
  }

  Widget _buildPlaceholderOrSpinner() {
    final placeholderImageUrl = widget.placeholderImageUrl;
    if (placeholderImageUrl != null &&
        placeholderImageUrl.isNotEmpty &&
        placeholderImageUrl != widget.imageUrl) {
      return _CachedImagePlaceholder(
        imageUrl: placeholderImageUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
      );
    }

    return const Center(child: CircularProgressIndicator());
  }

  void _retry() {
    unawaited(PetImageCache.evict(widget.imageUrl));
    setState(() {
      _imageBytesFuture = null;
      _reloadVersion += 1;
    });
  }

  Widget _buildError(BuildContext context, Object error) {
    final errorBuilder = widget.errorBuilder;
    if (errorBuilder != null) {
      return errorBuilder(context, error, _retry);
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Center(
        child: IconButton(
          tooltip: '重新載入圖片',
          icon: const Icon(Icons.refresh),
          onPressed: _retry,
        ),
      ),
    );
  }
}

class _CachedImagePlaceholder extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;

  const _CachedImagePlaceholder({
    required this.imageUrl,
    required this.fit,
    this.width,
    this.height,
  });

  @override
  State<_CachedImagePlaceholder> createState() =>
      _CachedImagePlaceholderState();
}

class _CachedImagePlaceholderState extends State<_CachedImagePlaceholder> {
  Future<Uint8List?>? _bytesFuture;

  @override
  void didUpdateWidget(covariant _CachedImagePlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _bytesFuture = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final memoryBytes = PetImageCache.memoryBytes(widget.imageUrl);
    if (memoryBytes != null && memoryBytes.isNotEmpty) {
      return _buildMemoryImage(memoryBytes);
    }

    _bytesFuture ??= PetImageCache.load(widget.imageUrl);

    return FutureBuilder<Uint8List?>(
      future: _bytesFuture,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes != null && bytes.isNotEmpty) {
          return _buildMemoryImage(bytes);
        }

        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }

  Widget _buildMemoryImage(Uint8List bytes) {
    return Image.memory(
      bytes,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) =>
          const Center(child: CircularProgressIndicator()),
    );
  }
}
