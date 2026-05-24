import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../firebase_options.dart';

class FirebaseService {
  static bool _isAvailable = false;

  static bool get isAvailable => _isAvailable;

  static Future<void> init() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      _isAvailable = true;
    } catch (error) {
      _isAvailable = false;
      debugPrint('Firebase 初始化失敗，改用本地模式: $error');
    }
  }

  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFunctions get functions => FirebaseFunctions.instance;

  static User get currentUser {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('Firebase anonymous auth is not initialized.');
    }
    return user;
  }
}
