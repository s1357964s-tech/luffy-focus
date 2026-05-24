import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class FirebaseStorageImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  const FirebaseStorageImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorBuilder,
  });

  @override
  State<FirebaseStorageImage> createState() => _FirebaseStorageImageState();
}

class _FirebaseStorageImageState extends State<FirebaseStorageImage> {
  Future<Uint8List?>? _fallbackBytesFuture;

  @override
  void didUpdateWidget(covariant FirebaseStorageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _fallbackBytesFuture = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Image.network(
      widget.imageUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (context, error, stackTrace) {
        debugPrint(
          '[FirebaseStorageImage] Image.network failed '
          'url=${widget.imageUrl} error=$error',
        );
        _fallbackBytesFuture ??= _loadViaFirebaseStorage();
        return FutureBuilder<Uint8List?>(
          future: _fallbackBytesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return SizedBox(
                width: widget.width,
                height: widget.height,
                child: const Center(child: CircularProgressIndicator()),
              );
            }

            final bytes = snapshot.data;
            if (bytes != null && bytes.isNotEmpty) {
              return Image.memory(
                bytes,
                width: widget.width,
                height: widget.height,
                fit: widget.fit,
                errorBuilder: (context, memoryError, stackTrace) {
                  debugPrint(
                    '[FirebaseStorageImage] Image.memory failed '
                    'url=${widget.imageUrl} error=$memoryError',
                  );
                  return _buildError(context, memoryError);
                },
              );
            }

            return _buildError(context, error);
          },
        );
      },
    );
  }

  Future<Uint8List?> _loadViaFirebaseStorage() async {
    try {
      final ref = FirebaseStorage.instance.refFromURL(widget.imageUrl);
      final bytes = await ref.getData(8 * 1024 * 1024);
      debugPrint(
        '[FirebaseStorageImage] Firebase Storage fallback loaded '
        'bytes=${bytes?.length ?? 0} url=${widget.imageUrl}',
      );
      return bytes;
    } catch (error) {
      debugPrint(
        '[FirebaseStorageImage] Firebase Storage fallback failed '
        'url=${widget.imageUrl} error=$error',
      );
      return null;
    }
  }

  Widget _buildError(BuildContext context, Object error) {
    final errorBuilder = widget.errorBuilder;
    if (errorBuilder != null) {
      return errorBuilder(context, error);
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: const Icon(Icons.error),
    );
  }
}
