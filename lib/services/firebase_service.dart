import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../firebase_options.dart';

class FirebaseService {
  static bool _isAvailable = false;

  static bool get isAvailable => _isAvailable;

  static Future<void> init() async {
    await ensureSignedIn(attempts: 1);
  }

  static Future<bool> ensureSignedIn({int attempts = 3}) async {
    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt += 1) {
      try {
        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        }
        if (FirebaseAuth.instance.currentUser == null) {
          await FirebaseAuth.instance.signInAnonymously();
        }
        _isAvailable = true;
        return true;
      } catch (error) {
        lastError = error;
        _isAvailable = false;
        debugPrint('Firebase 匿名登入失敗（第 $attempt 次）: $error');
        if (attempt < attempts) {
          await Future<void>.delayed(Duration(milliseconds: 700 * attempt));
        }
      }
    }

    debugPrint('Firebase 初始化失敗，改用本地模式: $lastError');
    return false;
  }

  static Future<void> resetAnonymousAuth() async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      await FirebaseAuth.instance.signOut();
    } catch (_) {
      // Ignore sign-out/reset failures; the next ensureSignedIn call will retry.
    } finally {
      _isAvailable = false;
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

  static const String customGatewayUrl =
      String.fromEnvironment('CUSTOM_FUNCTIONS_GATEWAY_URL', defaultValue: '');

  static Future<dynamic> callFunction(
    String name, {
    Map<String, dynamic> data = const {},
    required Duration timeout,
  }) async {
    final user = auth.currentUser;
    if (user == null) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Authentication is required.',
      );
    }

    if (customGatewayUrl.isNotEmpty) {
      String? token;
      try {
        token = await user.getIdToken(false);
      } catch (e) {
        debugPrint('[FirebaseHttp] Failed to get cached token: $e');
        try {
          token = await user.getIdToken(true).timeout(const Duration(seconds: 4));
        } catch (e2) {
          debugPrint('[FirebaseHttp] Failed to refresh token: $e2');
        }
      }

      final uri = Uri.parse('$customGatewayUrl/$name');
      final response = await http
          .post(
            uri,
            headers: {
              if (token != null) 'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'data': data}),
          )
          .timeout(timeout);

      final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
      if (decoded is Map && decoded['error'] is Map) {
        final error = decoded['error'] as Map;
        throw FirebaseFunctionsException(
          code: (error['status'] ?? 'unknown').toString().toLowerCase(),
          message: (error['message'] ?? '請求失敗，請稍後再試。').toString(),
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FirebaseFunctionsException(
          code: response.statusCode.toString(),
          message: '伺服器連線異常，請稍後再試。',
        );
      }
      if (decoded is Map && decoded.containsKey('result')) {
        return decoded['result'];
      }
      return decoded;
    } else {
      final callable = functions.httpsCallable(
        name,
        options: HttpsCallableOptions(timeout: timeout),
      );
      final response = await callable.call(data);
      return response.data;
    }
  }
}
