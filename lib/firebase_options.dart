import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Firebase options are not configured for web. Run flutterfire configure '
        'again if you want to support web.',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.android:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'Firebase options are only configured for iOS right now. Run '
          'flutterfire configure again to add this platform.',
        );
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBlO4yeLkJUZ3qXCE9R3z_U3i3-x7nPsOw',
    appId: '1:679091342765:ios:ed15bad52893d3cbaf2524',
    messagingSenderId: '679091342765',
    projectId: 'luffy-focus',
    storageBucket: 'luffy-focus.firebasestorage.app',
    iosBundleId: 'com.stevehu.luffyFocus',
  );
}
